import Foundation
import Network
import Observation
import PadelCore

/// Orchestration du partage : publication par l'organisateur, suivi par les spectateurs,
/// file d'envoi hors ligne avec nouvelles tentatives.
///
/// Garanties :
/// - Toute modification est d'abord enregistrée sur l'iPhone ; l'envoi en ligne vient après
///   et peut échouer sans rien perdre (il sera retenté).
/// - Une copie de spectateur n'est remplacée que par une version plus récente.
/// - La version en ligne n'est jamais écrasée si elle vient d'un autre appareil plus récent.
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case idle
        case syncing
        case upToDate(Date)
        /// Modifications locales pas encore envoyées.
        case pending(SyncFailure?)
        case failed(SyncFailure)
        /// Le tournoi suivi n'existe plus en ligne.
        case unpublished
    }

    private(set) var statuses: [Tournament.ID: Status] = [:]
    private(set) var isOnline = true

    @ObservationIgnored private let library: TournamentLibrary
    @ObservationIgnored private let service: any TournamentSyncService
    @ObservationIgnored let deviceID: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var publishTasks: [Tournament.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var monitor: NWPathMonitor?
    /// Délai de regroupement des envois (plusieurs scores saisis à la suite = un seul envoi).
    @ObservationIgnored var debounce: Duration = .seconds(1.5)

    init(
        library: TournamentLibrary,
        service: any TournamentSyncService,
        deviceID: String,
        now: @escaping () -> Date = { Date() }
    ) {
        self.library = library
        self.service = service
        self.deviceID = deviceID
        self.now = now
        library.onLocalChange = { [weak self] tournament in
            self?.localChange(tournament)
        }
    }

    var isConfigured: Bool { service.isConfigured }

    func status(of id: Tournament.ID) -> Status {
        statuses[id] ?? .idle
    }

    // MARK: - Réseau

    /// Surveille la connexion et renvoie les modifications en attente dès son retour.
    func startMonitoringNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "PadelBuddy.network"))
        self.monitor = monitor
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { publishAllPending() }
    }

    /// À appeler au lancement et au retour au premier plan.
    func publishAllPending() {
        for tournament in library.tournaments where SyncRules.needsPublish(tournament) {
            schedulePublish(tournament.id, delay: .zero)
        }
    }

    // MARK: - Organisateur

    /// Publie le tournoi et renvoie son code d'invitation (réutilisé s'il existe déjà).
    @discardableResult
    func share(_ id: Tournament.ID) async throws -> InviteCode {
        guard service.isConfigured else { throw SyncFailure.notConfigured }
        guard let tournament = library.tournament(id: id) else { throw SyncFailure.notFound }
        guard !tournament.isReadOnly else { throw SyncError.readOnly }
        if await service.availability() == .noAccount { throw SyncFailure.noAccount }

        statuses[id] = .syncing
        do {
            let code: InviteCode
            if let existing = tournament.sharing.flatMap({ InviteCode($0.code) }) {
                code = existing
            } else {
                code = try await freeCode()
            }
            try await publish(id, code: code)
            return code
        } catch {
            let failure = Self.failure(error)
            statuses[id] = .failed(failure)
            throw failure
        }
    }

    /// Retire le tournoi du partage : la version en ligne est supprimée, la copie locale reste.
    func unpublish(_ id: Tournament.ID) async throws {
        guard let tournament = library.tournament(id: id), let sharing = tournament.sharing,
              let code = InviteCode(sharing.code) else { return }
        guard sharing.effectiveRole == .organizer else { throw SyncError.readOnly }
        do {
            try await service.delete(code: code)
        } catch {
            throw Self.failure(error)
        }
        publishTasks[id]?.cancel()
        var updated = tournament
        updated.sharing = nil
        try library.saveSynced(updated)
        statuses[id] = nil
    }

    /// Attend la fin de l'envoi en cours (tests, retour au premier plan).
    func waitForPendingPublish(_ id: Tournament.ID) async {
        while let task = publishTasks[id] {
            await task.value
            if publishTasks[id] == task { publishTasks[id] = nil }
        }
    }

    private func localChange(_ tournament: Tournament) {
        guard SyncRules.needsPublish(tournament) else { return }
        statuses[tournament.id] = .pending(nil)
        schedulePublish(tournament.id, delay: debounce)
    }

    private func schedulePublish(_ id: Tournament.ID, delay: Duration) {
        publishTasks[id]?.cancel()
        publishTasks[id] = Task { [weak self] in
            var attempt = 0
            if delay > .zero { try? await Task.sleep(for: delay) }
            while !Task.isCancelled {
                guard let self else { return }
                guard let tournament = self.library.tournament(id: id),
                      SyncRules.needsPublish(tournament),
                      let code = tournament.sharing.flatMap({ InviteCode($0.code) }) else { return }
                do {
                    self.statuses[id] = .syncing
                    try await self.publish(id, code: code)
                    return
                } catch {
                    let failure = Self.failure(error)
                    // Conflit : intervention de l'organisateur nécessaire, pas de nouvel essai.
                    if failure == .conflict || failure == .notConfigured || failure == .noAccount {
                        self.statuses[id] = .failed(failure)
                        return
                    }
                    self.statuses[id] = .pending(failure)
                    attempt += 1
                    var wait = SyncRules.retryDelay(attempt: attempt)
                    if case .rateLimited(let retryAfter?) = failure { wait = max(wait, retryAfter) }
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    /// Envoie la version locale, après avoir vérifié qu'on n'écrase pas une version plus récente
    /// publiée depuis un autre appareil.
    private func publish(_ id: Tournament.ID, code: InviteCode) async throws {
        guard let tournament = library.tournament(id: id) else { return }
        let remote = try await service.fetch(code: code)
        if let remote {
            let remoteTournament = try? remote.decodeTournament()
            if let remoteTournament, remoteTournament.id != tournament.id { throw SyncFailure.codeUnavailable }
        }
        guard SyncRules.canOverwrite(remote: remote, local: tournament, deviceID: deviceID) else {
            throw SyncFailure.conflict
        }
        let snapshot = try PublishedSnapshot(tournament: tournament, code: code, deviceID: deviceID)
        try await service.publish(snapshot)

        // La copie locale a pu changer pendant l'envoi : on ne marque que la révision envoyée.
        guard var latest = library.tournament(id: id) else { return }
        SyncRules.markPublished(&latest, revision: snapshot.revision, code: code, deviceID: deviceID, now: now())
        try library.saveSynced(latest)
        if SyncRules.needsPublish(latest) {
            statuses[id] = .pending(nil)
            schedulePublish(id, delay: debounce)
        } else {
            statuses[id] = .upToDate(now())
        }
    }

    private func freeCode() async throws -> InviteCode {
        for _ in 0..<5 {
            let candidate = InviteCode.random()
            if try await service.fetch(code: candidate) == nil { return candidate }
        }
        throw SyncFailure.codeUnavailable
    }

    // MARK: - Spectateur

    /// Rejoint un tournoi par son code et enregistre une copie locale consultable hors ligne.
    func join(code: InviteCode) async throws -> Tournament.ID {
        guard service.isConfigured else { throw SyncFailure.notConfigured }
        let snapshot: PublishedSnapshot?
        do {
            snapshot = try await service.fetch(code: code)
        } catch {
            throw Self.failure(error)
        }
        guard let snapshot else { throw SyncFailure.notFound }
        let remote = try snapshot.decodeTournament()
        if let local = library.tournament(id: remote.id) {
            // C'est notre propre tournoi, ou une copie déjà suivie : on la met à jour si besoin.
            if let updated = try SyncRules.applyRemote(snapshot, to: local, now: now()) {
                try library.saveSynced(updated)
            }
            statuses[remote.id] = .upToDate(now())
            return remote.id
        }
        guard let copy = try SyncRules.applyRemote(snapshot, to: nil, now: now()) else { throw SyncFailure.notFound }
        try library.saveSynced(copy)
        statuses[copy.id] = .upToDate(now())
        return copy.id
    }

    /// Spectateur : récupère la dernière version publiée.
    func refresh(_ id: Tournament.ID) async {
        guard let local = library.tournament(id: id), local.isReadOnly,
              let code = local.sharing.flatMap({ InviteCode($0.code) }) else { return }
        statuses[id] = .syncing
        do {
            guard let snapshot = try await service.fetch(code: code) else {
                statuses[id] = .unpublished
                return
            }
            if let updated = try SyncRules.applyRemote(snapshot, to: local, now: now()) {
                try library.saveSynced(updated)
            } else if var touched = library.tournament(id: id) {
                touched.sharing?.lastSyncedAt = now()
                try library.saveSynced(touched)
            }
            statuses[id] = .upToDate(now())
        } catch {
            statuses[id] = .failed(Self.failure(error))
        }
    }

    static func failure(_ error: Error) -> SyncFailure {
        if let failure = error as? SyncFailure { return failure }
        if let syncError = error as? SyncError {
            switch syncError {
            case .conflict: return .conflict
            case .notFound: return .notFound
            case .mismatchedTournament: return .codeUnavailable
            case .readOnly: return .other(String(localized: "copie en lecture seule"))
            }
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet { return .offline }
        return CloudKitSyncService.map(error)
    }
}

/// Lien de téléchargement de l'application, à renseigner après la mise en ligne (TestFlight
/// public ou App Store). Tant qu'il est vide, le message d'invitation l'indique simplement.
enum AppLinks {
    static let download: URL? = nil
    /// Politique de confidentialité publiée (obligatoire pour l'App Store), voir docs/PUBLICATION.md.
    static let privacyPolicy: URL? = nil
}

/// Identifiant aléatoire de cet appareil (aucune donnée personnelle), conservé localement.
enum DeviceIdentity {
    static var current: String {
        let key = "PadelBuddy.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
