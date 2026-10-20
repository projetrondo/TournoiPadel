import Testing
@testable import PadelCore

@Suite("Règles de score")
struct ScoringRuleTests {
    @Test("Total fixe : la somme doit valoir le nombre de points")
    func fixedTotal() {
        let rule = ScoringRule.fixedTotal(points: 24)
        #expect(rule.validate(Score(15, 9)) == .valid)
        #expect(rule.validate(Score(24, 0)) == .valid)
        #expect(rule.validate(Score(12, 12)) == .valid)
        #expect(rule.validate(Score(15, 8)) == .invalid(.totalMustEqual(24)))
        #expect(rule.validate(Score(25, -1)) == .invalid(.negative))
    }

    @Test("Total fixe : le score adverse se déduit")
    func complement() {
        let rule = ScoringRule.fixedTotal(points: 24)
        #expect(rule.complement(of: 15) == 9)
        #expect(rule.complement(of: 0) == 24)
        #expect(rule.complement(of: 25) == nil)
        #expect(ScoringRule.free.complement(of: 3) == nil)
    }

    @Test("Premier à N : le gagnant atteint N, pas d'égalité")
    func raceTo() {
        let rule = ScoringRule.raceTo(points: 16)
        #expect(rule.validate(Score(16, 10)) == .valid)
        #expect(rule.validate(Score(3, 16)) == .valid)
        #expect(rule.validate(Score(15, 10)) == .invalid(.winnerMustReach(16)))
        #expect(rule.validate(Score(17, 10)) == .invalid(.winnerMustReach(16)))
        #expect(rule.validate(Score(16, 16)) == .invalid(.noDrawAllowed))
    }

    @Test("Score libre : au moins un point, plafond de cohérence")
    func free() {
        let rule = ScoringRule.free
        #expect(rule.validate(Score(7, 5)) == .valid)
        #expect(rule.validate(Score(6, 6)) == .valid)
        #expect(rule.validate(Score(0, 0)) == .invalid(.empty))
        #expect(rule.validate(Score(100, 2)) == .invalid(.tooHigh(99)))
    }

    @Test("Issue d'un match")
    func outcome() {
        #expect(Score(15, 9).outcome == .teamAWins)
        #expect(Score(9, 15).outcome == .teamBWins)
        #expect(Score(12, 12).outcome == .draw)
    }
}
