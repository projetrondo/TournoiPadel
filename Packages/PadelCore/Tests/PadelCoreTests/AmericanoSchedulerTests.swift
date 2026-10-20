import Foundation
import Testing
@testable import PadelCore

@Suite("Générateur Americano")
struct AmericanoSchedulerTests {
    static func ids(_ count: Int) -> [Player.ID] {
        (0..<count).map { _ in UUID() }
    }

    /// Nombre de terrains « naturel » pour un groupe : tout le monde joue si possible.
    static func courts(for players: Int) -> Int { max(1, players / 4) }

    static func recommendedRounds(players: Int, courts: Int) -> Int {
        RoundPlanner(playerCount: players, declaredCourts: courts).recommendedRounds(scoring: .fixedTotal(points: 24))!
    }

    @Test("Planning valide et équitable", arguments: [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 20, 24, 32])
    func validAndFair(players: Int) throws {
        let courts = Self.courts(for: players)
        let rounds = Self.recommendedRounds(players: players, courts: courts)
        let ids = Self.ids(players)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: courts, rounds: rounds, seed: 7).generate()

        #expect(schedule.count == rounds)
        let planner = RoundPlanner(playerCount: players, declaredCourts: courts)
        try ScheduleValidator.validate(rounds: schedule, playerIDs: ids, activeCourts: planner.activeCourts)

        let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
        if planner.isEquitable(rounds: rounds) {
            #expect(stats.matchesPerPlayer.lowerBound == stats.matchesPerPlayer.upperBound)
            #expect(stats.restsPerPlayer.lowerBound == stats.restsPerPlayer.upperBound)
        }
    }

    @Test("Aucune répétition de partenaire dans les cas parfaits", arguments: [4, 5, 8, 9, 12, 13, 16, 17, 20])
    func perfectPartners(players: Int) throws {
        let courts = Self.courts(for: players)
        // Un cycle complet : chacun est partenaire de chacun une fois.
        let rounds = players % 2 == 0 ? players - 1 : players
        let ids = Self.ids(players)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: courts, rounds: rounds, seed: 99).generate()
        let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
        #expect(stats.maxPartnerCount == 1)
        #expect(stats.neverPartneredPairs == 0)
        #expect(stats.compromises.isEmpty)
    }

    @Test("Répétitions limitées quand elles sont inévitables")
    func unavoidableRepeats() throws {
        // 6 joueurs, 9 tours : 6 matchs chacun pour seulement 5 partenaires possibles.
        let ids = Self.ids(6)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: 1, rounds: 9, seed: 3).generate()
        let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
        #expect(stats.matchesPerPlayer == 6...6)
        #expect(stats.maxPartnerCount == 2)
        #expect(stats.neverPartneredPairs == 0)
        #expect(stats.compromises == [.repeatedPartners(pairs: stats.repeatedPartnerPairs, maxTimes: 2)])
    }

    @Test("Pas de répétition de partenaire tant que c'est possible", arguments: [6, 7, 10, 11])
    func noEarlyRepeats(players: Int) throws {
        // Moins de matchs par joueur que de partenaires possibles : aucune répétition attendue.
        let courts = Self.courts(for: players)
        let planner = RoundPlanner(playerCount: players, declaredCourts: courts)
        let rounds = planner.equitableRoundOptions.last { planner.matchesPerPlayer(rounds: $0) <= Double(players - 1) }!
        let ids = Self.ids(players)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: courts, rounds: rounds, seed: 11).generate()
        #expect(ScheduleStatistics(rounds: schedule, playerIDs: ids).maxPartnerCount == 1, "\(players) joueurs, \(rounds) tours")
    }

    @Test("Moins de terrains que nécessaire : pauses tournantes équitables")
    func fewerCourts() throws {
        let ids = Self.ids(8)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: 1, rounds: 6, seed: 5).generate()
        try ScheduleValidator.validate(rounds: schedule, playerIDs: ids, activeCourts: 1)
        let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
        #expect(stats.matchesPerPlayer == 3...3)
        #expect(stats.restsPerPlayer == 3...3)
        #expect(schedule.allSatisfy { $0.resting.count == 4 && $0.matches.count == 1 })
    }

    @Test("Pas de pause deux tours de suite quand on peut l'éviter")
    func noConsecutiveRests() throws {
        let ids = Self.ids(6)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: 1, rounds: 6, seed: 21).generate()
        for (previous, next) in zip(schedule, schedule.dropFirst()) {
            #expect(Set(previous.resting).isDisjoint(with: next.resting))
        }
    }

    @Test("Nombre de tours non équitable : écart d'au plus un match")
    func unequalRounds() throws {
        let ids = Self.ids(6)
        let schedule = try AmericanoScheduler(playerIDs: ids, courts: 1, rounds: 4, seed: 2).generate()
        let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
        #expect(stats.matchesPerPlayer.upperBound - stats.matchesPerPlayer.lowerBound == 1)
        #expect(stats.compromises.contains(.unequalMatches(stats.matchesPerPlayer)))
    }

    @Test("Même graine, même planning ; graine différente, planning différent")
    func determinism() throws {
        let ids = Self.ids(8)
        let a = try AmericanoScheduler(playerIDs: ids, courts: 2, rounds: 7, seed: 42).generate()
        let b = try AmericanoScheduler(playerIDs: ids, courts: 2, rounds: 7, seed: 42).generate()
        let c = try AmericanoScheduler(playerIDs: ids, courts: 2, rounds: 7, seed: 43).generate()
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Cas impossibles signalés proprement")
    func impossibleCases() {
        #expect(throws: ScheduleError.notEnoughPlayers(minimum: 4)) {
            try AmericanoScheduler(playerIDs: Self.ids(3), courts: 1, rounds: 3, seed: 1).generate()
        }
        let id = UUID()
        #expect(throws: ScheduleError.duplicatePlayers) {
            try AmericanoScheduler(playerIDs: [id, id] + Self.ids(2), courts: 1, rounds: 3, seed: 1).generate()
        }
        #expect(throws: ScheduleError.invalidRoundCount) {
            try AmericanoScheduler(playerIDs: Self.ids(4), courts: 1, rounds: 0, seed: 1).generate()
        }
        #expect(throws: ScheduleError.noCourt) {
            try AmericanoScheduler(playerIDs: Self.ids(4), courts: 0, rounds: 3, seed: 1).generate()
        }
    }

    @Test("Grille exhaustive : toujours un planning valide", arguments: Array(4...24))
    func exhaustiveGrid(players: Int) throws {
        for courts in 1...min(6, max(1, players / 4) + 1) {
            let planner = RoundPlanner(playerCount: players, declaredCourts: courts)
            for rounds in [1, 2, 3, planner.equitableRoundUnit, players - 1] where RoundPlanner.roundsRange.contains(rounds) {
                let ids = Self.ids(players)
                let schedule = try AmericanoScheduler(playerIDs: ids, courts: courts, rounds: rounds, seed: UInt64(players * 100 + rounds)).generate()
                try ScheduleValidator.validate(rounds: schedule, playerIDs: ids, activeCourts: planner.activeCourts)
                let stats = ScheduleStatistics(rounds: schedule, playerIDs: ids)
                #expect(stats.matchesPerPlayer.upperBound - stats.matchesPerPlayer.lowerBound <= 1)
            }
        }
    }
}

@Suite("Validation des plannings")
struct ScheduleValidatorTests {
    let ids = (0..<5).map { _ in UUID() }

    func round(_ teamA: (Int, Int), _ teamB: (Int, Int), resting: [Int], court: Int = 1) -> Round {
        Round(
            index: 1,
            matches: [Match(court: court, teamA: Team(ids[teamA.0], ids[teamA.1]), teamB: Team(ids[teamB.0], ids[teamB.1]))],
            resting: resting.map { ids[$0] }
        )
    }

    @Test("Un tour correct est accepté")
    func valid() throws {
        try ScheduleValidator.validate(round: round((0, 1), (2, 3), resting: [4]), playerIDs: ids, activeCourts: 1)
    }

    @Test("Joueur deux fois dans le même tour")
    func playerTwice() {
        #expect(throws: ScheduleValidator.Violation.playerTwiceInRound(round: 1)) {
            try ScheduleValidator.validate(round: round((0, 1), (2, 3), resting: [3]), playerIDs: ids, activeCourts: 1)
        }
    }

    @Test("Équipe avec deux fois le même joueur")
    func sameTeammate() {
        #expect(throws: ScheduleValidator.Violation.teamWithSamePlayer(round: 1)) {
            try ScheduleValidator.validate(round: round((0, 0), (2, 3), resting: [1, 4]), playerIDs: ids, activeCourts: 1)
        }
    }

    @Test("Joueur oublié")
    func missing() {
        #expect(throws: ScheduleValidator.Violation.playerMissing(round: 1)) {
            try ScheduleValidator.validate(round: round((0, 1), (2, 3), resting: []), playerIDs: ids, activeCourts: 1)
        }
    }

    @Test("Terrain inexistant")
    func invalidCourt() {
        #expect(throws: ScheduleValidator.Violation.invalidCourt(round: 1)) {
            try ScheduleValidator.validate(round: round((0, 1), (2, 3), resting: [4], court: 2), playerIDs: ids, activeCourts: 1)
        }
    }
}

@Suite("Lancement d'un tournoi")
struct TournamentStartTests {
    static func draftTournament(format: TournamentFormat = .americano, players: Int = 8) throws -> Tournament {
        var draft = TournamentDraft(name: "Test", format: format, courts: 2)
        draft.players = (1...players).map { .init(name: "J\($0)") }
        draft.rounds = 7
        return try draft.makeTournament(now: Date(timeIntervalSince1970: 0), seed: 1234)
    }

    @Test("Lancer un Americano génère tous les tours")
    func startAmericano() throws {
        var tournament = try Self.draftTournament()
        try tournament.start(now: Date(timeIntervalSince1970: 10))
        #expect(tournament.status == .inProgress)
        #expect(tournament.rounds.count == 7)
        #expect(tournament.revision == 2)
        #expect(tournament.currentRound?.index == 1)
        #expect(tournament.scheduleStatistics.compromises.isEmpty)
    }

    @Test("On ne peut pas lancer deux fois")
    func startTwice() throws {
        var tournament = try Self.draftTournament()
        try tournament.start(now: Date())
        let snapshot = tournament
        #expect(throws: LifecycleError.alreadyStarted) { try tournament.start(now: Date()) }
        #expect(tournament == snapshot)
    }

    @Test("Mexicano : pas encore disponible, tournoi inchangé")
    func mexicanoNotYet() throws {
        var tournament = try Self.draftTournament(format: .mexicano)
        let snapshot = tournament
        #expect(throws: LifecycleError.unsupportedFormat(.mexicano)) { try tournament.start(now: Date()) }
        #expect(tournament == snapshot)
    }

    @Test("Le planning survit à la sauvegarde")
    func persistsSchedule() throws {
        var tournament = try Self.draftTournament()
        try tournament.start(now: Date())
        #expect(try TournamentCodec.decode(TournamentCodec.encode(tournament)) == tournament)
    }
}
