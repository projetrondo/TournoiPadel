import PadelCore
import SwiftUI

/// Modification du nombre de points par match d'un tournoi pas encore lancé.
struct EditScoringView: View {
    let tournament: Tournament

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ScoringSelection
    @State private var errorMessage: String?

    init(tournament: Tournament) {
        self.tournament = tournament
        _selection = State(initialValue: ScoringSelection(rule: tournament.settings.scoring))
    }

    var body: some View {
        NavigationStack {
            Form {
                ScoringSection(selection: $selection)
                Section {
                    let planner = RoundPlanner(playerCount: tournament.players.count, declaredCourts: tournament.settings.courts)
                    LabeledContent(
                        "Durée estimée",
                        value: String(localized: "environ \(planner.estimatedDurationMinutes(rounds: tournament.settings.plannedRounds, scoring: selection.rule)) min")
                    )
                }
            }
            .eagleScreenBackground()
            .navigationTitle("Points par match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .fontWeight(.semibold)
                }
            }
            .alert(
                "Erreur",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private func save() {
        do {
            try library.modify(id: tournament.id) { t, date in try t.updateScoring(selection.rule, now: date) }
            dismiss()
        } catch LifecycleError.alreadyStarted {
            errorMessage = String(localized: "Le tournoi a déjà commencé : les points ne peuvent plus être modifiés.")
        } catch {
            errorMessage = String(localized: "La modification n'a pas pu être enregistrée.")
        }
    }
}
