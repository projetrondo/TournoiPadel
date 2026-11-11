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
                        Text(preset.map { "\($0)" } ?? String(localized: "Perso", bundle: .appLanguage)).tag(preset)
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
            String(localized: "Les deux scores totalisent \(points) points (ex. \(points / 2 + 3)–\(points / 2 - 3)). Chaque joueur reçoit les points de son équipe.", bundle: .appLanguage)
        case .raceTo(let points):
            String(localized: "La première équipe à \(points) points gagne. Chaque joueur reçoit les points de son équipe.", bundle: .appLanguage)
        case .free:
            String(localized: "Pour les matchs au temps : saisissez les points marqués par chaque équipe à la fin.", bundle: .appLanguage)
        }
    }
}

/// Bonus de victoire : points ajoutés au classement pour chaque match gagné.
struct WinBonusSection: View {
    @Binding var bonus: Int

    var body: some View {
        Section {
            Picker("Bonus de victoire", selection: $bonus) {
                ForEach(Array(TournamentSettings.winBonusRange), id: \.self) { value in
                    if value == 0 {
                        Text("Aucun").tag(value)
                    } else {
                        Text(verbatim: "+\(value)").tag(value)
                    }
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Bonus de victoire")
        } footer: {
            if bonus == 0 {
                Text("Le classement compte seulement les points marqués.")
            } else {
                Text("Chaque victoire rapporte \(bonus) point(s) de plus au classement. Les scores des matchs ne changent pas ; en Mexicano, le bonus compte aussi pour composer les tours.")
            }
        }
    }
}

/// Mexicano : bonus de terrain. À partir du tour choisi, chaque joueur reçoit des points selon
/// son terrain : sur N terrains, le terrain 1 rapporte N points, le dernier 1 point.
struct CourtBonusSection: View {
    @Binding var startRound: Int?
    /// Terrains réellement utilisés (selon le nombre de joueurs).
    let courts: Int

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { startRound != nil },
                set: { startRound = $0 ? (startRound ?? 1) : nil }
            )) {
                Text("Bonus de terrain")
            }
            .tint(Theme.accent)
            if let start = startRound {
                Picker("À partir du tour", selection: Binding(get: { start }, set: { startRound = $0 })) {
                    ForEach(Array(TournamentSettings.courtBonusStartRange), id: \.self) { round in
                        Text(verbatim: "\(round)").tag(round)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("À partir du tour")
            }
        } header: {
            Text("Bonus de terrain")
        } footer: {
            if startRound != nil {
                Text(scale)
            } else {
                Text("Chaque joueur gagne des points selon le terrain où il joue : plus le terrain est haut, plus il rapporte.")
            }
        }
    }

    /// « Tour 2 et suivants : terrain 1 +4 pts, terrain 2 +3 pts… »
    private var scale: String {
        let count = max(1, courts)
        let points = (1...count).map { court in
            String(localized: "terrain \(court) : +\(count - court + 1)", bundle: .appLanguage)
        }.formatted(.list(type: .and).locale(.appLanguage))
        let start = startRound ?? 1
        return String(localized: "À partir du tour \(start), chaque joueur reçoit, qu'il gagne ou perde : \(points) points. Le bonus compte au classement et pour composer les tours suivants.", bundle: .appLanguage)
    }
}
