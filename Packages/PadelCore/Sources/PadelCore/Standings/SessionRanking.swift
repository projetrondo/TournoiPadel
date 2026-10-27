import Foundation

/// Période d'un classement de session.
public enum RankingPeriod: String, CaseIterable, Codable, Hashable, Sendable {
    case week
    case month
    case year
    case all

    /// Intervalle de la période qui contient `date` (nil pour « depuis le début »).
    /// Les semaines commencent le lundi (calendrier ISO 8601).
    public func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .week: calendar.dateInterval(of: .weekOfYear, for: date)
        case .month: calendar.dateInterval(of: .month, for: date)
        case .year: calendar.dateInterval(of: .year, for: date)
        case .all: nil
        }
    }

    /// Même moment, `count` périodes plus tôt (négatif) ou plus tard.
    public func shift(_ date: Date, by count: Int, calendar: Calendar) -> Date {
        let component: Calendar.Component? = switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
        guard let component else { return date }
        return calendar.date(byAdding: component, value: count, to: date) ?? date
    }
}

/// Une ligne du classement d'une session sur une période.
public struct SessionRankingRow: Hashable, Sendable, Identifiable {
    /// Position parmi les joueurs classés ; nil si le minimum de matchs n'est pas atteint.
    public let rank: Int?
    public let isTied: Bool
    public let stats: PlayerStats
    /// Tournois de la période auxquels le joueur a joué au moins un match.
    public let tournaments: Int

    public var id: Player.ID { stats.playerID }
    public var isRanked: Bool { rank != nil }
}

/// Classement d'une session sur une période, à partir des matchs validés de ses tournois.
///
/// Règle (choisie pour être équitable entre ceux qui viennent souvent et les autres) :
/// 1. moyenne de points marqués par match ;
/// 2. pourcentage de victoires ;
/// 3. différence de points moyenne par match ;
/// sinon ex aequo. Il faut au moins `minimumMatches` matchs sur la période pour être classé ;
/// les autres apparaissent à part, sans position.
///
/// Chaque tournoi compte entièrement dans la période où il s'est joué (`Tournament.playedOn`).
/// Les règles du classement d'un tournoi ne changent pas.
public struct SessionRanking: Hashable, Sendable {
    public let rows: [SessionRankingRow]
    /// Tournois de la session dans la période, avec au moins un match validé.
    public let tournamentCount: Int
    public let matchCount: Int
    public let interval: DateInterval?

    public init(
        session: PlaySession,
        tournaments: [Tournament],
        period: RankingPeriod,
        reference: Date,
        calendar: Calendar
    ) {
        let interval = period.interval(containing: reference, calendar: calendar)
        self.interval = interval
        let included = tournaments.filter { tournament in
            guard tournament.sessionID == session.id else { return false }
            guard let interval else { return true }
            let date = tournament.playedOn
            return date >= interval.start && date < interval.end
        }

        var totals: [Player.ID: PlayerStats] = [:]
        var presence: [Player.ID: Int] = [:]
        var tournamentCount = 0
        var matchCount = 0
        for tournament in included {
            let played = tournament.rounds
                .filter { !$0.isExcluded }
                .flatMap(\.matches)
                .filter { $0.state == .completed && $0.score != nil }
                .count
            guard played > 0 else { continue }
            tournamentCount += 1
            matchCount += played
            for (id, stats) in Standings.stats(for: tournament) where stats.played > 0 {
                totals[id, default: PlayerStats(playerID: id)].add(stats)
                presence[id, default: 0] += 1
            }
        }
        self.tournamentCount = tournamentCount
        self.matchCount = matchCount

        let minimum = max(1, session.minimumMatches)
        let ranked = totals.values.filter { $0.played >= minimum }.sorted { a, b in
            if Self.ranksAhead(a, b) { return true }
            if Self.ranksAhead(b, a) { return false }
            return Self.name(of: a.playerID, session: session, tournaments: included)
                .localizedStandardCompare(Self.name(of: b.playerID, session: session, tournaments: included)) == .orderedAscending
        }
        var rows: [SessionRankingRow] = []
        for (offset, stats) in ranked.enumerated() {
            let tiedWithPrevious = offset > 0 && Self.isTie(stats, ranked[offset - 1])
            let tiedWithNext = offset + 1 < ranked.count && Self.isTie(stats, ranked[offset + 1])
            let rank = tiedWithPrevious ? rows[offset - 1].rank : offset + 1
            rows.append(SessionRankingRow(
                rank: rank,
                isTied: tiedWithPrevious || tiedWithNext,
                stats: stats,
                tournaments: presence[stats.playerID] ?? 0
            ))
        }
        let unranked = totals.values.filter { $0.played < minimum }.sorted { a, b in
            if a.played != b.played { return a.played > b.played }
            return Self.name(of: a.playerID, session: session, tournaments: included)
                .localizedStandardCompare(Self.name(of: b.playerID, session: session, tournaments: included)) == .orderedAscending
        }
        rows += unranked.map {
            SessionRankingRow(rank: nil, isTied: false, stats: $0, tournaments: presence[$0.playerID] ?? 0)
        }
        self.rows = rows
    }

    public var ranked: [SessionRankingRow] { rows.filter(\.isRanked) }
    public var unranked: [SessionRankingRow] { rows.filter { !$0.isRanked } }

    /// Nom du joueur : celui de la session, sinon celui du tournoi le plus récent.
    public static func name(of id: Player.ID, session: PlaySession, tournaments: [Tournament]) -> String {
        if let member = session.member(id) { return member.name }
        return tournaments.sorted { $0.updatedAt > $1.updatedAt }.lazy.compactMap { $0.player(id)?.name }.first ?? "?"
    }

    static func ranksAhead(_ a: PlayerStats, _ b: PlayerStats) -> Bool {
        let average = (a.averagePoints ?? 0, b.averagePoints ?? 0)
        if average.0 != average.1 { return average.0 > average.1 }
        let rate = (a.winRate ?? 0, b.winRate ?? 0)
        if rate.0 != rate.1 { return rate.0 > rate.1 }
        return (a.averageDifference ?? 0) > (b.averageDifference ?? 0)
    }

    static func isTie(_ a: PlayerStats, _ b: PlayerStats) -> Bool {
        !ranksAhead(a, b) && !ranksAhead(b, a)
    }
}

extension PlayerStats {
    /// Cumule les statistiques d'un autre tournoi du même joueur.
    mutating func add(_ other: PlayerStats) {
        played += other.played
        pointsFor += other.pointsFor
        pointsAgainst += other.pointsAgainst
        wins += other.wins
        draws += other.draws
        losses += other.losses
        rests += other.rests
    }
}
