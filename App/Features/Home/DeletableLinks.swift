import PadelCore
import SwiftUI

/// Carte d'un tournoi qui ouvre le tournoi, avec suppression par la corbeille de la carte
/// ou par un appui long. Un tournoi partagé se supprime depuis son écran (il faut aussi le
/// retirer du partage en ligne).
struct TournamentLink: View {
    let tournament: Tournament

    @Environment(TournamentLibrary.self) private var library
    @State private var isConfirmingDelete = false

    private var canDeleteHere: Bool { tournament.sharing == nil }

    var body: some View {
        NavigationLink(value: HomeRoute.tournament(tournament.id)) {
            TournamentRow(tournament: tournament)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canDeleteHere { deleteButton }
        }
        .overlay(alignment: .bottomTrailing) {
            if canDeleteHere {
                TrashButton { isConfirmingDelete = true }
                    .accessibilityLabel(String(localized: "Supprimer le tournoi", bundle: .appLanguage))
            }
        }
        .confirmationDialog("Supprimer « \(tournament.name) » ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                library.perform { try library.delete(id: tournament.id) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les matchs et scores de ce tournoi seront définitivement effacés de cet iPhone.")
        }
    }

    private var deleteButton: some View {
        Button("Supprimer le tournoi", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
        }
    }
}

/// Carte d'une session, avec suppression par la corbeille ou un appui long.
/// Les tournois de la session restent enregistrés.
struct SessionLink: View {
    let session: PlaySession
    let tournaments: [Tournament]

    @Environment(SessionLibrary.self) private var sessions
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationLink(value: HomeRoute.session(session.id)) {
            SessionRow(session: session, tournaments: tournaments)
        }
        .buttonStyle(.plain)
        .contextMenu { deleteButton }
        .overlay(alignment: .bottomTrailing) {
            TrashButton { isConfirmingDelete = true }
                .accessibilityLabel(String(localized: "Supprimer la session", bundle: .appLanguage))
        }
        .confirmationDialog("Supprimer « \(session.name) » ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Supprimer la session", role: .destructive) {
                sessions.perform { try sessions.delete(id: session.id) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La liste des joueurs et les classements de la session seront supprimés. Les tournois restent enregistrés.")
        }
    }

    private var deleteButton: some View {
        Button("Supprimer la session", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
        }
    }
}

/// Petite corbeille en bas à droite d'une carte : demande confirmation avant de supprimer.
private struct TrashButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.error.opacity(0.85))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}
