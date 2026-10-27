import Foundation
import PadelCore

/// Client HTTP de l'API EAGLE (dossier `server/`). Garde le jeton d'accès en mémoire et le
/// renouvelle tout seul quand il expire.
actor EagleAPI: EagleBackend {
    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    private var refreshObserver: (@Sendable (String?) -> Void)?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Connexion

    func providers() async throws -> AuthProviders {
        try decode(AuthProviders.self, from: await send("GET", "auth/providers").data)
    }

    func startGoogleSignIn(codeChallenge: String) async throws -> URL {
        let response = try await send("POST", "auth/google/start", json: ["codeChallenge": codeChallenge])
        struct Start: Decodable { let authorizationUrl: URL }
        return try decode(Start.self, from: response.data).authorizationUrl
    }

    func redeemGoogle(handoff: String, codeVerifier: String) async throws -> AccountInfo {
        try await open(send("POST", "auth/google/redeem", json: ["handoff": handoff, "codeVerifier": codeVerifier]).data)
    }

    func signInWithApple(identityToken: String, nonce: String, name: String?) async throws -> AccountInfo {
        var body: [String: Any] = ["identityToken": identityToken, "nonce": nonce]
        if let name { body["name"] = name }
        return try await open(send("POST", "auth/apple", json: body).data)
    }

    func resume(refreshToken: String) {
        self.refreshToken = refreshToken
        accessToken = nil
    }

    func observeRefreshToken(_ observer: @escaping @Sendable (String?) -> Void) {
        refreshObserver = observer
    }

    func me() async throws -> AccountInfo {
        try decode(AccountInfo.self, from: await authorized("GET", "api/me").data)
    }

    func signOut() async {
        if let refreshToken {
            _ = try? await send("POST", "auth/logout", json: ["refreshToken": refreshToken])
        }
        clearTokens()
    }

    func deleteAccount() async throws {
        _ = try await authorized("DELETE", "api/me")
        clearTokens()
    }

    // MARK: - Sauvegarde

    func changes(since cursor: Int) async throws -> ChangePage {
        let data = try await authorized("GET", "api/sync?since=\(cursor)&limit=200").data
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = object["documents"] as? [[String: Any]] else { throw BackendError.unreachable }
        return ChangePage(
            documents: try documents.map(Self.document),
            cursor: object["cursor"] as? Int ?? cursor,
            hasMore: object["hasMore"] as? Bool ?? false
        )
    }

    func save(_ key: BackupKey, revision: Int, payload: Data) async throws -> SaveOutcome {
        let object = try JSONSerialization.jsonObject(with: payload)
        let response = try await authorized("PUT", "api/documents/\(key)", json: ["revision": revision, "payload": object], accepting: [409])
        guard response.status == 409 else { return .saved }
        guard let body = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let document = body["document"] as? [String: Any] else { throw BackendError.unreachable }
        return .conflict(try Self.document(document))
    }

    func delete(_ key: BackupKey, revision: Int) async throws {
        _ = try await authorized("DELETE", "api/documents/\(key)?revision=\(revision)")
    }

    // MARK: - Transport

    private struct Response {
        let status: Int
        let data: Data
    }

    private func open(_ data: Data) throws -> AccountInfo {
        struct Opened: Decodable {
            let accessToken: String
            let refreshToken: String
            let account: AccountInfo
        }
        let opened = try decode(Opened.self, from: data)
        accessToken = opened.accessToken
        setRefreshToken(opened.refreshToken)
        return opened.account
    }

    private func clearTokens() {
        accessToken = nil
        setRefreshToken(nil)
    }

    private func setRefreshToken(_ token: String?) {
        refreshToken = token
        refreshObserver?(token)
    }

    /// Requête authentifiée ; renouvelle le jeton d'accès une fois si le serveur le refuse.
    private func authorized(_ method: String, _ path: String, json: Any? = nil, accepting: Set<Int> = []) async throws -> Response {
        if accessToken == nil { try await renew() }
        do {
            return try await send(method, path, json: json, bearer: accessToken, accepting: accepting)
        } catch BackendError.signedOut {
            try await renew()
            return try await send(method, path, json: json, bearer: accessToken, accepting: accepting)
        }
    }

    private func renew() async throws {
        guard let refreshToken else { throw BackendError.signedOut }
        struct Renewed: Decodable {
            let accessToken: String
            let refreshToken: String
        }
        do {
            let renewed = try decode(Renewed.self, from: await send("POST", "auth/refresh", json: ["refreshToken": refreshToken]).data)
            accessToken = renewed.accessToken
            setRefreshToken(renewed.refreshToken)
        } catch BackendError.signedOut, BackendError.refused {
            clearTokens()
            throw BackendError.signedOut
        }
    }

    private func send(_ method: String, _ path: String, json: Any? = nil, bearer: String? = nil, accepting: Set<Int> = []) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw BackendError.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) || accepting.contains(status) {
            return Response(status: status, data: data)
        }
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        // 401 sur une requête authentifiée : jeton à renouveler. Sur une connexion : refus expliqué.
        if status == 401, bearer != nil { throw BackendError.signedOut }
        if let message, (400..<500).contains(status) { throw BackendError.refused(message) }
        if status == 401 { throw BackendError.signedOut }
        throw BackendError.unreachable
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BackendError.unreachable
        }
    }

    private static func document(_ object: [String: Any]) throws -> RemoteDocument {
        guard let kindRaw = object["kind"] as? String, let kind = BackupKind(rawValue: kindRaw),
              let idRaw = object["id"] as? String, let id = UUID(uuidString: idRaw),
              let revision = object["revision"] as? Int else { throw BackendError.unreachable }
        let payload = (object["payload"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return RemoteDocument(key: BackupKey(kind, id), revision: revision, isDeleted: object["deleted"] as? Bool ?? false, payload: payload)
    }
}
