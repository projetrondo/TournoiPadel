import Foundation

/// Vérifie qu'un planning est jouable. Appelé après chaque génération : un planning invalide
/// n'est jamais enregistré.
public enum ScheduleValidator {
    public enum Violation: Error, Hashable, Sendable {
        case unknownPlayer(round: Int)
        /// Un joueur apparaît deux fois dans le même tour (deux matchs, ou match + pause).
        case playerTwiceInRound(round: Int)
        /// Un joueur inscrit n'apparaît ni dans un match ni en pause.
        case playerMissing(round: Int)
        case teamWithSamePlayer(round: Int)
        case invalidCourt(round: Int)
        case duplicateCourt(round: Int)
        case wrongMatchCount(round: Int)
        case wrongRoundNumbering
    }

    public static func validate(rounds: [Round], playerIDs: [Player.ID], activeCourts: Int) throws {
        for (offset, round) in rounds.enumerated() {
            guard round.index == offset + 1 else { throw Violation.wrongRoundNumbering }
            try validate(round: round, playerIDs: playerIDs, activeCourts: activeCourts)
        }
    }

    public static func validate(round: Round, playerIDs: [Player.ID], activeCourts: Int) throws {
        let index = round.index
        let known = Set(playerIDs)
        guard round.matches.count == activeCourts else { throw Violation.wrongMatchCount(round: index) }

        var seen = Set<Player.ID>()
        var courts = Set<Int>()
        for match in round.matches {
            guard match.teamA.first != match.teamA.second, match.teamB.first != match.teamB.second else {
                throw Violation.teamWithSamePlayer(round: index)
            }
            guard (1...activeCourts).contains(match.court) else { throw Violation.invalidCourt(round: index) }
            guard courts.insert(match.court).inserted else { throw Violation.duplicateCourt(round: index) }
            for player in match.players {
                guard known.contains(player) else { throw Violation.unknownPlayer(round: index) }
                guard seen.insert(player).inserted else { throw Violation.playerTwiceInRound(round: index) }
            }
        }
        for player in round.resting {
            guard known.contains(player) else { throw Violation.unknownPlayer(round: index) }
            guard seen.insert(player).inserted else { throw Violation.playerTwiceInRound(round: index) }
        }
        guard seen.count == known.count else { throw Violation.playerMissing(round: index) }
    }
}
