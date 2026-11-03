import Foundation
import Observation
import PadelCore

/// Sessions enregistrées sur l'appareil (groupes de joueurs et leurs tournois).
/// Même règle que `TournamentLibrary` : on écrit d'abord sur disque, puis on met à jour
/// l'affichage ; si l'écriture échoue, rien ne change à l'écran.
@MainActor
@Observable
final class SessionLibrary {
    private(set) var sessions: [PlaySession] = []
    private(set) var hasLoaded = false
    var failure: TournamentLibrary.Failure?

    @ObservationIgnored private let store: any SessionStore
    @ObservationIgnored private let now: () -> Date
    /// Appelé après chaque modification enregistrée (pour la sauvegarde en ligne).
    @ObservationIgnored var onLocalChange: (@MainActor (PlaySession) -> Void)?
    /// Appelé après la suppression d'une session par l'utilisateur.
    @ObservationIgnored var onLocalDelete: (@MainActor (PlaySession) -> Void)?

    init(store: any SessionStore, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    func session(id: PlaySession.ID?) -> PlaySession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        do {
            sessions = try store.loadAll()
        } catch {
            failure = .init(message: String(localized: "Impossible de lire les sessions enregistrées.", bundle: .appLanguage))
        }
        hasLoaded = true
    }

    @discardableResult
    func create(name: String) throws -> PlaySession {
        let session = PlaySession(name: try PlaySession.validatedName(name), createdAt: now())
        try store.save(session)
        sessions.insert(session, at: 0)
        onLocalChange?(session)
        return session
    }

    /// Applique une modification sur une copie, l'enregistre, puis l'affiche.
    func modify(id: PlaySession.ID, _ change: (inout PlaySession) throws -> Void) throws {
        guard var session = session(id: id) else { return }
        try change(&session)
        session.touch(at: now())
        try store.save(session)
        sessions.removeAll { $0.id == id }
        sessions.insert(session, at: 0)
        onLocalChange?(session)
    }

    /// Les joueurs ajoutés pendant la création d'un tournoi rejoignent la liste de sa session.
    func absorbPlayers(of tournament: Tournament) throws {
        guard let id = tournament.sessionID, let current = session(id: id) else { return }
        var updated = current
        updated.absorbPlayers(of: tournament)
        guard updated.members != current.members else { return }
        try modify(id: id) { $0 = updated }
    }

    /// Enregistre une version reçue du serveur (sans la republier).
    func saveSynced(_ session: PlaySession) throws {
        try store.save(session)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    /// Supprime la session. Ses tournois restent enregistrés, comme tournois isolés.
    func delete(id: PlaySession.ID) throws {
        let deleted = session(id: id)
        try store.delete(id: id)
        sessions.removeAll { $0.id == id }
        if let deleted { onLocalDelete?(deleted) }
    }

    /// Suppression reçue du serveur (faite sur un autre appareil) : rien à renvoyer.
    func deleteSynced(id: PlaySession.ID) throws {
        try store.delete(id: id)
        sessions.removeAll { $0.id == id }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch let error as SessionError {
            failure = .init(message: error.message)
        } catch {
            failure = .init(message: String(localized: "L'enregistrement a échoué. Vos données précédentes sont intactes.", bundle: .appLanguage))
        }
    }
}

extension SessionError {
    var message: String {
        switch self {
        case .emptyName: String(localized: "Le nom ne peut pas être vide.", bundle: .appLanguage)
        case .nameTooLong(let max): String(localized: "Le nom ne doit pas dépasser \(max) caractères.", bundle: .appLanguage)
        case .duplicateName(let name): String(localized: "« \(name) » est déjà dans la liste.", bundle: .appLanguage)
        case .unknownMember: String(localized: "Ce joueur n'existe plus.", bundle: .appLanguage)
        }
    }
}

extension TournamentLibrary {
    /// Tournois d'une session, du plus récent au plus ancien (date de jeu).
    func tournaments(in session: PlaySession.ID) -> [Tournament] {
        tournaments.filter { $0.sessionID == session }.sorted { $0.playedOn > $1.playedOn }
    }
}
