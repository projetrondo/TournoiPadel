import PadelCore
import SwiftUI

struct CreateTournamentView: View {
    var onCreated: (Tournament) -> Void

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var model = CreateTournamentModel()
    @State private var isConfirmingDiscard = false
    @State private var errorMessage: String?
    @FocusState private var isPlayerFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                formatSection
                ScoringSection(selection: $model.scoringSelection)
                playersSection
                courtsSection
                roundsSection
                issuesSection
            }
            .navigationTitle("Nouveau tournoi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if model.hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { createButton }
            .confirmationDialog("Abandonner ce tournoi ?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer la saisie", role: .cancel) {}
            } message: {
                Text("Les informations saisies seront perdues.")
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
            .interactiveDismissDisabled(model.hasChanges)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Nom du tournoi") {
            TextField("Ex. : Padel du jeudi", text: $model.name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $model.format) {
                ForEach(TournamentFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)

            if model.format == .mexicano {
                Picker("Premier tour", selection: $model.mexicanoFirstRound) {
                    Text("Aléatoire").tag(FirstRoundMode.random)
                    Text("Selon le niveau").tag(FirstRoundMode.byLevel)
                }
            }
        } header: {
            Text("Format")
        } footer: {
            Text(model.format.explanation)
        }
    }

    private var playersSection: some View {
        Section {
            ForEach($model.players) { $player in
                HStack {
                    TextField("Nom du joueur", text: $player.name)
                        .textInputAutocapitalization(.words)
                    if model.needsLevels {
                        Picker("Niveau", selection: $player.level) {
                            Text("Niveau ?").tag(Int?.none)
                            ForEach(Array(Player.levelRange), id: \.self) { level in
                                Text("Niveau \(level)").tag(Int?.some(level))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .onDelete { model.removePlayers(at: $0) }

            HStack {
                TextField("Prénom ou surnom", text: $model.newPlayerName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($isPlayerFieldFocused)
                    .onSubmit(addPlayer)
                Button(action: addPlayer) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(model.newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Ajouter le joueur")
            }
        } header: {
            Text("Joueurs (\(model.players.count))")
        } footer: {
            Text("Minimum \(RoundPlanner.minPlayers) joueurs. Balayez une ligne vers la gauche pour la supprimer.")
        }
    }

    private var courtsSection: some View {
        let planner = model.draft.planner
        return Section {
            Stepper(
                value: Binding(get: { model.courts }, set: { model.courtsOverride = $0 }),
                in: RoundPlanner.courtsRange
            ) {
                LabeledContent("Terrains disponibles", value: "\(model.courts)")
            }
        } header: {
            Text("Terrains")
        } footer: {
            if planner.activeCourts == 0 {
                Text("Ajoutez des joueurs pour voir la répartition.")
            } else if planner.restingPerRound > 0 {
                Text("\(planner.activeCourts) terrain(s) utilisé(s), \(planner.restingPerRound) joueur(s) en pause à chaque tour, à tour de rôle.")
            } else {
                Text("\(planner.activeCourts) terrain(s) utilisé(s). Tout le monde joue à chaque tour.")
            }
        }
    }

    private var roundsSection: some View {
        let draft = model.draft
        let planner = draft.planner
        return Section {
            if planner.activeCourts == 0 {
                Text("Le nombre de tours sera proposé dès 4 joueurs.")
                    .foregroundStyle(.secondary)
            } else {
                Stepper(
                    value: Binding(get: { model.draft.rounds }, set: { model.roundsOverride = $0 }),
                    in: RoundPlanner.roundsRange
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(draft.rounds) tours")
                            .font(.headline)
                        Text(roundsDetail(draft))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let recommended = model.recommendedRounds, recommended != draft.rounds {
                    Button("Revenir à la recommandation (\(recommended) tours)") {
                        model.roundsOverride = nil
                    }
                }
            }
        } header: {
            Text("Tours")
        } footer: {
            if planner.activeCourts > 0 {
                if planner.isEquitable(rounds: draft.rounds) {
                    Label("Chacun joue le même nombre de matchs.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.green)
                } else {
                    Label("Tout le monde ne jouera pas le même nombre de matchs.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        let issues = model.draft.issues.filter { $0.isShownInIssueList }
        if !issues.isEmpty {
            Section("À vérifier") {
                ForEach(issues, id: \.self) { issue in
                    Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? Theme.error : Theme.warning)
                        .font(.subheadline)
                }
            }
        }
    }

    private var createButton: some View {
        Button(action: create) {
            Label("Créer le tournoi", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!model.draft.canCreate)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func addPlayer() {
        model.addPlayer()
        isPlayerFieldFocused = true
    }

    private func create() {
        do {
            let tournament = try library.create(from: model.draft)
            dismiss()
            onCreated(tournament)
        } catch {
            errorMessage = String(localized: "Le tournoi n'a pas pu être enregistré. Réessayez.")
        }
    }

    // MARK: - Textes

    private func roundsDetail(_ draft: TournamentDraft) -> String {
        let matches = draft.planner.matchesPerPlayer(rounds: draft.rounds)
            .formatted(.number.precision(.fractionLength(0...1)))
        let minutes = draft.planner.estimatedDurationMinutes(rounds: draft.rounds, scoring: draft.scoring)
        return String(localized: "≈ \(matches) matchs par joueur · environ \(minutes) min")
    }
}

#Preview {
    CreateTournamentView { _ in }
        .environment(TournamentLibrary(store: InMemoryTournamentStore()))
}
