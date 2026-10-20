import Foundation
@testable import PadelCore

enum TestSupport {
    static func tournament(
        format: TournamentFormat,
        players: Int,
        courts: Int? = nil,
        rounds: Int,
        scoring: ScoringRule = .fixedTotal(points: 24),
        firstRound: FirstRoundMode = .random,
        levels: [Int]? = nil,
        seed: UInt64 = 2024
    ) -> Tournament {
        let list = (0..<players).map { Player(name: "J\($0)", level: levels?[$0]) }
        return Tournament(
            name: "Test",
            format: format,
            settings: TournamentSettings(
                courts: courts ?? max(1, players / 4),
                scoring: scoring,
                plannedRounds: rounds,
                mexicanoFirstRound: firstRound
            ),
            players: list,
            seed: seed,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Termine tous les matchs du dernier tour avec le score fourni (écriture directe du modèle :
    /// la saisie officielle des scores est testée séparément).
    static func completeLastRound(_ tournament: inout Tournament, score: (Match) -> Score) {
        let last = tournament.rounds.count - 1
        for i in tournament.rounds[last].matches.indices {
            tournament.rounds[last].matches[i].score = score(tournament.rounds[last].matches[i])
            tournament.rounds[last].matches[i].state = .completed
        }
    }

    /// Score en 24 points où l'équipe la plus « forte » gagne ; force = indice de joueur bas.
    static func strengthScore(_ tournament: Tournament) -> (Match) -> Score {
        let index = Dictionary(uniqueKeysWithValues: tournament.players.enumerated().map { ($1.id, $0) })
        return { match in
            let a = match.teamA.players.map { index[$0]! }.reduce(0, +)
            let b = match.teamB.players.map { index[$0]! }.reduce(0, +)
            let margin = min(10, abs(a - b))
            return a < b ? Score(12 + margin / 2 + 1, 12 - margin / 2 - 1)
                : a > b ? Score(12 - margin / 2 - 1, 12 + margin / 2 + 1) : Score(12, 12)
        }
    }
}
