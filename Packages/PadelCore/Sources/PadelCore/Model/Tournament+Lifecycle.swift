import Foundation

public enum LifecycleError: Error, Hashable, Sendable {
    case alreadyStarted
    /// Format pas encore pris en charge par le moteur.
    case unsupportedFormat(TournamentFormat)
    case scheduling(ScheduleError)
}

extension Tournament {
    /// Tour en cours : le premier qui contient un match non terminé.
    public var currentRound: Round? {
        rounds.first { !$0.isComplete }
    }

    /// Lance le tournoi : génère les matchs et passe au statut « en cours ».
    /// En cas d'échec, le tournoi n'est pas modifié.
    public mutating func start(now: Date) throws {
        guard status == .draft, rounds.isEmpty else { throw LifecycleError.alreadyStarted }
        let generated: [Round]
        switch format {
        case .americano:
            do {
                generated = try AmericanoScheduler(tournament: self).generate()
            } catch let error as ScheduleError {
                throw LifecycleError.scheduling(error)
            }
        case .mexicano:
            throw LifecycleError.unsupportedFormat(.mexicano)
        }
        rounds = generated
        status = .inProgress
        touch(at: now)
    }

    public var scheduleStatistics: ScheduleStatistics {
        ScheduleStatistics(rounds: rounds, playerIDs: players.map(\.id))
    }
}
