import PadelCore
import SwiftUI

struct TournamentDetailView: View {
    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

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
                    infoRow("Score", value: tournament.settings.scoring.summary, systemImage: "number")
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
                    VStack(spacing: 8) {
                        Button {} label: {
                            Label("Lancer le tournoi", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(true)
                        Text("La génération des matchs arrive dans la prochaine version.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
