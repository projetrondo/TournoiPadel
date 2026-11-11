import Foundation
import Testing
@testable import PadelCore

@Suite("Bonus de terrain (Mexicano)")
struct CourtBonusTests {
    /// Mexicano lancé, tous les matchs des `rounds` premiers tours joués 13–11.
    static func played(players: Int, courts: Int, from start: Int?, rounds: Int) throws -> Tournament {
        var t = TestSupport.tournament(format: .mexicano, players: players, courts: courts, rounds: 6)
        t.settings.courtBonusFromRound = start
        try t.start(now: Date())
        for r in 0..<rounds {
            for match in t.rounds[r].matches {
                try t.validateScore(match.id, score: Score(13, 11), now: Date())
            }
            if r + 1 < rounds { try t.generateNextRound(now: Date()) }
        }
        return t
    }

    @Test("4 terrains : terrain 1 = 4 pts, 2 = 3 pts, 3 = 2 pts, 4 = 1 pt, pour les gagnants seulement")
    func fourCourts() throws {
        let t = try Self.played(players: 16, courts: 4, from: 1, rounds: 1)
        let stats = Standings.stats(for: t)
        for match in t.rounds[0].matches {
            // Tous les matchs sont gagnés 13–11 par l'équipe de gauche.
            for player in match.teamA.players {
                #expect(stats[player]?.courtBonus == 5 - match.court)
                #expect(stats[player]?.points == stats[player]!.pointsFor + 5 - match.court)
            }
            for player in match.teamB.players {
                #expect(stats[player]?.courtBonus == 0, "les perdants ne reçoivent rien")
            }
        }
    }

    @Test("Fonctionne pour tout nombre de terrains : N terrains, le terrain 1 vaut N")
    func anyCourtCount() {
        for courts in 1...8 {
            let t = TestSupport.tournament(format: .mexicano, players: courts * 4, courts: courts, rounds: 3)
            #expect((1...courts).map { t.courtBonus(forCourt: $0) } == Array((1...courts).reversed()))
        }
    }

    @Test("Seulement à partir du tour choisi")
    func startsAtChosenRound() throws {
        let t = try Self.played(players: 8, courts: 2, from: 3, rounds: 3)
        let stats = Standings.stats(for: t)
        let roundThree = t.rounds[2]
        for player in t.players.map(\.id) {
            let match = roundThree.matches.first { $0.players.contains(player) }!
            let expected = match.teamA.contains(player) ? 3 - match.court : 0
            #expect(stats[player]?.courtBonus == expected, "tours 1 et 2 : pas de bonus")
        }
        #expect(!t.courtBonusApplies(toRound: 2))
        #expect(t.courtBonusApplies(toRound: 3))
    }

    @Test("Désactivé par défaut, et sans effet en Americano")
    func onlyMexicano() throws {
        let draft = TournamentDraft(name: "Jeudi", format: .americano, players: (0..<8).map { .init(name: "J\($0)") }, courts: 2, rounds: 3, courtBonusFromRound: 1)
        let americano = try draft.makeTournament(now: Date(), seed: 1)
        #expect(americano.settings.courtBonusFromRound == nil)
        var mexicanoDraft = draft
        mexicanoDraft.format = .mexicano
        #expect(try mexicanoDraft.makeTournament(now: Date(), seed: 1).settings.courtBonusFromRound == 1)

        let off = try Self.played(players: 8, courts: 2, from: nil, rounds: 2)
        #expect(Standings.stats(for: off).values.allSatisfy { $0.courtBonus == 0 })
    }

    @Test("Se cumule avec le bonus de victoire ; rien sur un match nul ; compte pour le tour suivant")
    func combinesAndDrivesPairing() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, courts: 2, rounds: 4)
        t.settings.courtBonusFromRound = 1
        t.settings.winBonus = 3
        try t.start(now: Date())
        let courtOne = t.rounds[0].matches.first { $0.court == 1 }!
        let courtTwo = t.rounds[0].matches.first { $0.court == 2 }!
        try t.validateScore(courtOne.id, score: Score(13, 11), now: Date())
        try t.validateScore(courtTwo.id, score: Score(12, 12), now: Date())
        let stats = Standings.stats(for: t)
        for player in courtOne.teamA.players {
            #expect(stats[player]?.bonus == 3 + 2, "victoire +3, terrain 1 +2")
        }
        for player in courtOne.teamB.players + courtTwo.players {
            #expect(stats[player]?.bonus == 0, "défaite ou nul : aucun bonus")
        }
        try t.generateNextRound(now: Date())
        let nextCourtOne = Set(t.rounds[1].matches.first { $0.court == 1 }!.players)
        #expect(Set(courtOne.teamA.players).isSubset(of: nextCourtOne), "les gagnants bonifiés restent sur le terrain 1")
    }

    @Test("Réglage modifiable seulement avant le lancement")
    func lifecycle() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        try t.updateCourtBonus(fromRound: 2, now: Date())
        #expect(t.settings.courtBonusFromRound == 2)
        #expect(throws: LifecycleError.invalidScoring) { try t.updateCourtBonus(fromRound: 9, now: Date()) }
        try t.start(now: Date())
        #expect(throws: LifecycleError.alreadyStarted) { try t.updateCourtBonus(fromRound: nil, now: Date()) }
    }
}
