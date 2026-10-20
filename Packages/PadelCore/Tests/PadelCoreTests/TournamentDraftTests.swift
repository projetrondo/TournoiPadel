import Foundation
import Testing
@testable import PadelCore

@Suite("Création d'un tournoi")
struct TournamentDraftTests {
    static func draft(players count: Int, courts: Int = 1, rounds: Int? = nil) -> TournamentDraft {
        var draft = TournamentDraft(name: "Padel du jeudi", courts: courts)
        draft.players = (1...max(count, 1)).prefix(count).map { .init(name: "Joueur \($0)") }
        draft.rounds = rounds ?? draft.planner.recommendedRounds(scoring: draft.scoring) ?? 1
        return draft
    }

    @Test("Un tournoi valide se crée sans erreur", arguments: [4, 5, 6, 7, 8, 10, 12, 16])
    func validDraft(players: Int) throws {
        let draft = Self.draft(players: players, courts: max(1, players / 4))
        #expect(draft.errors.isEmpty)
        let tournament = try draft.makeTournament(now: Date(timeIntervalSince1970: 0), seed: 42)
        #expect(tournament.players.count == players)
        #expect(tournament.status == .draft)
        #expect(tournament.rounds.isEmpty)
        #expect(tournament.settings.plannedRounds == draft.rounds)
    }

    @Test("Minimum 4 joueurs")
    func minimumPlayers() {
        let draft = Self.draft(players: 3, rounds: 3)
        #expect(draft.errors.contains(.notEnoughPlayers(minimum: 4)))
        #expect(!draft.canCreate)
        #expect(throws: SetupError.self) {
            try draft.makeTournament(now: Date(), seed: 1)
        }
    }

    @Test("Nom obligatoire")
    func missingName() {
        var draft = Self.draft(players: 4)
        draft.name = "   "
        #expect(draft.errors == [.missingName])
    }

    @Test("Noms en double détectés sans tenir compte de la casse ni des accents")
    func duplicates() {
        var draft = Self.draft(players: 4)
        draft.players[1].name = "Léa"
        draft.players[3].name = " lea "
        #expect(draft.errors.contains(.duplicatePlayerNames(["Léa"])))
    }

    @Test("Nom de joueur vide refusé")
    func emptyPlayerName() {
        var draft = Self.draft(players: 4)
        draft.players[2].name = " "
        #expect(draft.errors.contains(.emptyPlayerName))
    }

    @Test("Avertissements : terrains en trop, pauses, tours non équitables")
    func warnings() {
        let draft = Self.draft(players: 6, courts: 3, rounds: 4)
        #expect(draft.errors.isEmpty)
        #expect(draft.warnings.contains(.unusedCourts(usable: 1)))
        #expect(draft.warnings.contains(.restingPlayers(perRound: 2)))
        #expect(draft.warnings.contains(.unequalMatchCount(suggestions: [3, 6])))
    }

    @Test("Mexicano par niveau : tous les niveaux sont requis")
    func levelsRequired() {
        var draft = Self.draft(players: 4)
        draft.format = .mexicano
        draft.mexicanoFirstRound = .byLevel
        #expect(draft.errors.contains(.missingLevels))
        for index in draft.players.indices { draft.players[index].level = 3 }
        #expect(draft.errors.isEmpty)
    }

    @Test("Points personnalisés hors limites refusés")
    func invalidPoints() {
        var draft = Self.draft(players: 4)
        draft.scoring = .fixedTotal(points: 2)
        #expect(draft.errors.contains(.invalidPoints(ScoringRule.pointsRange)))
    }

    @Test("Les noms sont nettoyés à la création")
    func trimsNames() throws {
        var draft = Self.draft(players: 4)
        draft.name = "  Tournoi  "
        draft.players[0].name = "  Max "
        let tournament = try draft.makeTournament(now: Date(), seed: 1)
        #expect(tournament.name == "Tournoi")
        #expect(tournament.players[0].name == "Max")
    }
}
