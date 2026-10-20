import Foundation

/// Historique d'un planning en cours de construction, indexé par position de joueur (0..<n)
/// pour des calculs rapides : partenariats, oppositions, matchs joués, pauses.
struct PairingLedger {
    /// Poids d'une répétition de partenaire : prioritaire sur tout le reste.
    static let partnerWeight = 100
    /// Poids d'une répétition d'adversaire.
    static let opponentWeight = 10

    let playerCount: Int
    private(set) var partner: [Int]
    private(set) var opponent: [Int]
    private(set) var played: [Int]
    private(set) var rests: [Int]
    /// Dernier tour (0-based) où le joueur a été au repos, -1 s'il n'a jamais pausé.
    private(set) var lastRest: [Int]
    private(set) var roundsRecorded = 0

    init(playerCount: Int) {
        self.playerCount = playerCount
        partner = Array(repeating: 0, count: playerCount * playerCount)
        opponent = Array(repeating: 0, count: playerCount * playerCount)
        played = Array(repeating: 0, count: playerCount)
        rests = Array(repeating: 0, count: playerCount)
        lastRest = Array(repeating: -1, count: playerCount)
    }

    func partners(_ a: Int, _ b: Int) -> Int { partner[a * playerCount + b] }
    func opponents(_ a: Int, _ b: Int) -> Int { opponent[a * playerCount + b] }

    /// Coût marginal d'un match [a1, a2, b1, b2] (équipe A = a1+a2, équipe B = b1+b2).
    /// Le total d'un planning vaut Σ poids × (nombre de rencontres)² : ajouter une rencontre
    /// à une paire déjà vue c fois coûte (c+1)² − c² = 2c + 1.
    func cost(_ a1: Int, _ a2: Int, _ b1: Int, _ b2: Int) -> Int {
        let p = (2 * partners(a1, a2) + 1) + (2 * partners(b1, b2) + 1)
        let o = (2 * opponents(a1, b1) + 1) + (2 * opponents(a1, b2) + 1)
            + (2 * opponents(a2, b1) + 1) + (2 * opponents(a2, b2) + 1)
        return Self.partnerWeight * p + Self.opponentWeight * o
    }

    mutating func record(matches: [[Int]], resting: [Int]) {
        for m in matches {
            addPartner(m[0], m[1])
            addPartner(m[2], m[3])
            for a in [m[0], m[1]] {
                for b in [m[2], m[3]] { addOpponent(a, b) }
            }
            for p in m { played[p] += 1 }
        }
        for p in resting {
            rests[p] += 1
            lastRest[p] = roundsRecorded
        }
        roundsRecorded += 1
    }

    /// Coût total du planning enregistré.
    var totalCost: Int {
        var total = 0
        for a in 0..<playerCount {
            for b in (a + 1)..<max(a + 1, playerCount) {
                let p = partners(a, b), o = opponents(a, b)
                total += Self.partnerWeight * p * p + Self.opponentWeight * o * o
            }
        }
        return total
    }

    private mutating func addPartner(_ a: Int, _ b: Int) {
        partner[a * playerCount + b] += 1
        partner[b * playerCount + a] += 1
    }

    private mutating func addOpponent(_ a: Int, _ b: Int) {
        opponent[a * playerCount + b] += 1
        opponent[b * playerCount + a] += 1
    }
}
