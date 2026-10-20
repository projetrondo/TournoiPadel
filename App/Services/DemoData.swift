import Foundation
import PadelCore

/// Données fictives pour les aperçus SwiftUI et les captures d'écran automatiques.
enum DemoData {
    static func tournaments() -> [Tournament] {
        let reference = Date(timeIntervalSince1970: 1_790_000_000)

        // Americano en cours : deux tours joués.
        var americano = makeTournament(
            name: "Americano du dimanche",
            format: .americano,
            names: ["Alex", "Manon", "Julien", "Camille", "Rayan", "Zoé", "Antoine", "Lina"],
            courts: 2,
            date: reference.addingTimeInterval(3_600)
        )
        try? americano.start(now: reference)
        play(&americano, rounds: 2, date: reference)

        // Mexicano terminé.
        var mexicano = makeTournament(
            name: "Mexicano du club",
            format: .mexicano,
            names: ["Paul", "Emma", "Yanis", "Jade", "Lucas"],
            courts: 1,
            date: reference.addingTimeInterval(-86_400 * 6)
        )
        try? mexicano.start(now: reference)
        for _ in 0..<50 where mexicano.status == .inProgress {
            play(&mexicano, rounds: Int.max, date: reference)
            if mexicano.canGenerateNextRound {
                try? mexicano.generateNextRound(now: reference)
            } else {
                try? mexicano.finish(now: reference)
                break
            }
        }

        let draft = makeTournament(
            name: "Padel du jeudi",
            format: .americano,
            names: ["Léa", "Max", "Inès", "Tom", "Chloé", "Hugo", "Sarah", "Nico"],
            courts: 2,
            date: reference.addingTimeInterval(-3_600)
        )
        return [americano, draft, mexicano]
    }

    /// Scores fictifs mais plausibles, déterministes.
    private static func play(_ tournament: inout Tournament, rounds: Int, date: Date) {
        let scores = [Score(15, 9), Score(11, 13), Score(17, 7), Score(12, 12), Score(10, 14), Score(16, 8)]
        var i = 0
        for match in tournament.orderedMatches where match.state != .completed {
            guard let location = tournament.location(of: match.id), location.round < rounds else { break }
            try? tournament.validateScore(match.id, score: scores[i % scores.count], now: date)
            i += 1
        }
    }

    private static func makeTournament(
        name: String,
        format: TournamentFormat,
        names: [String],
        courts: Int,
        date: Date
    ) -> Tournament {
        let planner = RoundPlanner(playerCount: names.count, declaredCourts: courts)
        let scoring = ScoringRule.fixedTotal(points: 24)
        return Tournament(
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
    }
}

/// Options de lancement réservées aux captures d'écran automatiques (avec `-ui-testing`).
enum LaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// `-demo-open draft|inProgress|finished` : ouvre le premier tournoi dans cet état.
    static var openStatus: TournamentStatus? {
        value(after: "-demo-open").flatMap(TournamentStatus.init(rawValue:))
    }

    /// `-demo-tab results|matches|standings|info`.
    static var tab: String? { value(after: "-demo-tab") }

    /// `-demo-score` : ouvre la saisie du premier match non joué.
    static var opensScoreEntry: Bool { arguments.contains("-ui-testing") && arguments.contains("-demo-score") }

    private static func value(after flag: String) -> String? {
        guard arguments.contains("-ui-testing"), let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
