import Foundation

public enum LifecycleError: Error, Hashable, Sendable {
    case alreadyStarted
    case notStarted
    /// Action réservée à un autre format (ex. tour suivant d'un Americano, déjà planifié).
    case wrongFormat
    /// Le tour en cours contient encore des matchs non terminés.
    case roundNotComplete
    /// Tous les tours prévus ont été générés.
    case allRoundsGenerated
    /// Le tour ne peut plus être régénéré : un score y a déjà été saisi.
    case roundAlreadyStarted
    case scheduling(ScheduleError)
}

extension Tournament {
    /// Tour en cours : le premier qui contient un match non terminé.
    public var currentRound: Round? {
        rounds.first { !$0.isComplete }
    }

    /// Lance le tournoi : Americano → tous les tours ; Mexicano → le premier tour.
    /// En cas d'échec, le tournoi n'est pas modifié.
    public mutating func start(now: Date) throws {
        guard status == .draft, rounds.isEmpty else { throw LifecycleError.alreadyStarted }
        let generated: [Round]
        switch format {
        case .americano:
            generated = try Self.scheduling { try AmericanoScheduler(tournament: self).generate() }
        case .mexicano:
            generated = [try Self.scheduling { try MexicanoScheduler(tournament: self).nextRound() }]
        }
        rounds = generated
        status = .inProgress
        touch(at: now)
    }

    /// Mexicano : le tour suivant peut être généré quand tous les matchs du tour actuel sont terminés.
    public var canGenerateNextRound: Bool {
        format == .mexicano && status == .inProgress
            && rounds.allSatisfy(\.isComplete) && rounds.count < settings.plannedRounds
    }

    /// Mexicano : génère le tour suivant à partir des scores saisis. Les tours précédents ne
    /// sont pas modifiés.
    public mutating func generateNextRound(now: Date) throws {
        guard format == .mexicano else { throw LifecycleError.wrongFormat }
        guard status == .inProgress else { throw LifecycleError.notStarted }
        guard rounds.allSatisfy(\.isComplete) else { throw LifecycleError.roundNotComplete }
        guard rounds.count < settings.plannedRounds else { throw LifecycleError.allRoundsGenerated }
        let round = try Self.scheduling { try MexicanoScheduler(tournament: self).nextRound() }
        rounds.append(round)
        touch(at: now)
    }

    /// Mexicano : le dernier tour peut être recalculé (après correction d'un score d'un tour
    /// précédent) tant qu'aucun de ses matchs n'a commencé.
    public var canRegenerateLastRound: Bool {
        guard format == .mexicano, status == .inProgress, rounds.count >= 2, let last = rounds.last else { return false }
        return last.matches.allSatisfy { $0.state == .scheduled && $0.score == nil }
    }

    /// Mexicano : recalcule le dernier tour avec le classement à jour. Seul ce tour change.
    public mutating func regenerateLastRound(now: Date) throws {
        guard format == .mexicano else { throw LifecycleError.wrongFormat }
        guard status == .inProgress, rounds.count >= 2 else { throw LifecycleError.notStarted }
        guard canRegenerateLastRound else { throw LifecycleError.roundAlreadyStarted }
        let history = Array(rounds.dropLast())
        let round = try Self.scheduling {
            try MexicanoScheduler(tournament: self).round(number: rounds.count, history: history)
        }
        rounds[rounds.count - 1] = round
        touch(at: now)
    }

    public var scheduleStatistics: ScheduleStatistics {
        ScheduleStatistics(rounds: rounds, playerIDs: players.map(\.id))
    }

    public var standings: [StandingRow] {
        Standings.compute(for: self)
    }

    private static func scheduling<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ScheduleError {
            throw LifecycleError.scheduling(error)
        }
    }
}
