import Foundation
import Observation
import PadelCore

/// Point d'entrée unique pour lire et modifier les tournois enregistrés sur l'appareil.
/// Règle : chaque modification est d'abord écrite sur disque, puis reflétée en mémoire.
/// Si l'écriture échoue, l'état affiché ne change pas et une erreur est présentée.
@MainActor
@Observable
final class TournamentLibrary {
    struct Failure: Identifiable {
        let id = UUID()
        let message: String
    }

    private(set) var tournaments: [Tournament] = []
    private(set) var hasLoaded = false
    private(set) var unreadableFileCount = 0
    var failure: Failure?

    @ObservationIgnored private let store: any TournamentStore
    @ObservationIgnored private let now: () -> Date
    /// Appelé après chaque modification locale enregistrée (pour la publication en ligne).
    @ObservationIgnored var onLocalChange: (@MainActor (Tournament) -> Void)?

    init(store: any TournamentStore, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    var activeTournaments: [Tournament] {
        tournaments.filter { $0.status != .finished }
    }

    var finishedTournaments: [Tournament] {
        tournaments.filter { $0.status == .finished }
    }

    func tournament(id: Tournament.ID) -> Tournament? {
        tournaments.first { $0.id == id }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        reload()
    }

    func reload() {
        do {
            let result = try store.loadAll()
            tournaments = result.tournaments
            unreadableFileCount = result.unreadableFiles.count
        } catch {
            failure = Failure(message: String(localized: "Impossible de lire les tournois enregistrés."))
        }
        hasLoaded = true
    }

    @discardableResult
    func create(from draft: TournamentDraft) throws -> Tournament {
        let tournament = try draft.makeTournament(now: now(), seed: UInt64.random(in: .min ... .max))
        try store.save(tournament)
        tournaments.insert(tournament, at: 0)
        return tournament
    }

    /// Enregistre une nouvelle version d'un tournoi existant (révision et date mises à jour).
    func update(_ tournament: Tournament) throws {
        guard !tournament.isReadOnly else { throw SyncError.readOnly }
        var updated = tournament
        updated.touch(at: now())
        try store.save(updated)
        tournaments.removeAll { $0.id == updated.id }
        tournaments.insert(updated, at: 0)
        onLocalChange?(updated)
    }

    /// Lance un tournoi : la génération du planning tourne hors du fil principal, puis le
    /// tournoi lancé est enregistré. En cas d'échec, le brouillon reste intact.
    func start(id: Tournament.ID) async throws {
        guard let draft = tournament(id: id) else { return }
        guard !draft.isReadOnly else { throw SyncError.readOnly }
        let date = now()
        let started = try await Task.detached(priority: .userInitiated) {
            var tournament = draft
            try tournament.start(now: date)
            return tournament
        }.value
        try store.save(started)
        tournaments.removeAll { $0.id == id }
        tournaments.insert(started, at: 0)
        onLocalChange?(started)
    }

    /// Applique une modification du moteur à un tournoi enregistré, puis sauvegarde.
    /// La modification travaille sur une copie : en cas d'erreur, rien ne change.
    func modify(id: Tournament.ID, _ change: (inout Tournament, Date) throws -> Void) throws {
        guard var tournament = tournament(id: id) else { return }
        guard !tournament.isReadOnly else { throw SyncError.readOnly }
        let revision = tournament.revision
        try change(&tournament, now())
        try store.save(tournament)
        tournaments.removeAll { $0.id == id }
        tournaments.insert(tournament, at: 0)
        if tournament.revision != revision { onLocalChange?(tournament) }
    }

    /// Enregistre une version reçue du serveur, ou des métadonnées de partage, sans la
    /// considérer comme une modification locale (pas de nouvelle publication).
    func saveSynced(_ tournament: Tournament) throws {
        try store.save(tournament)
        if let index = tournaments.firstIndex(where: { $0.id == tournament.id }) {
            tournaments[index] = tournament
        } else {
            tournaments.insert(tournament, at: 0)
        }
    }

    func delete(id: Tournament.ID) throws {
        try store.delete(id: id)
        tournaments.removeAll { $0.id == id }
    }

    /// Variante qui affiche l'erreur plutôt que de la propager (pour les actions de l'interface).
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            failure = Failure(message: String(localized: "L'enregistrement a échoué. Vos données précédentes sont intactes."))
        }
    }
}
