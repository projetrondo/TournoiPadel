import Foundation

/// Encodage JSON versionné d'une session (même conventions que `TournamentCodec`).
public enum SessionCodec {
    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    public static func encode(_ session: PlaySession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(session)
    }

    public static func decode(_ data: Data) throws -> PlaySession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        guard version <= PlaySession.currentSchemaVersion else {
            throw TournamentCodec.DecodingFailure.unsupportedSchemaVersion(version)
        }
        return try decoder.decode(PlaySession.self, from: data)
    }
}

public protocol SessionStore: Sendable {
    func loadAll() throws -> [PlaySession]
    func save(_ session: PlaySession) throws
    func delete(id: PlaySession.ID) throws
}

/// Un fichier JSON par session, écrit de façon atomique. Un fichier illisible est ignoré
/// et laissé en place (jamais supprimé).
public struct FileSessionStore: SessionStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(for id: PlaySession.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    public func loadAll() throws -> [PlaySession] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        return files
            .compactMap { try? SessionCodec.decode(Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ session: PlaySession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try SessionCodec.encode(session)
        #if canImport(Darwin)
        try data.write(to: fileURL(for: session.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL(for: session.id), options: [.atomic])
        #endif
    }

    public func delete(id: PlaySession.ID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// Stockage en mémoire, pour les tests et les captures d'écran.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PlaySession.ID: PlaySession]

    public init(_ sessions: [PlaySession] = []) {
        storage = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    public func loadAll() throws -> [PlaySession] {
        lock.lock(); defer { lock.unlock() }
        return storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ session: PlaySession) throws {
        lock.lock(); defer { lock.unlock() }
        storage[session.id] = session
    }

    public func delete(id: PlaySession.ID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[id] = nil
    }
}
