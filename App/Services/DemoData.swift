import Foundation
import PadelCore

/// Données fictives pour les aperçus SwiftUI et les captures d'écran automatiques.
enum DemoData {
    static func tournaments() -> [Tournament] {
        let reference = Date(timeIntervalSince1970: 1_790_000_000)
        var started = makeTournament(
            name: "Americano du dimanche",
            format: .americano,
            names: ["Alex", "Manon", "Julien", "Camille", "Rayan", "Zoé", "Antoine", "Lina"],
            courts: 2,
            status: .draft,
            date: reference.addingTimeInterval(3_600)
        )
        try? started.start(now: reference.addingTimeInterval(3_600))
        return [
            started,
            makeTournament(
                name: "Padel du jeudi",
                format: .americano,
                names: ["Léa", "Max", "Inès", "Tom", "Chloé", "Hugo", "Sarah", "Nico"],
                courts: 2,
                status: .draft,
                date: reference
            ),
            makeTournament(
                name: "Mexicano du club",
                format: .mexicano,
                names: ["Paul", "Emma", "Yanis", "Jade", "Lucas"],
                courts: 1,
                status: .finished,
                date: reference.addingTimeInterval(-86_400 * 6)
            ),
        ]
    }

    private static func makeTournament(
        name: String,
        format: TournamentFormat,
        names: [String],
        courts: Int,
        status: TournamentStatus,
        date: Date
    ) -> Tournament {
        let planner = RoundPlanner(playerCount: names.count, declaredCourts: courts)
        let scoring = ScoringRule.fixedTotal(points: 24)
        var tournament = Tournament(
            name: name,
            format: format,
            settings: TournamentSettings(
                courts: courts,
                scoring: scoring,
                plannedRounds: planner.recommendedRounds(scoring: scoring) ?? 1
            ),
            players: names.map { Player(name: $0) },
            seed: 1,
            createdAt: date
        )
        tournament.status = status
        return tournament
    }
}
