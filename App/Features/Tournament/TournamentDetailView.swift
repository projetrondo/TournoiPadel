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
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab?
    @State private var scoreTarget: ScoreTarget?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingLaunch = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingRegenerate = false
    @State private var isLaunching = false
    @State private var isEditingScoring = false
    @State private var isSharing = false
    @State private var isConfirmingUnfollow = false
    @State private var deleteFailure: SyncFailure?

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
                    PillTabBar(
                        items: available,
                        selection: Binding(get: { current }, set: { tab = $0 }),
                        title: \.title
                    )
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
        .refreshable {
            await sync.refresh(tournament.id)
        }
        .task(id: tournament.isReadOnly) {
            // Spectateur : rafraîchissement régulier tant que l'écran est affiché.
            guard tournament.isReadOnly else { return }
            while !Task.isCancelled {
                await sync.refresh(tournament.id)
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if tournament.isReadOnly {
                        Button("Actualiser", systemImage: "arrow.clockwise") {
                            Task { await sync.refresh(tournament.id) }
                        }
                        Button("Ne plus suivre", systemImage: "eye.slash", role: .destructive) {
                            isConfirmingUnfollow = true
                        }
                    } else {
                        Button("Partager le tournoi", systemImage: "person.2.wave.2") {
                            isSharing = true
                        }
                        Button("Supprimer le tournoi", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Options")
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareTournamentView(tournamentID: tournament.id)
        }
        .confirmationDialog("Ne plus suivre « \(tournament.name) » ?", isPresented: $isConfirmingUnfollow, titleVisibility: .visible) {
            Button("Ne plus suivre", role: .destructive) {
                library.perform { try library.delete(id: tournament.id) }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La copie de ce tournoi sera retirée de cet iPhone. Le tournoi de l'organisateur n'est pas modifié.")
        }
        .alert(
            "Suppression impossible",
            isPresented: Binding(get: { deleteFailure != nil }, set: { if !$0 { deleteFailure = nil } }),
            presenting: deleteFailure
        ) { _ in
            Button("Supprimer seulement de cet iPhone", role: .destructive) {
                library.perform { try library.delete(id: tournament.id) }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: { failure in
            Text("La version en ligne n'a pas pu être retirée : \(failure.message) Si vous supprimez seulement sur cet iPhone, le code restera lisible en ligne.")
        }
        .sheet(isPresented: $isEditingScoring) {
            EditScoringView(tournament: tournament)
        }
        .sheet(item: $scoreTarget) { target in
            ScoreEntryView(tournamentID: tournament.id, initialMatchID: target.id)
        }
        .confirmationDialog("Supprimer « \(tournament.name) » ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                delete(tournament)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if tournament.sharing != nil {
                Text("Les matchs et scores seront effacés de cet iPhone, et le tournoi retiré du partage.")
            } else {
                Text("Les matchs et scores de ce tournoi seront définitivement effacés de cet iPhone.")
            }
        }
    }

    private func header(_ tournament: Tournament) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BadgeView(text: tournament.format.title)
                BadgeView(text: tournament.statusText, color: tournament.statusColor)
            }
            Text(tournament.name)
                .font(Theme.display(.largeTitle, weight: .black))
            if tournament.isReadOnly {
                Label("Suivi en lecture seule : l'organisateur saisit les scores.", systemImage: "eye")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            if tournament.sharing != nil {
                SyncStatusLabel(status: sync.status(of: tournament.id), tournament: tournament)
            }
        }
    }

    // MARK: - Matchs

    @ViewBuilder
    private func matchesContent(_ tournament: Tournament) -> some View {
        if tournament.format == .americano {
            CompromiseNotice(compromises: tournament.scheduleStatistics.compromises)
        }
        if tournament.isReadOnly {
            ScheduleView(tournament: tournament)
        } else {
            mexicanoActions(tournament)
            finishAction(tournament)
            ScheduleView(tournament: tournament) { match in
                scoreTarget = ScoreTarget(id: match.id)
            }
        }
    }

    /// Arrêt du tournoi, possible à tout moment dès qu'un match a été validé.
    @ViewBuilder
    private func finishAction(_ tournament: Tournament) -> some View {
        if tournament.canFinish {
            // Bouton principal seulement quand il n'y a plus rien à jouer.
            let isMainAction = !tournament.canGenerateNextRound && tournament.currentRound == nil
            Group {
                if isMainAction {
                    finishButton.buttonStyle(PrimaryButtonStyle())
                } else {
                    finishButton.buttonStyle(SecondaryButtonStyle())
                }
            }
            .confirmationDialog("Terminer le tournoi ?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                if tournament.hasPartiallyPlayedRound {
                    if tournament.rounds.contains(where: \.isComplete) {
                        Button("Compter seulement les tours complets") { finish(tournament, mode: .completedRoundsOnly) }
                    }
                    Button("Compter tous les matchs joués") { finish(tournament, mode: .countAllPlayedMatches) }
                } else {
                    Button("Terminer et voir les résultats") { finish(tournament, mode: .countAllPlayedMatches) }
                }
                Button("Continuer à jouer", role: .cancel) {}
            } message: {
                Text(finishMessage(tournament))
            }
        }
    }

    private var finishButton: some View {
        Button {
            isConfirmingFinish = true
        } label: {
            Label("Terminer le tournoi", systemImage: "flag.checkered")
        }
    }

    private func finish(_ tournament: Tournament, mode: FinishMode) {
        library.perform {
            try library.modify(id: tournament.id) { t, date in try t.finish(now: date, mode: mode) }
        }
        tab = .results
    }

    private func finishMessage(_ tournament: Tournament) -> String {
        let played = tournament.rounds.filter(\.isComplete).count
        if let partial = tournament.rounds.first(where: { $0.hasPlayedMatch && !$0.isComplete }) {
            let done = partial.matches.filter { $0.state == .completed }.count
            return String(localized: "Le tour \(partial.index) est en cours (\(done) match(s) sur \(partial.matches.count) joués). Compter seulement les tours complets garantit que tout le monde a joué autant de tours ; ses scores restent conservés. Le classement final ne changera plus, mais les scores pourront encore être corrigés.", bundle: .appLanguage)
        }
        if !tournament.settings.isOpenEnded, played < tournament.settings.plannedRounds {
            return String(localized: "\(played) tour(s) joué(s) sur \(tournament.settings.plannedRounds) prévus. Les tours non joués seront retirés et le classement actuel deviendra le classement final.", bundle: .appLanguage)
        }
        return String(localized: "Le classement actuel deviendra le classement final. Les scores pourront encore être corrigés.", bundle: .appLanguage)
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
        } else if tournament.generatesRoundsOnDemand, tournament.status == .inProgress,
                  tournament.rounds.count < tournament.settings.maximumRounds {
            Label(tournament.format == .mexicano
                  ? String(localized: "Le tour suivant sera composé d'après le classement dès que tous les matchs de ce tour seront terminés.", bundle: .appLanguage)
                  : String(localized: "Le tour suivant sera généré dès que tous les matchs de ce tour seront terminés. Vous pouvez arrêter quand vous voulez.", bundle: .appLanguage),
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
            infoRow(
                "Tours",
                value: tournament.settings.isOpenEnded ? String(localized: "Libre", bundle: .appLanguage) : "\(tournament.settings.plannedRounds)",
                systemImage: "arrow.triangle.2.circlepath"
            )
            if tournament.status == .draft, !tournament.isReadOnly {
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
                            .foregroundStyle(Theme.accent)
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
                        .foregroundStyle(Theme.accent)
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
            if tournament.isReadOnly {
                Text("L'organisateur n'a pas encore lancé le tournoi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                launchSection(tournament)
            }
        }
    }

    @ViewBuilder
    private func launchSection(_ tournament: Tournament) -> some View {
        VStack(spacing: 8) {
            Button {
                isConfirmingLaunch = true
            } label: {
                if isLaunching {
                    ProgressView().tint(Theme.onAccent)
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

    private func delete(_ tournament: Tournament) {
        guard tournament.sharing != nil else {
            library.perform { try library.delete(id: tournament.id) }
            dismiss()
            return
        }
        Task {
            do {
                try await sync.unpublish(tournament.id)
                library.perform { try library.delete(id: tournament.id) }
                dismiss()
            } catch {
                deleteFailure = SyncCoordinator.failure(error)
            }
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
                    message: String(localized: "Le tournoi n'a pas pu être lancé. Il reste inchangé.", bundle: .appLanguage)
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
        case .results: String(localized: "Résultats", bundle: .appLanguage)
        case .matches: String(localized: "Matchs", bundle: .appLanguage)
        case .standings: String(localized: "Classement", bundle: .appLanguage)
        case .info: String(localized: "Infos", bundle: .appLanguage)
        }
    }
}
