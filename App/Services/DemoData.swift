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
        return [americano, draft, mexicano] + sessionTournaments()
    }

    // MARK: - Session de démonstration

    static let sessionID = UUID(uuidString: "5E55E55E-0000-4000-8000-000000000001")!
    static let sessionNames = ["Léa", "Max", "Inès", "Tom", "Chloé", "Hugo", "Sarah", "Nico", "Yanis"]

    /// Joueurs enregistrés de la session, avec des identifiants fixes.
    static var sessionMembers: [SessionMember] {
        sessionNames.enumerated().map { index, name in
            SessionMember(id: UUID(uuidString: String(format: "5E55E55E-0000-4000-8000-%012d", index + 2))!, name: name)
        }
    }

    static func sessions(now: Date = Date()) -> [PlaySession] {
        [PlaySession(
            id: sessionID,
            name: "Les Aigles du jeudi",
            members: sessionMembers,
            minimumMatches: 3,
            createdAt: now.addingTimeInterval(-86_400 * 40)
        )]
    }

    /// Trois soirées terminées, une par semaine, relatives à `now` pour que le classement
    /// du mois en cours ait du contenu sur les captures.
    static func sessionTournaments(now: Date = Date()) -> [Tournament] {
        let members = sessionMembers
        let evenings: [(days: Double, present: [Int], offset: Int)] = [
            (2, [0, 1, 2, 3, 4, 5, 6, 7], 0),
            (9, [0, 1, 2, 3, 4, 5, 7, 8], 2),
            (16, [0, 1, 3, 4, 5, 6, 7, 8], 4),
        ]
        return evenings.map { evening in
            let date = now.addingTimeInterval(-86_400 * evening.days)
            var tournament = makeTournament(
                name: "Jeudi " + date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))),
                format: .americano,
                players: evening.present.map { Player(id: members[$0].id, name: members[$0].name) },
                courts: 2,
                date: date,
                sessionID: sessionID
            )
            try? tournament.start(now: date)
            play(&tournament, rounds: Int.max, date: date, offset: evening.offset)
            try? tournament.finish(now: date)
            return tournament
        }
    }

    /// Scores fictifs mais plausibles, déterministes.
    private static func play(_ tournament: inout Tournament, rounds: Int, date: Date, offset: Int = 0) {
        let scores = [Score(15, 9), Score(11, 13), Score(17, 7), Score(12, 12), Score(10, 14), Score(16, 8)]
        var i = offset
        for match in tournament.orderedMatches where match.state != .completed {
            guard let location = tournament.location(of: match.id), location.round < rounds else { break }
            try? tournament.validateScore(match.id, score: scores[i % scores.count], now: date)
            i += 1
        }
    }

    private static func makeTournament(
        name: String,
        format: TournamentFormat,
        names: [String] = [],
        players: [Player]? = nil,
        courts: Int,
        date: Date,
        sessionID: UUID? = nil
    ) -> Tournament {
        let players = players ?? names.map { Player(name: $0) }
        let planner = RoundPlanner(playerCount: players.count, declaredCourts: courts)
        let scoring = ScoringRule.fixedTotal(points: 24)
        return Tournament(
            name: name,
            format: format,
            settings: TournamentSettings(
                courts: courts,
                scoring: scoring,
                plannedRounds: planner.recommendedRounds(scoring: scoring) ?? 1
            ),
            players: players,
            seed: 1,
            createdAt: date,
            sessionID: sessionID
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

    /// `-demo-session` : ouvre la première session ; `-demo-session-tab ranking|tournaments|players`.
    static var opensSession: Bool { arguments.contains("-ui-testing") && arguments.contains("-demo-session") }
    static var sessionTab: String? { value(after: "-demo-session-tab") }

    /// `-demo-account` : compte simulé connecté ; `-demo-open-account` ouvre l'écran du compte.
    static var opensAccount: Bool { arguments.contains("-ui-testing") && arguments.contains("-demo-open-account") }

    /// `-demo-language fr|en` : langue des captures d'écran.
    static var language: AppLanguage? { value(after: "-demo-language").flatMap(AppLanguage.init(rawValue:)) }

    /// `-demo-player` : ouvre le profil de l'Aigle depuis le classement.
    static var opensPlayerProfile: Bool { arguments.contains("-ui-testing") && arguments.contains("-demo-player") }

    private static func value(after flag: String) -> String? {
        guard arguments.contains("-ui-testing"), let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
