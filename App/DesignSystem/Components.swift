import PadelCore
import SwiftUI

/// Bouton plein, pleine largeur, pour l'action principale d'un écran.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(isEnabled ? Theme.buttonFill : Color.gray.opacity(0.4))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Bouton secondaire, teinté, pleine largeur.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .foregroundStyle(Theme.green)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.green.opacity(0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Carte arrondie sur fond secondaire.
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

/// Logo de l'application : pastille verte avec balle, et nom.
struct LogoView: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.green, Theme.deepGreen], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "figure.tennis")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                Circle()
                    .fill(Theme.ball)
                    .frame(width: 11, height: 11)
                    .offset(x: 15, y: -15)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Padel Buddy")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                Text("Tournois entre amis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Petite étiquette colorée (format, statut).
struct BadgeView: View {
    let text: String
    var color: Color = Theme.green

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

extension TournamentFormat {
    var title: String {
        switch self {
        case .americano: String(localized: "Americano")
        case .mexicano: String(localized: "Mexicano")
        }
    }

    var explanation: String {
        switch self {
        case .americano:
            String(localized: "Les partenaires changent à chaque tour. Chaque joueur marque les points de son équipe. Tout le programme est connu dès le départ.")
        case .mexicano:
            String(localized: "Après chaque tour, les joueurs proches au classement sont regroupés pour des matchs serrés. Les partenaires changent autant que possible.")
        }
    }
}

extension Tournament {
    var statusText: String {
        switch status {
        case .draft:
            String(localized: "Prêt à lancer")
        case .inProgress:
            settings.isOpenEnded
                ? String(localized: "Tour \(currentRound?.index ?? rounds.count)")
                : String(localized: "Tour \(currentRound?.index ?? rounds.count) sur \(settings.plannedRounds)")
        case .finished:
            String(localized: "Terminé")
        }
    }

    var statusColor: Color {
        switch status {
        case .draft: Theme.warning
        case .inProgress: Theme.green
        case .finished: .secondary
        }
    }
}

extension ScoringRule {
    var summary: String {
        switch self {
        case .fixedTotal(let points): String(localized: "\(points) points au total")
        case .raceTo(let points): String(localized: "Premier à \(points) points")
        case .free: String(localized: "Score libre (au temps)")
        }
    }
}
