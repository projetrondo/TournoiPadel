import Foundation
import Testing
@testable import PadelCore

@Suite("Codes d'invitation")
struct InviteCodeTests {
    @Test("Codes aléatoires valides et variés")
    func randomCodes() {
        var generator = SeededGenerator(seed: 1)
        let codes = (0..<1_000).map { _ in InviteCode.random(using: &generator) }
        #expect(codes.allSatisfy { InviteCode($0.value) == $0 })
        #expect(codes.allSatisfy { $0.value.count == 6 })
        #expect(Set(codes).count == 1_000)
    }

    @Test("Saisie tolérante : minuscules, espaces, tirets")
    func lenientInput() {
        #expect(InviteCode("k7m 2qp")?.value == "K7M2QP")
        #expect(InviteCode("K7M-2QP")?.value == "K7M2QP")
        #expect(InviteCode(" k7m2qp ")?.value == "K7M2QP")
    }

    @Test("Codes invalides refusés")
    func invalidCodes() {
        #expect(InviteCode("K7M2Q") == nil)        // trop court
        #expect(InviteCode("K7M2QO") == nil)       // O ambigu
        #expect(InviteCode("K7M2Q1") == nil)       // 1 ambigu
        #expect(InviteCode("") == nil)
    }

    @Test("Nettoyage pendant la frappe")
    func clean() {
        #expect(InviteCode.clean("k7m-2qp-xyz") == "K7M2QP")
        #expect(InviteCode.clean("io01") == "")
    }

    @Test("Affichage et lien")
    func formatting() throws {
        let code = try #require(InviteCode("K7M2QP"))
        #expect(code.formatted == "K7M 2QP")
        #expect(code.appURL.absoluteString == "padelbuddy://join/K7M2QP")
    }

    @Test("Lecture d'un lien d'invitation")
    func parseURL() throws {
        #expect(InviteCode(url: try #require(URL(string: "padelbuddy://join/K7M2QP")))?.value == "K7M2QP")
        #expect(InviteCode(url: try #require(URL(string: "padelbuddy://join?code=k7m2qp")))?.value == "K7M2QP")
        #expect(InviteCode(url: try #require(URL(string: "padelbuddy://autre/K7M2QP"))) == nil)
        #expect(InviteCode(url: try #require(URL(string: "https://join/K7M2QP"))) == nil)
        #expect(InviteCode(url: try #require(URL(string: "padelbuddy://join/"))) == nil)
    }
}

@Suite("Règles de synchronisation")
struct SyncRulesTests {
    let code = InviteCode("K7M2QP")!
    let organizerDevice = "device-orga"

    func organizerTournament() throws -> Tournament {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        try t.start(now: Date(timeIntervalSince1970: 0))
        SyncRules.markPublished(&t, revision: t.revision, code: code, deviceID: organizerDevice, now: Date())
        return t
    }

    @Test("Un spectateur reçoit une copie en lecture seule")
    func viewerReceivesCopy() throws {
        let organizer = try organizerTournament()
        let snapshot = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        let copy = try #require(try SyncRules.applyRemote(snapshot, to: nil, now: Date(timeIntervalSince1970: 50)))
        #expect(copy.id == organizer.id)
        #expect(copy.rounds == organizer.rounds)
        #expect(copy.isReadOnly)
        #expect(copy.sharing?.lastPublishedRevision == organizer.revision)
        #expect(copy.sharing?.lastSyncedAt == Date(timeIntervalSince1970: 50))
        #expect(!SyncRules.needsPublish(copy), "un spectateur ne publie jamais")
    }

    @Test("Une version plus récente remplace la copie, une plus ancienne est ignorée")
    func viewerAcceptsOnlyNewer() throws {
        var organizer = try organizerTournament()
        let old = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        let copy = try #require(try SyncRules.applyRemote(old, to: nil, now: Date()))

        try organizer.validateScore(organizer.rounds[0].matches[0].id, score: Score(15, 9), now: Date())
        let new = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        let updated = try #require(try SyncRules.applyRemote(new, to: copy, now: Date()))
        #expect(updated.rounds[0].matches[0].score == Score(15, 9))

        #expect(try SyncRules.applyRemote(old, to: updated, now: Date()) == nil)
        #expect(try SyncRules.applyRemote(new, to: updated, now: Date()) == nil)
    }

    @Test("La copie de l'organisateur n'est jamais écrasée par le serveur")
    func organizerNeverOverwritten() throws {
        let organizer = try organizerTournament()
        let snapshot = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        #expect(try SyncRules.applyRemote(snapshot, to: organizer, now: Date()) == nil)
    }

    @Test("Un code qui pointe vers un autre tournoi est signalé")
    func mismatch() throws {
        let organizer = try organizerTournament()
        let snapshot = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        var other = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        other.sharing = SharingInfo(code: code.value, role: .viewer)
        #expect(throws: SyncError.mismatchedTournament) { try SyncRules.applyRemote(snapshot, to: other, now: Date()) }
    }

    @Test("File d'envoi : publication nécessaire après chaque modification")
    func needsPublish() throws {
        var organizer = try organizerTournament()
        #expect(!SyncRules.needsPublish(organizer))
        try organizer.validateScore(organizer.rounds[0].matches[0].id, score: Score(15, 9), now: Date())
        #expect(SyncRules.needsPublish(organizer))
        SyncRules.markPublished(&organizer, revision: organizer.revision, code: code, deviceID: organizerDevice, now: Date())
        #expect(!SyncRules.needsPublish(organizer))
        // Un tournoi jamais partagé n'est pas publié.
        #expect(!SyncRules.needsPublish(TestSupport.tournament(format: .americano, players: 4, rounds: 3)))
    }

    @Test("Publication d'une ancienne révision : on garde la plus récente déjà publiée")
    func markPublishedKeepsMax() throws {
        var organizer = try organizerTournament()
        let revision = organizer.revision
        SyncRules.markPublished(&organizer, revision: revision - 1, code: code, deviceID: organizerDevice, now: Date())
        #expect(organizer.sharing?.lastPublishedRevision == revision)
    }

    @Test("Écrasement autorisé seulement sans conflit")
    func overwriteRules() throws {
        let organizer = try organizerTournament()
        let mine = try PublishedSnapshot(tournament: organizer, code: code, deviceID: organizerDevice)
        #expect(SyncRules.canOverwrite(remote: nil, local: organizer, deviceID: organizerDevice))
        #expect(SyncRules.canOverwrite(remote: mine, local: organizer, deviceID: organizerDevice))

        // Un autre appareil a publié une révision plus récente que la nôtre : conflit.
        var other = organizer
        other.revision += 5
        let theirs = try PublishedSnapshot(tournament: other, code: code, deviceID: "autre-appareil")
        #expect(!SyncRules.canOverwrite(remote: theirs, local: organizer, deviceID: organizerDevice))
    }

    @Test("Délais de nouvelle tentative croissants et plafonnés")
    func retry() {
        #expect(SyncRules.retryDelay(attempt: 1) == 2)
        #expect(SyncRules.retryDelay(attempt: 3) == 8)
        #expect(SyncRules.retryDelay(attempt: 20) == 120)
    }

    @Test("Anciens fichiers sans rôle : considérés comme organisateur")
    func legacySharingDecoding() throws {
        let json = #"{"code":"K7M2QP","lastPublishedRevision":3}"#
        let decoded = try JSONDecoder().decode(SharingInfo.self, from: Data(json.utf8))
        #expect(decoded.effectiveRole == .organizer)
        #expect(decoded.lastSyncedAt == nil)
    }
}
