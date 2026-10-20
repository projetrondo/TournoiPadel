import CloudKit
import Foundation
import PadelCore

/// Stockage des tournois partagés dans la base **publique** CloudKit de l'application.
///
/// - Un enregistrement `SharedTournament` par tournoi, identifié par `T_<code>` : on le lit
///   directement par son identifiant, sans requête ni index, donc sans pouvoir lister les
///   tournois des autres.
/// - Lecture possible sans compte iCloud ; écriture réservée au créateur de l'enregistrement
///   (rôle « Creator » par défaut de la base publique), ce qui garantit côté serveur que seul
///   l'organisateur modifie son tournoi.
/// - Écriture conditionnelle (`ifServerRecordUnchanged`) : jamais d'écrasement silencieux.
final class CloudKitSyncService: TournamentSyncService, @unchecked Sendable {
    static let recordType = "SharedTournament"

    private enum Field {
        static let payload = "payload"
        static let revision = "revision"
        static let organizerDeviceID = "organizerDeviceID"
        static let schemaVersion = "schemaVersion"
    }

    private let container: CKContainer

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    var isConfigured: Bool { true }

    private var database: CKDatabase { container.publicCloudDatabase }

    private func recordID(_ code: InviteCode) -> CKRecord.ID {
        CKRecord.ID(recordName: "T_\(code.value)")
    }

    func availability() async -> SyncAvailability {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount, .restricted: return .noAccount
            case .couldNotDetermine, .temporarilyUnavailable: return .unknown
            @unknown default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    func fetch(code: InviteCode) async throws -> PublishedSnapshot? {
        do {
            let record = try await database.record(for: recordID(code))
            return try snapshot(from: record, code: code)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw Self.map(error)
        }
    }

    func publish(_ snapshot: PublishedSnapshot) async throws {
        let id = recordID(snapshot.code)
        do {
            let record: CKRecord
            do {
                record = try await database.record(for: id)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: id)
            }
            record[Field.payload] = snapshot.payload
            record[Field.revision] = Int64(snapshot.revision)
            record[Field.organizerDeviceID] = snapshot.organizerDeviceID
            record[Field.schemaVersion] = Int64(Tournament.currentSchemaVersion)

            let (saveResults, _) = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            if case .failure(let error) = saveResults[id] {
                throw error
            }
        } catch {
            throw Self.map(error)
        }
    }

    func delete(code: InviteCode) async throws {
        do {
            _ = try await database.deleteRecord(withID: recordID(code))
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw Self.map(error)
        }
    }

    private func snapshot(from record: CKRecord, code: InviteCode) throws -> PublishedSnapshot {
        guard let payload = record[Field.payload] as? Data,
              let revision = record[Field.revision] as? Int64 else {
            throw SyncFailure.other(String(localized: "données en ligne incomplètes"))
        }
        return PublishedSnapshot(
            code: code,
            revision: Int(revision),
            organizerDeviceID: record[Field.organizerDeviceID] as? String,
            payload: payload
        )
    }

    static func map(_ error: Error) -> SyncFailure {
        if let failure = error as? SyncFailure { return failure }
        guard let error = error as? CKError else { return .other(error.localizedDescription) }
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy:
            return .offline
        case .notAuthenticated:
            return .noAccount
        case .serverRecordChanged:
            return .conflict
        case .permissionFailure:
            // L'enregistrement existe mais appartient à quelqu'un d'autre : code déjà pris.
            return .codeUnavailable
        case .requestRateLimited:
            return .rateLimited(retryAfter: error.retryAfterSeconds)
        case .badContainer, .missingEntitlement:
            return .notConfigured
        default:
            return .other(error.localizedDescription)
        }
    }
}
