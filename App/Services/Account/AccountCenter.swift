import CryptoKit
import Foundation
import Observation
import PadelCore

/// Compte EAGLE (facultatif) et sauvegarde en ligne des sessions et tournois.
///
/// Sans compte, rien ne change : tout reste sur l'iPhone. Une fois connecté, chaque
/// modification est envoyée au serveur et les changements faits sur un autre appareil
/// sont récupérés. Les règles de fusion sont celles de `BackupRules` (une version plus
/// ancienne ne remplace jamais une version plus récente).
@MainActor
@Observable
final class AccountCenter {
    enum State: Equatable {
        case signedOut
        case signedIn(AccountInfo)
    }

    private(set) var state: State = .signedOut
    private(set) var providers: AuthProviders?
    private(set) var isWorking = false
    private(set) var isBackingUp = false
    private(set) var lastBackupAt: Date?
    var errorMessage: String?

    /// Faux si aucune adresse d'API n'est configurée : l'entrée « Compte » n'apparaît pas.
    let isAvailable: Bool

    @ObservationIgnored private let backend: (any EagleBackend)?
    @ObservationIgnored private let library: TournamentLibrary
    @ObservationIgnored private let sessions: SessionLibrary
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let saveRefreshToken: @Sendable (String?) -> Void
    @ObservationIgnored private var ledger: BackupLedger?
    @ObservationIgnored private var pendingBackup: Task<Void, Never>?
    @ObservationIgnored private var googleVerifier: String?
    @ObservationIgnored private var appleNonce: String?

    private static let ledgerKey = "eagle.backup.ledger"

    init(
        backend: (any EagleBackend)?,
        library: TournamentLibrary,
        sessions: SessionLibrary,
        defaults: UserDefaults = .standard,
        storedRefreshToken: String? = nil,
        saveRefreshToken: @escaping @Sendable (String?) -> Void = { _ in }
    ) {
        self.backend = backend
        self.library = library
        self.sessions = sessions
        self.defaults = defaults
        self.saveRefreshToken = saveRefreshToken
        isAvailable = backend != nil
        ledger = (defaults.data(forKey: Self.ledgerKey)).flatMap { try? JSONDecoder().decode(BackupLedger.self, from: $0) }
        lastBackupAt = ledger?.lastBackupAt

        library.onBackupNeeded = { [weak self] in self?.scheduleBackup() }
        library.onLocalDelete = { [weak self] tournament in
            self?.recordDeletion(BackupKey(.tournament, tournament.id), revision: tournament.revision)
        }
        sessions.onLocalChange = { [weak self] _ in self?.scheduleBackup() }
        sessions.onLocalDelete = { [weak self] session in
            self?.recordDeletion(BackupKey(.session, session.id), revision: session.revision)
        }

        if let backend {
            Task {
                await backend.observeRefreshToken(saveRefreshToken)
                guard let storedRefreshToken else { return }
                await backend.resume(refreshToken: storedRefreshToken)
                await self.restoreSession()
            }
        }
    }

    var account: AccountInfo? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    // MARK: - Connexion

    func loadProviders() async {
        guard let backend, providers == nil else { return }
        providers = try? await backend.providers()
    }

    /// Google, étape 1 : adresse à ouvrir dans le navigateur de connexion.
    func googleSignInURL() async -> URL? {
        guard let backend else { return nil }
        let verifier = Self.randomToken()
        googleVerifier = verifier
        return await perform { try await backend.startGoogleSignIn(codeChallenge: Self.challenge(for: verifier)) }
    }

    /// Google, étape 2 : retour du navigateur (`eagle://auth?handoff=…` ou `?error=…`).
    func completeGoogleSignIn(callback: URL) async {
        guard let backend, let verifier = googleVerifier else { return }
        googleVerifier = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            if error != "cancelled" { errorMessage = error }
            return
        }
        guard let handoff = items.first(where: { $0.name == "handoff" })?.value else { return }
        if let account = await perform({ try await backend.redeemGoogle(handoff: handoff, codeVerifier: verifier) }) {
            await signedIn(account)
        }
    }

    /// Apple, étape 1 : condensé du nonce à placer dans la demande d'autorisation.
    func appleNonceHash() -> String {
        let nonce = Self.randomToken()
        appleNonce = nonce
        return Self.sha256Hex(nonce)
    }

    /// Apple, étape 2 : jeton d'identité reçu d'Apple.
    func completeAppleSignIn(identityToken: Data?, givenName: String?) async {
        guard let backend, let nonce = appleNonce, let identityToken,
              let token = String(data: identityToken, encoding: .utf8) else {
            errorMessage = String(localized: "Apple n'a pas transmis votre identité. Réessayez.")
            return
        }
        appleNonce = nil
        if let account = await perform({ try await backend.signInWithApple(identityToken: token, nonce: nonce, name: givenName) }) {
            await signedIn(account)
        }
    }

    func signOut() async {
        guard let backend else { return }
        isWorking = true
        await backend.signOut()
        isWorking = false
        resetAccountState()
    }

    /// Supprime le compte et sa sauvegarde en ligne ; les données de l'iPhone restent.
    func deleteAccount() async {
        guard let backend else { return }
        if await perform({ try await backend.deleteAccount() }) != nil {
            resetAccountState()
        }
    }

    private func signedIn(_ account: AccountInfo) async {
        if ledger?.accountID != account.id {
            ledger = BackupLedger(accountID: account.id)
            persistLedger()
        }
        state = .signedIn(account)
        await backUp()
    }

    private func restoreSession() async {
        guard let backend else { return }
        do {
            let account = try await backend.me()
            await signedIn(account)
        } catch BackendError.signedOut {
            resetAccountState()
        } catch {
            // Hors ligne au lancement : on reste connecté, la sauvegarde attendra le réseau.
            if let ledger { state = .signedIn(AccountInfo(id: ledger.accountID, displayName: nil, email: nil, providers: [])) }
        }
    }

    private func resetAccountState() {
        state = .signedOut
        ledger = nil
        lastBackupAt = nil
        defaults.removeObject(forKey: Self.ledgerKey)
        saveRefreshToken(nil)
    }

    /// Exécute un appel réseau en affichant l'attente et l'erreur éventuelle.
    private func perform<T>(_ call: () async throws -> T) async -> T? {
        isWorking = true
        defer { isWorking = false }
        do {
            return try await call()
        } catch let error as BackendError {
            if error != .cancelled { errorMessage = error.message }
        } catch {
            errorMessage = BackendError.unreachable.message
        }
        return nil
    }

    // MARK: - Sauvegarde

    /// Regroupe les modifications rapprochées (saisie de scores) en une seule sauvegarde.
    func scheduleBackup(after delay: Duration = .seconds(2)) {
        guard account != nil else { return }
        pendingBackup?.cancel()
        pendingBackup = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.backUp()
        }
    }

    private func recordDeletion(_ key: BackupKey, revision: Int) {
        guard ledger != nil else { return }
        ledger?.recordLocalDeletion(key, revision: revision)
        persistLedger()
        scheduleBackup()
    }

    /// Envoie les suppressions et les modifications, puis récupère celles des autres appareils.
    func backUp() async {
        guard let backend, account != nil, !isBackingUp, ledger != nil else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            try await sendDeletions(backend)
            try await pullChanges(backend)
            try await pushChanges(backend)
            ledger?.lastBackupAt = Date()
            lastBackupAt = ledger?.lastBackupAt
            persistLedger()
        } catch BackendError.signedOut {
            resetAccountState()
            errorMessage = BackendError.signedOut.message
        } catch {
            // Hors ligne : on réessaiera à la prochaine modification ou au prochain lancement.
            persistLedger()
        }
    }

    private func sendDeletions(_ backend: any EagleBackend) async throws {
        for (path, revision) in ledger?.pendingDeletions ?? [:] {
            guard let key = Self.key(path) else { continue }
            try await backend.delete(key, revision: revision)
            ledger?.forget(key)
        }
    }

    private func pullChanges(_ backend: any EagleBackend) async throws {
        var page: ChangePage
        repeat {
            page = try await backend.changes(since: ledger?.cursor ?? 0)
            for document in page.documents {
                try apply(document)
            }
            ledger?.cursor = page.cursor
            persistLedger()
        } while page.hasMore
    }

    private func pushChanges(_ backend: any EagleBackend) async throws {
        for session in sessions.sessions {
            try await push(BackupKey(.session, session.id), revision: session.revision, version: Self.version(session), payload: SessionCodec.encode(session), backend)
        }
        // Les tournois suivis en lecture seule appartiennent à leur organisateur : pas sauvegardés ici.
        for tournament in library.tournaments where !tournament.isReadOnly {
            try await push(BackupKey(.tournament, tournament.id), revision: tournament.revision, version: Self.version(tournament), payload: TournamentCodec.encode(tournament), backend)
        }
    }

    private func push(_ key: BackupKey, revision: Int, version: DocumentVersion, payload: Data, _ backend: any EagleBackend) async throws {
        guard ledger?.needsUpload(key, revision: revision) ?? false else { return }
        switch try await backend.save(key, revision: revision, payload: payload) {
        case .saved:
            ledger?.confirm(key, revision: revision)
        case .conflict(let server):
            switch BackupRules.rejected(local: version, server: try Self.version(of: server)) {
            case .adoptServer:
                try apply(server, force: true)
            case .resend(let newRevision):
                try await resend(key, revision: newRevision, backend)
            }
        }
    }

    /// La version locale est la plus récente : elle repart avec une révision supérieure.
    private func resend(_ key: BackupKey, revision: Int, _ backend: any EagleBackend) async throws {
        let payload: Data
        switch key.kind {
        case .session:
            guard var session = sessions.session(id: key.id) else { return }
            session.revision = revision
            try sessions.saveSynced(session)
            payload = try SessionCodec.encode(session)
        case .tournament:
            guard var tournament = library.tournament(id: key.id) else { return }
            tournament.revision = revision
            try library.saveSynced(tournament)
            payload = try TournamentCodec.encode(tournament)
        }
        if case .saved = try await backend.save(key, revision: revision, payload: payload) {
            ledger?.confirm(key, revision: revision)
        }
    }

    /// Intègre un document du serveur selon les règles de sauvegarde.
    private func apply(_ document: RemoteDocument, force: Bool = false) throws {
        let remote = try Self.version(of: document)
        let local: DocumentVersion?
        switch document.key.kind {
        case .session: local = sessions.session(id: document.key.id).map { Self.version($0) }
        case .tournament: local = library.tournament(id: document.key.id).map { Self.version($0) }
        }
        let decision: BackupRules.Incoming = force ? (document.isDeleted ? .deleteLocal : .adopt) : BackupRules.incoming(remote: remote, local: local)
        switch decision {
        case .adopt:
            guard let payload = document.payload else { return }
            switch document.key.kind {
            case .session: try sessions.saveSynced(SessionCodec.decode(payload))
            case .tournament: try library.saveSynced(TournamentCodec.decode(payload))
            }
            ledger?.confirm(document.key, revision: document.revision)
        case .deleteLocal:
            switch document.key.kind {
            case .session: try sessions.deleteSynced(id: document.key.id)
            case .tournament: try library.deleteSynced(id: document.key.id)
            }
            ledger?.forget(document.key)
        case .keepLocal:
            // La version locale est plus récente : elle sera envoyée.
            if document.isDeleted { ledger?.forget(document.key) }
        }
    }

    private func persistLedger() {
        guard let ledger, let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.ledgerKey)
    }

    // MARK: - Outils

    private static func version(_ session: PlaySession) -> DocumentVersion {
        DocumentVersion(revision: session.revision, updatedAt: session.updatedAt)
    }

    private static func version(_ tournament: Tournament) -> DocumentVersion {
        DocumentVersion(revision: tournament.revision, updatedAt: tournament.updatedAt)
    }

    private static func version(of document: RemoteDocument) throws -> DocumentVersion {
        guard let payload = document.payload else {
            return DocumentVersion(revision: document.revision, updatedAt: nil, isDeleted: true)
        }
        let updatedAt: Date
        switch document.key.kind {
        case .session: updatedAt = try SessionCodec.decode(payload).updatedAt
        case .tournament: updatedAt = try TournamentCodec.decode(payload).updatedAt
        }
        return DocumentVersion(revision: document.revision, updatedAt: updatedAt)
    }

    private static func key(_ path: String) -> BackupKey? {
        let parts = path.split(separator: "/")
        guard parts.count == 2, let kind = BackupKind(rawValue: String(parts[0])), let id = UUID(uuidString: String(parts[1])) else { return nil }
        return BackupKey(kind, id)
    }

    /// 32 octets aléatoires en base64url (secret PKCE ou nonce Apple).
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
