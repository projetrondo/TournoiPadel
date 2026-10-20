import Foundation

public enum ScheduleError: Error, Hashable, Sendable {
    case notEnoughPlayers(minimum: Int)
    case duplicatePlayers
    case invalidRoundCount
    case noCourt
}

/// Générateur du planning Americano complet (tous les tours sont connus au lancement).
///
/// Stratégie :
/// - Pauses : toujours les joueurs les moins reposés (voir `RestSelector`).
/// - Cas « parfaits » (4k joueurs sans pause, ou 4k+1 joueurs avec une pause par tour) :
///   méthode du cercle (tournoi toutes rondes) pour les partenaires — chacun est partenaire
///   de chacun exactement une fois sur un cycle — puis recherche locale sur les adversaires.
/// - Autres cas, et au-delà d'un cycle : recherche locale qui minimise
///   100 × Σ(partenariats répétés)² + 10 × Σ(oppositions répétées)².
/// - Plusieurs tentatives complètes avec des sous-graines différentes ; la meilleure est gardée.
/// Le résultat dépend uniquement des joueurs, des réglages et de la graine.
public struct AmericanoScheduler: Sendable {
    public let playerIDs: [Player.ID]
    public let courts: Int
    public let rounds: Int
    public let seed: UInt64

    public init(playerIDs: [Player.ID], courts: Int, rounds: Int, seed: UInt64) {
        self.playerIDs = playerIDs
        self.courts = courts
        self.rounds = rounds
        self.seed = seed
    }

    public init(tournament: Tournament) {
        self.init(
            playerIDs: tournament.players.map(\.id),
            courts: tournament.settings.courts,
            rounds: tournament.settings.plannedRounds,
            seed: tournament.seed
        )
    }

    var planner: RoundPlanner {
        RoundPlanner(playerCount: playerIDs.count, declaredCourts: courts)
    }

    /// Le cercle s'applique quand chaque tour laisse au plus un joueur au repos et que les
    /// partenariats d'un cycle complet couvrent exactement les joueurs actifs.
    var usesCircleMethod: Bool {
        let resting = planner.restingPerRound
        return (resting == 0 && playerIDs.count % 2 == 0) || (resting == 1 && playerIDs.count % 2 == 1)
    }

    /// Nombre de tentatives complètes, ajusté à la taille du problème.
    var attempts: Int {
        let n = playerIDs.count
        return max(3, min(40, 400_000 / max(1, rounds * n * n)))
    }

    static let restartsPerRound = 6

    public func generate() throws -> [Round] {
        let n = playerIDs.count
        guard n >= RoundPlanner.minPlayers else { throw ScheduleError.notEnoughPlayers(minimum: RoundPlanner.minPlayers) }
        guard Set(playerIDs).count == n else { throw ScheduleError.duplicatePlayers }
        guard RoundPlanner.roundsRange.contains(rounds) else { throw ScheduleError.invalidRoundCount }
        guard courts >= 1, planner.activeCourts >= 1 else { throw ScheduleError.noCourt }

        var master = SeededGenerator(seed: seed)
        var best: (cost: Int, rounds: [(matches: [[Int]], resting: [Int])])?
        for attempt in 0..<attempts {
            var rng = master.fork()
            // Une tentative sur deux sans le cercle, pour comparer les deux approches.
            let circle = usesCircleMethod && attempt % 2 == 0
            let (ledger, schedule) = buildSchedule(useCircle: circle, rng: &rng)
            if best == nil || ledger.totalCost < best!.cost {
                best = (ledger.totalCost, schedule)
            }
        }

        var rng = master.fork()
        let result = best!.rounds.enumerated().map { index, round in
            makeRound(index: index + 1, matches: round.matches, resting: round.resting, playerIDs: playerIDs, rng: &rng)
        }
        try ScheduleValidator.validate(rounds: result, playerIDs: playerIDs, activeCourts: planner.activeCourts)
        return result
    }

    private func buildSchedule(useCircle: Bool, rng: inout SeededGenerator) -> (PairingLedger, [(matches: [[Int]], resting: [Int])]) {
        let n = playerIDs.count
        let restCount = planner.restingPerRound
        var ledger = PairingLedger(playerCount: n)
        var schedule: [(matches: [[Int]], resting: [Int])] = []
        let circleRounds = useCircle ? circleSchedule(rng: &rng) : []

        for roundIndex in 0..<rounds {
            let matches: [[Int]]
            let resting: [Int]
            if roundIndex < circleRounds.count {
                let pairs = circleRounds[roundIndex]
                resting = pairs.filter { $0.0 >= n || $0.1 >= n }.map { min($0.0, $0.1) }
                let active = pairs.filter { $0.0 < n && $0.1 < n }
                matches = MatchArranger.groupPairs(active, ledger: ledger, restarts: Self.restartsPerRound, rng: &rng)
            } else {
                resting = RestSelector.choose(count: restCount, among: Array(0..<n), ledger: ledger, rng: &rng)
                let restingSet = Set(resting)
                let active = (0..<n).filter { !restingSet.contains($0) }
                matches = MatchArranger.arrange(players: active, ledger: ledger, restarts: Self.restartsPerRound, rng: &rng)
            }
            ledger.record(matches: matches, resting: resting)
            schedule.append((matches, resting))
        }
        return (ledger, schedule)
    }

    /// Méthode du cercle sur m joueurs (m pair ; un joueur fictif d'indice n si n est impair) :
    /// m − 1 tours où chaque joueur est associé une fois à chacun des autres.
    /// Les joueurs et l'ordre des tours sont mélangés selon la graine.
    private func circleSchedule(rng: inout SeededGenerator) -> [[(Int, Int)]] {
        let n = playerIDs.count
        let m = n % 2 == 0 ? n : n + 1
        let labels = rng.shuffled(Array(0..<m))
        let fixed = m - 1
        var result: [[(Int, Int)]] = []
        for r in rng.shuffled(Array(0..<(m - 1))) {
            var pairs = [(labels[fixed], labels[r])]
            for i in 1..<(m / 2) {
                pairs.append((labels[(r + i) % (m - 1)], labels[(r - i + (m - 1)) % (m - 1)]))
            }
            result.append(pairs)
        }
        return result
    }
}
