import Foundation
import Testing
@testable import PadelCore

@Suite("Générateur Mexicano")
struct MexicanoSchedulerTests {
    /// Joue un Mexicano complet avec des scores « réalistes » (les joueurs d'indice bas sont plus forts).
    static func play(players: Int, courts: Int? = nil, rounds: Int, seed: UInt64 = 7) throws -> Tournament {
        var t = TestSupport.tournament(format: .mexicano, players: players, courts: courts, rounds: rounds, seed: seed)
        try t.start(now: Date())
        let score = TestSupport.strengthScore(t)
        TestSupport.completeLastRound(&t, score: score)
        while t.canGenerateNextRound {
            let before = t.rounds
            try t.generateNextRound(now: Date())
            #expect(Array(t.rounds.dropLast()) == before, "les tours déjà joués ne changent pas")
            TestSupport.completeLastRound(&t, score: score)
        }
        return t
    }

    @Test("Tournoi complet valide et équitable", arguments: [4, 5, 6, 7, 8, 9, 10, 12, 16, 20])
    func fullTournament(players: Int) throws {
        let planner = RoundPlanner(playerCount: players, declaredCourts: max(1, players / 4))
        let rounds = planner.recommendedRounds(scoring: .fixedTotal(points: 24))!
        let t = try Self.play(players: players, rounds: rounds)
        #expect(t.rounds.count == rounds)
        try ScheduleValidator.validate(rounds: t.rounds, playerIDs: t.players.map(\.id), activeCourts: planner.activeCourts)
        if planner.isEquitable(rounds: rounds) {
            #expect(t.scheduleStatistics.matchesPerPlayer.lowerBound == t.scheduleStatistics.matchesPerPlayer.upperBound)
        }
        #expect(!t.canGenerateNextRound)
    }

    @Test("Groupes de 4 dans l'ordre du classement : 1+4 contre 2+3")
    func preferredPattern() {
        let ledger = PairingLedger(playerCount: 8)
        let groups = MexicanoScheduler.bestGroups(ranked: Array(0..<8), ledger: ledger)
        #expect(groups == [[0, 3, 1, 2], [4, 7, 5, 6]])
    }

    @Test("Partenaire déjà vu : schéma alternatif")
    func alternativePattern() {
        var ledger = PairingLedger(playerCount: 4)
        ledger.record(matches: [[0, 3, 1, 2]], resting: [])
        let groups = MexicanoScheduler.bestGroups(ranked: [0, 1, 2, 3], ledger: ledger)
        #expect(groups == [[0, 2, 1, 3]])
    }

    @Test("Aucun schéma possible dans le groupe : échange à la frontière")
    func boundarySwap() {
        var ledger = PairingLedger(playerCount: 8)
        // Le n° 1 a déjà joué avec 2, 3 et 4 : tout schéma du groupe 1–4 répète un partenaire.
        ledger.record(matches: [[0, 1, 4, 5]], resting: [2, 3, 6, 7])
        ledger.record(matches: [[0, 2, 6, 7]], resting: [1, 3, 4, 5])
        ledger.record(matches: [[0, 3, 4, 5]], resting: [1, 2, 6, 7])
        let groups = MexicanoScheduler.bestGroups(ranked: Array(0..<8), ledger: ledger)
        #expect(Set(groups[0]) == [0, 1, 2, 4])
        #expect(Set(groups[1]) == [3, 5, 6, 7])
        for g in groups {
            #expect(ledger.partners(g[0], g[1]) == 0 && ledger.partners(g[2], g[3]) == 0)
        }
    }

    @Test("Échange à distance 2 quand le voisin direct ne suffit pas")
    func distanceTwoExchange() {
        var ledger = PairingLedger(playerCount: 8)
        // Le n° 1 a déjà joué avec 2, 3, 4 et 5.
        ledger.record(matches: [[0, 1, 4, 5]], resting: [2, 3, 6, 7])
        ledger.record(matches: [[0, 2, 6, 7]], resting: [1, 3, 4, 5])
        ledger.record(matches: [[0, 3, 5, 6]], resting: [1, 2, 4, 7])
        ledger.record(matches: [[0, 4, 1, 7]], resting: [2, 3, 5, 6])
        let groups = MexicanoScheduler.bestGroups(ranked: Array(0..<8), ledger: ledger)
        #expect(groups[0].contains(5))
        #expect(Set(groups[0]).count == 4 && Set(groups[0] + groups[1]).count == 8)
        for g in groups {
            #expect(ledger.partners(g[0], g[1]) == 0 && ledger.partners(g[2], g[3]) == 0)
        }
    }

    @Test("Les meilleurs jouent ensemble sur le terrain 1")
    func strongestOnCourtOne() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 3)
        try t.start(now: Date())
        TestSupport.completeLastRound(&t, score: TestSupport.strengthScore(t))
        try t.generateNextRound(now: Date())

        var history = t
        history.rounds.removeLast()
        let scheduler = MexicanoScheduler(tournament: t)
        let order = scheduler.pairingOrder(Array(0..<8), stats: Standings.stats(for: history), playerIDs: t.players.map(\.id))
        let topFour = Set(order.prefix(4).map { t.players[$0].id })
        let courtOne = Set(t.rounds[1].matches.first { $0.court == 1 }!.players)
        // Au plus un échange à la frontière.
        #expect(topFour.intersection(courtOne).count >= 3)
    }

    @Test("Le tour 2 ne répète jamais un partenaire", arguments: [4, 5, 8, 9, 12, 16])
    func secondRoundNoRepeat(players: Int) throws {
        var t = TestSupport.tournament(format: .mexicano, players: players, rounds: 2, seed: UInt64(players))
        try t.start(now: Date())
        TestSupport.completeLastRound(&t, score: TestSupport.strengthScore(t))
        try t.generateNextRound(now: Date())
        #expect(t.scheduleStatistics.maxPartnerCount <= 1)
    }

    @Test("Premier tour par niveau : les meilleurs niveaux ensemble")
    func firstRoundByLevel() throws {
        let levels = [1, 5, 2, 5, 1, 4, 2, 5]
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 3, firstRound: .byLevel, levels: levels)
        try t.start(now: Date())
        let courtOne = t.rounds[0].matches.first { $0.court == 1 }!.players
        let courtOneLevels = courtOne.map { id in t.player(id)!.level! }.sorted(by: >)
        #expect(courtOneLevels == [5, 5, 5, 4])
    }

    @Test("Le tour suivant exige un tour terminé")
    func requiresCompleteRound() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 3)
        try t.start(now: Date())
        #expect(!t.canGenerateNextRound)
        #expect(throws: LifecycleError.roundNotComplete) { try t.generateNextRound(now: Date()) }
    }

    @Test("Impossible de dépasser le nombre de tours prévu")
    func roundLimit() throws {
        var t = try Self.play(players: 4, rounds: 2)
        #expect(throws: LifecycleError.allRoundsGenerated) { try t.generateNextRound(now: Date()) }
    }

    @Test("Americano : pas de tour suivant à générer")
    func notForAmericano() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        try t.start(now: Date())
        #expect(throws: LifecycleError.wrongFormat) { try t.generateNextRound(now: Date()) }
    }

    @Test("Même graine et mêmes scores : mêmes tours")
    func determinism() throws {
        let a = try Self.play(players: 10, rounds: 5, seed: 99)
        let b = try Self.play(players: 10, rounds: 5, seed: 99)
        // Les identifiants de joueurs diffèrent d'un tournoi à l'autre : on compare par position.
        func shape(_ t: Tournament) -> [[[Int]]] {
            let index = Dictionary(uniqueKeysWithValues: t.players.enumerated().map { ($1.id, $0) })
            return t.rounds.map { round in
                round.matches.sorted { $0.court < $1.court }.map { $0.players.map { index[$0]! } }
                    + [round.resting.map { index[$0]! }.sorted()]
            }
        }
        #expect(shape(a) == shape(b))
    }

    @Test("Les scores réels comptent, pas seulement les victoires")
    func usesActualScores() {
        // Deux joueurs avec une victoire chacun, mais des écarts très différents.
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 3)
        let ids = t.players.map(\.id)
        t.rounds = [Round(index: 1, matches: [
            Match(court: 1, teamA: Team(ids[0], ids[1]), teamB: Team(ids[2], ids[3]), score: Score(13, 11), state: .completed),
            Match(court: 2, teamA: Team(ids[4], ids[5]), teamB: Team(ids[6], ids[7]), score: Score(22, 2), state: .completed),
        ], resting: [])]
        t.status = .inProgress
        let order = MexicanoScheduler(tournament: t).pairingOrder(Array(0..<8), stats: Standings.stats(for: t), playerIDs: ids)
        #expect(Array(order.prefix(2)) == [4, 5])
        #expect(Array(order.suffix(2)) == [6, 7])
    }

    @Test("Régénérer le dernier tour après une correction, sans toucher au passé")
    func regenerateAfterCorrection() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 3)
        try t.start(now: Date())
        TestSupport.completeLastRound(&t, score: TestSupport.strengthScore(t))
        try t.generateNextRound(now: Date())
        #expect(t.canRegenerateLastRound)

        // Correction du tour 1 : on inverse les scores.
        for i in t.rounds[0].matches.indices {
            let s = t.rounds[0].matches[i].score!
            t.rounds[0].matches[i].score = Score(s.teamB, s.teamA)
        }
        let roundOne = t.rounds[0]
        try t.regenerateLastRound(now: Date())
        #expect(t.rounds.count == 2)
        #expect(t.rounds[0] == roundOne)
        try ScheduleValidator.validate(round: t.rounds[1], playerIDs: t.players.map(\.id), activeCourts: 2)

        // Dès qu'un score est saisi dans le dernier tour, il ne peut plus être régénéré.
        t.rounds[1].matches[0].score = Score(10, 14)
        #expect(!t.canRegenerateLastRound)
        #expect(throws: LifecycleError.roundAlreadyStarted) { try t.regenerateLastRound(now: Date()) }
    }
}
