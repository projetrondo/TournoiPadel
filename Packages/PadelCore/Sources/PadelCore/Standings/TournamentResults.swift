import Foundation

/// Récapitulatif d'un tournoi : podium, classement final, chiffres clés, résumé partageable.
public struct TournamentResults: Hashable, Sendable {
    public let standings: [StandingRow]
    public let matchesPlayed: Int
    public let totalPoints: Int
    public let roundsPlayed: Int
    /// Répartition réelle des matchs joués (compte les tours interrompus s'ils sont comptés).
    public let statistics: ScheduleStatistics

    public init(tournament: Tournament) {
        standings = Standings.compute(for: tournament)
        let counted = tournament.rounds.filter { !$0.isExcluded }
        let completed = counted.flatMap(\.matches).filter { $0.state == .completed && $0.score != nil }
        matchesPlayed = completed.count
        totalPoints = completed.compactMap(\.score).reduce(0) { $0 + $1.teamA + $1.teamB }
        roundsPlayed = counted.filter(\.hasPlayedMatch).count
        // Seuls les matchs réellement joués comptent (un tour interrompu peut en contenir d'autres).
        let played = counted.map { round in
            var round = round
            round.matches = round.matches.filter { $0.state == .completed }
            return round
        }
        statistics = ScheduleStatistics(rounds: played, playerIDs: tournament.players.map(\.id))
    }

    /// Meilleur(s) joueur(s) selon les règles du classement (plusieurs en cas d'égalité parfaite).
    public var winners: [StandingRow] {
        standings.filter { $0.rank == 1 }
    }

    /// Les trois premières positions ; les ex aequo partagent une marche.
    public var podium: [[StandingRow]] {
        let ranks = Array(Set(standings.map(\.rank))).sorted().filter { $0 <= 3 }
        return ranks.map { rank in standings.filter { $0.rank == rank } }
    }
}
