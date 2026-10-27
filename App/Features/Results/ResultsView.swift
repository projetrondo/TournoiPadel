import PadelCore
import SwiftUI

/// Récapitulatif de fin de tournoi : podium, chiffres clés, classement final, partage.
struct ResultsView: View {
    let tournament: Tournament

    @Environment(\.displayScale) private var displayScale
    @State private var shareImage: Image?

    var body: some View {
        let results = TournamentResults(tournament: tournament)
        VStack(alignment: .leading, spacing: 16) {
            Text("Podium final")
                .eagleSectionTitle()
            PodiumView(tournament: tournament, podium: results.podium)

            HStack(spacing: 10) {
                keyFigure("\(results.matchesPlayed)", label: results.matchesPlayed <= 1 ? String(localized: "match") : String(localized: "matchs"))
                keyFigure("\(results.roundsPlayed)", label: results.roundsPlayed <= 1 ? String(localized: "tour") : String(localized: "tours"))
                keyFigure("\(results.totalPoints)", label: String(localized: "points joués"))
            }

            CompromiseNotice(compromises: results.statistics.compromises.filter {
                if case .unequalMatches = $0 { return true }
                return false
            })

            shareButtons(results)

            StandingsView(tournament: tournament)
        }
        .task(id: tournament.revision) {
            renderShareImage(results)
        }
    }

    private func keyFigure(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.display(.title, weight: .black).monospacedDigit())
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func shareButtons(_ results: TournamentResults) -> some View {
        let text = shareText(results)
        VStack(spacing: 10) {
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    message: Text(text),
                    preview: SharePreview(tournament.name, image: shareImage)
                ) {
                    Label("Partager les résultats", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            ShareLink(item: text) {
                Label("Partager en texte", systemImage: "text.bubble")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func renderShareImage(_ results: TournamentResults) {
        let renderer = ImageRenderer(content: ResultsShareCard(tournament: tournament, results: results))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }

    /// Résumé texte pour WhatsApp, iMessage, etc. (aucune API tierce : feuille de partage iOS).
    private func shareText(_ results: TournamentResults) -> String {
        let medals = ["🦅", "🥈", "🥉"]
        var lines = ["EAGLE · \(tournament.name) — \(tournament.format.title)", ""]
        let eagles = results.winners.compactMap { tournament.player($0.id)?.name }
        if !eagles.isEmpty {
            lines.append(String(localized: "L'Aigle : \(eagles.formatted(.list(type: .and)))"))
            lines.append("")
        }
        for row in results.standings {
            let prefix = row.rank <= 3 ? medals[row.rank - 1] : "\(row.rank)."
            let name = tournament.player(row.id)?.name ?? "?"
            lines.append(String(localized: "\(prefix) \(name) — \(row.stats.pointsFor) pts (\(row.stats.pointDifference.signedText)), \(row.stats.wins) V"))
        }
        lines.append("")
        lines.append(String(localized: "\(results.matchesPlayed) matchs · \(results.totalPoints) points joués"))
        lines.append(String(localized: "EAGLE — Own the court."))
        return lines.joined(separator: "\n")
    }
}

/// Podium à trois marches : l'Aigle au sommet (ailes dorées), puis argent et bronze.
/// Les ex aequo partagent une marche ; mêmes données que le classement.
struct PodiumView: View {
    let tournament: Tournament
    let podium: [[StandingRow]]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Ordre visuel classique : 2ᵉ, 1ᵉʳ, 3ᵉ.
            ForEach([1, 0, 2], id: \.self) { index in
                if index < podium.count {
                    step(podium[index], height: [118, 84, 64][index])
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func step(_ rows: [StandingRow], height: CGFloat) -> some View {
        let rank = rows.first?.rank ?? 1
        let tier = RankTier(rank: rank)
        let isEagle = tier == .eagle
        return VStack(spacing: 6) {
            ZStack {
                if isEagle {
                    EagleWings()
                        .fill(Theme.goldGradient)
                        .frame(width: 190, height: 58)
                        .opacity(0.85)
                        .shadow(color: Theme.gold.opacity(0.5), radius: 12)
                        .offset(y: -6)
                        .accessibilityHidden(true)
                }
                HStack(spacing: -12) {
                    ForEach(rows.prefix(2)) { row in
                        PlayerAvatar(name: tournament.player(row.id)?.name ?? "?", tier: tier, size: isEagle ? 70 : 54)
                    }
                }
            }
            .overlay(alignment: .top) {
                if isEagle {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.goldGradient)
                        .shadow(color: Theme.gold.opacity(0.6), radius: 6)
                        .offset(y: -22)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, isEagle ? 22 : 0)

            if isEagle {
                Text(rows.count > 1 ? "Aigles" : "L'Aigle")
                    .font(.caption2.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.gold)
            }
            ForEach(rows) { row in
                Text(tournament.player(row.id)?.name ?? "?")
                    .font(Theme.display(isEagle ? .title3 : .headline, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let first = rows.first {
                VStack(spacing: 0) {
                    Text("\(first.stats.pointsFor) pts")
                        .font(Theme.display(.subheadline, weight: .black).monospacedDigit())
                        .foregroundStyle(isEagle ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(tier.color))
                    Text(verbatim: "\(first.stats.wins) V – \(first.stats.losses) D")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            pedestal(rank: rank, tier: tier, height: height)
        }
        .frame(maxWidth: .infinity)
    }

    /// Socle en verre sombre, arête lumineuse à la couleur du rang, grand numéro.
    private func pedestal(rank: Int, tier: RankTier, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [tier.color.opacity(0.30), Theme.graphite, Theme.carbon], startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(tier == .eagle ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(tier.color))
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                    .shadow(color: tier.color.opacity(0.9), radius: 8)
            }
            .overlay(shape.strokeBorder(tier.color.opacity(0.35), lineWidth: 1))
            .overlay {
                Text("\(rank)")
                    .font(.system(size: tier == .eagle ? 48 : 38, weight: .black).width(.condensed))
                    .foregroundStyle(tier == .eagle ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(tier.color))
                    .shadow(color: tier.color.opacity(0.5), radius: 8)
            }
            .shadow(color: tier.color.opacity(tier == .eagle ? 0.35 : 0.15), radius: 14, y: -2)
    }
}

/// Visuel partagé en image (format portrait, lisible dans une conversation).
struct ResultsShareCard: View {
    let tournament: Tournament
    let results: TournamentResults

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                EagleEmblem().filled(Theme.goldGradient).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "EAGLE")
                        .font(.system(size: 26, weight: .black).width(.compressed))
                        .tracking(2)
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: "OWN THE COURT.")
                        .font(.system(size: 10, weight: .heavy).width(.condensed))
                        .tracking(2)
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.system(.title2, weight: .black).width(.condensed))
                    .foregroundStyle(Theme.ink)
                Text("\(tournament.format.title) · \(results.matchesPlayed) matchs")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(spacing: 6) {
                ForEach(results.standings.prefix(10)) { row in
                    let tier = RankTier(rank: row.rank)
                    HStack {
                        RankMedal(rank: row.rank, isTied: row.isTied, tier: tier, size: 26)
                            .frame(width: 34, alignment: .leading)
                        Text(tournament.player(row.id)?.name ?? "?")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if tier == .eagle {
                            Text("L'Aigle")
                                .font(.caption2.weight(.heavy))
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.gold)
                        }
                        Spacer()
                        Text("\(row.stats.pointsFor) pts")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
                        Text(row.stats.pointDifference.signedText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tier == .eagle ? Theme.gold.opacity(0.14) : Theme.graphite)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(tier == .eagle ? Theme.gold.opacity(0.8) : Theme.stroke, lineWidth: 1)
                    )
                }
                if results.standings.count > 10 {
                    Text("+ \(results.standings.count - 10) autres joueurs")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(24)
        .frame(width: 390)
        .background(Theme.carbon)
        .environment(\.colorScheme, .dark)
    }

}
