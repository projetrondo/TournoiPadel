import Foundation

/// Un tournoi complet. C'est l'agrégat unique qui est sauvegardé, restauré et (plus tard) partagé.
/// Le classement n'est jamais stocké : il est toujours recalculé à partir des matchs terminés.
public struct Tournament: Codable, Identifiable, Hashable, Sendable {
    /// Version du format JSON. À incrémenter à chaque changement incompatible du modèle.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public var format: TournamentFormat
    public var settings: TournamentSettings
    /// Ordre d'inscription : sert aussi de dernier critère de tri stable.
    public var players: [Player]
    public var rounds: [Round]
    public var status: TournamentStatus
    /// Graine du générateur pseudo-aléatoire : un même tournoi produit toujours le même planning.
    public var seed: UInt64
    public var createdAt: Date
    public var updatedAt: Date
    /// Incrémenté à chaque modification ; sert à la synchronisation.
    public var revision: Int
    public var sharing: SharingInfo?

    public init(
        id: UUID = UUID(),
        name: String,
        format: TournamentFormat,
        settings: TournamentSettings,
        players: [Player],
        rounds: [Round] = [],
        status: TournamentStatus = .draft,
        seed: UInt64,
        createdAt: Date,
        updatedAt: Date? = nil,
        revision: Int = 1,
        sharing: SharingInfo? = nil
    ) {
        self.schemaVersion = Tournament.currentSchemaVersion
        self.id = id
        self.name = name
        self.format = format
        self.settings = settings
        self.players = players
        self.rounds = rounds
        self.status = status
        self.seed = seed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.revision = revision
        self.sharing = sharing
    }

    public func player(_ id: Player.ID) -> Player? {
        players.first { $0.id == id }
    }

    /// Enregistre une modification : date et révision.
    public mutating func touch(at date: Date) {
        updatedAt = date
        revision += 1
    }
}

public enum TournamentFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case americano
    case mexicano
}

public enum TournamentStatus: String, Codable, Hashable, Sendable {
    /// Créé, pas encore lancé : les matchs ne sont pas générés.
    case draft
    case inProgress
    case finished
}

public struct TournamentSettings: Codable, Hashable, Sendable {
    /// Terrains déclarés par l'organisateur (seuls ⌊joueurs / 4⌋ au maximum sont utilisés).
    public var courts: Int
    public var scoring: ScoringRule
    /// Nombre de tours prévus.
    public var plannedRounds: Int
    /// Mexicano uniquement : mode de constitution du premier tour.
    public var mexicanoFirstRound: FirstRoundMode

    public init(
        courts: Int,
        scoring: ScoringRule,
        plannedRounds: Int,
        mexicanoFirstRound: FirstRoundMode = .random
    ) {
        self.courts = courts
        self.scoring = scoring
        self.plannedRounds = plannedRounds
        self.mexicanoFirstRound = mexicanoFirstRound
    }
}

public enum FirstRoundMode: String, Codable, CaseIterable, Hashable, Sendable {
    case random
    case byLevel
}

/// Informations de partage (utilisées à partir de la phase 6).
public struct SharingInfo: Codable, Hashable, Sendable {
    public var code: String
    public var organizerDeviceID: String?
    public var lastPublishedRevision: Int?

    public init(code: String, organizerDeviceID: String? = nil, lastPublishedRevision: Int? = nil) {
        self.code = code
        self.organizerDeviceID = organizerDeviceID
        self.lastPublishedRevision = lastPublishedRevision
    }
}
