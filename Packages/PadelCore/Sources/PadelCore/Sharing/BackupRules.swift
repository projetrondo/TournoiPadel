import Foundation

/// Type de document sauvegardé dans le compte.
public enum BackupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case session
    case tournament
}

/// Identifie un document sauvegardé : « tournament/UUID ».
public struct BackupKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let kind: BackupKind
    public let id: UUID

    public init(_ kind: BackupKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }

    public var description: String { "\(kind.rawValue)/\(id.uuidString.lowercased())" }
}

/// Version d'un document : sa révision (incrémentée à chaque modification) et sa date.
public struct DocumentVersion: Hashable, Sendable {
    public let revision: Int
    public let updatedAt: Date?
    public let isDeleted: Bool

    public init(revision: Int, updatedAt: Date?, isDeleted: Bool = false) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

/// Ce que l'appareil sait de la sauvegarde de son compte : où il en est de la lecture des
/// changements, quelle version de chaque document le serveur a confirmée, et les
/// suppressions qui restent à envoyer (faites hors ligne).
public struct BackupLedger: Codable, Hashable, Sendable {
    public var accountID: String
    /// Dernier numéro de changement lu sur le serveur.
    public var cursor: Int
    /// Révision confirmée par le serveur, par document (envoyée ou reçue).
    public var confirmed: [String: Int]
    /// Suppressions locales pas encore transmises : document → révision de suppression.
    public var pendingDeletions: [String: Int]
    public var lastBackupAt: Date?

    public init(accountID: String) {
        self.accountID = accountID
        cursor = 0
        confirmed = [:]
        pendingDeletions = [:]
    }

    /// La version locale est-elle plus récente que celle que le serveur connaît ?
    public func needsUpload(_ key: BackupKey, revision: Int) -> Bool {
        (confirmed[key.description] ?? 0) < revision
    }

    public mutating func confirm(_ key: BackupKey, revision: Int) {
        confirmed[key.description] = revision
        pendingDeletions[key.description] = nil
    }

    public mutating func forget(_ key: BackupKey) {
        confirmed[key.description] = nil
        pendingDeletions[key.description] = nil
    }

    /// Supprimé sur l'appareil : à transmettre, seulement si le serveur l'avait déjà.
    public mutating func recordLocalDeletion(_ key: BackupKey, revision: Int) {
        guard let known = confirmed[key.description] else { return }
        pendingDeletions[key.description] = max(known, revision) + 1
    }
}

/// Règles de la sauvegarde en ligne, indépendantes du réseau.
///
/// Même principe que le partage : une version ne remplace jamais une version plus récente.
/// À révision égale (deux appareils ont modifié la même version hors ligne), la dernière
/// modification l'emporte.
public enum BackupRules {
    public enum Incoming: Hashable, Sendable {
        /// Enregistrer la version du serveur sur l'appareil.
        case adopt
        /// Supprimer la copie locale.
        case deleteLocal
        /// Garder la version locale (plus récente : elle sera envoyée).
        case keepLocal
    }

    public enum Rejected: Hashable, Sendable {
        /// Le serveur a mieux : on prend sa version (ou sa suppression).
        case adoptServer
        /// La version locale est la plus récente : la renvoyer avec cette révision.
        case resend(revision: Int)
    }

    /// Un changement lu sur le serveur, face à la copie locale (nil si absente).
    public static func incoming(remote: DocumentVersion, local: DocumentVersion?) -> Incoming {
        guard let local else { return remote.isDeleted ? .keepLocal : .adopt }
        if remote.isDeleted {
            return remote.revision >= local.revision ? .deleteLocal : .keepLocal
        }
        if remote.revision != local.revision {
            return remote.revision > local.revision ? .adopt : .keepLocal
        }
        return isNewer(remote.updatedAt, than: local.updatedAt) ? .adopt : .keepLocal
    }

    /// Envoi refusé : le serveur a une version de révision au moins égale.
    public static func rejected(local: DocumentVersion, server: DocumentVersion) -> Rejected {
        if server.revision > local.revision || server.isDeleted {
            return .adoptServer
        }
        return isNewer(local.updatedAt, than: server.updatedAt) ? .resend(revision: server.revision + 1) : .adoptServer
    }

    private static func isNewer(_ a: Date?, than b: Date?) -> Bool {
        (a ?? .distantPast) > (b ?? .distantPast)
    }
}
