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
            PodiumView(tournament: tournament, podium: results.podium)

            if !results.winners.isEmpty {
                winnerBanner(results)
            }

            HStack(spacing: 10) {
                keyFigure("\(results.matchesPlayed)", label: String(localized: "matchs"))
                keyFigure("\(results.roundsPlayed)", label: String(localized: "tours"))
                keyFigure("\(results.totalPoints)", label: String(localized: "points joués"))
            }

            shareButtons(results)

            StandingsView(tournament: tournament)
        }
        .task(id: tournament.revision) {
            renderShareImage(results)
        }
    }

    private func winnerBanner(_ results: TournamentResults) -> some View {
        let names = results.winners.compactMap { tournament.player($0.id)?.name }.formatted(.list(type: .and))
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(results.winners.count > 1 ? "Meilleurs joueurs (ex aequo)" : "Meilleur joueur")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(names)
                    .font(.title3.weight(.bold))
            }
        } icon: {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(Theme.ball)
        }
        .cardStyle()
    }

    private func keyFigure(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.heavy).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.card)
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
        let medals = ["🥇", "🥈", "🥉"]
        var lines = ["🎾 \(tournament.name) — \(tournament.format.title)", ""]
        for row in results.standings {
            let prefix = row.rank <= 3 ? medals[row.rank - 1] : "\(row.rank)."
            let name = tournament.player(row.id)?.name ?? "?"
            lines.append(String(localized: "\(prefix) \(name) — \(row.stats.pointsFor) pts (\(row.stats.pointDifference.signedText)), \(row.stats.wins) V"))
        }
        lines.append("")
        lines.append(String(localized: "\(results.matchesPlayed) matchs · \(results.totalPoints) points joués"))
        lines.append(String(localized: "Organisé avec Padel Buddy"))
        return lines.joined(separator: "\n")
    }
}

/// Podium à trois marches ; les ex aequo partagent une marche.
struct PodiumView: View {
    let tournament: Tournament
    let podium: [[StandingRow]]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Ordre visuel classique : 2ᵉ, 1ᵉʳ, 3ᵉ.
            ForEach([1, 0, 2], id: \.self) { index in
                if index < podium.count {
                    step(podium[index], height: [120, 90, 70][index])
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ rows: [StandingRow], height: CGFloat) -> some View {
        let rank = rows.first?.rank ?? 1
        return VStack(spacing: 6) {
            Text(verbatim: ["🥇", "🥈", "🥉"][min(max(rank, 1), 3) - 1])
                .font(.largeTitle)
            ForEach(rows) { row in
                Text(tournament.player(row.id)?.name ?? "?")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let first = rows.first {
                Text("\(first.stats.pointsFor) pts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Theme.green, Theme.deepGreen], startPoint: .top, endPoint: .bottom))
                .frame(height: height)
                .overlay(alignment: .top) {
                    Text("\(rank)")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                }
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.name)
                        .font(.title.weight(.heavy))
                    Text("\(tournament.format.title) · \(results.matchesPlayed) matchs")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.ball)
            }
            VStack(spacing: 6) {
                ForEach(results.standings.prefix(10)) { row in
                    HStack {
                        Text(row.isTied ? "\(row.rank)=" : "\(row.rank)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 34, alignment: .leading)
                        Text(tournament.player(row.id)?.name ?? "?")
                            .font(.headline)
                        Spacer()
                        Text("\(row.stats.pointsFor) pts")
                            .font(.headline.monospacedDigit())
                        Text(row.stats.pointDifference.signedText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(row.rank == 1 ? 0.22 : 0.1)))
                }
                if results.standings.count > 10 {
                    Text("+ \(results.standings.count - 10) autres joueurs")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Text(verbatim: "Padel Buddy")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 390)
        .background(LinearGradient(colors: [Color(light: 0x1E9E5A, dark: 0x1E9E5A), Color(light: 0x0F5132, dark: 0x0F5132)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
