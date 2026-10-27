import Foundation
import Testing
@testable import PadelCore

@Suite("Sessions : joueurs enregistrés et classements par période")
struct SessionTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 2026-03-11 (un mercredi) à 20 h, heure de Paris.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 20))!
    }

    static func session(_ names: [String] = ["Alex", "Manon", "Julien", "Camille", "Rayan"]) -> PlaySession {
        var session = PlaySession(name: "Padel du jeudi", createdAt: date(2026, 1, 1))
        for name in names { try! session.addMember(name: name) }
        return session
    }

    /// Tournoi de la session, un match par tour, joué le `day` (scores validés ce jour-là).
    static func tournament(
        _ session: PlaySession,
        on day: Date,
        _ matches: [(a: (Int, Int), b: (Int, Int), score: Score)],
        sessionID: UUID? = nil
    ) -> Tournament {
        let members = session.activeMembers
        let players = members.map { Player(id: $0.id, name: $0.name) }
        let rounds = matches.enumerated().map { i, m in
            Round(index: i + 1, matches: [Match(
                court: 1,
                teamA: Team(members[m.a.0].id, members[m.a.1].id),
                teamB: Team(members[m.b.0].id, members[m.b.1].id),
                score: m.score,
                state: .completed,
                edits: [ScoreEdit(kind: .validation, date: day, previous: nil, new: m.score)]
            )], resting: [])
        }
        return Tournament(
            name: "Tournoi",
            format: .americano,
            settings: TournamentSettings(courts: 1, scoring: .fixedTotal(points: 24), plannedRounds: rounds.count),
            players: players,
            rounds: rounds,
            status: .finished,
            seed: 1,
            createdAt: day.addingTimeInterval(-3_600),
            sessionID: sessionID ?? session.id
        )
    }

    // MARK: - Liste de joueurs

    @Test("Ajout : nom nettoyé, doublon refusé sans tenir compte de la casse ni des accents")
    func addMember() throws {
        var session = Self.session(["Zoé"])
        let added = try session.addMember(name: "  Léa ", level: 3)
        #expect(added.name == "Léa")
        #expect(added.level == 3)
        #expect(throws: SessionError.duplicateName("Zoé")) { try session.addMember(name: "zoe") }
        #expect(throws: SessionError.emptyName) { try session.addMember(name: "   ") }
        #expect(throws: SessionError.nameTooLong(TournamentDraft.maxPlayerNameLength)) {
            try session.addMember(name: String(repeating: "a", count: 21))
        }
    }

    @Test("Retirer un joueur l'archive ; le rajouter le réactive avec son historique")
    func archiveAndRestore() throws {
        var session = Self.session(["Alex", "Manon"])
        let alex = session.members[0]
        session.archiveMember(id: alex.id)
        #expect(session.activeMembers.map(\.name) == ["Manon"])
        #expect(session.members.count == 2, "jamais supprimé")
        let again = try session.addMember(name: "alex")
        #expect(again.id == alex.id)
        #expect(session.activeMembers.count == 2)
    }

    @Test("Renommer : refusé si le nom est déjà pris par un autre joueur")
    func renameMember() throws {
        var session = Self.session(["Alex", "Manon"])
        let alex = session.members[0]
        try session.updateMember(id: alex.id, name: "Alexandre", level: 4)
        #expect(session.member(alex.id)?.name == "Alexandre")
        #expect(session.member(alex.id)?.level == 4)
        #expect(throws: SessionError.duplicateName("Manon")) {
            try session.updateMember(id: alex.id, name: "MANON", level: nil)
        }
        #expect(throws: SessionError.unknownMember) {
            try session.updateMember(id: UUID(), name: "X", level: nil)
        }
    }

    @Test("Un tournoi créé depuis la session garde les identifiants des joueurs")
    func draftFromSession() throws {
        let session = Self.session(["Alex", "Manon", "Julien", "Camille"])
        let draft = TournamentDraft(
            name: "Jeudi",
            players: session.activeMembers.map(\.draftEntry),
            sessionID: session.id
        )
        let tournament = try draft.makeTournament(now: Self.date(2026, 3, 12), seed: 1)
        #expect(tournament.sessionID == session.id)
        #expect(tournament.players.map(\.id) == session.activeMembers.map(\.id))
    }

    @Test("Les nouveaux joueurs d'un tournoi rejoignent la liste de la session")
    func absorbPlayers() throws {
        var session = Self.session(["Alex", "Manon", "Julien"])
        let newcomer = TournamentDraft.PlayerEntry(name: "Rayan")
        let draft = TournamentDraft(
            name: "Jeudi",
            players: session.activeMembers.map(\.draftEntry) + [newcomer, .init(name: "MANON")],
            sessionID: session.id
        )
        // Le brouillon refuse le doublon ; on retire l'homonyme pour créer le tournoi.
        var valid = draft
        valid.players.removeLast()
        let tournament = try valid.makeTournament(now: Self.date(2026, 3, 12), seed: 1)
        session.absorbPlayers(of: tournament)
        #expect(session.members.map(\.name) == ["Alex", "Manon", "Julien", "Rayan"])
        #expect(session.member(newcomer.id)?.name == "Rayan", "même identifiant que dans le tournoi")
        session.absorbPlayers(of: tournament)
        #expect(session.members.count == 4, "pas de doublon")
    }

    // MARK: - Date de jeu

    @Test("Un tournoi est daté de son premier score validé")
    func playedOn() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        #expect(t.playedOn == t.createdAt)
        try t.start(now: Self.date(2026, 3, 1))
        let first = t.rounds[0].matches[0].id
        try t.validateScore(first, score: Score(15, 9), now: Self.date(2026, 3, 12))
        #expect(t.playedOn == Self.date(2026, 3, 12))
    }

    // MARK: - Classement

    @Test("Moyenne de points par match, cumulée sur les tournois de la période")
    func averageRanking() {
        var session = Self.session()
        session.minimumMatches = 1
        // Tournoi 1 : Alex+Manon 15-9 contre Julien+Camille.
        let t1 = Self.tournament(session, on: Self.date(2026, 3, 10), [((0, 1), (2, 3), Score(15, 9))])
        // Tournoi 2 : Alex+Julien 6-18 contre Manon+Rayan.
        let t2 = Self.tournament(session, on: Self.date(2026, 3, 12), [((0, 2), (1, 4), Score(6, 18))])
        let ranking = SessionRanking(session: session, tournaments: [t1, t2], period: .month, reference: Self.date(2026, 3, 20), calendar: Self.calendar)
        let names = ranking.rows.map { SessionRanking.name(of: $0.id, session: session, tournaments: [t1, t2]) }
        // Moyennes : Rayan 18, Manon 16.5 (33/2), Alex 10.5, Camille 9, Julien 7.5.
        #expect(names == ["Rayan", "Manon", "Alex", "Camille", "Julien"])
        #expect(ranking.rows.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(ranking.tournamentCount == 2)
        #expect(ranking.matchCount == 2)
        let manon = ranking.rows[1]
        #expect(manon.stats.played == 2 && manon.stats.pointsFor == 33 && manon.stats.wins == 2)
        #expect(manon.tournaments == 2)
    }

    @Test("En dessous du minimum de matchs : affiché à part, sans position")
    func minimumMatches() {
        var session = Self.session()
        session.minimumMatches = 2
        let t1 = Self.tournament(session, on: Self.date(2026, 3, 10), [
            ((0, 1), (2, 3), Score(15, 9)),
            ((0, 2), (1, 3), Score(12, 12)),
        ])
        let t2 = Self.tournament(session, on: Self.date(2026, 3, 11), [((0, 4), (1, 2), Score(20, 4))])
        let ranking = SessionRanking(session: session, tournaments: [t1, t2], period: .all, reference: Self.date(2026, 3, 20), calendar: Self.calendar)
        let rayan = session.members[4].id
        #expect(ranking.unranked.map(\.id) == [rayan])
        #expect(ranking.ranked.count == 4)
        #expect(ranking.rows.last?.id == rayan)
    }

    @Test("Égalité parfaite : même position ; départage au pourcentage de victoires")
    func tiesAndWinRate() {
        var session = Self.session(["A", "B", "C", "D"])
        session.minimumMatches = 1
        let t = Self.tournament(session, on: Self.date(2026, 3, 10), [
            ((0, 1), (2, 3), Score(13, 11)),
            ((0, 2), (1, 3), Score(11, 13)),
        ])
        // Points : A 24, B 26, C 22, D 24 → moyennes A 12, B 13, C 11, D 12.
        // A et D : même moyenne, même % (1 V sur 2), même différence → ex aequo.
        let ranking = SessionRanking(session: session, tournaments: [t], period: .all, reference: Self.date(2026, 3, 20), calendar: Self.calendar)
        #expect(ranking.rows.map(\.rank) == [1, 2, 2, 4])
        #expect(ranking.rows[1].isTied && ranking.rows[2].isTied)
        #expect(!ranking.rows[0].isTied)
    }

    @Test("Seuls les tournois de la session et de la période comptent")
    func periodAndSessionFilter() {
        var session = Self.session()
        session.minimumMatches = 1
        let thisWeek = Self.tournament(session, on: Self.date(2026, 3, 11), [((0, 1), (2, 3), Score(15, 9))])
        let lastWeek = Self.tournament(session, on: Self.date(2026, 3, 4), [((0, 4), (2, 3), Score(15, 9))])
        let lastYear = Self.tournament(session, on: Self.date(2025, 12, 31), [((0, 1), (2, 4), Score(15, 9))])
        let otherSession = Self.tournament(session, on: Self.date(2026, 3, 11), [((0, 1), (2, 3), Score(1, 23))], sessionID: UUID())
        let all = [thisWeek, lastWeek, lastYear, otherSession]
        func count(_ period: RankingPeriod) -> Int {
            SessionRanking(session: session, tournaments: all, period: period, reference: Self.date(2026, 3, 12), calendar: Self.calendar).tournamentCount
        }
        #expect(count(.week) == 1)
        #expect(count(.month) == 2)
        #expect(count(.year) == 2)
        #expect(count(.all) == 3)
    }

    @Test("Semaine du lundi au dimanche ; navigation d'une période à l'autre")
    func periods() {
        let wednesday = Self.date(2026, 3, 11)
        let week = RankingPeriod.week.interval(containing: wednesday, calendar: Self.calendar)!
        #expect(Self.calendar.component(.weekday, from: week.start) == 2, "lundi")
        #expect(week.duration == 7 * 86_400)
        let previous = RankingPeriod.month.shift(wednesday, by: -1, calendar: Self.calendar)
        #expect(Self.calendar.component(.month, from: previous) == 2)
        #expect(RankingPeriod.all.interval(containing: wednesday, calendar: Self.calendar) == nil)
        #expect(RankingPeriod.all.shift(wednesday, by: 3, calendar: Self.calendar) == wednesday)
    }

    @Test("Matchs non validés et tours exclus ignorés ; un tournoi sans score ne compte pas")
    func onlyValidatedMatches() {
        var session = Self.session(["A", "B", "C", "D"])
        session.minimumMatches = 1
        var t = Self.tournament(session, on: Self.date(2026, 3, 10), [
            ((0, 1), (2, 3), Score(15, 9)),
            ((0, 2), (1, 3), Score(20, 4)),
        ])
        t.rounds[1].excluded = true
        var empty = Self.tournament(session, on: Self.date(2026, 3, 10), [((0, 1), (2, 3), Score(15, 9))])
        empty.rounds[0].matches[0].state = .scheduled
        let ranking = SessionRanking(session: session, tournaments: [t, empty], period: .all, reference: Self.date(2026, 3, 20), calendar: Self.calendar)
        #expect(ranking.tournamentCount == 1)
        #expect(ranking.matchCount == 1)
        #expect(ranking.rows.allSatisfy { $0.stats.played == 1 })
    }

    // MARK: - Sauvegarde

    @Test("Session : aller-retour JSON et stockage fichier")
    func persistence() throws {
        var session = Self.session()
        session.archiveMember(id: session.members[1].id)
        let decoded = try SessionCodec.decode(SessionCodec.encode(session))
        #expect(decoded == session)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSessionStore(directory: directory)
        try store.save(session)
        #expect(try store.loadAll() == [session])
        try store.delete(id: session.id)
        #expect(try store.loadAll().isEmpty)
    }

    @Test("Un tournoi enregistré avant les sessions se relit sans session")
    func legacyTournamentWithoutSession() throws {
        let t = TestSupport.tournament(format: .americano, players: 4, rounds: 1)
        var json = try JSONSerialization.jsonObject(with: TournamentCodec.encode(t)) as! [String: Any]
        json["sessionID"] = nil
        let legacy = try TournamentCodec.decode(JSONSerialization.data(withJSONObject: json))
        #expect(legacy.sessionID == nil)
        #expect(legacy == t)
    }
}
