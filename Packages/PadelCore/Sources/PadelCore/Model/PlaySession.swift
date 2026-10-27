import Foundation

/// Une session : un groupe qui joue régulièrement ensemble (« Padel du jeudi »).
/// Elle garde la liste des joueurs, pour ne pas les retaper à chaque tournoi, et regroupe
/// ses tournois pour établir des classements par semaine, mois ou année.
///
/// Les tournois ne sont pas copiés ici : chacun porte l'identifiant de sa session
/// (`Tournament.sessionID`). Un joueur garde le même identifiant d'un tournoi à l'autre,
/// c'est ce qui permet de le suivre dans le temps.
public struct PlaySession: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maxNameLength = TournamentDraft.maxNameLength
    public static let defaultMinimumMatches = 3

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    /// Joueurs enregistrés, dans l'ordre d'ajout. Un joueur retiré est archivé, jamais
    /// supprimé : ses résultats passés restent dans les classements.
    public var members: [SessionMember]
    /// Matchs nécessaires sur la période pour apparaître dans le classement.
    public var minimumMatches: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// Incrémenté à chaque modification ; sert à la synchronisation.
    public var revision: Int

    public init(
        id: UUID = UUID(),
        name: String,
        members: [SessionMember] = [],
        minimumMatches: Int = PlaySession.defaultMinimumMatches,
        createdAt: Date,
        updatedAt: Date? = nil,
        revision: Int = 1
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.members = members
        self.minimumMatches = minimumMatches
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.revision = revision
    }

    /// Joueurs proposés à la création d'un tournoi.
    public var activeMembers: [SessionMember] {
        members.filter { !$0.isArchived }
    }

    public func member(_ id: SessionMember.ID) -> SessionMember? {
        members.first { $0.id == id }
    }

    /// Nom de session valide (sans espaces superflus).
    public static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.emptyName }
        guard trimmed.count <= maxNameLength else { throw SessionError.nameTooLong(maxNameLength) }
        return trimmed
    }

    public mutating func rename(_ name: String) throws {
        self.name = try Self.validatedName(name)
    }

    /// Ajoute un joueur. Un joueur archivé du même nom est réactivé plutôt que dupliqué,
    /// pour qu'il retrouve son historique.
    @discardableResult
    public mutating func addMember(name: String, level: Int? = nil) throws -> SessionMember {
        let trimmed = try Self.validatedMemberName(name)
        let key = Player.normalizedName(trimmed)
        if let index = members.firstIndex(where: { Player.normalizedName($0.name) == key }) {
            guard members[index].isArchived else { throw SessionError.duplicateName(members[index].name) }
            members[index].archived = nil
            if let level { members[index].level = level }
            return members[index]
        }
        let member = SessionMember(name: trimmed, level: level)
        members.append(member)
        return member
    }

    public mutating func updateMember(id: SessionMember.ID, name: String, level: Int?) throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { throw SessionError.unknownMember }
        let trimmed = try Self.validatedMemberName(name)
        let key = Player.normalizedName(trimmed)
        if let other = members.first(where: { $0.id != id && Player.normalizedName($0.name) == key }) {
            throw SessionError.duplicateName(other.name)
        }
        members[index].name = trimmed
        members[index].level = level.flatMap { Player.levelRange.contains($0) ? $0 : nil }
    }

    /// Retire un joueur de la liste proposée, sans effacer ses résultats.
    public mutating func archiveMember(id: SessionMember.ID) {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        members[index].archived = true
    }

    /// Enregistre les joueurs d'un tournoi de la session : les nouveaux noms saisis pendant la
    /// création rejoignent la liste, avec le même identifiant que dans le tournoi.
    public mutating func absorbPlayers(of tournament: Tournament) {
        for player in tournament.players {
            if let index = members.firstIndex(where: { $0.id == player.id }) {
                members[index].archived = nil
                continue
            }
            let key = Player.normalizedName(player.name)
            guard !members.contains(where: { Player.normalizedName($0.name) == key }) else { continue }
            members.append(SessionMember(id: player.id, name: player.name, level: player.level))
        }
    }

    public mutating func touch(at date: Date) {
        updatedAt = date
        revision += 1
    }

    private static func validatedMemberName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionError.emptyName }
        guard trimmed.count <= TournamentDraft.maxPlayerNameLength else {
            throw SessionError.nameTooLong(TournamentDraft.maxPlayerNameLength)
        }
        return trimmed
    }
}

/// Joueur enregistré dans une session.
public struct SessionMember: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var level: Int?
    /// Retiré de la liste proposée (absent = actif).
    public var archived: Bool?

    public init(id: UUID = UUID(), name: String, level: Int? = nil) {
        self.id = id
        self.name = name
        self.level = level
    }

    public var isArchived: Bool { archived ?? false }

    /// Entrée prête pour la création d'un tournoi (même identifiant que dans la session).
    public var draftEntry: TournamentDraft.PlayerEntry {
        TournamentDraft.PlayerEntry(id: id, name: name, level: level)
    }
}

public enum SessionError: Error, Hashable, Sendable {
    case emptyName
    case nameTooLong(Int)
    case duplicateName(String)
    case unknownMember
}
