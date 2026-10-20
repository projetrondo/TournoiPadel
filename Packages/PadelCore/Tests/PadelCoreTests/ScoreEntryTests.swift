import Foundation
import Testing
@testable import PadelCore

@Suite("Saisie et correction des scores")
struct ScoreEntryTests {
    static func started(_ format: TournamentFormat = .americano, players: Int = 4, rounds: Int = 3,
                        scoring: ScoringRule = .fixedTotal(points: 24)) throws -> Tournament {
        var t = TestSupport.tournament(format: format, players: players, rounds: rounds, scoring: scoring)
        try t.start(now: Date(timeIntervalSince1970: 0))
        return t
    }

    @Test("Valider un score : match terminé, historique, révision")
    func validate() throws {
        var t = try Self.started()
        let match = t.rounds[0].matches[0]
        let revision = t.revision
        try t.validateScore(match.id, score: Score(15, 9), now: Date(timeIntervalSince1970: 100))
        let saved = try #require(t.match(match.id))
        #expect(saved.state == .completed)
        #expect(saved.score == Score(15, 9))
        #expect(saved.edits.map(\.kind) == [.validation])
        #expect(t.revision == revision + 1)
        // Les points individuels sont attribués.
        #expect(Standings.stats(for: t)[match.teamA.first]?.pointsFor == 15)
        #expect(Standings.stats(for: t)[match.teamB.second]?.pointsFor == 9)
    }

    @Test("Impossible de valider deux fois le même match")
    func doubleValidation() throws {
        var t = try Self.started()
        let id = t.rounds[0].matches[0].id
        try t.validateScore(id, score: Score(15, 9), now: Date())
        let snapshot = t
        #expect(throws: ScoreEntryError.alreadyValidated) { try t.validateScore(id, score: Score(14, 10), now: Date()) }
        #expect(t == snapshot)
    }

    @Test("Un score invalide n'est jamais enregistré")
    func invalidScore() throws {
        var t = try Self.started()
        let id = t.rounds[0].matches[0].id
        let snapshot = t
        #expect(throws: ScoreEntryError.invalidScore(.totalMustEqual(24))) {
            try t.validateScore(id, score: Score(15, 8), now: Date())
        }
        #expect(t == snapshot)
        #expect(t.match(id)?.state == .scheduled)
    }

    @Test("Règle « premier à » appliquée à la validation")
    func raceToRule() throws {
        var t = try Self.started(scoring: .raceTo(points: 16))
        let id = t.rounds[0].matches[0].id
        #expect(throws: ScoreEntryError.invalidScore(.winnerMustReach(16))) {
            try t.validateScore(id, score: Score(15, 10), now: Date())
        }
        try t.validateScore(id, score: Score(16, 10), now: Date())
    }

    @Test("Corriger un score : classement mis à jour, ancien score conservé")
    func correction() throws {
        var t = try Self.started()
        let match = t.rounds[0].matches[0]
        try t.validateScore(match.id, score: Score(15, 9), now: Date())
        try t.correctScore(match.id, score: Score(9, 15), now: Date())

        let saved = try #require(t.match(match.id))
        #expect(saved.score == Score(9, 15))
        #expect(saved.edits.map(\.kind) == [.validation, .correction])
        #expect(saved.edits.last?.previous == Score(15, 9))
        let stats = Standings.stats(for: t)
        #expect(stats[match.teamA.first]?.pointsFor == 9)
        #expect(stats[match.teamA.first]?.losses == 1)
        #expect(stats[match.teamB.first]?.wins == 1)
    }

    @Test("Corriger un match non validé est refusé")
    func correctionNeedsValidation() throws {
        var t = try Self.started()
        #expect(throws: ScoreEntryError.notValidated) {
            try t.correctScore(t.rounds[0].matches[0].id, score: Score(12, 12), now: Date())
        }
    }

    @Test("Une correction invalide ne change rien")
    func invalidCorrection() throws {
        var t = try Self.started()
        let id = t.rounds[0].matches[0].id
        try t.validateScore(id, score: Score(15, 9), now: Date())
        let snapshot = t
        #expect(throws: ScoreEntryError.invalidScore(.totalMustEqual(24))) {
            try t.correctScore(id, score: Score(30, 9), now: Date())
        }
        #expect(t == snapshot)
    }

    @Test("Rouvrir un match annule sa validation")
    func reopen() throws {
        var t = try Self.started()
        let id = t.rounds[0].matches[0].id
        try t.validateScore(id, score: Score(15, 9), now: Date())
        try t.reopenMatch(id, now: Date())
        #expect(t.match(id)?.score == nil)
        #expect(t.match(id)?.state == .inProgress)
        #expect(t.match(id)?.edits.map(\.kind) == [.validation, .reset])
        #expect(Standings.stats(for: t).values.allSatisfy { $0.played == 0 })
        // Puis on peut le valider à nouveau.
        try t.validateScore(id, score: Score(13, 11), now: Date())
    }

    @Test("Mexicano : un match d'un tour déjà suivi ne se rouvre pas, mais se corrige")
    func mexicanoLockedRound() throws {
        var t = try Self.started(.mexicano, players: 4, rounds: 3)
        let first = t.rounds[0].matches[0].id
        try t.validateScore(first, score: Score(15, 9), now: Date())
        try t.generateNextRound(now: Date())
        let roundTwo = t.rounds[1]

        #expect(!t.canReopen(first))
        #expect(throws: ScoreEntryError.roundLocked) { try t.reopenMatch(first, now: Date()) }
        try t.correctScore(first, score: Score(10, 14), now: Date())
        #expect(t.rounds[1] == roundTwo, "le tour suivant n'est pas modifié par une correction")
        #expect(t.canRegenerateLastRound)
    }

    @Test("Marquer un match en cours")
    func inProgress() throws {
        var t = try Self.started()
        let id = t.rounds[0].matches[0].id
        try t.markInProgress(id, now: Date())
        #expect(t.match(id)?.state == .inProgress)
        #expect(t.currentRound?.index == 1)
    }

    @Test("Saisie impossible avant le lancement")
    func notStarted() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        #expect(throws: ScoreEntryError.tournamentNotStarted) { try t.validateScore(UUID(), score: Score(12, 12), now: Date()) }
    }

    @Test("Match inconnu")
    func unknownMatch() throws {
        var t = try Self.started()
        #expect(throws: ScoreEntryError.matchNotFound) { try t.validateScore(UUID(), score: Score(12, 12), now: Date()) }
    }

    @Test("Ordre de jeu : tour puis terrain")
    func orderedMatches() throws {
        let t = try Self.started(players: 8, rounds: 7)
        let order = t.orderedMatches
        #expect(order.count == 14)
        #expect(order.first?.id == t.rounds[0].matches.first { $0.court == 1 }?.id)
    }
}

@Suite("Clôture et résultats")
struct ResultsTests {
    static func playAll(_ t: inout Tournament) throws {
        let score = TestSupport.strengthScore(t)
        for match in t.orderedMatches where match.state != .completed {
            try t.validateScore(match.id, score: score(match), now: Date())
        }
    }

    @Test("Americano : clôture possible une fois tous les matchs joués")
    func finishAmericano() throws {
        var t = TestSupport.tournament(format: .americano, players: 5, rounds: 5)
        try t.start(now: Date())
        #expect(!t.canFinish)
        #expect(throws: LifecycleError.roundNotComplete) { try t.finish(now: Date()) }
        try Self.playAll(&t)
        #expect(t.canFinish)
        try t.finish(now: Date())
        #expect(t.status == .finished)
        #expect(throws: LifecycleError.notStarted) { try t.finish(now: Date()) }
    }

    @Test("Mexicano : clôture possible après n'importe quel tour terminé")
    func finishMexicanoEarly() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 8, rounds: 5)
        try t.start(now: Date())
        try Self.playAll(&t)
        #expect(t.canFinish)
        try t.finish(now: Date())
        #expect(!t.canGenerateNextRound)
    }

    @Test("Correction encore possible après la clôture")
    func correctionAfterFinish() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        try t.start(now: Date())
        try Self.playAll(&t)
        try t.finish(now: Date())
        let id = t.rounds[0].matches[0].id
        try t.correctScore(id, score: Score(0, 24), now: Date())
        #expect(t.match(id)?.score == Score(0, 24))
        #expect(!t.canReopen(id))
    }

    @Test("Résultats : podium, vainqueur, chiffres clés")
    func results() throws {
        var t = TestSupport.tournament(format: .americano, players: 8, rounds: 7)
        try t.start(now: Date())
        try Self.playAll(&t)
        let results = TournamentResults(tournament: t)
        #expect(results.matchesPlayed == 14)
        #expect(results.totalPoints == 14 * 24)
        #expect(results.roundsPlayed == 7)
        #expect(results.standings.count == 8)
        #expect(results.winners.first?.id == t.players[0].id, "le joueur le plus fort gagne")
        #expect(results.podium.flatMap { $0 }.count >= 3)
        #expect(results.podium.first?.allSatisfy { $0.rank == 1 } == true)
    }

    @Test("Podium avec ex aequo : une marche partagée")
    func tiedPodium() throws {
        var t = TestSupport.tournament(format: .americano, players: 4, rounds: 3)
        try t.start(now: Date())
        for match in t.orderedMatches {
            try t.validateScore(match.id, score: Score(12, 12), now: Date())
        }
        let results = TournamentResults(tournament: t)
        #expect(results.winners.count == 4)
        #expect(results.podium.count == 1)
    }

    @Test("Un tournoi joué survit à la sauvegarde")
    func persistence() throws {
        var t = TestSupport.tournament(format: .mexicano, players: 6, rounds: 3)
        try t.start(now: Date())
        try Self.playAll(&t)
        try t.generateNextRound(now: Date())
        try Self.playAll(&t)
        try t.correctScore(t.rounds[0].matches[0].id, score: Score(20, 4), now: Date())
        let restored = try TournamentCodec.decode(TournamentCodec.encode(t))
        #expect(restored == t)
        #expect(restored.standings == t.standings)
    }
}
