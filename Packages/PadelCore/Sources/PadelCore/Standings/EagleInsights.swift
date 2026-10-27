import Foundation

/// Distinction visuelle d'une ligne du classement.
public enum RankTier: Hashable, Sendable {
    /// Numéro 1 : l'Aigle (plusieurs en cas d'égalité parfaite).
    case eagle
    case silver
    case bronze
    case standard

    /// Distinction d'une position du classement (1 = Aigle, 2 = argent, 3 = bronze).
    public init(rank: Int) {
        switch rank {
        case 1: self = .eagle
        case 2: self = .silver
        case 3: self = .bronze
        default: self = .standard
        }
    }
}

/// Lecture « EAGLE » du classement : qui est l'Aigle, qui progresse, depuis quand l'Aigle
/// tient sa place, et l'écart qui sépare chacun de lui.
///
/// Tout est dérivé du classement réel (`Standings`), jamais saisi à la main : le statut
/// d'Aigle passe automatiquement au nouveau numéro 1 dès qu'un score change le classement.
/// Aucune règle de calcul n'est modifiée.
public struct EagleInsights: Hashable, Sendable {
    public let standings: [StandingRow]
    /// Au moins un match validé compte au classement. Sans résultat, il n'y a pas d'Aigle.
    public let hasResults: Bool
    /// Places gagnées (positif) ou perdues (négatif) depuis le tour précédent.
    public let movement: [Player.ID: Int]
    /// Nombre de tours consécutifs (jusqu'au dernier) terminés avec ce joueur numéro 1.
    public let crownStreak: [Player.ID: Int]
    /// Position de chaque joueur après chaque tour joué (pour la courbe du profil).
    public let rankHistory: [Player.ID: [RankPoint]]

    public init(tournament: Tournament) {
        let current = Standings.compute(for: tournament)
        standings = current
        hasResults = current.contains { $0.stats.played > 0 }

        // Tours qui ont déjà au moins un match compté, dans l'ordre.
        let playedRounds = tournament.rounds.indices.filter {
            !tournament.rounds[$0].isExcluded && tournament.rounds[$0].hasPlayedMatch
        }

        func snapshot(upTo lastIndex: Int) -> [StandingRow] {
            var partial = tournament
            partial.rounds = Array(tournament.rounds[...lastIndex])
            return Standings.compute(for: partial)
        }

        // Historique : classement après chaque tour joué, dans l'ordre.
        var history: [Player.ID: [RankPoint]] = [:]
        for index in playedRounds {
            let roundNumber = tournament.rounds[index].index
            for row in snapshot(upTo: index) {
                history[row.id, default: []].append(RankPoint(round: roundNumber, rank: row.rank))
            }
        }
        rankHistory = history

        // Évolution : classement actuel comparé à celui d'avant le dernier tour joué.
        var movement: [Player.ID: Int] = [:]
        if playedRounds.count >= 2 {
            let previous = snapshot(upTo: playedRounds[playedRounds.count - 2])
            let previousRank = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.rank) })
            for row in current {
                if let before = previousRank[row.id] { movement[row.id] = before - row.rank }
            }
        }
        self.movement = movement

        // Série de l'Aigle : en remontant depuis le dernier tour joué, tant qu'il est numéro 1.
        var streak: [Player.ID: Int] = [:]
        if hasResults {
            let snapshots = playedRounds.reversed().map { snapshot(upTo: $0) }
            for eagle in current where eagle.rank == 1 {
                var count = 0
                for rows in snapshots {
                    guard rows.first(where: { $0.id == eagle.id })?.rank == 1 else { break }
                    count += 1
                }
                streak[eagle.id] = count
            }
        }
        crownStreak = streak
    }

    /// Le ou les Aigles actuels (vide tant qu'aucun résultat ne compte).
    public var eagles: [StandingRow] {
        hasResults ? standings.filter { $0.rank == 1 } : []
    }

    public func tier(of row: StandingRow) -> RankTier {
        hasResults ? RankTier(rank: row.rank) : .standard
    }

    /// Points de retard sur l'Aigle (nil pour l'Aigle lui-même ou sans résultat).
    public func pointsBehindEagle(_ row: StandingRow) -> Int? {
        guard let leader = eagles.first, row.rank != 1 else { return nil }
        return leader.stats.pointsFor - row.stats.pointsFor
    }
}

/// Position d'un joueur à l'issue d'un tour.
public struct RankPoint: Hashable, Sendable {
    public let round: Int
    public let rank: Int
}

extension PlayerStats {
    /// Part des matchs gagnés (les nuls ne sont pas des victoires) ; nil sans match joué.
    public var winRate: Double? {
        played > 0 ? Double(wins) / Double(played) : nil
    }
}
