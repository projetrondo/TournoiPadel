import Foundation

/// Statistiques individuelles d'un joueur, calculées à partir des matchs terminés uniquement.
public struct PlayerStats: Hashable, Sendable {
    public let playerID: Player.ID
    public var played = 0
    public var pointsFor = 0
    public var pointsAgainst = 0
    public var wins = 0
    public var draws = 0
    public var losses = 0
    public var rests = 0

    public init(playerID: Player.ID) {
        self.playerID = playerID
    }

    public var pointDifference: Int { pointsFor - pointsAgainst }

    public var averagePoints: Double? {
        played > 0 ? Double(pointsFor) / Double(played) : nil
    }

    public var averageDifference: Double? {
        played > 0 ? Double(pointDifference) / Double(played) : nil
    }
}

/// Une ligne du classement.
public struct StandingRow: Hashable, Sendable, Identifiable {
    /// Position affichée. Les ex aequo partagent la même position (1, 2, 2, 4…).
    public let rank: Int
    public let isTied: Bool
    public let stats: PlayerStats

    public var id: Player.ID { stats.playerID }
}

/// Classement individuel.
///
/// Règles de départage, dans l'ordre :
/// 1. points marqués (total) ;
/// 2. victoires ;
/// 3. différence de points ;
/// 4. sinon ex aequo : même position. Pour l'affichage, les ex aequo restent dans l'ordre
///    d'inscription.
/// Seuls les matchs terminés avec un score comptent, hors tours exclus à la clôture. Le classement n'est jamais stocké :
/// il est recalculé à chaque fois, donc toujours à jour après une validation ou une correction.
public enum Standings {
    public static func stats(for tournament: Tournament) -> [Player.ID: PlayerStats] {
        var stats = Dictionary(uniqueKeysWithValues: tournament.players.map { ($0.id, PlayerStats(playerID: $0.id)) })
        for round in tournament.rounds where !round.isExcluded {
            for match in round.matches {
                guard match.state == .completed, let score = match.score else { continue }
                record(team: match.teamA, scored: score.teamA, conceded: score.teamB, into: &stats)
                record(team: match.teamB, scored: score.teamB, conceded: score.teamA, into: &stats)
            }
            // Les pauses d'un tour comptent dès qu'il est généré.
            for player in round.resting { stats[player]?.rests += 1 }
        }
        return stats
    }

    public static func compute(for tournament: Tournament) -> [StandingRow] {
        let stats = stats(for: tournament)
        let order = Dictionary(uniqueKeysWithValues: tournament.players.enumerated().map { ($1.id, $0) })
        let sorted = tournament.players.compactMap { stats[$0.id] }.sorted { a, b in
            if ranksAhead(a, b) { return true }
            if ranksAhead(b, a) { return false }
            return order[a.playerID]! < order[b.playerID]!
        }

        var rows: [StandingRow] = []
        for (offset, entry) in sorted.enumerated() {
            let tiedWithPrevious = offset > 0 && isTie(entry, sorted[offset - 1])
            let tiedWithNext = offset + 1 < sorted.count && isTie(entry, sorted[offset + 1])
            let rank = tiedWithPrevious ? rows[offset - 1].rank : offset + 1
            rows.append(StandingRow(rank: rank, isTied: tiedWithPrevious || tiedWithNext, stats: entry))
        }
        return rows
    }

    /// `true` si `a` est strictement devant `b` selon les règles de départage.
    static func ranksAhead(_ a: PlayerStats, _ b: PlayerStats) -> Bool {
        if a.pointsFor != b.pointsFor { return a.pointsFor > b.pointsFor }
        if a.wins != b.wins { return a.wins > b.wins }
        return a.pointDifference > b.pointDifference
    }

    static func isTie(_ a: PlayerStats, _ b: PlayerStats) -> Bool {
        !ranksAhead(a, b) && !ranksAhead(b, a)
    }

    private static func record(team: Team, scored: Int, conceded: Int, into stats: inout [Player.ID: PlayerStats]) {
        for player in team.players {
            stats[player]?.played += 1
            stats[player]?.pointsFor += scored
            stats[player]?.pointsAgainst += conceded
            if scored > conceded {
                stats[player]?.wins += 1
            } else if scored < conceded {
                stats[player]?.losses += 1
            } else {
                stats[player]?.draws += 1
            }
        }
    }
}
