import PadelCore
import SwiftUI

struct TournamentDetailView: View {
    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isConfirmingLaunch = false
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
    }

    private func content(_ tournament: Tournament) -> some View {
        let planner = RoundPlanner(playerCount: tournament.players.count, declaredCourts: tournament.settings.courts)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        BadgeView(text: tournament.format.title)
                        BadgeView(text: tournament.statusText, color: tournament.statusColor)
                    }
                    Text(tournament.name)
                        .font(.largeTitle.weight(.bold))
                }

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
                } else {
                    if tournament.format == .americano {
                        CompromiseNotice(compromises: tournament.scheduleStatistics.compromises)
                    }
                    mexicanoActions(tournament)
                    ScheduleView(tournament: tournament)
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
    }

    private func launch(_ tournament: Tournament) {
        isLaunching = true
        Task {
            do {
                try await library.start(id: tournament.id)
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
