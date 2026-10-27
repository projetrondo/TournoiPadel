import PadelCore
import SwiftUI

/// Classement individuel, recalculé à chaque affichage à partir des matchs terminés.
/// Le numéro 1 est mis en scène comme « l'Aigle » ; les règles de calcul ne changent pas.
struct StandingsView: View {
    let tournament: Tournament

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPlayer: PlayerSelection?
    @State private var isShowingRules = false

    struct PlayerSelection: Identifiable {
        let id: Player.ID
    }

    var body: some View {
        let insights = EagleInsights(tournament: tournament)
        let challengers = insights.hasResults ? insights.standings.filter { $0.rank != 1 } : insights.standings
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Classement")
                    .eagleSectionTitle()
                Spacer()
                Button {
                    isShowingRules = true
                } label: {
                    Label("Règles de départage", systemImage: "questionmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            if insights.hasResults {
                ForEach(insights.eagles) { eagle in
                    Button {
                        selectedPlayer = PlayerSelection(id: eagle.id)
                    } label: {
                        EagleChampionCard(
                            row: eagle,
                            name: name(eagle.id),
                            isShared: insights.eagles.count > 1,
                            streak: insights.crownStreak[eagle.id] ?? 0,
                            hasHistory: !insights.movement.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Voir le profil du joueur")
                }
            } else {
                noEagleYet
            }

            if !challengers.isEmpty {
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        headerRow
                    }
                    ForEach(challengers) { row in
                        Divider().overlay(Theme.stroke)
                        Button {
                            selectedPlayer = PlayerSelection(id: row.id)
                        } label: {
                            StandingRowView(
                                row: row,
                                name: name(row.id),
                                tier: insights.tier(of: row),
                                movement: insights.movement[row.id],
                                pointsBehind: insights.pointsBehindEagle(row)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Voir le profil du joueur")
                    }
                }
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
            }
        }
        .sheet(item: $selectedPlayer) { selection in
            PlayerDetailView(tournament: tournament, playerID: selection.id)
        }
        .sheet(isPresented: $isShowingRules) {
            RankingRulesView()
                .presentationDetents([.medium])
        }
    }

    private func name(_ id: Player.ID) -> String {
        tournament.player(id)?.name ?? "?"
    }

    /// Aucun score validé : personne n'est encore l'Aigle.
    private var noEagleYet: some View {
        HStack(spacing: 14) {
            EagleEmblem()
                .stroke(Theme.gold.opacity(0.6), lineWidth: 1.5)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pas encore d'Aigle")
                    .font(Theme.display(.headline, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.gold)
                Text("Le premier score validé désigne l'Aigle. Gagnez des points pour prendre sa place.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .cardStyle()
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 34, alignment: .leading)
            Text("Joueur").frame(maxWidth: .infinity, alignment: .leading)
            Text("J").frame(width: 26)
            Text("V").frame(width: 26)
            Text("Diff").frame(width: 40)
            Text("Pts").frame(width: 44, alignment: .trailing)
        }
        .font(.caption.weight(.bold))
        .textCase(.uppercase)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

/// Carte du champion : l'Aigle, numéro 1 du classement réel.
struct EagleChampionCard: View {
    let row: StandingRow
    let name: String
    /// Plusieurs joueurs à égalité parfaite en tête.
    let isShared: Bool
    /// Tours consécutifs terminés en tête.
    let streak: Int
    /// Au moins deux tours joués (une évolution est mesurable).
    let hasHistory: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            EagleEmblem()
                .filled(Theme.gold)
                .frame(width: 64, height: 64)
                .shadow(color: Theme.gold.opacity(0.45), radius: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(isShared ? "Aigles ex aequo" : "L'Aigle · Champion actuel")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.gold)
                Text(name)
                    .font(Theme.display(.title, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "J \(row.stats.played) · V \(row.stats.wins) · N \(row.stats.draws) · D \(row.stats.losses) · \(row.stats.pointDifference.signedText)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                if let crownText {
                    Label(crownText, systemImage: "crown.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                Text("\(row.stats.pointsFor)")
                    .font(.system(size: 40, weight: .black).width(.condensed).monospacedDigit())
                    .foregroundStyle(Theme.gold)
                Text("pts")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.gold.opacity(0.16), Theme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous)
                .strokeBorder(Theme.gold.opacity(0.85), lineWidth: 1.5)
        )
        .shadow(color: Theme.gold.opacity(0.18), radius: 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// « Defend your crown » : depuis combien de tours l'Aigle tient la première place.
    private var crownText: String? {
        guard hasHistory else { return nil }
        if streak >= 2 {
            return String(localized: "Defend your crown · en tête depuis \(streak) tours")
        }
        return String(localized: "Nouvel Aigle")
    }

    private var accessibilityText: String {
        let title = isShared ? String(localized: "Aigle ex aequo") : String(localized: "L'Aigle, champion actuel")
        return "\(title), \(name), \(FrenchPlural.count(row.stats.pointsFor, "point", "points")), \(FrenchPlural.count(row.stats.wins, "victoire", "victoires")), différence \(row.stats.pointDifference.signedText), \(FrenchPlural.count(row.stats.played, "match", "matchs"))"
    }
}

struct StandingRowView: View {
    let row: StandingRow
    let name: String
    var tier: RankTier = .standard
    /// Places gagnées (positif) ou perdues depuis le tour précédent.
    var movement: Int?
    /// Retard sur l'Aigle, en points.
    var pointsBehind: Int?

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
                .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
            Text(verbatim: "\(FrenchPlural.count(row.stats.pointsFor, "point", "points")) · \(FrenchPlural.count(row.stats.wins, "victoire", "victoires")) · \(row.stats.pointDifference.signedText)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if let huntText {
                Text(huntText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let rank = row.rank == 1 ? "1er" : "\(row.rank)e"
        var parts = [rank, name, FrenchPlural.count(row.stats.pointsFor, "point", "points"),
                     FrenchPlural.count(row.stats.wins, "victoire", "victoires"),
                     "différence \(row.stats.pointDifference.signedText)",
                     FrenchPlural.count(row.stats.played, "match", "matchs")]
        if let movementText { parts.append(movementText) }
        if let huntText { parts.append(huntText) }
        return parts.joined(separator: ", ")
    }

    /// « Hunt the Eagle » : retard sur le numéro 1.
    private var huntText: String? {
        guard let pointsBehind else { return nil }
        if pointsBehind <= 0 { return String(localized: "À égalité de points avec l'Aigle") }
        return String(localized: "À \(FrenchPlural.count(pointsBehind, "pt", "pts")) de l'Aigle")
    }

    private var movementText: String? {
        guard let movement, movement != 0 else { return nil }
        return movement > 0
            ? String(localized: "gagne \(FrenchPlural.count(movement, "place", "places"))")
            : String(localized: "perd \(FrenchPlural.count(-movement, "place", "places"))")
    }

    private var tableLayout: some View {
        HStack(spacing: 8) {
            RankMedal(rank: row.rank, isTied: row.isTied, tier: tier, size: 30)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(tier == .standard ? .medium : .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    MovementIndicator(movement: movement)
                }
                if let huntText {
                    Text(huntText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.stats.played)").frame(width: 26)
            Text("\(row.stats.wins)").frame(width: 26)
            Text(row.stats.pointDifference.signedText).frame(width: 40)
            Text("\(row.stats.pointsFor)")
                .font(Theme.display(.headline, weight: .heavy).monospacedDigit())
                .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// « Rise above » : flèche de progression depuis le tour précédent.
struct MovementIndicator: View {
    let movement: Int?

    var body: some View {
        if let movement, movement != 0 {
            HStack(spacing: 1) {
                Image(systemName: movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(abs(movement))")
                    .font(.caption2.weight(.heavy).monospacedDigit())
            }
            .foregroundStyle(movement > 0 ? Theme.accent : Theme.error)
            .accessibilityHidden(true)
        }
    }
}

/// Détail des statistiques et des matchs d'un joueur.
struct PlayerDetailView: View {
    let tournament: Tournament
    let playerID: Player.ID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = Standings.stats(for: tournament)[playerID] ?? PlayerStats(playerID: playerID)
        let insights = EagleInsights(tournament: tournament)
        let row = insights.standings.first { $0.id == playerID }
        NavigationStack {
            List {
                if let row {
                    Section {
                        profileHeader(row, insights: insights)
                    }
                }
                Section("Statistiques") {
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
            .eagleScreenBackground()
            .navigationTitle("Eagle Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    /// En-tête du profil : position, statut (Aigle, argent, bronze), progression, écart.
    private func profileHeader(_ row: StandingRow, insights: EagleInsights) -> some View {
        let tier = insights.tier(of: row)
        let movement = insights.movement[row.id] ?? 0
        return HStack(spacing: 14) {
            RankMedal(rank: row.rank, isTied: row.isTied, tier: tier, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(tournament.player(playerID)?.name ?? "")
                    .font(Theme.display(.title2, weight: .black))
                    .foregroundStyle(Theme.ink)
                Text(tierTitle(tier, row: row, insights: insights))
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(tier == .standard ? Theme.secondaryText : tier.color)
                if movement != 0 {
                    Label(
                        movement > 0
                            ? String(localized: "Rise above : \(FrenchPlural.count(movement, "place gagnée", "places gagnées")) au dernier tour")
                            : String(localized: "\(FrenchPlural.count(-movement, "place perdue", "places perdues")) au dernier tour"),
                        systemImage: movement > 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(movement > 0 ? Theme.accent : Theme.error)
                }
                if let behind = insights.pointsBehindEagle(row), behind > 0 {
                    Text("Hunt the Eagle : \(FrenchPlural.count(behind, "point", "points")) de retard")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func tierTitle(_ tier: RankTier, row: StandingRow, insights: EagleInsights) -> String {
        switch tier {
        case .eagle:
            let streak = insights.crownStreak[row.id] ?? 0
            return streak >= 2
                ? String(localized: "L'Aigle · en tête depuis \(streak) tours")
                : String(localized: "L'Aigle · champion actuel")
        case .silver: return String(localized: "\(row.rank)e place · argent")
        case .bronze: return String(localized: "\(row.rank)e place · bronze")
        case .standard:
            return insights.hasResults
                ? String(localized: "\(row.rank)e place")
                : String(localized: "Pas encore classé")
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
                    .foregroundStyle(own > other ? Theme.accent : own < other ? Theme.error : Theme.secondaryText)
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
                    Label("Le numéro 1 du classement est l'Aigle. Le statut change automatiquement dès qu'un autre joueur passe devant.", systemImage: "crown.fill")
                } header: {
                    Text("L'Aigle")
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
            .eagleScreenBackground()
            .navigationTitle("Règles du classement")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Accord en nombre pour les textes français construits à l'exécution
/// (en français, 0 et 1 sont au singulier). À remplacer par les variantes de pluriel du
/// String Catalog lors de l'ajout de l'anglais.
enum FrenchPlural {
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(abs(value) <= 1 ? singular : plural)"
    }
}

extension Int {
    /// « +5 », « 0 », « −3 ».
    var signedText: String {
        self > 0 ? "+\(self)" : "\(self)"
    }
}
