import PadelCore
import SwiftUI

/// État du sélecteur de règle de score : type de règle, nombre de points prédéfini ou personnalisé.
struct ScoringSelection: Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case fixedTotal
        case raceTo
        case free

        var id: Self { self }
    }

    /// `nil` = points personnalisés.
    static let pointsPresets: [Int?] = ScoringRule.presetPoints.map { Optional($0) } + [nil]

    var kind: Kind = .fixedTotal
    var preset: Int? = 24
    var customPoints = 20

    init() {}

    init(rule: ScoringRule) {
        switch rule {
        case .fixedTotal(let points):
            kind = .fixedTotal
            setPoints(points)
        case .raceTo(let points):
            kind = .raceTo
            setPoints(points)
        case .free:
            kind = .free
        }
    }

    var rule: ScoringRule {
        let points = preset ?? customPoints
        switch kind {
        case .fixedTotal: return .fixedTotal(points: points)
        case .raceTo: return .raceTo(points: points)
        case .free: return .free
        }
    }

    private mutating func setPoints(_ points: Int) {
        if ScoringRule.presetPoints.contains(points) {
            preset = points
        } else {
            preset = nil
            customPoints = points
        }
    }
}

/// Section de formulaire « Points par match ».
struct ScoringSection: View {
    @Binding var selection: ScoringSelection

    var body: some View {
        Section {
            if selection.kind != .free {
                Picker("Points par match", selection: $selection.preset) {
                    ForEach(ScoringSelection.pointsPresets, id: \.self) { preset in
                        Text(preset.map { "\($0)" } ?? String(localized: "Perso")).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                if selection.preset == nil {
                    Stepper(value: $selection.customPoints, in: ScoringRule.pointsRange) {
                        LabeledContent("Points personnalisés", value: "\(selection.customPoints)")
                    }
                }
            }

            Picker("Règle de score", selection: $selection.kind) {
                Text("Total fixe").tag(ScoringSelection.Kind.fixedTotal)
                Text("Premier à").tag(ScoringSelection.Kind.raceTo)
                Text("Libre (au temps)").tag(ScoringSelection.Kind.free)
            }
        } header: {
            Text("Points par match")
        } footer: {
            Text(selection.rule.explanation)
        }
    }
}

extension ScoringRule {
    var explanation: String {
        switch self {
        case .fixedTotal(let points):
            String(localized: "Les deux scores totalisent \(points) points (ex. \(points / 2 + 3)–\(points / 2 - 3)). Chaque joueur reçoit les points de son équipe.")
        case .raceTo(let points):
            String(localized: "La première équipe à \(points) points gagne. Chaque joueur reçoit les points de son équipe.")
        case .free:
            String(localized: "Pour les matchs au temps : saisissez les points marqués par chaque équipe à la fin.")
        }
    }
}
