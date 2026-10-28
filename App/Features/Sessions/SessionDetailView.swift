import PadelCore
import SwiftUI

/// Une session : classement par période, tournois joués et liste des joueurs.
struct SessionDetailView: View {
    enum Tab: String, Hashable, CaseIterable {
        case ranking
        case tournaments
        case players

        var title: String {
            switch self {
            case .ranking: String(localized: "Classement", bundle: .appLanguage)
            case .tournaments: String(localized: "Tournois", bundle: .appLanguage)
            case .players: String(localized: "Joueurs", bundle: .appLanguage)
            }
        }
    }

    let sessionID: PlaySession.ID
    /// Ouvre un tournoi créé depuis cette session.
    var onTournamentCreated: (Tournament) -> Void = { _ in }

    @Environment(SessionLibrary.self) private var sessions
    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = LaunchOptions.sessionTab.flatMap(Tab.init(rawValue:)) ?? .ranking
    @State private var isCreatingTournament = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let session = sessions.session(id: sessionID) {
                content(session)
            } else {
                ContentUnavailableView("Session introuvable", systemImage: "questionmark.circle")
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ session: PlaySession) -> some View {
        let tournaments = library.tournaments(in: session.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(session, tournamentCount: tournaments.count)
                PillTabBar(items: Tab.allCases, selection: $tab, title: \.title)
                switch tab {
                case .ranking:
                    SessionRankingView(session: session, tournaments: tournaments)
                case .tournaments:
                    tournamentList(tournaments)
                case .players:
                    SessionPlayersView(session: session)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isCreatingTournament = true
            } label: {
                Label("Nouveau tournoi", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.background.opacity(0.94))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Renommer", systemImage: "pencil") {
                        renameText = session.name
                        isRenaming = true
                    }
                    Picker("Matchs minimum pour être classé", selection: Binding(
                        get: { session.minimumMatches },
                        set: { value in sessions.perform { try sessions.modify(id: session.id) { $0.minimumMatches = value } } }
                    )) {
                        ForEach([1, 2, 3, 4, 5, 6, 8, 10], id: \.self) { count in
                            Text("Classé dès \(Plural.count(count, "match", "matchs"))").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    Button("Supprimer la session", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Options")
                }
            }
        }
        .sheet(isPresented: $isCreatingTournament) {
            CreateTournamentView(session: session) { tournament in
                onTournamentCreated(tournament)
            }
        }
        .alert("Renommer la session", isPresented: $isRenaming) {
            TextField("Nom", text: $renameText)
            Button("Enregistrer") {
                sessions.perform { try sessions.modify(id: session.id) { try $0.rename(renameText) } }
            }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer « \(session.name) » ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer la session", role: .destructive) {
                sessions.perform { try sessions.delete(id: session.id) }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La liste des joueurs et les classements de la session seront supprimés. Les tournois restent enregistrés.")
        }
    }

    private func header(_ session: PlaySession, tournamentCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BadgeView(text: String(localized: "Session", bundle: .appLanguage), color: Theme.gold)
                BadgeView(text: Plural.count(session.activeMembers.count, "joueur", "joueurs"), color: Theme.secondaryText)
                BadgeView(text: Plural.count(tournamentCount, "tournoi", "tournois"), color: Theme.secondaryText)
            }
            Text(session.name)
                .font(Theme.display(.largeTitle, weight: .black))
                .foregroundStyle(Theme.ink)
        }
    }

    @ViewBuilder
    private func tournamentList(_ tournaments: [Tournament]) -> some View {
        if tournaments.isEmpty {
            Text("Aucun tournoi pour l'instant. Créez-en un : les joueurs de la session seront proposés, il suffira de cocher les présents.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .cardStyle()
        } else {
            VStack(spacing: 10) {
                ForEach(tournaments) { tournament in
                    NavigationLink(value: HomeRoute.tournament(tournament.id)) {
                        TournamentRow(tournament: tournament)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Classement de la session sur une semaine, un mois, une année ou depuis le début.
struct SessionRankingView: View {
    let session: PlaySession
    let tournaments: [Tournament]

    @State private var period: RankingPeriod = .month
    @State private var reference = Date()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .appLanguage
        calendar.timeZone = .current
        return calendar
    }

    var body: some View {
        let ranking = SessionRanking(
            session: session,
            tournaments: tournaments,
            period: period,
            reference: reference,
            calendar: Self.calendar
        )
        VStack(alignment: .leading, spacing: 14) {
            PillTabBar(items: RankingPeriod.allCases, selection: $period, title: \.title)
            periodNavigator(ranking)

            if ranking.rows.isEmpty {
                VStack(spacing: 10) {
                    EagleEmblem()
                        .stroke(Theme.gold.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Text("Aucun match validé sur cette période.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()
            } else {
                Text("\(Plural.count(ranking.tournamentCount, "tournoi", "tournois")) · \(Plural.count(ranking.matchCount, "match", "matchs")) · classé dès \(Plural.count(session.minimumMatches, "match", "matchs"))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)

                let leaders = ranking.ranked.filter { $0.rank == 1 }
                ForEach(leaders) { row in
                    SessionLeaderCard(row: row, name: name(row.id), period: period)
                }
                let others = ranking.ranked.filter { $0.rank != 1 }
                if !others.isEmpty {
                    rowsCard(others)
                }
                if !ranking.unranked.isEmpty {
                    Text("Pas encore classés")
                        .font(Theme.display(.headline, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                    rowsCard(ranking.unranked)
                }
                Text("Classement à la moyenne de points par match, puis au % de victoires, puis à la différence moyenne. Chaque tournoi compte dans la période où il a été joué.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onChange(of: period) { reference = Date() }
    }

    private func name(_ id: Player.ID) -> String {
        SessionRanking.name(of: id, session: session, tournaments: tournaments)
    }

    private func rowsCard(_ rows: [SessionRankingRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Divider().overlay(Theme.stroke).padding(.leading, 14)
                }
                SessionRankingRowView(row: row, name: name(row.id))
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// « ‹ Mars 2026 › » : période affichée, avec la précédente et la suivante.
    @ViewBuilder
    private func periodNavigator(_ ranking: SessionRanking) -> some View {
        if period != .all {
            HStack {
                Button {
                    reference = period.shift(reference, by: -1, calendar: Self.calendar)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Période précédente")
                Spacer()
                Text(periodTitle(ranking.interval))
                    .font(Theme.display(.title3, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    reference = period.shift(reference, by: 1, calendar: Self.calendar)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Période suivante")
                .disabled(ranking.interval.map { $0.end > Date() } ?? true)
            }
            .font(.headline)
        }
    }

    private func periodTitle(_ interval: DateInterval?) -> String {
        guard let interval else { return String(localized: "Depuis le début", bundle: .appLanguage) }
        let calendar = Self.calendar
        switch period {
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let start = interval.start.formatted(.dateTime.day().month(.abbreviated).locale(calendar.locale!))
            let end = last.formatted(.dateTime.day().month(.abbreviated).year().locale(calendar.locale!))
            return "\(start) – \(end)"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year().locale(calendar.locale!)).capitalized
        case .year:
            return interval.start.formatted(.dateTime.year().locale(calendar.locale!))
        case .all:
            return String(localized: "Depuis le début", bundle: .appLanguage)
        }
    }
}

extension RankingPeriod {
    var title: String {
        switch self {
        case .week: String(localized: "Semaine", bundle: .appLanguage)
        case .month: String(localized: "Mois", bundle: .appLanguage)
        case .year: String(localized: "Année", bundle: .appLanguage)
        case .all: String(localized: "Tout", bundle: .appLanguage)
        }
    }
}

extension PlayerStats {
    /// « 12,5 » points par match.
    var averageText: String {
        (averagePoints ?? 0).formatted(.number.precision(.fractionLength(1)).locale(.appLanguage))
    }
}

/// Le n°1 de la session sur la période : l'Aigle de la semaine, du mois ou de l'année.
struct SessionLeaderCard: View {
    let row: SessionRankingRow
    let name: String
    let period: RankingPeriod

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            CrownRank()
            PlayerAvatar(name: name, tier: .eagle, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(eagleTitle)
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
                    Text(row.stats.averageText)
                        .font(.system(size: 30, weight: .black).width(.condensed).monospacedDigit())
                        .foregroundStyle(Theme.goldGradient)
                    Text("pts / match")
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(verbatim: "\(row.stats.recordText) · \(Plural.count(row.tournaments, "tournoi", "tournois"))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) {
            EagleEmblem()
                .filled(Theme.goldGradient)
                .frame(width: 150, height: 150)
                .opacity(0.16)
                .offset(x: 34, y: 8)
                .accessibilityHidden(true)
        }
        .goldGlowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(eagleTitle), \(name), \(row.stats.averageText) points par match, \(Plural.count(row.stats.wins, "victoire", "victoires")), \(Plural.count(row.stats.played, "match", "matchs"))")
    }

    private var eagleTitle: String {
        let base = row.isTied ? String(localized: "Aigle ex aequo", bundle: .appLanguage) : String(localized: "L'Aigle", bundle: .appLanguage)
        switch period {
        case .week: return String(localized: "\(base) de la semaine", bundle: .appLanguage)
        case .month: return String(localized: "\(base) du mois", bundle: .appLanguage)
        case .year: return String(localized: "\(base) de l'année", bundle: .appLanguage)
        case .all: return base
        }
    }
}

struct SessionRankingRowView: View {
    let row: SessionRankingRow
    let name: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tier = row.rank.map(RankTier.init(rank:)) ?? .standard
        HStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize {
                if let rank = row.rank {
                    RankMedal(rank: rank, isTied: row.isTied, tier: tier, size: 28)
                        .frame(width: 30)
                } else {
                    Text("–")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 30)
                }
                PlayerAvatar(name: name, tier: tier, size: 38)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: dynamicTypeSize.isAccessibilitySize ? "\(positionText) \(name)" : name)
                    .font(.body.weight(tier == .standard ? .semibold : .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(verbatim: "\(row.stats.recordText) · \(Plural.count(row.stats.played, "match", "matchs"))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.stats.averageText)
                    .font(Theme.display(.title3, weight: .black).monospacedDigit())
                    .foregroundStyle(tier == .standard ? Theme.ink : tier.color)
                Text("pts/m")
                    .font(.caption2.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// « 2 », « 2= » ou « – » (non classé).
    private var positionText: String {
        guard let rank = row.rank else { return "–" }
        return row.isTied ? "\(rank)=" : "\(rank)"
    }

    private var accessibilityText: String {
        let position = row.rank.map(\.ordinalText) ?? String(localized: "non classé", bundle: .appLanguage)
        return "\(position), \(name), \(row.stats.averageText) points par match, \(Plural.count(row.stats.wins, "victoire", "victoires")), \(Plural.count(row.stats.losses, "défaite", "défaites")), \(Plural.count(row.stats.played, "match", "matchs"))"
    }
}
