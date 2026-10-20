import Foundation
import Observation
import PadelCore
import SwiftUI // remove(atOffsets:)

/// État de l'écran de création. Les valeurs « automatiques » (terrains, tours) suivent le nombre
/// de joueurs tant que l'organisateur ne les a pas modifiées lui-même.
@MainActor
@Observable
final class CreateTournamentModel {
    enum ScoringKind: String, CaseIterable, Identifiable {
        case fixedTotal
        case raceTo
        case free

        var id: Self { self }
    }

    /// `nil` = points personnalisés.
    static let pointsPresets: [Int?] = ScoringRule.presetPoints.map { Optional($0) } + [nil]

    var name = ""
    var format: TournamentFormat = .americano
    var players: [TournamentDraft.PlayerEntry] = []
    var newPlayerName = ""
    var scoringKind: ScoringKind = .fixedTotal
    var pointsPreset: Int? = 24
    var customPoints = 20
    var mexicanoFirstRound: FirstRoundMode = .random
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
            mexicanoFirstRound: mexicanoFirstRound
        )
        draft.rounds = roundsOverride ?? draft.planner.recommendedRounds(scoring: scoring) ?? 1
        return draft
    }

    var scoring: ScoringRule {
        let points = pointsPreset ?? customPoints
        switch scoringKind {
        case .fixedTotal: return .fixedTotal(points: points)
        case .raceTo: return .raceTo(points: points)
        case .free: return .free
        }
    }

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
