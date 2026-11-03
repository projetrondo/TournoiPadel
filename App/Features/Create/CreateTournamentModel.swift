import Foundation
import Observation
import PadelCore
import SwiftUI // remove(atOffsets:)

/// État de l'écran de création. Les valeurs « automatiques » (terrains, tours) suivent le nombre
/// de joueurs tant que l'organisateur ne les a pas modifiées lui-même.
@MainActor
@Observable
final class CreateTournamentModel {
    var name = ""
    var format: TournamentFormat = .americano
    var players: [TournamentDraft.PlayerEntry] = []
    var newPlayerName = ""
    var scoringSelection = ScoringSelection()
    var mexicanoFirstRound: FirstRoundMode = .random
    var isOpenEnded = false
    var courtsOverride: Int?
    var roundsOverride: Int?
    /// Session d'origine : ses joueurs sont proposés, il suffit de cocher les présents.
    let session: PlaySession?
    var selectedMemberIDs: Set<SessionMember.ID> = []
    /// Niveaux saisis pour les joueurs de la session pendant la création.
    var memberLevels: [SessionMember.ID: Int] = [:]

    init(session: PlaySession? = nil, now: Date = Date()) {
        self.session = session
        if let session {
            name = "\(session.name) · \(now.formatted(.dateTime.day().month(.abbreviated).locale(.appLanguage)))"
        }
    }

    /// Joueurs de la session cochés, dans l'ordre de la liste, puis les joueurs ajoutés à la main.
    var allPlayers: [TournamentDraft.PlayerEntry] {
        let members = (session?.activeMembers ?? []).filter { selectedMemberIDs.contains($0.id) }.map { member in
            var entry = member.draftEntry
            if let level = memberLevels[member.id] { entry.level = level }
            return entry
        }
        return members + players
    }

    func toggle(_ member: SessionMember) {
        if selectedMemberIDs.contains(member.id) {
            selectedMemberIDs.remove(member.id)
        } else {
            selectedMemberIDs.insert(member.id)
        }
    }

    func selectAllMembers(_ selected: Bool) {
        selectedMemberIDs = selected ? Set(session?.activeMembers.map(\.id) ?? []) : []
    }

    var draft: TournamentDraft {
        var draft = TournamentDraft(
            name: name,
            format: format,
            players: allPlayers,
            courts: courts,
            scoring: scoring,
            rounds: 1,
            mexicanoFirstRound: mexicanoFirstRound,
            isOpenEnded: isOpenEnded,
            sessionID: session?.id
        )
        draft.rounds = roundsOverride ?? draft.planner.recommendedRounds(scoring: scoring) ?? 1
        return draft
    }

    var scoring: ScoringRule { scoringSelection.rule }

    var suggestedCourts: Int {
        min(RoundPlanner.courtsRange.upperBound, max(1, allPlayers.count / 4))
    }

    var courts: Int { courtsOverride ?? suggestedCourts }

    var recommendedRounds: Int? {
        RoundPlanner(playerCount: allPlayers.count, declaredCourts: courts).recommendedRounds(scoring: scoring)
    }

    var hasChanges: Bool {
        (session == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty) || !allPlayers.isEmpty
    }

    var needsLevels: Bool {
        format == .mexicano && mexicanoFirstRound == .byLevel
    }

    /// Ajoute le joueur saisi. Retourne `false` si le nom est vide.
    @discardableResult
    func addPlayer() -> Bool {
        let trimmed = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        players.append(.init(name: String(trimmed.prefix(TournamentDraft.maxPlayerNameLength))))
        newPlayerName = ""
        return true
    }

    func removePlayers(at offsets: IndexSet) {
        players.remove(atOffsets: offsets)
    }
}
