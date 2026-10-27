import Foundation
import PadelCore

/// Compte connecté, tel que l'API le décrit.
struct AccountInfo: Codable, Hashable, Sendable {
    let id: String
    let displayName: String?
    let email: String?
    let providers: [String]
}

struct AuthProviders: Decodable, Hashable, Sendable {
    let google: Bool
    let apple: Bool
}

/// Un document lu sur le serveur (`payload` : JSON du tournoi ou de la session).
struct RemoteDocument: Hashable, Sendable {
    let key: BackupKey
    let revision: Int
    let isDeleted: Bool
    let payload: Data?
}

struct ChangePage: Sendable {
    let documents: [RemoteDocument]
    let cursor: Int
    let hasMore: Bool
}

enum SaveOutcome: Sendable {
    case saved
    /// Le serveur a une version au moins aussi récente : la voici.
    case conflict(RemoteDocument)
}

enum BackendError: Error, Equatable, Sendable {
    /// Session expirée ou révoquée : il faut se reconnecter.
    case signedOut
    /// Pas de réseau, ou serveur injoignable.
    case unreachable
    /// Refus expliqué par le serveur (message affichable).
    case refused(String)
    /// Connexion annulée par l'utilisateur.
    case cancelled

    var message: String {
        switch self {
        case .signedOut: String(localized: "Votre session a expiré. Reconnectez-vous.")
        case .unreachable: String(localized: "Serveur injoignable. Vos données restent sur l'iPhone ; la sauvegarde reprendra au retour du réseau.")
        case .refused(let message): message
        case .cancelled: String(localized: "Connexion annulée.")
        }
    }
}

/// Le serveur EAGLE : connexion et sauvegarde. Deux implémentations : HTTP (`EagleAPI`) et
/// en mémoire (`InMemoryBackend`, pour les tests et les captures d'écran).
protocol EagleBackend: AnyObject, Sendable {
    func providers() async throws -> AuthProviders
    func startGoogleSignIn(codeChallenge: String) async throws -> URL
    func redeemGoogle(handoff: String, codeVerifier: String) async throws -> AccountInfo
    func signInWithApple(identityToken: String, nonce: String, name: String?) async throws -> AccountInfo
    /// Reprend une session enregistrée (jeton de renouvellement du trousseau).
    func resume(refreshToken: String) async
    /// Appelé à chaque nouveau jeton de renouvellement (à enregistrer), ou nil à la déconnexion.
    func observeRefreshToken(_ observer: @escaping @Sendable (String?) -> Void) async
    func me() async throws -> AccountInfo
    func signOut() async
    func deleteAccount() async throws
    func changes(since cursor: Int) async throws -> ChangePage
    func save(_ key: BackupKey, revision: Int, payload: Data) async throws -> SaveOutcome
    func delete(_ key: BackupKey, revision: Int) async throws
}
