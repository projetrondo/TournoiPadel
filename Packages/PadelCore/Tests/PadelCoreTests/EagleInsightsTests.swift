import Foundation
import Testing
@testable import PadelCore

@Suite("L'Aigle : statut du numéro 1")
struct EagleInsightsTests {
    /// 4 joueurs, tours construits à la main (un match par tour).
    static func tournament(_ matches: [(a: (Int, Int), b: (Int, Int), score: Score?)]) -> Tournament {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: max(1, matches.count))
        let ids = t.players.map(\.id)
        t.rounds = matches.enumerated().map { i, m in
            Round(index: i + 1, matches: [Match(
                court: 1,
                teamA: Team(ids[m.a.0], ids[m.a.1]),
                teamB: Team(ids[m.b.0], ids[m.b.1]),
                score: m.score,
                state: m.score == nil ? .scheduled : .completed
            )], resting: [])
        }
        t.status = .inProgress
        return t
    }

    @Test("Pas d'Aigle tant qu'aucun score n'est validé")
    func noEagleWithoutResults() {
        let t = Self.tournament([((0, 1), (2, 3), nil)])
        let insights = EagleInsights(tournament: t)
        #expect(!insights.hasResults)
        #expect(insights.eagles.isEmpty)
        #expect(insights.standings.allSatisfy { insights.tier(of: $0) == .standard })
    }

    @Test("L'Aigle est toujours le numéro 1 du classement réel")
    func eagleIsRankOne() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9)), ((0, 2), (1, 3), Score(10, 14))])
        // J0 25, J1 29, J2 19, J3 23 → J1 premier.
        let insights = EagleInsights(tournament: t)
        #expect(insights.standings == Standings.compute(for: t), "même classement que l'existant")
        #expect(insights.eagles.map(\.id) == [t.players[1].id])
        let tiers = insights.standings.map { insights.tier(of: $0) }
        #expect(tiers == [.eagle, .silver, .bronze, .standard])
    }

    @Test("Le badge passe au nouveau numéro 1 après une correction")
    func eagleFollowsCorrection() {
        var t = Self.tournament([((0, 1), (2, 3), Score(15, 9))])
        #expect(EagleInsights(tournament: t).eagles.map(\.id) == [t.players[0].id, t.players[1].id])
        t.rounds[0].matches[0].score = Score(9, 15)
        #expect(EagleInsights(tournament: t).eagles.map(\.id) == [t.players[2].id, t.players[3].id])
    }

    @Test("Ex aequo en tête : plusieurs Aigles, le suivant reste bronze selon son rang")
    func tiedEagles() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9))])
        let insights = EagleInsights(tournament: t)
        #expect(insights.eagles.count == 2)
        #expect(insights.standings.map(\.rank) == [1, 1, 3, 3])
        #expect(insights.standings.map { insights.tier(of: $0) } == [.eagle, .eagle, .bronze, .bronze])
    }

    @Test("Écart avec l'Aigle")
    func pointsBehind() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9)), ((0, 2), (1, 3), Score(10, 14))])
        let insights = EagleInsights(tournament: t)
        let byID = Dictionary(uniqueKeysWithValues: insights.standings.map { ($0.id, $0) })
        #expect(insights.pointsBehindEagle(byID[t.players[1].id]!) == nil)
        #expect(insights.pointsBehindEagle(byID[t.players[0].id]!) == 4)
        #expect(insights.pointsBehindEagle(byID[t.players[2].id]!) == 10)
    }

    @Test("Progression depuis le tour précédent")
    func movement() {
        // Tour 1 : J0+J1 en tête. Tour 2 : J1+J3 gagnent largement.
        let t = Self.tournament([((0, 1), (2, 3), Score(13, 11)), ((0, 2), (1, 3), Score(4, 20))])
        let insights = EagleInsights(tournament: t)
        // Avant : J0 1=, J1 1=, J2 3=, J3 3=. Après : J1 33, J3 31, J0 17, J2 15.
        #expect(insights.movement[t.players[3].id] == 1)   // 3 → 2
        #expect(insights.movement[t.players[1].id] == 0)   // 1 → 1
        #expect(insights.movement[t.players[0].id] == -2)  // 1 → 3
        #expect(insights.movement[t.players[2].id] == -1)  // 3 → 4
    }

    @Test("Pas d'évolution affichée après un seul tour")
    func noMovementAfterFirstRound() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9))])
        #expect(EagleInsights(tournament: t).movement.isEmpty)
    }

    @Test("Défense de la couronne : tours consécutifs en tête")
    func crownStreak() {
        // J0 en tête après chacun des 3 tours.
        let t = Self.tournament([
            ((0, 1), (2, 3), Score(15, 9)),
            ((0, 2), (1, 3), Score(14, 10)),
            ((0, 3), (1, 2), Score(16, 8)),
        ])
        let insights = EagleInsights(tournament: t)
        #expect(insights.eagles.map(\.id) == [t.players[0].id])
        #expect(insights.crownStreak[t.players[0].id] == 3)
    }

    @Test("Nouvel Aigle : la série repart à 1")
    func newEagleStreak() {
        let t = Self.tournament([((0, 1), (2, 3), Score(13, 11)), ((0, 2), (1, 3), Score(4, 20))])
        let insights = EagleInsights(tournament: t)
        #expect(insights.eagles.map(\.id) == [t.players[1].id])
        #expect(insights.crownStreak[t.players[1].id] == 2, "J1 était déjà co-premier après le tour 1")
        let t2 = Self.tournament([((0, 1), (2, 3), Score(15, 9)), ((2, 3), (0, 1), Score(24, 0))])
        let i2 = EagleInsights(tournament: t2)
        #expect(i2.eagles.allSatisfy { i2.crownStreak[$0.id] == 1 })
    }

    @Test("Les tours exclus à la clôture ne comptent pas")
    func excludedRoundsIgnored() {
        var t = Self.tournament([((0, 1), (2, 3), Score(15, 9)), ((2, 3), (0, 1), Score(24, 0))])
        t.rounds[1].excluded = true
        let insights = EagleInsights(tournament: t)
        #expect(insights.eagles.map(\.id) == [t.players[0].id, t.players[1].id])
        #expect(insights.movement.isEmpty)
    }
}
