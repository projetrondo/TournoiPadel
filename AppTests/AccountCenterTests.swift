import Foundation
import PadelCore
import Testing
@testable import PadelBuddy

@MainActor
@Suite("Compte et sauvegarde en ligne (serveur simulé)")
struct AccountCenterTests {
    struct Device {
        let library: TournamentLibrary
        let sessions: SessionLibrary
        let center: AccountCenter
    }

    static func device(_ backend: InMemoryBackend, tournaments: [Tournament] = [], sessions: [PlaySession] = []) -> Device {
        let library = TournamentLibrary(store: InMemoryTournamentStore(tournaments))
        let sessionLibrary = SessionLibrary(store: InMemorySessionStore(sessions))
        library.loadIfNeeded()
        sessionLibrary.loadIfNeeded()
        let center = AccountCenter(
            backend: backend,
            library: library,
            sessions: sessionLibrary,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        return Device(library: library, sessions: sessionLibrary, center: center)
    }

    static func signIn(_ device: Device) async {
        _ = device.center.appleNonceHash()
        await device.center.completeAppleSignIn(identityToken: Data("jeton".utf8), givenName: "Léa")
    }

    static func draft(_ name: String = "Jeudi") -> TournamentDraft {
        TournamentDraft(name: name, players: ["Léa", "Max", "Inès", "Tom"].map { .init(name: $0) }, courts: 1, rounds: 3)
    }

    @Test("Connexion : tout ce qui est sur l'iPhone est sauvegardé")
    func firstBackupUploadsEverything() async throws {
        let backend = InMemoryBackend()
        let session = PlaySession(name: "Les Aigles", createdAt: Date())
        let device = Self.device(backend, sessions: [session])
        let tournament = try device.library.create(from: Self.draft())

        await Self.signIn(device)

        #expect(device.center.account?.displayName == "Léa")
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == tournament.revision)
        #expect(backend.storedRevision(BackupKey(.session, session.id)) == session.revision)
        #expect(device.center.lastBackupAt != nil)
    }

    @Test("Nouvel iPhone : connexion au même compte, tout est récupéré")
    func restoreOnNewDevice() async throws {
        let backend = InMemoryBackend()
        let first = Self.device(backend, sessions: [PlaySession(name: "Les Aigles", createdAt: Date())])
        let tournament = try first.library.create(from: Self.draft())
        await Self.signIn(first)

        let second = Self.device(backend)
        await Self.signIn(second)
        #expect(second.library.tournament(id: tournament.id)?.name == "Jeudi")
        #expect(second.sessions.sessions.map(\.name) == ["Les Aigles"])
    }

    @Test("Modification après connexion : la nouvelle révision est envoyée")
    func modificationsAreUploaded() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        await Self.signIn(device)
        let tournament = try device.library.create(from: Self.draft())
        try await device.library.start(id: tournament.id)
        await device.center.backUp()

        let started = try #require(device.library.tournament(id: tournament.id))
        #expect(started.status == .inProgress)
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == started.revision)
    }

    @Test("Une version plus récente faite sur un autre appareil remplace la copie locale")
    func newerRemoteVersionIsAdopted() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        let tournament = try device.library.create(from: Self.draft())
        await Self.signIn(device)

        var elsewhere = tournament
        elsewhere.name = "Jeudi (renommé ailleurs)"
        elsewhere.touch(at: Date().addingTimeInterval(60))
        backend.storeFromAnotherDevice(BackupKey(.tournament, tournament.id), revision: elsewhere.revision, payload: try TournamentCodec.encode(elsewhere))

        await device.center.backUp()
        #expect(device.library.tournament(id: tournament.id)?.name == "Jeudi (renommé ailleurs)")
    }

    @Test("Une vieille version du serveur n'écrase jamais la version locale")
    func olderRemoteVersionIsIgnored() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        let tournament = try device.library.create(from: Self.draft())
        await Self.signIn(device)
        try device.library.update(tournament)   // révision 2 en local
        try device.library.update(try #require(device.library.tournament(id: tournament.id)))   // révision 3

        var stale = tournament
        stale.name = "Ancien nom"
        backend.storeFromAnotherDevice(BackupKey(.tournament, tournament.id), revision: 2, payload: try TournamentCodec.encode(stale))

        await device.center.backUp()
        #expect(device.library.tournament(id: tournament.id)?.name == "Jeudi")
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == 3, "la version locale est renvoyée")
    }

    @Test("Suppression sur l'iPhone : supprimée aussi de la sauvegarde")
    func localDeletionIsUploaded() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        let tournament = try device.library.create(from: Self.draft())
        await Self.signIn(device)

        try device.library.delete(id: tournament.id)
        await device.center.backUp()
        #expect(backend.storedPayload(BackupKey(.tournament, tournament.id)) == nil)
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) != nil, "trace de suppression")
    }

    @Test("Suppression faite sur un autre appareil : appliquée ici, sans être renvoyée")
    func remoteDeletionIsApplied() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        let tournament = try device.library.create(from: Self.draft())
        await Self.signIn(device)

        backend.storeFromAnotherDevice(BackupKey(.tournament, tournament.id), revision: tournament.revision + 1, payload: nil)
        await device.center.backUp()
        #expect(device.library.tournament(id: tournament.id) == nil)
    }

    @Test("Hors ligne : rien n'est perdu, la sauvegarde reprend au retour du réseau")
    func offlineThenOnline() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        await Self.signIn(device)

        backend.isReachable = false
        let tournament = try device.library.create(from: Self.draft())
        await device.center.backUp()
        #expect(device.center.account != nil, "reste connecté")
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == nil)

        backend.isReachable = true
        await device.center.backUp()
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == tournament.revision)
    }

    @Test("Déconnexion et suppression du compte : les données de l'iPhone restent")
    func signOutKeepsLocalData() async throws {
        let backend = InMemoryBackend()
        let device = Self.device(backend)
        let tournament = try device.library.create(from: Self.draft())
        await Self.signIn(device)

        await device.center.signOut()
        #expect(device.center.account == nil)
        #expect(device.library.tournament(id: tournament.id) != nil)

        await Self.signIn(device)
        await device.center.deleteAccount()
        #expect(device.center.account == nil)
        #expect(backend.storedRevision(BackupKey(.tournament, tournament.id)) == nil)
        #expect(device.library.tournament(id: tournament.id) != nil)
    }

    @Test("Les tournois suivis en lecture seule ne sont pas sauvegardés")
    func readOnlyTournamentsAreSkipped() async throws {
        let backend = InMemoryBackend()
        var followed = try Self.draft("Tournoi d'un ami").makeTournament(now: Date(), seed: 1)
        followed.sharing = SharingInfo(code: "ABC234", role: .viewer)
        let device = Self.device(backend, tournaments: [followed])
        await Self.signIn(device)
        #expect(backend.storedRevision(BackupKey(.tournament, followed.id)) == nil)
    }

    @Test("PKCE : le condensé envoyé correspond au secret gardé par l'app")
    func pkceChallenge() {
        // Exemple de la RFC 7636, annexe B.
        #expect(AccountCenter.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(AccountCenter.randomToken().count == 43)
    }
}
