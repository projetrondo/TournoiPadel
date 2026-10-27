import Foundation
import Testing
@testable import PadelCore

@Suite("Sauvegarde en ligne : règles")
struct BackupRulesTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static func version(_ revision: Int, _ minutes: Double = 0, deleted: Bool = false) -> DocumentVersion {
        DocumentVersion(revision: revision, updatedAt: t0.addingTimeInterval(minutes * 60), isDeleted: deleted)
    }

    @Test("Document inconnu sur l'appareil : on le récupère ; une suppression est ignorée")
    func unknownLocally() {
        #expect(BackupRules.incoming(remote: Self.version(3), local: nil) == .adopt)
        #expect(BackupRules.incoming(remote: Self.version(3, deleted: true), local: nil) == .keepLocal)
    }

    @Test("Jamais une version plus ancienne ne remplace la version locale")
    func olderNeverWins() {
        #expect(BackupRules.incoming(remote: Self.version(5), local: Self.version(4)) == .adopt)
        #expect(BackupRules.incoming(remote: Self.version(4), local: Self.version(5)) == .keepLocal)
    }

    @Test("Même révision, modifiée sur deux appareils : la dernière modification l'emporte")
    func sameRevision() {
        #expect(BackupRules.incoming(remote: Self.version(4, 10), local: Self.version(4, 5)) == .adopt)
        #expect(BackupRules.incoming(remote: Self.version(4, 5), local: Self.version(4, 10)) == .keepLocal)
        #expect(BackupRules.incoming(remote: Self.version(4, 5), local: Self.version(4, 5)) == .keepLocal, "identique : rien à faire")
    }

    @Test("Suppression faite ailleurs : appliquée, sauf si la copie locale a été modifiée depuis")
    func remoteDeletion() {
        #expect(BackupRules.incoming(remote: Self.version(6, deleted: true), local: Self.version(5)) == .deleteLocal)
        #expect(BackupRules.incoming(remote: Self.version(6, deleted: true), local: Self.version(7)) == .keepLocal)
    }

    @Test("Envoi refusé : version du serveur plus récente, ou locale renvoyée si elle est la dernière")
    func rejectedUpload() {
        #expect(BackupRules.rejected(local: Self.version(4), server: Self.version(6)) == .adoptServer)
        #expect(BackupRules.rejected(local: Self.version(4, 10), server: Self.version(4, 5)) == .resend(revision: 5))
        #expect(BackupRules.rejected(local: Self.version(4, 5), server: Self.version(4, 10)) == .adoptServer)
        #expect(BackupRules.rejected(local: Self.version(4, 10), server: Self.version(4, 5, deleted: true)) == .adoptServer)
    }

    @Test("Registre : envoi nécessaire tant que le serveur n'a pas confirmé la révision locale")
    func ledger() throws {
        var ledger = BackupLedger(accountID: "compte")
        let key = BackupKey(.tournament, UUID())
        #expect(ledger.needsUpload(key, revision: 1))
        ledger.confirm(key, revision: 3)
        #expect(!ledger.needsUpload(key, revision: 3))
        #expect(ledger.needsUpload(key, revision: 4))

        ledger.recordLocalDeletion(key, revision: 4)
        #expect(ledger.pendingDeletions[key.description] == 5)
        ledger.forget(key)
        #expect(ledger.pendingDeletions.isEmpty && ledger.confirmed.isEmpty)

        // Jamais envoyé : rien à supprimer sur le serveur.
        let local = BackupKey(.session, UUID())
        ledger.recordLocalDeletion(local, revision: 2)
        #expect(ledger.pendingDeletions.isEmpty)

        let decoded = try JSONDecoder().decode(BackupLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
    }

    @Test("Clé de document : forme attendue par l'API")
    func keyFormat() {
        let id = UUID(uuidString: "5E55E55E-0000-4000-8000-000000000001")!
        #expect(BackupKey(.session, id).description == "session/5e55e55e-0000-4000-8000-000000000001")
    }
}
