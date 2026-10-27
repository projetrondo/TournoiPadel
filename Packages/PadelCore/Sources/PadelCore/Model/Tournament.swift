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
    /// Session à laquelle appartient le tournoi (absent = tournoi isolé, fichiers antérieurs).
    public var sessionID: UUID?

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
        sharing: SharingInfo? = nil,
        sessionID: UUID? = nil
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
        self.sessionID = sessionID
    }

    public func player(_ id: Player.ID) -> Player? {
        players.first { $0.id == id }
    }

    /// Date à laquelle le tournoi s'est joué : premier score validé, sinon sa création.
    /// C'est elle qui range le tournoi dans une semaine, un mois ou une année.
    public var playedOn: Date {
        rounds.lazy
            .flatMap(\.matches)
            .compactMap { $0.state == .completed ? $0.edits.first?.date : nil }
            .min() ?? createdAt
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
    /// Nombre de tours prévus (ignoré en mode libre).
    public var plannedRounds: Int
    /// Mexicano uniquement : mode de constitution du premier tour.
    public var mexicanoFirstRound: FirstRoundMode
    /// Mode libre : pas de nombre de tours fixé, chaque tour est généré à la demande et on
    /// s'arrête quand on veut. Absent des fichiers antérieurs : `nil` = nombre fixe.
    public var openEnded: Bool?

    public init(
        courts: Int,
        scoring: ScoringRule,
        plannedRounds: Int,
        mexicanoFirstRound: FirstRoundMode = .random,
        isOpenEnded: Bool = false
    ) {
        self.courts = courts
        self.scoring = scoring
        self.plannedRounds = plannedRounds
        self.mexicanoFirstRound = mexicanoFirstRound
        self.openEnded = isOpenEnded ? true : nil
    }

    public var isOpenEnded: Bool { openEnded ?? false }

    /// Nombre maximal de tours : celui prévu, ou la limite technique en mode libre.
    public var maximumRounds: Int {
        isOpenEnded ? RoundPlanner.roundsRange.upperBound : plannedRounds
    }
}

public enum FirstRoundMode: String, Codable, CaseIterable, Hashable, Sendable {
    case random
    case byLevel
}

/// Informations de partage entre iPhone.
public struct SharingInfo: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Hashable, Sendable {
        /// Appareil qui a créé le tournoi : seul à pouvoir le modifier et le publier.
        case organizer
        /// Copie reçue d'un organisateur : lecture seule, mise à jour depuis le serveur.
        case viewer
    }

    public var code: String
    /// Absent dans les fichiers antérieurs à la phase 6 : considéré comme organisateur.
    public var role: Role?
    public var organizerDeviceID: String?
    /// Dernière révision envoyée au serveur (organisateur) ou reçue (spectateur).
    public var lastPublishedRevision: Int?
    /// Dernier échange réussi avec le serveur.
    public var lastSyncedAt: Date?

    public init(
        code: String,
        role: Role = .organizer,
        organizerDeviceID: String? = nil,
        lastPublishedRevision: Int? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.code = code
        self.role = role
        self.organizerDeviceID = organizerDeviceID
        self.lastPublishedRevision = lastPublishedRevision
        self.lastSyncedAt = lastSyncedAt
    }

    public var effectiveRole: Role { role ?? .organizer }
}
