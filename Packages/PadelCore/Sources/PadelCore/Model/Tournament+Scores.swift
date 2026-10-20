import Foundation

public enum ScoreEntryError: Error, Hashable, Sendable {
    case matchNotFound
    case tournamentNotStarted
    /// Le match est déjà validé : il faut passer par une correction (protection contre la
    /// double validation).
    case alreadyValidated
    /// Le match n'est pas encore validé : rien à corriger ni à rouvrir.
    case notValidated
    case invalidScore(ScoreError)
    /// Mexicano : un tour suivant a déjà été composé à partir de ce résultat ; on peut corriger
    /// le score, mais pas rouvrir le match.
    case roundLocked
}

public struct MatchLocation: Hashable, Sendable {
    public let round: Int
    public let match: Int
}

extension Tournament {
    public func location(of matchID: Match.ID) -> MatchLocation? {
        for (r, round) in rounds.enumerated() {
            if let m = round.matches.firstIndex(where: { $0.id == matchID }) {
                return MatchLocation(round: r, match: m)
            }
        }
        return nil
    }

    public func match(_ id: Match.ID) -> Match? {
        location(of: id).map { rounds[$0.round].matches[$0.match] }
    }

    /// Tous les matchs dans l'ordre de jeu (tour, puis terrain).
    public var orderedMatches: [Match] {
        rounds.flatMap { $0.matches.sorted { $0.court < $1.court } }
    }

    public func validation(of score: Score) -> ScoreValidation {
        settings.scoring.validate(score)
    }

    /// Marque un match « en cours » (facultatif, purement informatif).
    public mutating func markInProgress(_ matchID: Match.ID, now: Date) throws {
        let location = try editableLocation(of: matchID)
        guard rounds[location.round].matches[location.match].state == .scheduled else { return }
        rounds[location.round].matches[location.match].state = .inProgress
        touch(at: now)
    }

    /// Valide le résultat d'un match. Échoue si le score ne respecte pas la règle du tournoi
    /// ou si le match est déjà validé : un même match ne peut pas être validé deux fois.
    public mutating func validateScore(_ matchID: Match.ID, score: Score, now: Date) throws {
        let location = try editableLocation(of: matchID)
        let match = rounds[location.round].matches[location.match]
        guard match.state != .completed else { throw ScoreEntryError.alreadyValidated }
        if case .invalid(let error) = validation(of: score) { throw ScoreEntryError.invalidScore(error) }

        rounds[location.round].matches[location.match].score = score
        rounds[location.round].matches[location.match].state = .completed
        rounds[location.round].matches[location.match].edits.append(
            ScoreEdit(kind: .validation, date: now, previous: nil, new: score)
        )
        touch(at: now)
    }

    /// Corrige le score d'un match déjà validé. L'ancien score reste dans l'historique.
    /// Le classement se met à jour de lui-même ; les tours Mexicano déjà composés ne changent pas.
    public mutating func correctScore(_ matchID: Match.ID, score: Score, now: Date) throws {
        let location = try editableLocation(of: matchID)
        let match = rounds[location.round].matches[location.match]
        guard match.state == .completed, let previous = match.score else { throw ScoreEntryError.notValidated }
        if case .invalid(let error) = validation(of: score) { throw ScoreEntryError.invalidScore(error) }
        guard previous != score else { return }

        rounds[location.round].matches[location.match].score = score
        rounds[location.round].matches[location.match].edits.append(
            ScoreEdit(kind: .correction, date: now, previous: previous, new: score)
        )
        touch(at: now)
    }

    /// Le match peut-il être rouvert (annulation de la validation) ?
    /// En Mexicano, pas si un tour suivant a été composé à partir de son résultat.
    public func canReopen(_ matchID: Match.ID) -> Bool {
        guard status == .inProgress, let location = location(of: matchID),
              rounds[location.round].matches[location.match].state == .completed else { return false }
        return format == .americano || location.round == rounds.count - 1
    }

    /// Annule la validation d'un match (ex. bouton « Annuler » juste après une validation).
    public mutating func reopenMatch(_ matchID: Match.ID, now: Date) throws {
        let location = try editableLocation(of: matchID)
        let match = rounds[location.round].matches[location.match]
        guard match.state == .completed else { throw ScoreEntryError.notValidated }
        guard canReopen(matchID) else { throw ScoreEntryError.roundLocked }

        rounds[location.round].matches[location.match].edits.append(
            ScoreEdit(kind: .reset, date: now, previous: match.score, new: nil)
        )
        rounds[location.round].matches[location.match].score = nil
        rounds[location.round].matches[location.match].state = .inProgress
        touch(at: now)
    }

    /// Le tournoi peut être clôturé : tous les matchs générés sont terminés, et pour l'Americano
    /// tous les tours prévus ont été joués. Un Mexicano peut s'arrêter après n'importe quel tour.
    public var canFinish: Bool {
        guard status == .inProgress, !rounds.isEmpty, rounds.allSatisfy(\.isComplete) else { return false }
        return format == .mexicano || rounds.count == settings.plannedRounds
    }

    public mutating func finish(now: Date) throws {
        guard status == .inProgress else { throw LifecycleError.notStarted }
        guard canFinish else { throw LifecycleError.roundNotComplete }
        status = .finished
        touch(at: now)
    }

    /// Les corrections restent possibles après la clôture (une erreur peut être découverte
    /// en relisant les résultats) ; la saisie initiale, elle, exige un tournoi en cours.
    private func editableLocation(of matchID: Match.ID) throws -> MatchLocation {
        guard status != .draft else { throw ScoreEntryError.tournamentNotStarted }
        guard let location = location(of: matchID) else { throw ScoreEntryError.matchNotFound }
        return location
    }
}
