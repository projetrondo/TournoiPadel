import Foundation

/// Résultat d'un chargement : les tournois lisibles et les fichiers qui n'ont pas pu être lus.
public struct TournamentLoadResult: Sendable {
    public var tournaments: [Tournament]
    public var unreadableFiles: [URL]

    public init(tournaments: [Tournament], unreadableFiles: [URL]) {
        self.tournaments = tournaments
        self.unreadableFiles = unreadableFiles
    }
}

public protocol TournamentStore: Sendable {
    func loadAll() throws -> TournamentLoadResult
    func save(_ tournament: Tournament) throws
    func delete(id: Tournament.ID) throws
}

/// Un fichier JSON par tournoi, écrit de façon atomique (fichier temporaire puis renommage) :
/// une interruption pendant l'écriture ne peut jamais laisser un fichier à moitié écrit.
/// Un fichier illisible n'est jamais supprimé : il est déplacé dans `Unreadable/` pour diagnostic.
public struct FileTournamentStore: TournamentStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func fileURL(for id: Tournament.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    public func loadAll() throws -> TournamentLoadResult {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        var tournaments: [Tournament] = []
        var unreadable: [URL] = []
        for file in files {
            do {
                tournaments.append(try TournamentCodec.decode(Data(contentsOf: file)))
            } catch TournamentCodec.DecodingFailure.unsupportedSchemaVersion {
                // Fichier d'une version plus récente : on le laisse en place, intact.
                unreadable.append(file)
            } catch {
                unreadable.append(quarantine(file) ?? file)
            }
        }
        tournaments.sort { $0.updatedAt > $1.updatedAt }
        return TournamentLoadResult(tournaments: tournaments, unreadableFiles: unreadable)
    }

    public func save(_ tournament: Tournament) throws {
        try ensureDirectory()
        let data = try TournamentCodec.encode(tournament)
        #if canImport(Darwin)
        try data.write(to: fileURL(for: tournament.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL(for: tournament.id), options: [.atomic])
        #endif
    }

    public func delete(id: Tournament.ID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func quarantine(_ file: URL) -> URL? {
        let folder = directory.appendingPathComponent("Unreadable", isDirectory: true)
        let target = folder.appendingPathComponent(
            "\(Int(Date().timeIntervalSince1970))-\(file.lastPathComponent)"
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file, to: target)
            return target
        } catch {
            return nil
        }
    }
}

/// Stockage en mémoire, pour les tests et les aperçus SwiftUI.
public final class InMemoryTournamentStore: TournamentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Tournament.ID: Tournament]

    public init(_ tournaments: [Tournament] = []) {
        storage = Dictionary(uniqueKeysWithValues: tournaments.map { ($0.id, $0) })
    }

    public func loadAll() throws -> TournamentLoadResult {
        lock.lock(); defer { lock.unlock() }
        let sorted = storage.values.sorted { $0.updatedAt > $1.updatedAt }
        return TournamentLoadResult(tournaments: sorted, unreadableFiles: [])
    }

    public func save(_ tournament: Tournament) throws {
        lock.lock(); defer { lock.unlock() }
        storage[tournament.id] = tournament
    }

    public func delete(id: Tournament.ID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[id] = nil
    }
}
