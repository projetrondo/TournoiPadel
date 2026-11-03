import PadelCore
import SwiftUI

/// Bouton plein, pleine largeur, pour l'action principale d'un écran (vert électrique).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(.headline, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.secondaryText)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(isEnabled ? Theme.accent : Color.white.opacity(0.08))
            )
            .shadow(color: isEnabled ? Theme.accent.opacity(configuration.isPressed ? 0.15 : 0.35) : .clear, radius: 12, y: 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Bouton secondaire : contour vert sur fond sombre.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(.headline, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Carte sombre à bordure discrète.
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }

    /// Titre de section en capitales condensées.
    func eagleSectionTitle() -> some View {
        font(Theme.display(.title3, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Emblème EAGLE : tête d'aigle angulaire de profil, vectorielle (mêmes points que
/// docs/brand/eagle-emblem.svg). Le regard et la commissure du bec sont évidés.
struct EagleEmblem: Shape {
    private static let headPoints: [(CGFloat, CGFloat)] = [
        (4, 50), (18, 32), (36, 18), (56, 11), (74, 12), (87, 19), (96, 31), (100, 45), (97, 60), (91, 52),
        (84, 49), (79, 57), (69, 59), (63, 71), (56, 95), (45, 85), (42, 73), (30, 83), (31, 67), (15, 73), (22, 57),
    ]
    private static let eyePoints: [(CGFloat, CGFloat)] = [(58, 29), (80, 35), (63, 39)]
    private static let mouthPoints: [(CGFloat, CGFloat)] = [(79, 44), (95, 40), (95, 42.5), (81, 47)]

    private static let head = headPoints.map { CGPoint(x: $0.0, y: $0.1) }
    private static let eye = eyePoints.map { CGPoint(x: $0.0, y: $0.1) }
    private static let mouth = mouthPoints.map { CGPoint(x: $0.0, y: $0.1) }

    func path(in rect: CGRect) -> Path {
        // Repère 104 × 104 (dessin 100 × 95 centré), mis à l'échelle sans déformation.
        let scale = min(rect.width, rect.height) / 104
        let origin = CGPoint(
            x: rect.midX - 52 * scale,
            y: rect.midY - 52 * scale + 4 * scale
        )
        func polygon(_ points: [CGPoint]) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
            path.closeSubpath()
            return path
        }
        var path = polygon(Self.head)
        path.addPath(polygon(Self.eye))
        path.addPath(polygon(Self.mouth))
        return path
    }
}

extension EagleEmblem {
    /// Emblème rempli avec les évidements (règle pair-impair).
    func filled<S: ShapeStyle>(_ style: S) -> some View {
        fill(style, style: FillStyle(eoFill: true))
    }
}

/// Petite étiquette colorée (format, statut).
struct BadgeView: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

extension RankTier {
    var color: Color {
        switch self {
        case .eagle: Theme.gold
        case .silver: Theme.silver
        case .bronze: Theme.bronze
        case .standard: Theme.secondaryText
        }
    }
}

/// Médaille de position : emblème doré pour l'Aigle, disque argent / bronze, numéro sinon.
struct RankMedal: View {
    let rank: Int
    let isTied: Bool
    let tier: RankTier
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            switch tier {
            case .eagle:
                Circle().fill(Theme.gold.opacity(0.16))
                Circle().strokeBorder(Theme.gold, lineWidth: 1.5)
                EagleEmblem().filled(Theme.gold).padding(size * 0.17)
            case .silver, .bronze:
                Circle().fill(tier.color)
                Text(rankText)
                    .font(.system(size: size * 0.42, weight: .black).width(.condensed))
                    .foregroundStyle(Theme.carbon)
            case .standard:
                Text(rankText)
                    .font(.system(size: size * 0.42, weight: .heavy).width(.condensed).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var rankText: String { isTied ? "\(rank)=" : "\(rank)" }
}

extension TournamentFormat {
    var title: String {
        switch self {
        case .americano: String(localized: "Americano", bundle: .appLanguage)
        case .mexicano: String(localized: "Mexicano", bundle: .appLanguage)
        }
    }

    var explanation: String {
        switch self {
        case .americano:
            String(localized: "Les partenaires changent à chaque tour. Chaque joueur marque les points de son équipe. Tout le programme est connu dès le départ.", bundle: .appLanguage)
        case .mexicano:
            String(localized: "Après chaque tour, les joueurs proches au classement sont regroupés pour des matchs serrés. Les partenaires changent autant que possible.", bundle: .appLanguage)
        }
    }
}

extension Tournament {
    var statusText: String {
        switch status {
        case .draft:
            String(localized: "Prêt à lancer", bundle: .appLanguage)
        case .inProgress:
            settings.isOpenEnded
                ? String(localized: "Tour \(currentRound?.index ?? rounds.count)", bundle: .appLanguage)
                : String(localized: "Tour \(currentRound?.index ?? rounds.count) sur \(settings.plannedRounds)", bundle: .appLanguage)
        case .finished:
            String(localized: "Terminé", bundle: .appLanguage)
        }
    }

    var statusColor: Color {
        switch status {
        case .draft: Theme.warning
        case .inProgress: Theme.accent
        case .finished: Theme.secondaryText
        }
    }
}

extension ScoringRule {
    var summary: String {
        switch self {
        case .fixedTotal(let points): String(localized: "\(points) points au total", bundle: .appLanguage)
        case .raceTo(let points): String(localized: "Premier à \(points) points", bundle: .appLanguage)
        case .free: String(localized: "Score libre (au temps)", bundle: .appLanguage)
        }
    }
}
