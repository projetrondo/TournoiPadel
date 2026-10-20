import PadelCore
import SwiftUI

/// Classement individuel, recalculé à chaque affichage à partir des matchs terminés.
struct StandingsView: View {
    let tournament: Tournament

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPlayer: PlayerSelection?
    @State private var isShowingRules = false

    struct PlayerSelection: Identifiable {
        let id: Player.ID
    }

    var body: some View {
        let rows = tournament.standings
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Classement")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    isShowingRules = true
                } label: {
                    Label("Règles de départage", systemImage: "questionmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
            }

            if rows.allSatisfy({ $0.stats.played == 0 }) {
                Text("Le classement apparaîtra dès le premier score validé.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            }

            VStack(spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    headerRow
                }
                ForEach(rows) { row in
                    Divider()
                    Button {
                        selectedPlayer = PlayerSelection(id: row.id)
                    } label: {
                        StandingRowView(row: row, name: tournament.player(row.id)?.name ?? "?")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Voir le détail du joueur")
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
        }
        .sheet(item: $selectedPlayer) { selection in
            PlayerDetailView(tournament: tournament, playerID: selection.id)
        }
        .sheet(isPresented: $isShowingRules) {
            RankingRulesView()
                .presentationDetents([.medium])
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 30, alignment: .leading)
            Text("Joueur").frame(maxWidth: .infinity, alignment: .leading)
            Text("J").frame(width: 26)
            Text("V").frame(width: 26)
            Text("Diff").frame(width: 40)
            Text("Pts").frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

struct StandingRowView: View {
    let row: StandingRow
    let name: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedLayout
        } else {
            tableLayout
        }
    }

    /// Très grandes tailles de texte : une ligne par information plutôt que des colonnes.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(row.isTied ? "\(row.rank)=" : "\(row.rank)") \(name)")
                .font(.headline)
            Text("\(row.stats.pointsFor) points · \(row.stats.wins) victoires · \(row.stats.pointDifference.signedText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        String(localized: "\(row.rank)e, \(name), \(row.stats.pointsFor) points, \(row.stats.wins) victoires, différence \(row.stats.pointDifference.signedText), \(row.stats.played) matchs")
    }

    private var tableLayout: some View {
        HStack(spacing: 8) {
            Text(row.isTied ? "\(row.rank)=" : "\(row.rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(row.rank <= 3 ? Theme.green : .primary)
                .frame(width: 30, alignment: .leading)
            Text(name)
                .font(.body.weight(row.rank == 1 ? .bold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.stats.played)").frame(width: 26)
            Text("\(row.stats.wins)").frame(width: 26)
            Text(row.stats.pointDifference.signedText).frame(width: 40)
            Text("\(row.stats.pointsFor)")
                .font(.headline.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Détail des statistiques et des matchs d'un joueur.
struct PlayerDetailView: View {
    let tournament: Tournament
    let playerID: Player.ID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = Standings.stats(for: tournament)[playerID] ?? PlayerStats(playerID: playerID)
        let row = tournament.standings.first { $0.id == playerID }
        NavigationStack {
            List {
                Section {
                    statRow("Position", value: row.map { $0.isTied ? "\($0.rank)= " : "\($0.rank)" } ?? "–")
                    statRow("Matchs joués", value: "\(stats.played)")
                    statRow("Points marqués", value: "\(stats.pointsFor)")
                    statRow("Points encaissés", value: "\(stats.pointsAgainst)")
                    statRow("Différence", value: stats.pointDifference.signedText)
                    statRow("Victoires · nuls · défaites", value: "\(stats.wins) · \(stats.draws) · \(stats.losses)")
                    if let average = stats.averagePoints {
                        statRow("Points par match", value: average.formatted(.number.precision(.fractionLength(1))))
                    }
                    statRow("Pauses", value: "\(stats.rests)")
                }
                Section("Matchs") {
                    ForEach(matches, id: \.match.id) { entry in
                        matchRow(entry.round, entry.match)
                    }
                }
            }
            .navigationTitle(tournament.player(playerID)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var matches: [(round: Int, match: Match)] {
        tournament.rounds.flatMap { round in
            round.matches.filter { $0.players.contains(playerID) }.map { (round.index, $0) }
        }
    }

    private func statRow(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func matchRow(_ round: Int, _ match: Match) -> some View {
        let ownTeam = match.teamA.contains(playerID) ? match.teamA : match.teamB
        let otherTeam = match.teamA.contains(playerID) ? match.teamB : match.teamA
        let partner = ownTeam.players.first { $0 != playerID }.flatMap { tournament.player($0)?.name } ?? "?"
        let opponents = otherTeam.players.compactMap { tournament.player($0)?.name }.formatted(.list(type: .and))
        let own = match.score.map { match.teamA.contains(playerID) ? $0.teamA : $0.teamB }
        let other = match.score.map { match.teamA.contains(playerID) ? $0.teamB : $0.teamA }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tour \(round) · avec \(partner)")
                    .font(.subheadline.weight(.semibold))
                Text("contre \(opponents)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let own, let other, match.state == .completed {
                Text("\(own)–\(other)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(own > other ? Theme.green : own < other ? Theme.error : .secondary)
            } else {
                Text(match.state.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RankingRulesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Chaque joueur reçoit les points marqués par son équipe.", systemImage: "person.2.fill")
                } header: {
                    Text("Points individuels")
                }
                Section {
                    Text("1. Points marqués (total)")
                    Text("2. Victoires")
                    Text("3. Différence de points (marqués − encaissés)")
                    Text("4. Sinon ex aequo : même position, signalée par « = »")
                } header: {
                    Text("Ordre du classement")
                } footer: {
                    Text("Seuls les matchs validés comptent. Une correction de score met le classement à jour immédiatement.")
                }
            }
            .navigationTitle("Règles du classement")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension Int {
    /// « +5 », « 0 », « −3 ».
    var signedText: String {
        self > 0 ? "+\(self)" : "\(self)"
    }
}
