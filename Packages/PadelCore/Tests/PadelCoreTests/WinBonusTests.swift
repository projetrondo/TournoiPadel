import Foundation
import Testing
@testable import PadelCore

@Suite("Bonus de victoire")
struct WinBonusTests {
    /// 4 joueurs, un match par tour, scores fixés.
    static func tournament(bonus: Int, _ matches: [(a: (Int, Int), b: (Int, Int), score: Score)]) -> Tournament {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: matches.count)
        t.settings.winBonus = bonus > 0 ? bonus : nil
        let ids = t.players.map(\.id)
        t.rounds = matches.enumerated().map { i, m in
            Round(index: i + 1, matches: [Match(
                court: 1, teamA: Team(ids[m.a.0], ids[m.a.1]), teamB: Team(ids[m.b.0], ids[m.b.1]),
                score: m.score, state: .completed
            )], resting: [])
        }
        t.status = .inProgress
        return t
    }

    @Test("Chaque victoire ajoute le bonus aux points du classement, pas aux scores")
    func bonusAddsToPoints() {
        let t = Self.tournament(bonus: 3, [((0, 1), (2, 3), Score(13, 11)), ((0, 2), (1, 3), Score(11, 13))])
        let stats = Standings.stats(for: t)
        let j0 = stats[t.players[0].id]!
        #expect(j0.pointsFor == 24)
        #expect(j0.bonus == 3)
        #expect(j0.points == 27)
        #expect(j0.pointDifference == 0, "la différence reste celle des scores")
        #expect(j0.averagePoints == 13.5)
    }

    @Test("Classement : points du classement = points marqués + bonus × victoires")
    func bonusInStandings() {
        let matches: [(a: (Int, Int), b: (Int, Int), score: Score)] = [
            ((0, 1), (2, 3), Score(13, 11)),
            ((0, 3), (1, 2), Score(13, 11)),
            ((1, 3), (0, 2), Score(4, 20)),
        ]
        // Points : J0 13+13+20=46 (3 V), J1 13+11+4=28 (1 V), J2 11+11+20=42 (1 V), J3 11+13+4=28 (1 V).
        let plain = Standings.compute(for: Self.tournament(bonus: 0, matches))
        let withBonus = Standings.compute(for: Self.tournament(bonus: 3, matches))
        #expect(plain.first?.stats.points == 46)
        #expect(withBonus.first?.stats.points == 55)
        #expect(withBonus.map(\.stats.points) == [55, 45, 31, 31])
    }

    @Test("Sans réglage (anciens tournois) : aucun bonus")
    func noBonusByDefault() throws {
        let t = TestSupport.tournament(format: .americano, players: 4, rounds: 1)
        #expect(t.settings.winBonusPoints == 0)
        var json = try JSONSerialization.jsonObject(with: TournamentCodec.encode(t)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings["winBonus"] = nil
        json["settings"] = settings
        let legacy = try TournamentCodec.decode(JSONSerialization.data(withJSONObject: json))
        #expect(legacy.settings.winBonusPoints == 0)
    }

    @Test("Réglé à la création ; modifiable seulement avant le lancement")
    func draftAndLifecycle() throws {
        let draft = TournamentDraft(name: "Jeudi", players: ["A", "B", "C", "D"].map { .init(name: $0) }, courts: 1, rounds: 3, winBonus: 2)
        var t = try draft.makeTournament(now: Date(), seed: 1)
        #expect(t.settings.winBonusPoints == 2)
        try t.updateWinBonus(3, now: Date())
        #expect(t.settings.winBonusPoints == 3)
        #expect(throws: LifecycleError.invalidScoring) { try t.updateWinBonus(5, now: Date()) }
        try t.start(now: Date())
        #expect(throws: LifecycleError.alreadyStarted) { try t.updateWinBonus(0, now: Date()) }
    }

    @Test("Mexicano : le bonus compte dans la composition des tours")
    func mexicanoUsesBonus() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, courts: 2, rounds: 3)
        t.settings.winBonus = 3
        try t.start(now: Date())
        // Tour 1 : terrain 1 gagné 13–11, terrain 2 gagné 12–12 impossible → 14–10.
        for (i, match) in t.rounds[0].matches.enumerated() {
            try t.validateScore(match.id, score: i == 0 ? Score(13, 11) : Score(10, 14), now: Date())
        }
        try t.generateNextRound(now: Date())
        let stats = Standings.stats(for: t)
        // Les 4 gagnants ont au moins 13 + 3 = 16 points : ils jouent ensemble sur le terrain 1.
        let winners = Set(stats.filter { $0.value.wins == 1 }.map(\.key))
        let court1 = Set(t.rounds[1].matches.first { $0.court == 1 }!.players)
        #expect(court1 == winners)
    }
}
