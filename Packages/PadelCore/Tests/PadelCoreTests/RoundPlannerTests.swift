import Testing
@testable import PadelCore

@Suite("Planification des tours")
struct RoundPlannerTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let players: Int
        let courts: Int
        let activeCourts: Int
        let resting: Int
        let unit: Int
        let recommended: Int

        var testDescription: String { "\(players) joueurs, \(courts) terrain(s)" }
    }

    // Recommandations calculées avec un match en 24 points (≈ 12 min) et une durée cible de 150 min.
    static let cases: [Case] = [
        Case(players: 4, courts: 1, activeCourts: 1, resting: 0, unit: 1, recommended: 3),
        Case(players: 5, courts: 1, activeCourts: 1, resting: 1, unit: 5, recommended: 5),
        Case(players: 6, courts: 1, activeCourts: 1, resting: 2, unit: 3, recommended: 9),
        Case(players: 7, courts: 1, activeCourts: 1, resting: 3, unit: 7, recommended: 7),
        Case(players: 8, courts: 2, activeCourts: 2, resting: 0, unit: 1, recommended: 7),
        Case(players: 8, courts: 1, activeCourts: 1, resting: 4, unit: 2, recommended: 12),
        Case(players: 9, courts: 2, activeCourts: 2, resting: 1, unit: 9, recommended: 9),
        Case(players: 10, courts: 2, activeCourts: 2, resting: 2, unit: 5, recommended: 10),
        Case(players: 12, courts: 3, activeCourts: 3, resting: 0, unit: 1, recommended: 11),
        Case(players: 16, courts: 4, activeCourts: 4, resting: 0, unit: 1, recommended: 12),
        Case(players: 16, courts: 8, activeCourts: 4, resting: 0, unit: 1, recommended: 12),
    ]

    @Test("Capacité et recommandation", arguments: cases)
    func capacity(_ c: Case) {
        let planner = RoundPlanner(playerCount: c.players, declaredCourts: c.courts)
        #expect(planner.activeCourts == c.activeCourts)
        #expect(planner.restingPerRound == c.resting)
        #expect(planner.equitableRoundUnit == c.unit)
        #expect(planner.recommendedRounds(scoring: .fixedTotal(points: 24)) == c.recommended)
    }

    @Test("Un nombre de tours équitable donne le même nombre de matchs à tous")
    func equitableMeansWholeMatches() {
        for players in 4...32 {
            for courts in 1...8 {
                let planner = RoundPlanner(playerCount: players, declaredCourts: courts)
                for rounds in planner.equitableRoundOptions {
                    let matches = planner.matchesPerPlayer(rounds: rounds)
                    #expect(matches == matches.rounded(), "\(players) joueurs, \(courts) terrains, \(rounds) tours")
                }
            }
        }
    }

    @Test("Équité détectée")
    func equity() {
        let planner = RoundPlanner(playerCount: 6, declaredCourts: 1)
        #expect(planner.isEquitable(rounds: 6))
        #expect(!planner.isEquitable(rounds: 4))
        #expect(planner.equitableRoundOptions.prefix(3) == [3, 6, 9])
    }

    @Test("Moins de 4 joueurs : aucun terrain utilisable")
    func tooFewPlayers() {
        let planner = RoundPlanner(playerCount: 3, declaredCourts: 2)
        #expect(planner.activeCourts == 0)
        #expect(planner.equitableRoundOptions.isEmpty)
        #expect(planner.recommendedRounds(scoring: .free) == nil)
    }
}
