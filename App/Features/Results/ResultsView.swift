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

/// Podium à trois marches : l'Aigle au sommet (or), puis argent et bronze.
/// Les ex aequo partagent une marche ; mêmes données que le classement.
struct PodiumView: View {
    let tournament: Tournament
    let podium: [[StandingRow]]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Ordre visuel classique : 2ᵉ, 1ᵉʳ, 3ᵉ.
            ForEach([1, 0, 2], id: \.self) { index in
                if index < podium.count {
                    step(podium[index], height: [132, 92, 68][index])
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ rows: [StandingRow], height: CGFloat) -> some View {
        let rank = rows.first?.rank ?? 1
        let tier = RankTier(rank: rank)
        return VStack(spacing: 6) {
            if tier == .eagle {
                EagleEmblem()
                    .filled(Theme.gold)
                    .frame(width: 54, height: 54)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 14)
                Text(rows.count > 1 ? "Aigles" : "L'Aigle")
                    .font(.caption2.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.gold)
            } else {
                RankMedal(rank: rank, isTied: rows.count > 1, tier: tier, size: 36)
            }
            ForEach(rows) { row in
                Text(tournament.player(row.id)?.name ?? "?")
                    .font(Theme.display(tier == .eagle ? .title3 : .headline, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let first = rows.first {
                Text("\(first.stats.pointsFor) pts")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(tier.color)
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tier.color.opacity(0.9), tier.color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(height: height)
                .overlay(alignment: .top) {
                    Text("\(rank)")
                        .font(.system(size: 30, weight: .black).width(.condensed))
                        .foregroundStyle(Theme.carbon)
                        .padding(.top, 8)
                }
                .shadow(color: tier == .eagle ? Theme.gold.opacity(0.3) : .clear, radius: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Visuel partagé en image (format portrait, lisible dans une conversation).
struct ResultsShareCard: View {
    let tournament: Tournament
    let results: TournamentResults

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                EagleEmblem().filled(Theme.gold).frame(width: 40, height: 40)
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
