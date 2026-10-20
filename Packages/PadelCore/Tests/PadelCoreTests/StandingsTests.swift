import Foundation
import Testing
@testable import PadelCore

@Suite("Classement individuel")
struct StandingsTests {
    /// 4 joueurs, matchs construits à la main.
    static func tournament(_ matches: [(a: (Int, Int), b: (Int, Int), score: Score?)]) -> Tournament {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: matches.count)
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

    @Test("Chaque joueur reçoit les points de son équipe (15–9 en 24)")
    func individualPoints() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9))])
        let stats = Standings.stats(for: t)
        let ids = t.players.map(\.id)
        #expect(stats[ids[0]]?.pointsFor == 15)
        #expect(stats[ids[1]]?.pointsFor == 15)
        #expect(stats[ids[2]]?.pointsFor == 9)
        #expect(stats[ids[3]]?.pointsFor == 9)
        #expect(stats[ids[0]]?.pointsAgainst == 9)
        #expect(stats[ids[2]]?.pointDifference == -6)
        #expect(stats[ids[0]]?.wins == 1)
        #expect(stats[ids[3]]?.losses == 1)
        #expect(stats[ids[0]]?.played == 1)
    }

    @Test("Les matchs non terminés ne comptent pas")
    func ignoresUnfinished() {
        let t = Self.tournament([((0, 1), (2, 3), Score(15, 9)), ((0, 2), (1, 3), nil)])
        let stats = Standings.stats(for: t)
        #expect(stats[t.players[0].id]?.played == 1)
        #expect(stats[t.players[2].id]?.pointsFor == 9)
    }

    @Test("Égalité 12–12 : match nul")
    func draw() {
        let t = Self.tournament([((0, 1), (2, 3), Score(12, 12))])
        let stats = Standings.stats(for: t)
        #expect(stats[t.players[0].id]?.draws == 1)
        #expect(stats[t.players[0].id]?.wins == 0)
        #expect(stats[t.players[0].id]?.losses == 0)
    }

    @Test("Ordre : points, puis victoires, puis différence")
    func ordering() {
        // Tour 1 : 0+1 battent 2+3 15–9. Tour 2 : 0+2 battent 1+3 13–11. Tour 3 : 1+2 battent 0+3 14–10.
        let t = Self.tournament([
            ((0, 1), (2, 3), Score(15, 9)),
            ((0, 2), (1, 3), Score(13, 11)),
            ((1, 2), (0, 3), Score(14, 10)),
        ])
        // Points : J0 38, J1 40, J2 36, J3 30.
        let rows = Standings.compute(for: t)
        #expect(rows.map { t.player($0.id)!.name } == ["J1", "J0", "J2", "J3"])
        #expect(rows.map(\.rank) == [1, 2, 3, 4])
        #expect(rows.allSatisfy { !$0.isTied })
    }

    @Test("Égalité parfaite (points, victoires, différence) : ex aequo")
    func winsBreakTies() {
        // J0 et J2 : 24 points chacun. J0 : 1 victoire (16–8) + 1 défaite (8–16) ; J2 idem ;
        // on construit un écart de victoires avec un nul.
        let t = Self.tournament([
            ((0, 1), (2, 3), Score(13, 11)),  // J0 13 V, J2 11 D
            ((0, 3), (1, 2), Score(11, 13)),  // J0 11 D, J2 13 V
            ((0, 2), (1, 3), Score(12, 12)),  // nul
            ((0, 1), (2, 3), Score(10, 14)),  // J0 10 D, J2 14 V
            ((2, 1), (0, 3), Score(10, 14)),  // J0 14 V, J2 10 D
        ])
        // J0 : 13+11+12+10+14 = 60, 2 V. J2 : 11+13+12+14+10 = 60, 2 V. Égalité totale → ex aequo.
        let rows = Standings.compute(for: t)
        let r0 = rows.first { $0.id == t.players[0].id }!
        let r2 = rows.first { $0.id == t.players[2].id }!
        #expect(r0.stats.pointsFor == r2.stats.pointsFor)
        #expect(r0.rank == r2.rank)
        #expect(r0.isTied && r2.isTied)
    }

    @Test("Départage par victoires puis par différence")
    func tieBreakRules() {
        func stats(_ points: Int, wins: Int, diff: Int) -> PlayerStats {
            var s = PlayerStats(playerID: UUID())
            s.pointsFor = points
            s.pointsAgainst = points - diff
            s.wins = wins
            return s
        }
        #expect(Standings.ranksAhead(stats(40, wins: 1, diff: 0), stats(39, wins: 3, diff: 10)))
        #expect(Standings.ranksAhead(stats(40, wins: 2, diff: -5), stats(40, wins: 1, diff: 10)))
        #expect(Standings.ranksAhead(stats(40, wins: 2, diff: 3), stats(40, wins: 2, diff: 1)))
        #expect(Standings.isTie(stats(40, wins: 2, diff: 3), stats(40, wins: 2, diff: 3)))
    }

    @Test("Ex aequo : même position, la suivante est sautée (1, 2, 2, 4)")
    func sharedRanks() {
        let t = Self.tournament([((0, 1), (2, 3), Score(12, 12)), ((0, 2), (1, 3), Score(16, 8))])
        // J0 28 (1 V), J1 20, J2 28 (1 V), J3 20 → J0 et J2 à égalité, J1 et J3 à égalité.
        let rows = Standings.compute(for: t)
        #expect(rows.map(\.rank) == [1, 1, 3, 3])
        #expect(rows.map { t.player($0.id)!.name } == ["J0", "J2", "J1", "J3"])
    }

    @Test("Une correction de score met le classement à jour")
    func correctionUpdatesStandings() {
        var t = Self.tournament([((0, 1), (2, 3), Score(15, 9))])
        #expect(t.standings.first?.id == t.players[0].id)
        t.rounds[0].matches[0].score = Score(9, 15)
        #expect(t.standings.first?.id == t.players[2].id)
    }

    @Test("Pauses comptées")
    func rests() {
        var t = TestSupport.tournament(format: .americano, players: 5, rounds: 5)
        try? t.start(now: Date())
        let stats = Standings.stats(for: t)
        #expect(stats.values.allSatisfy { $0.rests == 1 })
    }
}
