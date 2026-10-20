import Foundation

/// Calculs de capacité d'un tournoi : terrains utilisés, pauses, nombres de tours équitables.
public struct RoundPlanner: Hashable, Sendable {
    public static let minPlayers = 4
    public static let maxPlayers = 32
    public static let courtsRange = 1...8
    public static let roundsRange = 1...40
    /// Durée cible au-delà de laquelle la recommandation cherche un nombre de tours plus court.
    public static let targetDurationMinutes = 150
    /// Estimation grossière : environ 30 secondes par point joué.
    public static let minutesPerPoint = 0.5
    /// Durée supposée d'un match quand les points ne sont pas fixés (match au temps).
    public static let defaultMatchMinutes = 15

    public let playerCount: Int
    public let declaredCourts: Int

    public init(playerCount: Int, declaredCourts: Int) {
        self.playerCount = playerCount
        self.declaredCourts = declaredCourts
    }

    /// Terrains réellement occupés à chaque tour : min(terrains, ⌊joueurs / 4⌋).
    public var activeCourts: Int {
        max(0, min(declaredCourts, playerCount / 4))
    }

    public var playersPerRound: Int { activeCourts * 4 }

    /// Joueurs au repos à chaque tour.
    public var restingPerRound: Int { playerCount - playersPerRound }

    /// Le nombre de tours doit être un multiple de cette valeur pour que chacun se repose autant.
    public var equitableRoundUnit: Int {
        guard restingPerRound > 0 else { return 1 }
        return playerCount / gcd(playerCount, restingPerRound)
    }

    public func isEquitable(rounds: Int) -> Bool {
        rounds > 0 && rounds % equitableRoundUnit == 0
    }

    /// Nombre moyen de matchs par joueur pour un nombre de tours donné.
    public func matchesPerPlayer(rounds: Int) -> Double {
        guard playerCount > 0 else { return 0 }
        return Double(rounds * playersPerRound) / Double(playerCount)
    }

    /// Nombres de tours qui donnent à chacun le même nombre de matchs et de pauses.
    public var equitableRoundOptions: [Int] {
        guard activeCourts > 0 else { return [] }
        return Array(stride(from: equitableRoundUnit, through: Self.roundsRange.upperBound, by: equitableRoundUnit))
    }

    public static func estimatedMatchMinutes(for scoring: ScoringRule) -> Double {
        switch scoring {
        case .fixedTotal(let points), .raceTo(let points):
            return Double(points) * minutesPerPoint
        case .free:
            return Double(defaultMatchMinutes)
        }
    }

    public func estimatedDurationMinutes(rounds: Int, scoring: ScoringRule) -> Int {
        Int((Double(rounds) * Self.estimatedMatchMinutes(for: scoring)).rounded())
    }

    /// Recommandation : le plus petit nombre de tours équitable qui permet à chacun de jouer
    /// au moins `joueurs − 1` matchs (idéalement avec chaque partenaire une fois). Si cela dépasse
    /// la durée cible, on prend le plus grand nombre équitable qui tient dans la durée cible
    /// (au minimum la plus petite option équitable).
    public func recommendedRounds(scoring: ScoringRule) -> Int? {
        let options = equitableRoundOptions
        guard let smallest = options.first else { return nil }
        let ideal = options.first { matchesPerPlayer(rounds: $0) >= Double(playerCount - 1) }
        if let ideal, estimatedDurationMinutes(rounds: ideal, scoring: scoring) <= Self.targetDurationMinutes {
            return ideal
        }
        let fitting = options.filter {
            estimatedDurationMinutes(rounds: $0, scoring: scoring) <= Self.targetDurationMinutes
        }
        return fitting.last ?? smallest
    }
}

func gcd(_ a: Int, _ b: Int) -> Int {
    var (x, y) = (abs(a), abs(b))
    while y != 0 { (x, y) = (y, x % y) }
    return x
}
