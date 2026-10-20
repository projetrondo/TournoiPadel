import Foundation

/// Version publiée d'un tournoi, telle qu'elle est stockée en ligne.
public struct PublishedSnapshot: Hashable, Sendable {
    public let code: InviteCode
    public let revision: Int
    public let organizerDeviceID: String?
    public let payload: Data

    public init(code: InviteCode, revision: Int, organizerDeviceID: String?, payload: Data) {
        self.code = code
        self.revision = revision
        self.organizerDeviceID = organizerDeviceID
        self.payload = payload
    }

    /// Prépare la publication d'un tournoi d'organisateur.
    public init(tournament: Tournament, code: InviteCode, deviceID: String) throws {
        var published = tournament
        published.sharing = SharingInfo(code: code.value, role: .organizer, organizerDeviceID: deviceID)
        self.init(code: code, revision: tournament.revision, organizerDeviceID: deviceID,
                  payload: try TournamentCodec.encode(published))
    }

    public func decodeTournament() throws -> Tournament {
        try TournamentCodec.decode(payload)
    }
}

public enum SyncError: Error, Hashable, Sendable {
    /// La copie locale est en lecture seule (spectateur).
    case readOnly
    /// Le code reçu ne correspond à aucun tournoi en ligne (ou il a été dépublié).
    case notFound
    /// Le tournoi en ligne a été modifié depuis un autre appareil organisateur.
    case conflict(remoteRevision: Int)
    /// Le tournoi en ligne ne correspond pas à la copie locale (code réattribué).
    case mismatchedTournament
}

/// Règles de synchronisation, indépendantes de CloudKit.
///
/// Principe : un seul écrivain. L'organisateur est la source de vérité ; les spectateurs
/// n'acceptent une version distante que si elle est plus récente. Rien n'est jamais
/// remplacé silencieusement par une version plus ancienne.
public enum SyncRules {
    /// Spectateur : intègre une version distante dans la copie locale.
    /// Renvoie `nil` si la copie locale est déjà à jour (ou plus récente).
    public static func applyRemote(_ snapshot: PublishedSnapshot, to local: Tournament?, now: Date) throws -> Tournament? {
        var remote = try snapshot.decodeTournament()
        if let local {
            guard local.id == remote.id else { throw SyncError.mismatchedTournament }
            guard local.sharing?.effectiveRole != .organizer else { return nil }
            guard snapshot.revision > (local.sharing?.lastPublishedRevision ?? -1) else { return nil }
        }
        remote.sharing = SharingInfo(
            code: snapshot.code.value,
            role: .viewer,
            organizerDeviceID: snapshot.organizerDeviceID,
            lastPublishedRevision: snapshot.revision,
            lastSyncedAt: now
        )
        return remote
    }

    /// Organisateur : la version locale doit-elle être envoyée ?
    public static func needsPublish(_ tournament: Tournament) -> Bool {
        guard let sharing = tournament.sharing, sharing.effectiveRole == .organizer else { return false }
        return (sharing.lastPublishedRevision ?? -1) < tournament.revision
    }

    /// Organisateur : peut-on écraser la version en ligne ?
    /// Oui si elle n'existe pas, si elle vient de cet appareil, ou si elle n'est pas plus récente
    /// que la dernière version que cet appareil a publiée. Sinon, conflit à résoudre par
    /// l'organisateur (cas d'une reprise d'organisation sur un autre appareil).
    public static func canOverwrite(remote: PublishedSnapshot?, local: Tournament, deviceID: String) -> Bool {
        guard let remote else { return true }
        if remote.organizerDeviceID == deviceID { return true }
        return remote.revision <= (local.sharing?.lastPublishedRevision ?? -1)
    }

    /// Organisateur : enregistre localement qu'une révision a bien été publiée.
    public static func markPublished(_ tournament: inout Tournament, revision: Int, code: InviteCode, deviceID: String, now: Date) {
        var sharing = tournament.sharing ?? SharingInfo(code: code.value)
        sharing.code = code.value
        sharing.role = .organizer
        sharing.organizerDeviceID = deviceID
        sharing.lastPublishedRevision = max(sharing.lastPublishedRevision ?? -1, revision)
        sharing.lastSyncedAt = now
        tournament.sharing = sharing
    }

    /// Délai avant une nouvelle tentative d'envoi : 2 s, 4 s, 8 s… plafonné à 2 minutes.
    public static func retryDelay(attempt: Int) -> TimeInterval {
        min(120, pow(2, Double(max(1, attempt))))
    }
}

extension Tournament {
    /// Copie d'un spectateur : aucune modification locale n'est autorisée.
    public var isReadOnly: Bool {
        sharing?.effectiveRole == .viewer
    }
}
