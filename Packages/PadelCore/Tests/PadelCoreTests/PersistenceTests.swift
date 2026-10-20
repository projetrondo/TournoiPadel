import Foundation
import Testing
@testable import PadelCore

@Suite("Sauvegarde et restauration")
struct PersistenceTests {
    static func sampleTournament(updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000.123)) -> Tournament {
        let players = (1...4).map { (number: Int) in Player(name: "Joueur \(number)", level: number) }
        let match = Match(
            court: 1,
            teamA: Team(players[0].id, players[3].id),
            teamB: Team(players[1].id, players[2].id),
            score: Score(15, 9),
            state: .completed,
            edits: [ScoreEdit(kind: .validation, date: updatedAt, previous: nil, new: Score(15, 9))]
        )
        return Tournament(
            name: "Test",
            format: .mexicano,
            settings: TournamentSettings(courts: 1, scoring: .raceTo(points: 16), plannedRounds: 3, mexicanoFirstRound: .byLevel),
            players: players,
            rounds: [Round(index: 1, matches: [match], resting: [])],
            status: .inProgress,
            seed: .max,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.5),
            updatedAt: updatedAt,
            sharing: SharingInfo(code: "K7M2QP")
        )
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PadelCoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("Encodage puis décodage : tournoi identique")
    func codecRoundTrip() throws {
        let tournament = Self.sampleTournament()
        let decoded = try TournamentCodec.decode(TournamentCodec.encode(tournament))
        #expect(decoded == tournament)
    }

    @Test("Toutes les règles de score survivent à l'encodage")
    func scoringRulesRoundTrip() throws {
        for rule in [ScoringRule.fixedTotal(points: 32), .raceTo(points: 21), .free] {
            var tournament = Self.sampleTournament()
            tournament.settings.scoring = rule
            #expect(try TournamentCodec.decode(TournamentCodec.encode(tournament)).settings.scoring == rule)
        }
    }

    @Test("Version de format plus récente refusée proprement")
    func futureSchema() throws {
        var tournament = Self.sampleTournament()
        tournament.schemaVersion = Tournament.currentSchemaVersion + 1
        let data = try TournamentCodec.encode(tournament)
        #expect(throws: TournamentCodec.DecodingFailure.unsupportedSchemaVersion(Tournament.currentSchemaVersion + 1)) {
            try TournamentCodec.decode(data)
        }
    }

    @Test("Sauvegarde sur disque, rechargement et suppression")
    func fileStore() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileTournamentStore(directory: directory)

        let older = Self.sampleTournament(updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = Self.sampleTournament(updatedAt: Date(timeIntervalSince1970: 2_000))
        try store.save(older)
        try store.save(newer)

        let loaded = try store.loadAll()
        #expect(loaded.unreadableFiles.isEmpty)
        #expect(loaded.tournaments == [newer, older])

        try store.delete(id: older.id)
        #expect(try store.loadAll().tournaments == [newer])
        try store.delete(id: older.id) // supprimer deux fois ne doit pas échouer
    }

    @Test("Une nouvelle sauvegarde remplace la précédente")
    func overwrite() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileTournamentStore(directory: directory)

        var tournament = Self.sampleTournament()
        try store.save(tournament)
        tournament.rounds[0].matches[0].score = Score(10, 6)
        tournament.touch(at: Date(timeIntervalSince1970: 1_900_000_000))
        try store.save(tournament)

        let loaded = try store.loadAll().tournaments
        #expect(loaded.count == 1)
        #expect(loaded.first?.rounds[0].matches[0].score == Score(10, 6))
        #expect(loaded.first?.revision == 2)
    }

    @Test("Un fichier corrompu est mis de côté sans bloquer les autres ni être supprimé")
    func corruptedFile() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileTournamentStore(directory: directory)

        let good = Self.sampleTournament()
        try store.save(good)
        let corrupted = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{ pas du json".utf8).write(to: corrupted)

        let loaded = try store.loadAll()
        #expect(loaded.tournaments == [good])
        #expect(loaded.unreadableFiles.count == 1)
        let quarantined = try #require(loaded.unreadableFiles.first)
        #expect(quarantined.path.contains("Unreadable"))
        #expect(FileManager.default.fileExists(atPath: quarantined.path))
        #expect(try store.loadAll().unreadableFiles.isEmpty) // plus relu au chargement suivant
    }
}
