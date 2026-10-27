import Foundation
import PadelCore

/// Serveur EAGLE simulé en mémoire, avec les mêmes règles que l'API (révision plus récente
/// seulement, suppressions tracées, curseur). Sert aux tests et aux captures d'écran.
final class InMemoryBackend: EagleBackend, @unchecked Sendable {
    private struct Stored {
        var revision: Int
        var payload: Data?
        var sequence: Int
    }

    private let lock = NSLock()
    private var documents: [BackupKey: Stored] = [:]
    private var sequence = 0
    private var signedIn: Bool
    private var refreshObserver: (@Sendable (String?) -> Void)?
    let account: AccountInfo
    /// Simule une coupure réseau.
    var isReachable = true

    init(account: AccountInfo = AccountInfo(id: "compte-demo", displayName: "Léa", email: "lea@example.com", providers: ["google"]), signedIn: Bool = false) {
        self.account = account
        self.signedIn = signedIn
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard isReachable else { throw BackendError.unreachable }
        return try body()
    }

    private func authorized<T>(_ body: () throws -> T) throws -> T {
        try locked {
            guard signedIn else { throw BackendError.signedOut }
            return try body()
        }
    }

    /// Écrit directement côté serveur, comme le ferait un autre appareil du compte.
    func storeFromAnotherDevice(_ key: BackupKey, revision: Int, payload: Data?) {
        lock.lock(); defer { lock.unlock() }
        sequence += 1
        documents[key] = Stored(revision: revision, payload: payload, sequence: sequence)
    }

    func storedRevision(_ key: BackupKey) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return documents[key]?.revision
    }

    func storedPayload(_ key: BackupKey) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return documents[key]?.payload
    }

    func providers() async throws -> AuthProviders {
        try locked { AuthProviders(google: true, apple: true) }
    }

    func startGoogleSignIn(codeChallenge: String) async throws -> URL {
        try locked { URL(string: "https://accounts.google.com/o/oauth2/v2/auth?demo=1")! }
    }

    func redeemGoogle(handoff: String, codeVerifier: String) async throws -> AccountInfo {
        try open()
    }

    func signInWithApple(identityToken: String, nonce: String, name: String?) async throws -> AccountInfo {
        try open()
    }

    private func open() throws -> AccountInfo {
        let account = try locked {
            signedIn = true
            return self.account
        }
        refreshObserver?("jeton-demo")
        return account
    }

    func resume(refreshToken: String) async {
        lock.lock(); signedIn = true; lock.unlock()
    }

    func observeRefreshToken(_ observer: @escaping @Sendable (String?) -> Void) async {
        refreshObserver = observer
    }

    func me() async throws -> AccountInfo {
        try authorized { account }
    }

    func signOut() async {
        lock.lock(); signedIn = false; lock.unlock()
        refreshObserver?(nil)
    }

    func deleteAccount() async throws {
        try authorized {
            documents = [:]
            signedIn = false
        }
        refreshObserver?(nil)
    }

    func changes(since cursor: Int) async throws -> ChangePage {
        try authorized {
            let changed = documents.filter { $0.value.sequence > cursor }.sorted { $0.value.sequence < $1.value.sequence }
            return ChangePage(
                documents: changed.map { RemoteDocument(key: $0.key, revision: $0.value.revision, isDeleted: $0.value.payload == nil, payload: $0.value.payload) },
                cursor: changed.last?.value.sequence ?? cursor,
                hasMore: false
            )
        }
    }

    func save(_ key: BackupKey, revision: Int, payload: Data) async throws -> SaveOutcome {
        try authorized {
            if let existing = documents[key], existing.revision >= revision {
                if existing.revision == revision, existing.payload == payload { return .saved }
                return .conflict(RemoteDocument(key: key, revision: existing.revision, isDeleted: existing.payload == nil, payload: existing.payload))
            }
            sequence += 1
            documents[key] = Stored(revision: revision, payload: payload, sequence: sequence)
            return .saved
        }
    }

    func delete(_ key: BackupKey, revision: Int) async throws {
        try authorized {
            guard let existing = documents[key], existing.payload != nil else { return }
            sequence += 1
            documents[key] = Stored(revision: max(existing.revision, revision), payload: nil, sequence: sequence)
        }
    }
}
