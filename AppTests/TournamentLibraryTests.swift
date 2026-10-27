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

    @Test("Mexicano : premier tour au lancement, tour suivant après les scores")
    func mexicano() async throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store)
        var draft = Self.validDraft()
        draft.format = .mexicano
        let tournament = try library.create(from: draft)
        try await library.start(id: tournament.id)
        #expect(library.tournament(id: tournament.id)?.rounds.count == 1)

        try library.modify(id: tournament.id) { t, _ in
            for i in t.rounds[0].matches.indices {
                t.rounds[0].matches[i].score = Score(15, 9)
                t.rounds[0].matches[i].state = .completed
            }
        }
        #expect(library.tournament(id: tournament.id)?.canGenerateNextRound == true)
        try library.modify(id: tournament.id) { t, date in try t.generateNextRound(now: date) }
        #expect(try store.loadAll().tournaments.first?.rounds.count == 2)
    }

    @Test("Une modification qui échoue ne change rien")
    func failedModification() throws {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        let tournament = try library.create(from: Self.validDraft())
        #expect(throws: LifecycleError.self) {
            try library.modify(id: tournament.id) { t, date in try t.generateNextRound(now: date) }
        }
        #expect(library.tournament(id: tournament.id) == tournament)
    }

    @Test("Sélecteur de points : aller-retour avec la règle de score")
    func scoringSelection() {
        for rule in [ScoringRule.fixedTotal(points: 24), .fixedTotal(points: 21), .fixedTotal(points: 20), .raceTo(points: 32), .raceTo(points: 11), .free] {
            #expect(ScoringSelection(rule: rule).rule == rule)
        }
        #expect(ScoringSelection(rule: .fixedTotal(points: 21)).preset == 21)
        var selection = ScoringSelection(rule: .fixedTotal(points: 20))
        #expect(selection.preset == nil && selection.customPoints == 20)
        selection.preset = 16
        #expect(selection.rule == .fixedTotal(points: 16))
    }

    @Test("Saisie, correction et clôture enregistrées immédiatement")
    func scoresAreSaved() async throws {
        let store = InMemoryTournamentStore()
        let library = TournamentLibrary(store: store)
        let created = try library.create(from: Self.validDraft())
        try await library.start(id: created.id)
        let matches = try #require(library.tournament(id: created.id)).orderedMatches

        try library.modify(id: created.id) { t, date in try t.validateScore(matches[0].id, score: Score(15, 9), now: date) }
        #expect(try store.loadAll().tournaments.first?.match(matches[0].id)?.score == Score(15, 9))

        // Double validation refusée, rien ne change.
        #expect(throws: ScoreEntryError.alreadyValidated) {
            try library.modify(id: created.id) { t, date in try t.validateScore(matches[0].id, score: Score(9, 15), now: date) }
        }
        #expect(try store.loadAll().tournaments.first?.match(matches[0].id)?.score == Score(15, 9))

        try library.modify(id: created.id) { t, date in try t.correctScore(matches[0].id, score: Score(13, 11), now: date) }
        for match in matches.dropFirst() {
            try library.modify(id: created.id) { t, date in try t.validateScore(match.id, score: Score(12, 12), now: date) }
        }
        try library.modify(id: created.id) { t, date in try t.finish(now: date) }
        let saved = try #require(store.loadAll().tournaments.first)
        #expect(saved.status == .finished)
        #expect(saved.match(matches[0].id)?.score == Score(13, 11))
        #expect(library.finishedTournaments.count == 1)
    }

    @Test("Les données de démonstration sont cohérentes")
    func demoData() throws {
        let demo = DemoData.tournaments()
        let standalone = demo.filter { $0.sessionID == nil }
        #expect(standalone.map(\.status).sorted { $0.rawValue < $1.rawValue } == [.draft, .finished, .inProgress])
        let session = try #require(DemoData.sessions().first)
        let inSession = demo.filter { $0.sessionID == session.id }
        #expect(inSession.count == 3 && inSession.allSatisfy { $0.status == .finished })
        #expect(inSession.allSatisfy { $0.players.allSatisfy { session.member($0.id) != nil } })
        for tournament in demo where tournament.status != .draft {
            try ScheduleValidator.validate(
                rounds: tournament.rounds,
                playerIDs: tournament.players.map(\.id),
                activeCourts: RoundPlanner(playerCount: tournament.players.count, declaredCourts: tournament.settings.courts).activeCourts
            )
        }
    }

    @Test("Tours libres : 16 joueurs, 4 terrains, 21 points, arrêt en plein tour")
    func openEndedEvening() async throws {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        let model = CreateTournamentModel()
        model.name = "Jeudi soir"
        for index in 1...16 {
            model.newPlayerName = "Joueur \(index)"
            model.addPlayer()
        }
        model.scoringSelection.preset = 21
        model.isOpenEnded = true
        #expect(model.courts == 4)
        #expect(model.draft.canCreate)

        let created = try library.create(from: model.draft)
        try await library.start(id: created.id)
        var tournament = try #require(library.tournament(id: created.id))
        #expect(tournament.rounds.count == 1)
        for match in tournament.rounds[0].matches {
            try library.modify(id: created.id) { t, date in try t.validateScore(match.id, score: Score(11, 10), now: date) }
        }
        try library.modify(id: created.id) { t, date in try t.generateNextRound(now: date) }
        tournament = try #require(library.tournament(id: created.id))
        let firstOfRoundTwo = try #require(tournament.rounds[1].matches.first)
        try library.modify(id: created.id) { t, date in try t.validateScore(firstOfRoundTwo.id, score: Score(13, 8), now: date) }

        try library.modify(id: created.id) { t, date in try t.finish(now: date, mode: .completedRoundsOnly) }
        let finished = try #require(library.tournament(id: created.id))
        #expect(finished.status == .finished)
        #expect(finished.rounds[1].isExcluded)
        #expect(finished.standings.allSatisfy { $0.stats.played == 1 })
    }

    @Test("L'Aigle affiché sur l'accueil suit le vrai numéro 1")
    func currentEagleFollowsStandings() async throws {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        let created = try library.create(from: Self.validDraft())
        try await library.start(id: created.id)
        #expect(library.tournament(id: created.id)?.currentEagles.isEmpty == true, "pas d'Aigle sans score")

        let match = try #require(library.tournament(id: created.id)?.orderedMatches.first)
        try library.modify(id: created.id) { t, date in try t.validateScore(match.id, score: Score(15, 9), now: date) }
        var tournament = try #require(library.tournament(id: created.id))
        #expect(Set(tournament.currentEagles.map(\.id)) == Set(match.teamA.players))

        try library.modify(id: created.id) { t, date in try t.correctScore(match.id, score: Score(9, 15), now: date) }
        tournament = try #require(library.tournament(id: created.id))
        #expect(Set(tournament.currentEagles.map(\.id)) == Set(match.teamB.players))
        #expect(tournament.currentEagles.map(\.id) == EagleInsights(tournament: tournament).eagles.map(\.id))
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
