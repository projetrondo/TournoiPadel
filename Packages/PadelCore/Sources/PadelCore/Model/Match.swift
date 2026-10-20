import Foundation

/// Une équipe de deux joueurs distincts.
public struct Team: Codable, Hashable, Sendable {
    public let first: Player.ID
    public let second: Player.ID

    public init(_ first: Player.ID, _ second: Player.ID) {
        self.first = first
        self.second = second
    }

    public var players: [Player.ID] { [first, second] }

    public func contains(_ player: Player.ID) -> Bool {
        first == player || second == player
    }
}

/// Score d'un match : points de l'équipe A et de l'équipe B.
public struct Score: Codable, Hashable, Sendable {
    public var teamA: Int
    public var teamB: Int

    public init(_ teamA: Int, _ teamB: Int) {
        self.teamA = teamA
        self.teamB = teamB
    }

    public var outcome: MatchOutcome {
        if teamA > teamB { return .teamAWins }
        if teamB > teamA { return .teamBWins }
        return .draw
    }
}

public enum MatchOutcome: Hashable, Sendable {
    case teamAWins
    case teamBWins
    case draw
}

public enum MatchState: String, Codable, Hashable, Sendable {
    case scheduled
    case inProgress
    case completed
}

/// Trace d'une validation ou d'une correction de score (historique, jamais effacé).
public struct ScoreEdit: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case validation
        case correction
        case reset
    }

    public var kind: Kind
    public var date: Date
    public var previous: Score?
    public var new: Score?

    public init(kind: Kind, date: Date, previous: Score?, new: Score?) {
        self.kind = kind
        self.date = date
        self.previous = previous
        self.new = new
    }
}

public struct Match: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Numéro de terrain, à partir de 1.
    public let court: Int
    public let teamA: Team
    public let teamB: Team
    public var score: Score?
    public var state: MatchState
    public var edits: [ScoreEdit]

    public init(
        id: UUID = UUID(),
        court: Int,
        teamA: Team,
        teamB: Team,
        score: Score? = nil,
        state: MatchState = .scheduled,
        edits: [ScoreEdit] = []
    ) {
        self.id = id
        self.court = court
        self.teamA = teamA
        self.teamB = teamB
        self.score = score
        self.state = state
        self.edits = edits
    }

    public var players: [Player.ID] { teamA.players + teamB.players }
}

public struct Round: Codable, Hashable, Sendable {
    /// Numéro du tour, à partir de 1.
    public let index: Int
    public var matches: [Match]
    /// Joueurs au repos pendant ce tour.
    public var resting: [Player.ID]
    /// Tour interrompu à la clôture et non compté au classement (ses scores sont conservés).
    public var excluded: Bool?

    public init(index: Int, matches: [Match], resting: [Player.ID], isExcluded: Bool = false) {
        self.index = index
        self.matches = matches
        self.resting = resting
        self.excluded = isExcluded ? true : nil
    }

    public var isExcluded: Bool { excluded ?? false }

    public var hasPlayedMatch: Bool {
        matches.contains { $0.state == .completed }
    }

    public var isComplete: Bool {
        matches.allSatisfy { $0.state == .completed }
    }
}
