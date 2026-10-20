import Foundation
import PadelCore
import Testing
@testable import PadelBuddy

@MainActor
@Suite("Bibliothèque de tournois")
struct TournamentLibraryTests {
    static func validDraft() -> TournamentDraft {
        TournamentDraft(
            name: "Jeudi",
            players: ["Léa", "Max", "Inès", "Tom"].map { .init(name: $0) },
            courts: 1,
            rounds: 3
        )
    }

    /// Stockage qui refuse toute écriture, pour vérifier qu'un échec ne modifie pas l'état affiché.
    final class FailingStore: TournamentStore, @unchecked Sendable {
        struct WriteError: Error {}
        func loadAll() throws -> TournamentLoadResult { TournamentLoadResult(tournaments: [], unreadableFiles: []) }
        func save(_ tournament: Tournament) throws { throw WriteError() }
        func delete(id: Tournament.ID) throws { throw WriteError() }
    }

    @Test("Créer un tournoi l'enregistre et l'affiche")
    func create() throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store)
        library.loadIfNeeded()

        let tournament = try library.create(from: Self.validDraft())

        #expect(library.tournaments.map(\.id) == [tournament.id])
        #expect(try store.loadAll().tournaments.map(\.id) == [tournament.id])
        #expect(library.activeTournaments.count == 1)
        #expect(library.finishedTournaments.isEmpty)
    }

    @Test("Un brouillon invalide n'est pas enregistré")
    func invalidDraft() {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        var draft = Self.validDraft()
        draft.players.removeLast()
        #expect(throws: SetupError.self) { try library.create(from: draft) }
        #expect(library.tournaments.isEmpty)
    }

    @Test("Un échec d'écriture ne modifie pas l'état affiché")
    func failingWrite() {
        let library = TournamentLibrary(store: FailingStore())
        library.loadIfNeeded()
        #expect(throws: FailingStore.WriteError.self) { try library.create(from: Self.validDraft()) }
        #expect(library.tournaments.isEmpty)
    }

    @Test("Mise à jour : révision incrémentée et sauvegardée")
    func update() throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store, now: { Date(timeIntervalSince1970: 5_000) })
        var tournament = try library.create(from: Self.validDraft())
        tournament.name = "Vendredi"
        try library.update(tournament)

        let saved = try #require(store.loadAll().tournaments.first)
        #expect(saved.name == "Vendredi")
        #expect(saved.revision == 2)
        #expect(library.tournament(id: tournament.id)?.name == "Vendredi")
    }

    @Test("Lancer un Americano enregistre le programme")
    func start() async throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store)
        let tournament = try library.create(from: Self.validDraft())
        try await library.start(id: tournament.id)

        let saved = try #require(store.loadAll().tournaments.first)
        #expect(saved.status == .inProgress)
        #expect(saved.rounds.count == 3)
        #expect(library.tournament(id: tournament.id)?.rounds.count == 3)
    }

    @Test("Suppression")
    func delete() throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store)
        let tournament = try library.create(from: Self.validDraft())
        try library.delete(id: tournament.id)
        #expect(library.tournaments.isEmpty)
        #expect(try store.loadAll().tournaments.isEmpty)
    }

    @Test("Le formulaire suit les recommandations tant qu'on ne les modifie pas")
    func createModelDefaults() {
        let model = CreateTournamentModel()
        model.name = "Test"
        for name in ["A", "B", "C", "D", "E", "F", "G", "H"] {
            model.newPlayerName = name
            model.addPlayer()
        }
        #expect(model.courts == 2)
        #expect(model.draft.rounds == 7)
        #expect(model.draft.canCreate)

        model.roundsOverride = 4
        #expect(model.draft.rounds == 4)
        model.newPlayerName = "   "
        #expect(!model.addPlayer())
        #expect(model.players.count == 8)
    }
}
