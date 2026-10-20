import Foundation

/// Mesures de qualité d'un planning, et compromis à expliquer à l'organisateur.
public struct ScheduleStatistics: Hashable, Sendable {
    public let matchesPerPlayer: ClosedRange<Int>
    public let restsPerPlayer: ClosedRange<Int>
    /// Nombre maximal de fois où deux mêmes joueurs ont été partenaires.
    public let maxPartnerCount: Int
    /// Nombre de paires de joueurs associées plus d'une fois.
    public let repeatedPartnerPairs: Int
    /// Nombre de paires de joueurs jamais associées.
    public let neverPartneredPairs: Int
    /// Nombre maximal de fois où deux mêmes joueurs se sont affrontés.
    public let maxOpponentCount: Int

    public init(rounds: [Round], playerIDs: [Player.ID]) {
        let index = Dictionary(uniqueKeysWithValues: playerIDs.enumerated().map { ($1, $0) })
        let n = playerIDs.count
        var partner = Array(repeating: 0, count: n * n)
        var opponent = Array(repeating: 0, count: n * n)
        var played = Array(repeating: 0, count: n)
        var rests = Array(repeating: 0, count: n)

        for round in rounds {
            for match in round.matches {
                let a = match.teamA.players.compactMap { index[$0] }
                let b = match.teamB.players.compactMap { index[$0] }
                for team in [a, b] where team.count == 2 {
                    partner[team[0] * n + team[1]] += 1
                    partner[team[1] * n + team[0]] += 1
                }
                for x in a { for y in b { opponent[x * n + y] += 1; opponent[y * n + x] += 1 } }
                for p in a + b { played[p] += 1 }
            }
            for p in round.resting.compactMap({ index[$0] }) { rests[p] += 1 }
        }

        var maxPartner = 0, repeated = 0, never = 0, maxOpponent = 0
        for x in 0..<n {
            for y in (x + 1)..<max(x + 1, n) {
                let p = partner[x * n + y]
                maxPartner = max(maxPartner, p)
                if p > 1 { repeated += 1 }
                if p == 0 { never += 1 }
                maxOpponent = max(maxOpponent, opponent[x * n + y])
            }
        }
        matchesPerPlayer = (played.min() ?? 0)...(played.max() ?? 0)
        restsPerPlayer = (rests.min() ?? 0)...(rests.max() ?? 0)
        maxPartnerCount = maxPartner
        repeatedPartnerPairs = repeated
        neverPartneredPairs = never
        maxOpponentCount = maxOpponent
    }

    public var compromises: [ScheduleCompromise] {
        var result: [ScheduleCompromise] = []
        if matchesPerPlayer.lowerBound != matchesPerPlayer.upperBound {
            result.append(.unequalMatches(matchesPerPlayer))
        }
        if repeatedPartnerPairs > 0 {
            result.append(.repeatedPartners(pairs: repeatedPartnerPairs, maxTimes: maxPartnerCount))
        }
        return result
    }
}

public enum ScheduleCompromise: Hashable, Sendable {
    /// Certains joueurs jouent moins de matchs que d'autres.
    case unequalMatches(ClosedRange<Int>)
    /// Certains partenaires se retrouvent plusieurs fois (inévitable quand il y a plus de
    /// matchs par joueur que de partenaires possibles, ou à cause des pauses).
    case repeatedPartners(pairs: Int, maxTimes: Int)
}
