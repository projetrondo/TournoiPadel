import Foundation
import PadelCore
import Testing
@testable import PadelBuddy

@MainActor
@Suite("Partage entre iPhone (serveur simulé)")
struct SyncCoordinatorTests {
    struct Device {
        let library: TournamentLibrary
        let sync: SyncCoordinator
    }

    static func device(_ server: InMemorySyncService, id: String) -> Device {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        library.loadIfNeeded()
        let sync = SyncCoordinator(library: library, service: server, deviceID: id)
        sync.debounce = .zero
        return Device(library: library, sync: sync)
    }

    static func startedTournament(on device: Device) async throws -> Tournament.ID {
        let draft = TournamentDraft(
            name: "Jeudi",
            players: ["Léa", "Max", "Inès", "Tom"].map { .init(name: $0) },
            courts: 1,
            rounds: 3
        )
        let tournament = try device.library.create(from: draft)
        try await device.library.start(id: tournament.id)
        return tournament.id
    }

    @Test("Partager, rejoindre, suivre les scores")
    func shareJoinFollow() async throws {
        let server = InMemorySyncService()
        let organizer = Self.device(server, id: "orga")
        let friend = Self.device(server, id: "ami")
        let id = try await Self.startedTournament(on: organizer)

        let code = try await organizer.sync.share(id)
        #expect(organizer.library.tournament(id: id)?.sharing?.code == code.value)

        let joined = try await friend.sync.join(code: code)
        #expect(joined == id)
        let copy = try #require(friend.library.tournament(id: id))
        #expect(copy.isReadOnly)
        #expect(copy.rounds == organizer.library.tournament(id: id)?.rounds)

        // L'organisateur valide un score : envoi automatique, le spectateur le reçoit.
        let match = try #require(organizer.library.tournament(id: id)?.orderedMatches.first)
        try organizer.library.modify(id: id) { t, date in try t.validateScore(match.id, score: Score(15, 9), now: date) }
        await organizer.sync.waitForPendingPublish(id)
        #expect(organizer.sync.status(of: id).date != nil, "envoi terminé")

        await friend.sync.refresh(id)
        #expect(friend.library.tournament(id: id)?.match(match.id)?.score == Score(15, 9))
        #expect(friend.library.tournament(id: id)?.standings.first?.stats.pointsFor == 15)
    }

    @Test("Le spectateur ne peut rien modifier")
    func viewerIsReadOnly() async throws {
        let server = InMemorySyncService()
        let organizer = Self.device(server, id: "orga")
        let friend = Self.device(server, id: "ami")
        let id = try await Self.startedTournament(on: organizer)
        let code = try await organizer.sync.share(id)
        _ = try await friend.sync.join(code: code)

        let match = try #require(friend.library.tournament(id: id)?.orderedMatches.first)
        #expect(throws: SyncError.readOnly) {
            try friend.library.modify(id: id) { t, date in try t.validateScore(match.id, score: Score(15, 9), now: date) }
        }
        #expect(friend.library.tournament(id: id)?.match(match.id)?.score == nil)
    }

    @Test("Hors ligne : rien n'est perdu, envoi au retour du réseau")
    func offlineQueue() async throws {
        let server = InMemorySyncService()
        let organizer = Self.device(server, id: "orga")
        let id = try await Self.startedTournament(on: organizer)
        let code = try await organizer.sync.share(id)

        await server.setOnline(false)
        let match = try #require(organizer.library.tournament(id: id)?.orderedMatches.first)
        try organizer.library.modify(id: id) { t, date in try t.validateScore(match.id, score: Score(15, 9), now: date) }
        // Le score est enregistré localement malgré l'absence de réseau.
        #expect(organizer.library.tournament(id: id)?.match(match.id)?.score == Score(15, 9))
        try await Task.sleep(for: .milliseconds(100))
        #expect(organizer.sync.status(of: id) == .pending(.offline))
        #expect(SyncRules.needsPublish(try #require(organizer.library.tournament(id: id))))

        await server.setOnline(true)
        organizer.sync.publishAllPending()
        await organizer.sync.waitForPendingPublish(id)
        let online = try #require(try await server.fetch(code: code))
        #expect(try online.decodeTournament().match(match.id)?.score == Score(15, 9))
        #expect(!SyncRules.needsPublish(try #require(organizer.library.tournament(id: id))))
    }

    @Test("Conflit : une version plus récente d'un autre appareil n'est jamais écrasée")
    func conflict() async throws {
        let server = InMemorySyncService()
        let organizer = Self.device(server, id: "orga")
        let id = try await Self.startedTournament(on: organizer)
        let code = try await organizer.sync.share(id)

        var other = try #require(organizer.library.tournament(id: id))
        other.revision += 10
        await server.inject(try PublishedSnapshot(tournament: other, code: code, deviceID: "autre-ipad"))

        let match = try #require(other.orderedMatches.first)
        try organizer.library.modify(id: id) { t, date in try t.validateScore(match.id, score: Score(15, 9), now: date) }
        await organizer.sync.waitForPendingPublish(id)
        #expect(organizer.sync.status(of: id) == .failed(.conflict))
        let online = try #require(try await server.fetch(code: code))
        #expect(online.organizerDeviceID == "autre-ipad")
    }

    @Test("Code inconnu et tournoi retiré du partage")
    func unknownAndUnpublished() async throws {
        let server = InMemorySyncService()
        let organizer = Self.device(server, id: "orga")
        let friend = Self.device(server, id: "ami")
        await #expect(throws: SyncFailure.notFound) {
            _ = try await friend.sync.join(code: InviteCode("K7M2QP")!)
        }

        let id = try await Self.startedTournament(on: organizer)
        let code = try await organizer.sync.share(id)
        _ = try await friend.sync.join(code: code)
        try await organizer.sync.unpublish(id)
        #expect(organizer.library.tournament(id: id)?.sharing == nil)

        await friend.sync.refresh(id)
        #expect(friend.sync.status(of: id) == .unpublished)
        #expect(friend.library.tournament(id: id) != nil, "la dernière version reste consultable")
    }

    @Test("Partage indisponible sans configuration CloudKit")
    func notConfigured() async throws {
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        let sync = SyncCoordinator(library: library, service: UnavailableSyncService(), deviceID: "x")
        let id = try await Self.startedTournament(on: Device(library: library, sync: sync))
        await #expect(throws: SyncFailure.notConfigured) { try await sync.share(id) }
        #expect(library.tournament(id: id)?.sharing == nil)
    }
}

extension SyncCoordinator.Status {
    var date: Date? {
        if case .upToDate(let date) = self { return date }
        return nil
    }
}
