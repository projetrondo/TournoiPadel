import Foundation

/// Générateur Mexicano : un tour à la fois, à partir des scores réellement saisis.
///
/// Stratégie pour le tour n + 1 :
/// 1. **Classement d'appariement** : moyenne de points par match joué (pour ne pas pénaliser
///    ceux qui viennent de pauser), puis différence moyenne, puis victoires, puis ordre
///    d'inscription. Un joueur sans match reçoit la moyenne générale (position neutre).
/// 2. **Pauses** : les joueurs les moins reposés (`RestSelector`).
/// 3. **Groupes de 4 consécutifs** dans ce classement (1–4, 5–8…) ; le groupe 1 va au terrain 1.
/// 4. Dans un groupe classé a > b > c > d : **a+d contre b+c** de préférence (équipes
///    équilibrées), sinon a+c contre b+d, en dernier recours a+b contre c+d.
/// 5. Pour éviter un partenaire déjà vu, un joueur peut être échangé avec un voisin à la
///    frontière de deux groupes : 4ᵉ ↔ 5ᵉ (distance 1), 3ᵉ ↔ 5ᵉ ou 4ᵉ ↔ 6ᵉ (distance 2).
/// Le choix minimise, de façon exacte (programmation dynamique sur les frontières) :
/// 1000 × partenaires répétés + 50 × distance des échanges + 10 × adversaires répétés
/// + 2 × écart au schéma préféré (0, 1 ou 3).
///
/// Premier tour : ordre aléatoire (seedé) ou par niveau, puis mêmes groupes de 4.
/// Les tours déjà générés ne sont jamais modifiés.
public struct MexicanoScheduler: Sendable {
    static let partnerWeight = 1000
    static let swapWeight = 50
    static let opponentWeight = 10
    static let patternWeight = 2
    /// Pénalité de schéma : a+d/b+c, a+c/b+d, a+b/c+d.
    static let patternPenalty = [0, 1, 3]

    public let tournament: Tournament

    public init(tournament: Tournament) {
        self.tournament = tournament
    }

    var planner: RoundPlanner {
        RoundPlanner(playerCount: tournament.players.count, declaredCourts: tournament.settings.courts)
    }

    /// Génère le tour qui suit les tours existants (le tour 1 si aucun n'existe).
    public func nextRound() throws -> Round {
        try round(number: tournament.rounds.count + 1, history: tournament.rounds)
    }

    /// Génère le tour `number` à partir des tours précédents `history` (qui doivent être terminés).
    func round(number: Int, history: [Round]) throws -> Round {
        let playerIDs = tournament.players.map(\.id)
        let n = playerIDs.count
        guard n >= RoundPlanner.minPlayers else { throw ScheduleError.notEnoughPlayers(minimum: RoundPlanner.minPlayers) }
        guard Set(playerIDs).count == n else { throw ScheduleError.duplicatePlayers }
        guard planner.activeCourts >= 1 else { throw ScheduleError.noCourt }

        let index = Dictionary(uniqueKeysWithValues: playerIDs.enumerated().map { ($1, $0) })
        let ledger = PairingLedger(rounds: history, index: index)
        // Graine propre à chaque tour : régénérer un tour donne le même résultat.
        var rng = SeededGenerator.derived(seed: tournament.seed, salt: UInt64(number))

        let resting = RestSelector.choose(count: planner.restingPerRound, among: Array(0..<n), ledger: ledger, rng: &rng)
        let restingSet = Set(resting)
        let active = (0..<n).filter { !restingSet.contains($0) }

        let ordered: [Int]
        if history.isEmpty {
            ordered = firstRoundOrder(active, rng: &rng)
        } else {
            var historyTournament = tournament
            historyTournament.rounds = history
            ordered = pairingOrder(active, stats: Standings.stats(for: historyTournament), playerIDs: playerIDs)
        }

        let matches = Self.bestGroups(ranked: ordered, ledger: ledger)
        let built = matches.enumerated().map { court, m in
            Match(
                id: rng.uuid(),
                court: court + 1,
                teamA: Team(playerIDs[m[0]], playerIDs[m[1]]),
                teamB: Team(playerIDs[m[2]], playerIDs[m[3]])
            )
        }
        let round = Round(index: number, matches: built, resting: resting.sorted().map { playerIDs[$0] })
        try ScheduleValidator.validate(round: round, playerIDs: playerIDs, activeCourts: planner.activeCourts)
        return round
    }

    private func firstRoundOrder(_ active: [Int], rng: inout SeededGenerator) -> [Int] {
        let shuffled = rng.shuffled(active)
        guard tournament.settings.mexicanoFirstRound == .byLevel else { return shuffled }
        // Tri stable par niveau décroissant ; à niveau égal, l'ordre aléatoire est conservé.
        let position = Dictionary(uniqueKeysWithValues: shuffled.enumerated().map { ($1, $0) })
        return shuffled.sorted { a, b in
            let la = tournament.players[a].level ?? 0, lb = tournament.players[b].level ?? 0
            return la != lb ? la > lb : position[a]! < position[b]!
        }
    }

    /// Classement d'appariement des joueurs actifs (voir la documentation du type).
    func pairingOrder(_ active: [Int], stats: [Player.ID: PlayerStats], playerIDs: [Player.ID]) -> [Int] {
        let all = playerIDs.compactMap { stats[$0] }
        let withMatches = all.filter { $0.played > 0 }
        let meanPoints = withMatches.isEmpty ? 0 : withMatches.compactMap(\.averagePoints).reduce(0, +) / Double(withMatches.count)
        let meanDiff = withMatches.isEmpty ? 0 : withMatches.compactMap(\.averageDifference).reduce(0, +) / Double(withMatches.count)

        return active.sorted { a, b in
            let sa = stats[playerIDs[a]]!, sb = stats[playerIDs[b]]!
            let pa = sa.averagePoints ?? meanPoints, pb = sb.averagePoints ?? meanPoints
            if pa != pb { return pa > pb }
            let da = sa.averageDifference ?? meanDiff, db = sb.averageDifference ?? meanDiff
            if da != db { return da > db }
            if sa.wins != sb.wins { return sa.wins > sb.wins }
            return a < b
        }
    }

    /// Échanges possibles à la frontière entre un groupe et le suivant (positions dans le
    /// groupe du dessus, positions dans celui du dessous, distance au classement).
    static let exchanges: [(upper: Int, lower: Int, distance: Int)?] = [
        nil,                                 // aucun échange
        (upper: 3, lower: 0, distance: 1),   // 4ᵉ ↔ 5ᵉ
        (upper: 2, lower: 0, distance: 2),   // 3ᵉ ↔ 5ᵉ
        (upper: 3, lower: 1, distance: 2),   // 4ᵉ ↔ 6ᵉ
    ]

    /// Choix exact des échanges aux frontières et des schémas d'équipes, par programmation
    /// dynamique : le coût d'un groupe ne dépend que des échanges à ses deux frontières.
    /// `ranked` : joueurs actifs du meilleur au moins bon (multiple de 4).
    static func bestGroups(ranked: [Int], ledger: PairingLedger) -> [[Int]] {
        let groups = ranked.count / 4
        precondition(groups >= 1 && ranked.count % 4 == 0)
        let kinds = exchanges.count

        // Meilleur match du groupe g selon l'échange à sa frontière haute (incoming) et basse (outgoing).
        func evaluate(_ g: Int, incoming: Int, outgoing: Int) -> (cost: Int, match: [Int]) {
            var positions = Array((4 * g)..<(4 * g + 4))
            if let e = exchanges[incoming] { positions[e.lower] = 4 * (g - 1) + e.upper }
            if let e = exchanges[outgoing] { positions[e.upper] = 4 * (g + 1) + e.lower }
            positions.sort()
            let (a, b, c, d) = (ranked[positions[0]], ranked[positions[1]], ranked[positions[2]], ranked[positions[3]])
            let options = [[a, d, b, c], [a, c, b, d], [a, b, c, d]]
            var best: (cost: Int, match: [Int]) = (.max, options[0])
            for (pattern, m) in options.enumerated() {
                let partnerRepeats = ledger.partners(m[0], m[1]) + ledger.partners(m[2], m[3])
                let opponentRepeats = ledger.opponents(m[0], m[2]) + ledger.opponents(m[0], m[3])
                    + ledger.opponents(m[1], m[2]) + ledger.opponents(m[1], m[3])
                let cost = partnerWeight * partnerRepeats + opponentWeight * opponentRepeats
                    + patternWeight * patternPenalty[pattern]
                if cost < best.cost { best = (cost, m) }
            }
            return best
        }

        // dp[k] : coût minimal des groupes 0..<g quand l'échange k a lieu à la frontière g−1|g.
        var dp = [0] + Array(repeating: Int.max, count: kinds - 1)
        var choices: [[(previous: Int, match: [Int])]] = []
        for g in 0..<groups {
            let outgoingKinds = g == groups - 1 ? [0] : Array(0..<kinds)
            var next = Array(repeating: Int.max, count: kinds)
            var nextChoice = Array(repeating: (previous: 0, match: [Int]()), count: kinds)
            for incoming in 0..<kinds where dp[incoming] != .max {
                for outgoing in outgoingKinds {
                    let (cost, match) = evaluate(g, incoming: incoming, outgoing: outgoing)
                    let total = dp[incoming] + cost + swapWeight * (exchanges[outgoing]?.distance ?? 0)
                    if total < next[outgoing] {
                        next[outgoing] = total
                        nextChoice[outgoing] = (incoming, match)
                    }
                }
            }
            dp = next
            choices.append(nextChoice)
        }

        var result: [[Int]] = Array(repeating: [], count: groups)
        var state = 0
        for g in stride(from: groups - 1, through: 0, by: -1) {
            result[g] = choices[g][state].match
            state = choices[g][state].previous
        }
        return result
    }
}

extension PairingLedger {
    /// Reconstruit l'historique à partir de tours existants.
    init(rounds: [Round], index: [Player.ID: Int]) {
        self.init(playerCount: index.count)
        for round in rounds {
            let matches = round.matches.map { m in
                (m.teamA.players + m.teamB.players).map { index[$0]! }
            }
            record(matches: matches, resting: round.resting.map { index[$0]! })
        }
    }
}
