import Foundation
import PadelCore

/// Erreurs de synchronisation présentées à l'utilisateur.
enum SyncFailure: Error, Equatable {
    /// Pas de connexion : les modifications restent sur l'iPhone et partiront plus tard.
    case offline
    /// Partage non configuré dans cette version (compte Apple Developer / CloudKit absent).
    case notConfigured
    /// Pas de compte iCloud sur cet iPhone (nécessaire pour publier, pas pour suivre).
    case noAccount
    /// Aucun tournoi en ligne pour ce code (ou il a été dépublié).
    case notFound
    /// Plus de code libre après plusieurs essais (très improbable).
    case codeUnavailable
    /// Le tournoi en ligne a été modifié depuis un autre appareil.
    case conflict
    /// Le service a demandé de patienter (trop de requêtes).
    case rateLimited(retryAfter: TimeInterval?)
    case other(String)

    var message: String {
        switch self {
        case .offline:
            String(localized: "Pas de connexion. Les scores sont enregistrés sur cet iPhone et seront envoyés dès le retour du réseau.")
        case .notConfigured:
            String(localized: "Le partage entre iPhone n'est pas encore activé dans cette version de l'app.")
        case .noAccount:
            String(localized: "Connectez-vous à iCloud (Réglages › votre nom) pour publier un tournoi. Suivre un tournoi ne nécessite pas de compte.")
        case .notFound:
            String(localized: "Aucun tournoi ne correspond à ce code. Vérifiez-le auprès de l'organisateur : le tournoi a peut-être été retiré.")
        case .codeUnavailable:
            String(localized: "Impossible d'obtenir un code d'invitation. Réessayez dans un instant.")
        case .conflict:
            String(localized: "Ce tournoi a été modifié en ligne depuis un autre appareil. Rien n'a été remplacé.")
        case .rateLimited:
            String(localized: "Le service de partage est très sollicité. Nouvel essai automatique dans un instant.")
        case .other(let detail):
            String(localized: "Le partage a échoué (\(detail)). Les données de cet iPhone sont intactes.")
        }
    }
}

enum SyncAvailability: Equatable {
    case available
    case noAccount
    case notConfigured
    /// Statut iCloud inconnu (réseau, restriction…) : on tentera quand même.
    case unknown
}

/// Accès au stockage en ligne des tournois partagés.
protocol TournamentSyncService: Sendable {
    var isConfigured: Bool { get }
    func availability() async -> SyncAvailability
    /// `nil` si aucun tournoi n'est publié avec ce code.
    func fetch(code: InviteCode) async throws -> PublishedSnapshot?
    /// Crée ou remplace la version en ligne (seul son créateur peut la remplacer).
    func publish(_ snapshot: PublishedSnapshot) async throws
    func delete(code: InviteCode) async throws
}

/// Version sans partage (avant l'activation de CloudKit) : tout échoue proprement.
struct UnavailableSyncService: TournamentSyncService {
    var isConfigured: Bool { false }
    func availability() async -> SyncAvailability { .notConfigured }
    func fetch(code: InviteCode) async throws -> PublishedSnapshot? { throw SyncFailure.notConfigured }
    func publish(_ snapshot: PublishedSnapshot) async throws { throw SyncFailure.notConfigured }
    func delete(code: InviteCode) async throws { throw SyncFailure.notConfigured }
}

/// Serveur simulé en mémoire : tests, aperçus et captures d'écran.
actor InMemorySyncService: TournamentSyncService {
    private var records: [InviteCode: PublishedSnapshot] = [:]
    private(set) var isOnline = true
    private(set) var publishCount = 0

    nonisolated var isConfigured: Bool { true }

    func setOnline(_ online: Bool) { isOnline = online }

    func availability() async -> SyncAvailability { .available }

    func fetch(code: InviteCode) async throws -> PublishedSnapshot? {
        guard isOnline else { throw SyncFailure.offline }
        return records[code]
    }

    func publish(_ snapshot: PublishedSnapshot) async throws {
        guard isOnline else { throw SyncFailure.offline }
        records[snapshot.code] = snapshot
        publishCount += 1
    }

    func delete(code: InviteCode) async throws {
        guard isOnline else { throw SyncFailure.offline }
        records[code] = nil
    }

    /// Simule une publication faite depuis un autre appareil.
    func inject(_ snapshot: PublishedSnapshot) {
        records[snapshot.code] = snapshot
    }
}
