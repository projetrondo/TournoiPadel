import Foundation

/// Saisie en cours lors de la création d'un tournoi, avant sa validation.
public struct TournamentDraft: Hashable, Sendable {
    public struct PlayerEntry: Hashable, Identifiable, Sendable {
        public let id: UUID
        public var name: String
        public var level: Int?

        public init(id: UUID = UUID(), name: String, level: Int? = nil) {
            self.id = id
            self.name = name
            self.level = level
        }
    }

    public static let maxNameLength = 40
    public static let maxPlayerNameLength = 20

    public var name: String
    public var format: TournamentFormat
    public var players: [PlayerEntry]
    public var courts: Int
    public var scoring: ScoringRule
    public var rounds: Int
    public var mexicanoFirstRound: FirstRoundMode
    /// Mode libre : pas de nombre de tours fixé, on s'arrête quand on veut.
    public var isOpenEnded: Bool
    /// Session d'origine : le tournoi y sera rattaché.
    public var sessionID: UUID?

    public init(
        name: String = "",
        format: TournamentFormat = .americano,
        players: [PlayerEntry] = [],
        courts: Int = 1,
        scoring: ScoringRule = .fixedTotal(points: 24),
        rounds: Int = 3,
        mexicanoFirstRound: FirstRoundMode = .random,
        isOpenEnded: Bool = false,
        sessionID: UUID? = nil
    ) {
        self.name = name
        self.format = format
        self.players = players
        self.courts = courts
        self.scoring = scoring
        self.rounds = rounds
        self.mexicanoFirstRound = mexicanoFirstRound
        self.isOpenEnded = isOpenEnded
        self.sessionID = sessionID
    }

    public var planner: RoundPlanner {
        RoundPlanner(playerCount: players.count, declaredCourts: courts)
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Problèmes bloquants (erreurs) et points d'attention (avertissements).
    public var issues: [SetupIssue] {
        var issues: [SetupIssue] = []
        let planner = planner

        if trimmedName.isEmpty { issues.append(.missingName) }
        if trimmedName.count > Self.maxNameLength { issues.append(.nameTooLong(Self.maxNameLength)) }

        if players.count < RoundPlanner.minPlayers {
            issues.append(.notEnoughPlayers(minimum: RoundPlanner.minPlayers))
        }
        if players.count > RoundPlanner.maxPlayers {
            issues.append(.tooManyPlayers(maximum: RoundPlanner.maxPlayers))
        }
        if players.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.emptyPlayerName)
        }
        let duplicates = duplicatePlayerNames
        if !duplicates.isEmpty { issues.append(.duplicatePlayerNames(duplicates)) }

        if !RoundPlanner.courtsRange.contains(courts) {
            issues.append(.invalidCourtCount(RoundPlanner.courtsRange))
        }
        if let points = scoring.points, !ScoringRule.pointsRange.contains(points) {
            issues.append(.invalidPoints(ScoringRule.pointsRange))
        }
        if !isOpenEnded, !RoundPlanner.roundsRange.contains(rounds) {
            issues.append(.invalidRoundCount(RoundPlanner.roundsRange))
        }
        if format == .mexicano, mexicanoFirstRound == .byLevel, players.contains(where: { $0.level == nil }) {
            issues.append(.missingLevels)
        }

        // Avertissements : le tournoi reste valide.
        if players.count >= RoundPlanner.minPlayers {
            if courts > planner.activeCourts {
                issues.append(.unusedCourts(usable: planner.activeCourts))
            }
            if planner.restingPerRound > 0 {
                issues.append(.restingPlayers(perRound: planner.restingPerRound))
            }
            if !isOpenEnded, RoundPlanner.roundsRange.contains(rounds), !planner.isEquitable(rounds: rounds) {
                issues.append(.unequalMatchCount(suggestions: nearestEquitableRounds()))
            }
        }
        return issues
    }

    public var errors: [SetupIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [SetupIssue] { issues.filter { $0.severity == .warning } }
    public var canCreate: Bool { errors.isEmpty }

    /// Noms en double (forme affichée du premier exemplaire).
    public var duplicatePlayerNames: [String] {
        var seen: [String: String] = [:]
        var duplicates: [String] = []
        for entry in players {
            let display = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = Player.normalizedName(display)
            if let first = seen[key] {
                if !duplicates.contains(first) { duplicates.append(first) }
            } else {
                seen[key] = display
            }
        }
        return duplicates
    }

    /// Les nombres de tours équitables juste en dessous et au-dessus de la valeur choisie.
    public func nearestEquitableRounds() -> [Int] {
        let options = planner.equitableRoundOptions
        let below = options.last { $0 < rounds }
        let above = options.first { $0 > rounds }
        return [below, above].compactMap { $0 }
    }

    /// Construit le tournoi (statut brouillon, sans matchs). Échoue si la saisie contient des erreurs.
    public func makeTournament(now: Date, seed: UInt64) throws -> Tournament {
        let errors = errors
        guard errors.isEmpty else { throw SetupError.invalidDraft(errors) }
        let players = players.map {
            Player(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                level: $0.level
            )
        }
        let settings = TournamentSettings(
            courts: courts,
            scoring: scoring,
            plannedRounds: isOpenEnded ? RoundPlanner.roundsRange.upperBound : rounds,
            mexicanoFirstRound: mexicanoFirstRound,
            isOpenEnded: isOpenEnded
        )
        return Tournament(
            name: trimmedName,
            format: format,
            settings: settings,
            players: players,
            seed: seed,
            createdAt: now,
            sessionID: sessionID
        )
    }
}

public enum SetupError: Error, Hashable {
    case invalidDraft([SetupIssue])
}

public enum SetupIssue: Hashable, Sendable {
    public enum Severity: Hashable, Sendable {
        case error
        case warning
    }

    case missingName
    case nameTooLong(Int)
    case notEnoughPlayers(minimum: Int)
    case tooManyPlayers(maximum: Int)
    case emptyPlayerName
    case duplicatePlayerNames([String])
    case invalidCourtCount(ClosedRange<Int>)
    case invalidPoints(ClosedRange<Int>)
    case invalidRoundCount(ClosedRange<Int>)
    case missingLevels
    case unusedCourts(usable: Int)
    case restingPlayers(perRound: Int)
    case unequalMatchCount(suggestions: [Int])

    public var severity: Severity {
        switch self {
        case .unusedCourts, .restingPlayers, .unequalMatchCount: .warning
        default: .error
        }
    }
}
