import Charts
import PadelCore
import SwiftUI

/// Classement individuel, recalculé à chaque affichage à partir des matchs terminés.
/// Le numéro 1 est mis en scène comme « l'Aigle » ; les règles de calcul ne changent pas.
struct StandingsView: View {
    let tournament: Tournament

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
                    ForEach(challengers) { row in
                        if row.id != challengers.first?.id {
                            Divider().overlay(Theme.stroke).padding(.leading, 14)
                        }
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
        .onAppear {
            if LaunchOptions.opensPlayerProfile, selectedPlayer == nil, let eagle = insights.eagles.first {
                selectedPlayer = PlayerSelection(id: eagle.id)
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
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            CrownRank()
            PlayerAvatar(name: name, tier: .eagle, size: 64)

            VStack(alignment: .leading, spacing: 4) {
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(row.stats.pointsFor)")
                        .font(.system(size: 30, weight: .black).width(.condensed).monospacedDigit())
                        .foregroundStyle(Theme.goldGradient)
                    Text("pts")
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(verbatim: row.stats.recordText)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink.opacity(0.8))
                if let crownText {
                    Label(crownText, systemImage: "crown.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) {
            // Grand aigle décoratif, à droite de la carte.
            EagleEmblem()
                .filled(Theme.goldGradient)
                .frame(width: 150, height: 150)
                .opacity(0.16)
                .offset(x: 34, y: 8)
                .accessibilityHidden(true)
        }
        .goldGlowCard()
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
        var parts = [title, name, FrenchPlural.count(row.stats.pointsFor, "point", "points"),
                     FrenchPlural.count(row.stats.wins, "victoire", "victoires"),
                     FrenchPlural.count(row.stats.losses, "défaite", "défaites")]
        if row.stats.winRate != nil {
            parts.append(String(localized: "\(row.stats.winRateText) de victoires"))
        }
        parts.append(FrenchPlural.count(row.stats.played, "match", "matchs"))
        if let crownText { parts.append(crownText) }
        return parts.joined(separator: ", ")
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
            rowLayout
        }
    }

    /// Très grandes tailles de texte : une ligne par information plutôt que des colonnes.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(row.isTied ? "\(row.rank)=" : "\(row.rank)") \(name)")
                .font(.headline)
                .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
            Text(verbatim: "\(FrenchPlural.count(row.stats.pointsFor, "point", "points")) · \(row.stats.recordText)")
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
                     FrenchPlural.count(row.stats.losses, "défaite", "défaites"),
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

    /// Médaille, avatar, nom et bilan, points à droite, chevron.
    private var rowLayout: some View {
        HStack(spacing: 10) {
            RankMedal(rank: row.rank, isTied: row.isTied, tier: tier, size: 28)
                .frame(width: 30)
            PlayerAvatar(name: name, tier: tier, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(tier == .standard ? .semibold : .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    MovementIndicator(movement: movement)
                }
                Text(verbatim: "\(row.stats.recordText) · \(row.stats.pointDifference.signedText)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let huntText {
                    Text(huntText)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(row.stats.pointsFor)")
                    .font(Theme.display(.title3, weight: .black).monospacedDigit())
                    .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
                Text("pts")
                    .font(.caption2.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.secondaryText.opacity(0.6))
        }
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

/// Profil d'un joueur : statut, chiffres clés, courbe de classement et matchs.
struct PlayerDetailView: View {
    let tournament: Tournament
    let playerID: Player.ID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stats = Standings.stats(for: tournament)[playerID] ?? PlayerStats(playerID: playerID)
        let insights = EagleInsights(tournament: tournament)
        let row = insights.standings.first { $0.id == playerID }
        let tier = row.map { insights.tier(of: $0) } ?? .standard
        NavigationStack {
            List {
                Section {
                    profileHeader(row, tier: tier, insights: insights)
                    if let row { statusTile(row, tier: tier, insights: insights) }
                    statTiles(stats)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

                Section {
                    RankHistoryChart(
                        history: insights.rankHistory[playerID] ?? [],
                        playerCount: insights.standings.count,
                        tier: tier
                    )
                    .listRowBackground(Theme.card)
                } header: {
                    Text("Historique classement")
                }

                Section("Statistiques") {
                    statRow("Matchs joués", value: "\(stats.played)")
                    statRow("Points encaissés", value: "\(stats.pointsAgainst)")
                    statRow("Différence", value: stats.pointDifference.signedText)
                    statRow("Matchs nuls", value: "\(stats.draws)")
                    if let average = stats.averagePoints {
                        statRow("Points par match", value: average.formatted(.number.precision(.fractionLength(1))))
                    }
                    statRow("Pauses", value: "\(stats.rests)")
                }
                .listRowBackground(Theme.card)

                Section("Matchs") {
                    ForEach(matches, id: \.match.id) { entry in
                        matchRow(entry.round, entry.match)
                    }
                }
                .listRowBackground(Theme.card)
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

    /// Avatar à anneau, nom et statut (Aigle, argent, bronze).
    private func profileHeader(_ row: StandingRow?, tier: RankTier, insights: EagleInsights) -> some View {
        let name = tournament.player(playerID)?.name ?? ""
        return VStack(spacing: 8) {
            ZStack(alignment: .top) {
                PlayerAvatar(name: name, tier: tier, size: 104)
                    .padding(.top, tier == .eagle ? 18 : 0)
                if tier == .eagle {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.goldGradient)
                        .shadow(color: Theme.gold.opacity(0.6), radius: 6)
                        .accessibilityHidden(true)
                }
            }
            Text(name)
                .font(Theme.display(.largeTitle, weight: .black))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let row {
                Text(tierTitle(tier, row: row, insights: insights))
                    .font(Theme.display(.subheadline, weight: .heavy))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(tier == .standard ? AnyShapeStyle(Theme.secondaryText) : tier == .eagle ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(tier.color))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Tuile de statut : couronne à défendre pour l'Aigle, écart à combler pour les autres.
    private func statusTile(_ row: StandingRow, tier: RankTier, insights: EagleInsights) -> some View {
        let movement = insights.movement[row.id] ?? 0
        return HStack(spacing: 14) {
            if tier == .eagle {
                GoldEagle(size: 52)
            } else {
                RankMedal(rank: row.rank, isTied: row.isTied, tier: tier, size: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusHeadline(row, tier: tier, insights: insights))
                    .font(Theme.display(.headline, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(tier == .eagle ? Theme.gold : Theme.ink)
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
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(StatusTileBackground(isEagle: tier == .eagle))
        .accessibilityElement(children: .combine)
    }

    private func statusHeadline(_ row: StandingRow, tier: RankTier, insights: EagleInsights) -> String {
        if tier == .eagle {
            let streak = insights.crownStreak[row.id] ?? 0
            return streak >= 2
                ? String(localized: "Defend your crown · \(streak) tours en tête")
                : String(localized: "Defend your crown")
        }
        if let behind = insights.pointsBehindEagle(row) {
            return behind > 0
                ? String(localized: "Hunt the Eagle : \(FrenchPlural.count(behind, "point", "points")) de retard")
                : String(localized: "À égalité de points avec l'Aigle")
        }
        return String(localized: "Pas encore classé")
    }

    private func statTiles(_ stats: PlayerStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: "\(stats.pointsFor)", label: String(localized: "Points"), systemImage: "star.fill", color: Theme.gold)
            StatTile(value: "\(stats.wins)", label: String(localized: "Victoires"), systemImage: "checkmark.circle.fill", color: Theme.accent)
            StatTile(value: "\(stats.losses)", label: String(localized: "Défaites"), systemImage: "xmark.circle.fill", color: Theme.error)
            StatTile(value: stats.winRateText, label: String(localized: "Win rate"), systemImage: "percent", color: Theme.silver)
        }
    }

    private func tierTitle(_ tier: RankTier, row: StandingRow, insights: EagleInsights) -> String {
        switch tier {
        case .eagle: return String(localized: "L'Aigle")
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

/// Fond de la tuile de statut : doré pour l'Aigle, carte sobre sinon.
private struct StatusTileBackground: ViewModifier {
    let isEagle: Bool

    func body(content: Content) -> some View {
        if isEagle {
            content.goldGlowCard(cornerRadius: Theme.cornerRadius)
        } else {
            content
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
}

/// Courbe de la position du joueur après chaque tour (1 en haut), couronne quand il est l'Aigle.
struct RankHistoryChart: View {
    let history: [RankPoint]
    let playerCount: Int
    let tier: RankTier

    var body: some View {
        if history.count < 2 {
            Text("La courbe apparaît après deux tours joués.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.vertical, 8)
        } else {
            Chart {
                ForEach(history, id: \.round) { point in
                    AreaMark(
                        x: .value("Tour", point.round),
                        yStart: .value("Position", playerCount),
                        yEnd: .value("Position", point.rank)
                    )
                    .foregroundStyle(LinearGradient(colors: [lineColor.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                    LineMark(x: .value("Tour", point.round), y: .value("Position", point.rank))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Tour", point.round), y: .value("Position", point.rank))
                        .foregroundStyle(point.rank == 1 ? Theme.gold : lineColor)
                        .symbolSize(point.rank == 1 ? 80 : 36)
                        .annotation(position: .top, spacing: 2) {
                            if point.rank == 1 {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: min(playerCount, 5))) { value in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let rank = value.as(Int.self) { Text(verbatim: "\(rank)") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: history.map(\.round)) { value in
                    AxisValueLabel {
                        if let round = value.as(Int.self) { Text("T\(round)") }
                    }
                }
            }
            .frame(height: 180)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var lineColor: Color {
        tier == .standard ? Theme.accent : tier.color
    }

    private var accessibilityText: String {
        history.map { String(localized: "tour \($0.round) : \($0.rank)e") }.joined(separator: ", ")
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
