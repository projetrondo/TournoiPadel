import PadelCore
import SwiftUI

/// Emblème doré « premium » : dégradé or et halo lumineux.
struct GoldEagle: View {
    var size: CGFloat
    var glow: Double = 0.45

    var body: some View {
        EagleEmblem()
            .filled(Theme.goldGradient)
            .frame(width: size, height: size)
            .shadow(color: Theme.gold.opacity(glow), radius: size * 0.22)
            .accessibilityHidden(true)
    }
}

/// En-tête de marque centré : emblème et « EAGLE » en italique, signature dessous.
struct EagleWordmark: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                GoldEagle(size: 38, glow: 0.4)
                Text(verbatim: "EAGLE")
                    .font(.system(size: 36, weight: .black).width(.compressed).italic())
                    .tracking(3)
                    .foregroundStyle(Theme.goldGradient)
                    .shadow(color: Theme.gold.opacity(0.35), radius: 8)
            }
            Text(verbatim: "OWN THE COURT.")
                .font(.system(.caption2, weight: .heavy).width(.condensed))
                .tracking(3)
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EAGLE, Own the court")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Ailes d'aigle stylisées (déployées de part et d'autre du centre), derrière le n°1 du podium.
struct EagleWings: Shape {
    /// Aile droite dans un repère 100 × 60 : x = 0 au centre, plumes dentelées en bas.
    private static let wing: [(CGFloat, CGFloat)] = [
        (6, 34), (22, 16), (44, 7), (70, 2), (100, 0),
        (90, 12), (96, 14), (82, 24), (88, 27), (72, 34), (77, 38),
        (60, 42), (64, 47), (46, 48), (48, 54), (30, 50), (28, 56), (12, 46),
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 200
        let sy = rect.height / 60
        var path = Path()
        for side: CGFloat in [1, -1] {
            let points = Self.wing.map { CGPoint(x: rect.midX + side * $0.0 * sx, y: rect.minY + $0.1 * sy) }
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }
}

/// Avatar sans photo : initiales du joueur dans un anneau à la couleur de son rang.
struct PlayerAvatar: View {
    let name: String
    var tier: RankTier = .standard
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [ringColor.opacity(0.28), Theme.graphite],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: size
                ))
            Text(Self.initials(of: name))
                .font(.system(size: size * 0.38, weight: .heavy).width(.condensed))
                .foregroundStyle(tier == .standard ? Theme.ink : ringColor)
                .minimumScaleFactor(0.5)
            Circle()
                .strokeBorder(ringStyle, lineWidth: max(1.5, size * 0.05))
        }
        .frame(width: size, height: size)
        .shadow(color: tier == .eagle ? Theme.gold.opacity(0.45) : .clear, radius: size * 0.2)
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        tier == .standard ? Theme.secondaryText : tier.color
    }

    private var ringStyle: AnyShapeStyle {
        switch tier {
        case .eagle: AnyShapeStyle(Theme.goldGradient)
        case .standard: AnyShapeStyle(Color.white.opacity(0.18))
        default: AnyShapeStyle(tier.color)
        }
    }

    /// « Léa Martin » → « LM », « Max » → « MA ».
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return String([first, second]).uppercased()
        }
        return String(name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
    }
}

/// Couronne et numéro 1, au-dessus du nom de l'Aigle.
struct CrownRank: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .bold))
            Text(verbatim: "1")
                .font(.system(size: 30, weight: .black).width(.condensed))
        }
        .foregroundStyle(Theme.goldGradient)
        .shadow(color: Theme.gold.opacity(0.5), radius: 6)
        .accessibilityHidden(true)
    }
}

/// Tuile de statistique (valeur forte, libellé en capitales).
struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String
    var color: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(Theme.display(.title, weight: .black).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.10), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) : \(value)")
    }
}

/// Barre d'onglets en pilules à bordure dorée (remplace le contrôle segmenté système).
struct PillTabBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(Theme.display(.subheadline, weight: .heavy))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.secondaryText))
                        .background(Capsule().fill(isSelected ? Theme.gold.opacity(0.14) : Theme.card))
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.stroke),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                        )
                        .shadow(color: isSelected ? Theme.gold.opacity(0.3) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

extension View {
    /// Carte premium : fond sombre, bordure dégradée or et halo doré.
    func goldGlowCard(cornerRadius: CGFloat = Theme.cornerRadius + 4) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.gold.opacity(0.18), Theme.graphite, Theme.carbon],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.goldGradient, lineWidth: 1.5)
        )
        .shadow(color: Theme.gold.opacity(0.25), radius: 18)
    }
}

extension PlayerStats {
    /// « 75 % » ou « – » sans match joué.
    var winRateText: String {
        winRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
    }

    /// « 3 V · 1 N · 2 D · 50 % » (nuls affichés seulement s'il y en a).
    var recordText: String {
        var parts = ["\(wins) V"]
        if draws > 0 { parts.append("\(draws) N") }
        parts.append("\(losses) D")
        parts.append(winRateText)
        return parts.joined(separator: " · ")
    }
}
