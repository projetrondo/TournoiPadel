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

    var draft: TournamentDraft {
        var draft = TournamentDraft(
            name: name,
            format: format,
            players: players,
            courts: courts,
            scoring: scoring,
            rounds: 1,
            mexicanoFirstRound: mexicanoFirstRound,
            isOpenEnded: isOpenEnded
        )
        draft.rounds = roundsOverride ?? draft.planner.recommendedRounds(scoring: scoring) ?? 1
        return draft
    }

    var scoring: ScoringRule { scoringSelection.rule }

    var suggestedCourts: Int {
        min(RoundPlanner.courtsRange.upperBound, max(1, players.count / 4))
    }

    var courts: Int { courtsOverride ?? suggestedCourts }

    var recommendedRounds: Int? {
        RoundPlanner(playerCount: players.count, declaredCourts: courts).recommendedRounds(scoring: scoring)
    }

    var hasChanges: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || !players.isEmpty
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
