import Foundation

/// Règle de score d'un match.
public enum ScoringRule: Codable, Hashable, Sendable {
    /// Nombre total de points fixe : A + B = points (Americano classique, ex. 15–9 en 24).
    case fixedTotal(points: Int)
    /// Premier à `points` : le gagnant atteint exactement `points`, le perdant reste en dessous.
    case raceTo(points: Int)
    /// Scores libres (match au temps) : valeurs positives, au moins un point joué.
    case free

    public static let presetPoints = [16, 24, 32]
    public static let pointsRange = 4...99
    /// Plafond de cohérence pour les scores libres.
    public static let maxFreeScore = 99

    public var points: Int? {
        switch self {
        case .fixedTotal(let points), .raceTo(let points): points
        case .free: nil
        }
    }

    public func validate(_ score: Score) -> ScoreValidation {
        guard score.teamA >= 0, score.teamB >= 0 else { return .invalid(.negative) }
        switch self {
        case .fixedTotal(let points):
            return score.teamA + score.teamB == points ? .valid : .invalid(.totalMustEqual(points))
        case .raceTo(let points):
            let winner = max(score.teamA, score.teamB)
            let loser = min(score.teamA, score.teamB)
            guard winner == points else { return .invalid(.winnerMustReach(points)) }
            return loser < points ? .valid : .invalid(.noDrawAllowed)
        case .free:
            guard score.teamA + score.teamB > 0 else { return .invalid(.empty) }
            guard max(score.teamA, score.teamB) <= Self.maxFreeScore else {
                return .invalid(.tooHigh(Self.maxFreeScore))
            }
            return .valid
        }
    }

    /// En total fixe, le score adverse se déduit de celui saisi.
    public func complement(of score: Int) -> Int? {
        guard case .fixedTotal(let points) = self, (0...points).contains(score) else { return nil }
        return points - score
    }
}

public enum ScoreValidation: Hashable, Sendable {
    case valid
    case invalid(ScoreError)

    public var isValid: Bool { self == .valid }
}

public enum ScoreError: Hashable, Sendable {
    case negative
    case totalMustEqual(Int)
    case winnerMustReach(Int)
    case noDrawAllowed
    case empty
    case tooHigh(Int)
}
