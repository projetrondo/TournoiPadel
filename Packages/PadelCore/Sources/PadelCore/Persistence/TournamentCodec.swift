import Foundation

/// Encodage JSON versionné d'un tournoi. Même format pour la sauvegarde, la synchronisation et l'export.
public enum TournamentCodec {
    public enum DecodingFailure: Error, Equatable {
        /// Fichier produit par une version plus récente de l'application.
        case unsupportedSchemaVersion(Int)
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    public static func encode(_ tournament: Tournament) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(tournament)
    }

    public static func decode(_ data: Data) throws -> Tournament {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        guard version <= Tournament.currentSchemaVersion else {
            throw DecodingFailure.unsupportedSchemaVersion(version)
        }
        return try decoder.decode(Tournament.self, from: data)
    }
}
