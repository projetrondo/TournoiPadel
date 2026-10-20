import PadelCore
import SwiftUI

struct TournamentDetailView: View {
    enum Tab: String, Hashable {
        case results
        case matches
        case standings
        case info
    }

    /// Match ouvert dans la feuille de saisie.
    struct ScoreTarget: Identifiable {
        let id: Match.ID
    }

    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab?
    @State private var scoreTarget: ScoreTarget?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingLaunch = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingRegenerate = false
    @State private var isLaunching = false
    @State private var isEditingScoring = false

    var body: some View {
        Group {
            if let tournament = library.tournament(id: tournamentID) {
                content(tournament)
            } else {
                ContentUnavailableView("Tournoi introuvable", systemImage: "questionmark.circle")
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: applyLaunchOptions)
    }

    private func applyLaunchOptions() {
        guard tab == nil, let tournament = library.tournament(id: tournamentID) else { return }
        if let raw = LaunchOptions.tab, let requested = Tab(rawValue: raw) {
            tab = requested
        }
        if LaunchOptions.opensScoreEntry, let pending = tournament.orderedMatches.first(where: { $0.state != .completed }) {
            scoreTarget = ScoreTarget(id: pending.id)
        }
    }

    private func tabs(for tournament: Tournament) -> [Tab] {
        switch tournament.status {
        case .draft: [.info]
        case .inProgress: [.matches, .standings, .info]
        case .finished: [.results, .matches, .standings]
        }
    }

    private func content(_ tournament: Tournament) -> some View {
        let available = tabs(for: tournament)
        let current = tab.flatMap { available.contains($0) ? $0 : nil } ?? available[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(tournament)

                if available.count > 1 {
                    Picker("Affichage", selection: Binding(get: { current }, set: { tab = $0 })) {
                        ForEach(available, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch current {
                case .results:
                    ResultsView(tournament: tournament)
                case .matches:
                    matchesContent(tournament)
                case .standings:
                    StandingsView(tournament: tournament)
                case .info:
                    infoContent(tournament)
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Supprimer le tournoi", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Options")
                }
            }
        }
        .sheet(isPresented: $isEditingScoring) {
            EditScoringView(tournament: tournament)
        }
        .sheet(item: $scoreTarget) { target in
            ScoreEntryView(tournamentID: tournament.id, initialMatchID: target.id)
        }
        .confirmationDialog("Supprimer « \(tournament.name) » ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                library.perform { try library.delete(id: tournament.id) }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les matchs et scores de ce tournoi seront définitivement effacés de cet iPhone.")
        }
    }

    private func header(_ tournament: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BadgeView(text: tournament.format.title)
                BadgeView(text: tournament.statusText, color: tournament.statusColor)
            }
            Text(tournament.name)
                .font(.largeTitle.weight(.bold))
        }
    }

    // MARK: - Matchs

    @ViewBuilder
    private func matchesContent(_ tournament: Tournament) -> some View {
        if tournament.format == .americano {
            CompromiseNotice(compromises: tournament.scheduleStatistics.compromises)
        }
        finishAction(tournament)
        mexicanoActions(tournament)
        ScheduleView(tournament: tournament) { match in
            scoreTarget = ScoreTarget(id: match.id)
        }
    }

    @ViewBuilder
    private func finishAction(_ tournament: Tournament) -> some View {
        if tournament.canFinish {
            Button {
                isConfirmingFinish = true
            } label: {
                Label("Terminer le tournoi", systemImage: "flag.checkered")
            }
            .buttonStyle(PrimaryButtonStyle())
            .confirmationDialog("Terminer le tournoi ?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button("Terminer et voir les résultats") {
                    library.perform {
                        try library.modify(id: tournament.id) { t, date in try t.finish(now: date) }
                    }
                    tab = .results
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                if tournament.format == .mexicano, tournament.rounds.count < tournament.settings.plannedRounds {
                    Text("\(tournament.rounds.count) tour(s) joué(s) sur \(tournament.settings.plannedRounds) prévus. Le classement actuel deviendra le classement final.")
                } else {
                    Text("Le classement actuel deviendra le classement final. Les scores pourront encore être corrigés.")
                }
            }
        }
    }

    /// Mexicano : tour suivant, ou nouveau calcul du dernier tour après une correction.
    @ViewBuilder
    private func mexicanoActions(_ tournament: Tournament) -> some View {
        if tournament.canGenerateNextRound {
            Button {
                library.perform {
                    try library.modify(id: tournament.id) { t, date in try t.generateNextRound(now: date) }
                }
            } label: {
                Label("Générer le tour \(tournament.rounds.count + 1)", systemImage: "wand.and.stars")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if tournament.format == .mexicano, tournament.status == .inProgress,
                  tournament.rounds.count < tournament.settings.plannedRounds {
            Label("Le tour suivant sera composé d'après le classement dès que tous les matchs de ce tour seront terminés.",
                  systemImage: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .cardStyle()
        }
        if tournament.canRegenerateLastRound {
            Button {
                isConfirmingRegenerate = true
            } label: {
                Label("Recomposer le tour \(tournament.rounds.count)", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            .confirmationDialog("Recomposer le tour \(tournament.rounds.count) ?", isPresented: $isConfirmingRegenerate, titleVisibility: .visible) {
                Button("Recomposer") {
                    library.perform {
                        try library.modify(id: tournament.id) { t, date in try t.regenerateLastRound(now: date) }
                    }
                }
                Button("Garder les matchs actuels", role: .cancel) {}
            } message: {
                Text("Utile après la correction d'un score : les équipes de ce tour seront recalculées avec le classement à jour. Aucun score n'y a encore été saisi.")
            }
        }
    }

    // MARK: - Infos

    @ViewBuilder
    private func infoContent(_ tournament: Tournament) -> some View {
        let planner = RoundPlanner(playerCount: tournament.players.count, declaredCourts: tournament.settings.courts)
        VStack(alignment: .leading, spacing: 10) {
            infoRow("Terrains", value: "\(planner.activeCourts)", systemImage: "square.split.2x1")
            infoRow("Tours", value: "\(tournament.settings.plannedRounds)", systemImage: "arrow.triangle.2.circlepath")
            if tournament.status == .draft {
                Button {
                    isEditingScoring = true
                } label: {
                    HStack {
                        Label("Points par match", systemImage: "number")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(tournament.settings.scoring.summary)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(Theme.green)
                    }
                }
                .accessibilityHint("Modifier le nombre de points par match")
            } else {
                infoRow("Points par match", value: tournament.settings.scoring.summary, systemImage: "number")
            }
            if planner.restingPerRound > 0 {
                infoRow("En pause par tour", value: "\(planner.restingPerRound)", systemImage: "cup.and.saucer")
            }
        }
        .cardStyle()

        VStack(alignment: .leading, spacing: 10) {
            Text("Joueurs (\(tournament.players.count))")
                .font(.headline)
            ForEach(tournament.players) { player in
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Theme.green)
                    Text(player.name)
                    Spacer()
                    if let level = player.level {
                        Text("Niveau \(level)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()

        if tournament.status == .draft {
            launchSection(tournament)
        }
    }

    @ViewBuilder
    private func launchSection(_ tournament: Tournament) -> some View {
        VStack(spacing: 8) {
            Button {
                isConfirmingLaunch = true
            } label: {
                if isLaunching {
                    ProgressView().tint(.white)
                } else {
                    Label("Lancer le tournoi", systemImage: "play.fill")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLaunching)

            Group {
                if tournament.format == .americano {
                    Text("Tout le programme sera généré d'un coup.")
                } else {
                    Text("Le premier tour sera généré. Les suivants dépendront des scores.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .confirmationDialog("Lancer le tournoi ?", isPresented: $isConfirmingLaunch, titleVisibility: .visible) {
            Button("Lancer") { launch(tournament) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les joueurs et les réglages ne pourront plus être modifiés.")
        }
    }

    private func launch(_ tournament: Tournament) {
        isLaunching = true
        Task {
            do {
                try await library.start(id: tournament.id)
                tab = .matches
            } catch {
                library.failure = TournamentLibrary.Failure(
                    message: String(localized: "Le tournoi n'a pas pu être lancé. Il reste inchangé.")
                )
            }
            isLaunching = false
        }
    }

    private func infoRow(_ title: LocalizedStringKey, value: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

extension TournamentDetailView.Tab {
    var title: String {
        switch self {
        case .results: String(localized: "Résultats")
        case .matches: String(localized: "Matchs")
        case .standings: String(localized: "Classement")
        case .info: String(localized: "Infos")
        }
    }
}
