import Foundation
import Testing
@testable import PadelCore

/// Cas réel : 16 joueurs, 4 terrains, matchs en 21 points, environ 2 heures de jeu,
/// nombre de tours inconnu à l'avance ; on arrête quand le temps est écoulé.
@Suite("Tours libres et arrêt à tout moment")
struct OpenEndedTests {
    static func openTournament(_ format: TournamentFormat, players: Int = 16, courts: Int = 4, seed: UInt64 = 21) throws -> Tournament {
        var draft = TournamentDraft(name: "Jeudi soir", format: format, courts: courts, scoring: .fixedTotal(points: 21), isOpenEnded: true)
        draft.players = (0..<players).map { .init(name: "J\($0)") }
        #expect(draft.errors.isEmpty)
        var t = try draft.makeTournament(now: Date(timeIntervalSince1970: 0), seed: seed)
        try t.start(now: Date())
        return t
    }

    /// Score en 21 points (jamais de nul) : l'équipe la plus forte gagne.
    static func score21(_ t: Tournament) -> (Match) -> Score {
        let index = Dictionary(uniqueKeysWithValues: t.players.enumerated().map { ($1.id, $0) })
        return { match in
            let a = match.teamA.players.map { index[$0]! }.reduce(0, +)
            let b = match.teamB.players.map { index[$0]! }.reduce(0, +)
            return a <= b ? Score(12, 9) : Score(9, 12)
        }
    }

    static func playRound(_ t: inout Tournament, matches limit: Int = .max) throws {
        let score = score21(t)
        let pending = t.rounds.last!.matches.sorted { $0.court < $1.court }.filter { $0.state != .completed }
        for match in pending.prefix(limit) {
            try t.validateScore(match.id, score: score(match), now: Date())
        }
    }

    @Test("Americano libre, 16 joueurs, 4 terrains : 11 tours joués puis arrêt")
    func americanoSixteenPlayers() throws {
        var t = try Self.openTournament(.americano)
        #expect(t.rounds.count == 1, "un seul tour généré au départ")
        #expect(t.rounds[0].matches.count == 4)

        for round in 1...11 {
            try Self.playRound(&t)
            if round < 11 { try t.generateNextRound(now: Date()) }
        }
        try ScheduleValidator.validate(rounds: t.rounds, playerIDs: t.players.map(\.id), activeCourts: 4)
        let stats = t.scheduleStatistics
        #expect(stats.maxPartnerCount == 1, "aucun partenaire répété sur 11 tours")
        #expect(stats.matchesPerPlayer == 11...11)

        #expect(t.canFinish)
        #expect(!t.hasPartiallyPlayedRound)
        try t.finish(now: Date())
        let results = TournamentResults(tournament: t)
        #expect(results.matchesPlayed == 44)
        #expect(results.roundsPlayed == 11)
        #expect(results.totalPoints == 44 * 21)
        #expect(results.statistics.compromises.isEmpty)
        #expect(results.standings.allSatisfy { $0.stats.played == 11 })
    }

    @Test("Americano libre : sur un cycle complet, chacun joue avec chacun", arguments: [8, 9, 16])
    func fullCycle(players: Int) throws {
        var t = try Self.openTournament(.americano, players: players, courts: players / 4)
        let cycle = players % 2 == 0 ? players - 1 : players
        for round in 1...cycle {
            try Self.playRound(&t)
            if round < cycle { try t.generateNextRound(now: Date()) }
        }
        let stats = t.scheduleStatistics
        #expect(stats.maxPartnerCount == 1)
        #expect(stats.neverPartneredPairs == 0)
        #expect(stats.restsPerPlayer.lowerBound == stats.restsPerPlayer.upperBound)
    }

    @Test("Americano libre : au-delà d'un cycle, la rotation continue")
    func beyondCycle() throws {
        var t = try Self.openTournament(.americano, players: 8, courts: 2)
        for _ in 1...10 {
            try Self.playRound(&t)
            try t.generateNextRound(now: Date())
        }
        try ScheduleValidator.validate(rounds: t.rounds, playerIDs: t.players.map(\.id), activeCourts: 2)
        #expect(t.scheduleStatistics.maxPartnerCount <= 2)
    }

    @Test("Le tour suivant est le même quel que soit le moment où on le génère")
    func deterministic() throws {
        var a = try Self.openTournament(.americano)
        var b = a
        try Self.playRound(&a)
        try Self.playRound(&b)
        try a.generateNextRound(now: Date())
        try b.generateNextRound(now: Date(timeIntervalSince1970: 999))
        #expect(a.rounds[1].matches.map(\.players) == b.rounds[1].matches.map(\.players))
    }

    @Test("Mexicano libre : pas de limite de tours fixée")
    func mexicanoOpenEnded() throws {
        var t = try Self.openTournament(.mexicano)
        for _ in 1...12 {
            try Self.playRound(&t)
            try t.generateNextRound(now: Date())
        }
        #expect(t.rounds.count == 13)
        #expect(t.canFinish)
    }

    @Test("Identifiants de match uniques sur tout un tournoi", arguments: [TournamentFormat.americano, .mexicano])
    func uniqueMatchIDs(format: TournamentFormat) throws {
        for seed in UInt64(0)..<20 {
            var t = try Self.openTournament(format, seed: seed)
            for _ in 1...15 {
                try Self.playRound(&t)
                try t.generateNextRound(now: Date())
            }
            let ids = t.rounds.flatMap(\.matches).map(\.id)
            #expect(Set(ids).count == ids.count, "graine \(seed)")
        }
    }

    @Test("Arrêt en plein tour : compter les matchs joués")
    func stopMidRoundCountingAll() throws {
        var t = try Self.openTournament(.americano)
        try Self.playRound(&t)
        try t.generateNextRound(now: Date())
        try Self.playRound(&t, matches: 2)          // 2 matchs sur 4 du tour 2
        #expect(t.hasPartiallyPlayedRound)

        try t.finish(now: Date(), mode: .countAllPlayedMatches)
        #expect(t.status == .finished)
        let results = TournamentResults(tournament: t)
        #expect(results.matchesPlayed == 6)
        #expect(results.statistics.matchesPerPlayer == 1...2)
        #expect(results.statistics.compromises.contains(.unequalMatches(1...2)))
    }

    @Test("Arrêt en plein tour : seulement les tours complets, scores conservés")
    func stopMidRoundCompletedOnly() throws {
        var t = try Self.openTournament(.americano)
        try Self.playRound(&t)
        try t.generateNextRound(now: Date())
        try Self.playRound(&t, matches: 2)

        try t.finish(now: Date(), mode: .completedRoundsOnly)
        #expect(t.rounds.count == 2)
        #expect(t.rounds[1].isExcluded)
        #expect(t.rounds[1].matches.filter { $0.state == .completed }.count == 2, "les scores ne sont pas effacés")
        let results = TournamentResults(tournament: t)
        #expect(results.matchesPlayed == 4)
        #expect(results.standings.allSatisfy { $0.stats.played == 1 })
        #expect(results.statistics.compromises.isEmpty)
    }

    @Test("« Seulement les tours complets » impossible si aucun tour n'est complet")
    func completedOnlyNeedsACompleteRound() throws {
        var t = try Self.openTournament(.americano)
        try Self.playRound(&t, matches: 1)
        #expect(throws: LifecycleError.roundNotComplete) { try t.finish(now: Date(), mode: .completedRoundsOnly) }
        try t.finish(now: Date(), mode: .countAllPlayedMatches)
    }

    @Test("Americano à nombre de tours fixe : arrêt anticipé, tours non joués retirés")
    func fixedAmericanoEarlyStop() throws {
        var t = TestSupport.tournament(format: .americano, players: 8, rounds: 7)
        try t.start(now: Date())
        #expect(!t.canFinish, "rien n'a été joué")
        for match in t.rounds.prefix(3).flatMap(\.matches) {
            try t.validateScore(match.id, score: Score(15, 9), now: Date())
        }
        #expect(t.canFinish)
        try t.finish(now: Date())
        #expect(t.rounds.count == 3)
        #expect(TournamentResults(tournament: t).roundsPlayed == 3)
    }

    @Test("Un tour exclu ne compte pas dans les pauses ni les points")
    func excludedRoundIgnored() throws {
        var t = try Self.openTournament(.americano, players: 5, courts: 1)
        try Self.playRound(&t)
        try t.generateNextRound(now: Date())
        // Le tour 2 n'a qu'un match : on ne le joue pas, puis on arrête.
        try t.finish(now: Date(), mode: .completedRoundsOnly)
        #expect(t.rounds.count == 1)
        #expect(Standings.stats(for: t).values.map(\.rests).reduce(0, +) == 1)
    }

    @Test("21 points au total : jamais de match nul")
    func twentyOnePoints() {
        let rule = ScoringRule.fixedTotal(points: 21)
        #expect(rule.validate(Score(11, 10)) == .valid)
        #expect(rule.validate(Score(21, 0)) == .valid)
        #expect(rule.validate(Score(10, 10)) == .invalid(.totalMustEqual(21)))
        #expect(ScoringRule.presetPoints.contains(21))
    }

    @Test("Les anciens fichiers restent lisibles (nombre de tours fixe, aucun tour exclu)")
    func legacyFiles() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        try t.start(now: Date())
        var json = String(decoding: try TournamentCodec.encode(t), as: UTF8.self)
        json = json.replacingOccurrences(of: #","openEnded":true"#, with: "")
        let decoded = try TournamentCodec.decode(Data(json.utf8))
        #expect(!decoded.settings.isOpenEnded)
        #expect(decoded.rounds.allSatisfy { !$0.isExcluded })
    }
}
