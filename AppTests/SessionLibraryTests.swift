import Foundation
import PadelCore
import Testing
@testable import PadelBuddy

@MainActor
@Suite("Sessions dans l'application")
struct SessionLibraryTests {
    @Test("Créer une session, ajouter des joueurs, tout est enregistré")
    func createAndAddMembers() throws {
        let store = InMemorySessionStore()
        let sessions = SessionLibrary(store: store)
        sessions.loadIfNeeded()
        let session = try sessions.create(name: "  Les Aigles du jeudi ")
        #expect(session.name == "Les Aigles du jeudi")
        try sessions.modify(id: session.id) { try $0.addMember(name: "Léa") }
        try sessions.modify(id: session.id) { try $0.addMember(name: "Max") }
        let saved = try #require(try store.loadAll().first)
        #expect(saved.activeMembers.map(\.name) == ["Léa", "Max"])
        #expect(saved.revision == 3)
    }

    @Test("Un doublon est refusé et rien ne change")
    func duplicateRefused() throws {
        let sessions = SessionLibrary(store: InMemorySessionStore())
        let session = try sessions.create(name: "Jeudi")
        try sessions.modify(id: session.id) { try $0.addMember(name: "Léa") }
        sessions.perform { try sessions.modify(id: session.id) { try $0.addMember(name: "LEA") } }
        #expect(sessions.failure != nil)
        #expect(sessions.session(id: session.id)?.members.count == 1)
    }

    @Test("Tournoi depuis une session : présents cochés, invité ajouté à la liste")
    func tournamentFromSession() throws {
        let sessions = SessionLibrary(store: InMemorySessionStore())
        let library = TournamentLibrary(store: InMemoryTournamentStore())
        var session = try sessions.create(name: "Jeudi")
        for name in ["Léa", "Max", "Inès", "Tom", "Chloé"] {
            try sessions.modify(id: session.id) { try $0.addMember(name: name) }
        }
        session = try #require(sessions.session(id: session.id))

        let model = CreateTournamentModel(session: session)
        #expect(model.name.hasPrefix("Jeudi · "))
        for member in session.activeMembers.prefix(3) { model.toggle(member) }
        model.newPlayerName = "Rayan"
        model.addPlayer()
        #expect(model.allPlayers.map(\.name) == ["Léa", "Max", "Inès", "Rayan"])

        let tournament = try library.create(from: model.draft)
        #expect(tournament.sessionID == session.id)
        #expect(Array(tournament.players.prefix(3).map(\.id)) == Array(session.activeMembers.prefix(3).map(\.id)))

        try sessions.absorbPlayers(of: tournament)
        let updated = try #require(sessions.session(id: session.id))
        #expect(updated.activeMembers.map(\.name) == ["Léa", "Max", "Inès", "Tom", "Chloé", "Rayan"])
        #expect(library.tournaments(in: session.id).map(\.id) == [tournament.id])
    }
}
