import Foundation

/// Choix des joueurs au repos, commun à l'Americano et au Mexicano.
enum RestSelector {
    /// Retient `count` joueurs parmi `candidates`, par ordre de priorité :
    /// 1. le moins de pauses ; 2. pas de pause au tour précédent ; 3. le plus de matchs joués ;
    /// 4. la pause la plus ancienne ; 5. tirage déterministe.
    /// Choisir toujours les moins reposés garde un écart d'au plus une pause entre joueurs,
    /// donc une égalité parfaite dès que le nombre de tours est équitable.
    static func choose(count: Int, among candidates: [Int], ledger: PairingLedger, rng: inout SeededGenerator) -> [Int] {
        guard count > 0 else { return [] }
        let previousRound = ledger.roundsRecorded - 1
        let tieBreak = Dictionary(uniqueKeysWithValues: candidates.map { ($0, rng.next()) })
        let ordered = candidates.sorted { a, b in
            if ledger.rests[a] != ledger.rests[b] { return ledger.rests[a] < ledger.rests[b] }
            let aConsecutive = ledger.lastRest[a] == previousRound && previousRound >= 0
            let bConsecutive = ledger.lastRest[b] == previousRound && previousRound >= 0
            if aConsecutive != bConsecutive { return !aConsecutive }
            if ledger.played[a] != ledger.played[b] { return ledger.played[a] > ledger.played[b] }
            if ledger.lastRest[a] != ledger.lastRest[b] { return ledger.lastRest[a] < ledger.lastRest[b] }
            return tieBreak[a]! < tieBreak[b]!
        }
        return Array(ordered.prefix(count))
    }
}

/// Recherche locale : répartit des joueurs actifs en matchs de façon à minimiser le coût
/// de répétition (partenaires puis adversaires). Les positions 4m…4m+3 forment le match m :
/// équipe A = 4m, 4m+1 ; équipe B = 4m+2, 4m+3.
enum MatchArranger {
    static func arrange(players: [Int], ledger: PairingLedger, restarts: Int, rng: inout SeededGenerator) -> [[Int]] {
        precondition(players.count % 4 == 0)
        var best: [Int] = players
        var bestCost = Int.max
        for _ in 0..<max(1, restarts) {
            var slots = rng.shuffled(players)
            improve(&slots, ledger: ledger)
            let cost = totalCost(slots, ledger: ledger)
            if cost < bestCost {
                bestCost = cost
                best = slots
            }
        }
        return stride(from: 0, to: best.count, by: 4).map { Array(best[$0..<($0 + 4)]) }
    }

    /// Regroupe des paires de partenaires déjà fixées en matchs (seules les oppositions varient).
    static func groupPairs(_ pairs: [(Int, Int)], ledger: PairingLedger, restarts: Int, rng: inout SeededGenerator) -> [[Int]] {
        precondition(pairs.count % 2 == 0)
        func matchCost(_ order: [(Int, Int)], _ m: Int) -> Int {
            let a = order[2 * m], b = order[2 * m + 1]
            return ledger.cost(a.0, a.1, b.0, b.1)
        }
        var best = pairs
        var bestCost = Int.max
        for _ in 0..<max(1, restarts) {
            var order = rng.shuffled(pairs)
            var improved = true
            while improved {
                improved = false
                for i in 0..<order.count {
                    for j in (i + 1)..<order.count where i / 2 != j / 2 {
                        let before = matchCost(order, i / 2) + matchCost(order, j / 2)
                        order.swapAt(i, j)
                        let after = matchCost(order, i / 2) + matchCost(order, j / 2)
                        if after < before { improved = true } else { order.swapAt(i, j) }
                    }
                }
            }
            let cost = (0..<(order.count / 2)).reduce(0) { $0 + matchCost(order, $1) }
            if cost < bestCost {
                bestCost = cost
                best = order
            }
        }
        return (0..<(best.count / 2)).map { m in
            [best[2 * m].0, best[2 * m].1, best[2 * m + 1].0, best[2 * m + 1].1]
        }
    }

    static func totalCost(_ slots: [Int], ledger: PairingLedger) -> Int {
        stride(from: 0, to: slots.count, by: 4).reduce(0) { total, i in
            total + ledger.cost(slots[i], slots[i + 1], slots[i + 2], slots[i + 3])
        }
    }

    private static func matchCost(_ slots: [Int], _ match: Int, _ ledger: PairingLedger) -> Int {
        let i = match * 4
        return ledger.cost(slots[i], slots[i + 1], slots[i + 2], slots[i + 3])
    }

    /// Échange deux joueurs d'équipes différentes tant que cela réduit le coût.
    private static func improve(_ slots: inout [Int], ledger: PairingLedger) {
        var improved = true
        while improved {
            improved = false
            for i in 0..<slots.count {
                for j in (i + 1)..<slots.count where i / 2 != j / 2 {
                    let mi = i / 4, mj = j / 4
                    let before = matchCost(slots, mi, ledger) + (mi == mj ? 0 : matchCost(slots, mj, ledger))
                    slots.swapAt(i, j)
                    let after = matchCost(slots, mi, ledger) + (mi == mj ? 0 : matchCost(slots, mj, ledger))
                    if after < before { improved = true } else { slots.swapAt(i, j) }
                }
            }
        }
    }
}

extension SeededGenerator {
    /// UUID tiré du générateur : un planning est entièrement reproductible à partir de sa graine.
    mutating func uuid() -> UUID {
        let a = next(), b = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i)))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variante RFC 4122
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Conversion d'un tour indexé (positions de joueurs) en `Round` du modèle.
func makeRound(index: Int, matches: [[Int]], resting: [Int], playerIDs: [Player.ID], rng: inout SeededGenerator) -> Round {
    let ordered = rng.shuffled(matches)
    let built = ordered.enumerated().map { court, m in
        Match(
            id: rng.uuid(),
            court: court + 1,
            teamA: Team(playerIDs[m[0]], playerIDs[m[1]]),
            teamB: Team(playerIDs[m[2]], playerIDs[m[3]])
        )
    }
    return Round(index: index, matches: built, resting: resting.sorted().map { playerIDs[$0] })
}
