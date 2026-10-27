import PadelCore
import SwiftUI

/// Saisie rapide du score d'un match, pensée pour le bord du terrain : gros chiffres, pavé
/// numérique, score adverse calculé automatiquement, passage au match suivant après validation.
struct ScoreEntryView: View {
    enum Side: Hashable {
        case teamA
        case teamB
    }

    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var matchID: Match.ID
    @State private var scoreA: Int?
    @State private var scoreB: Int?
    @State private var selected: Side = .teamA
    /// Le prochain chiffre tapé remplace la valeur au lieu de la compléter.
    @State private var replaceOnNextDigit = true
    @State private var isCorrecting = false
    @State private var isSaving = false
    @State private var isConfirmingCorrection = false
    @State private var isConfirmingReopen = false
    @State private var validationCount = 0
    @State private var undoMatchID: Match.ID?
    @State private var errorMessage: String?

    init(tournamentID: Tournament.ID, initialMatchID: Match.ID) {
        self.tournamentID = tournamentID
        _matchID = State(initialValue: initialMatchID)
    }

    private var tournament: Tournament? { library.tournament(id: tournamentID) }
    private var match: Match? { tournament?.match(matchID) }

    var body: some View {
        NavigationStack {
            Group {
                if let tournament, let match {
                    content(tournament, match)
                } else {
                    ContentUnavailableView("Match introuvable", systemImage: "questionmark.circle")
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    navigationButtons
                }
            }
            .sensoryFeedback(.success, trigger: validationCount)
            .onAppear { loadFields() }
            .onChange(of: matchID) { _, _ in loadFields() }
            .alert(
                "Score non enregistré",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Contenu

    private func content(_ tournament: Tournament, _ match: Match) -> some View {
        let editable = match.state != .completed || isCorrecting
        let round = tournament.location(of: match.id).map { $0.round + 1 } ?? 0
        return ScrollView {
            VStack(spacing: 16) {
                if let undoMatchID, undoMatchID != match.id {
                    undoBanner(undoMatchID)
                }

                HStack {
                    Text("Tour \(round) · Terrain \(match.court)")
                        .font(.headline)
                    Spacer()
                    BadgeView(text: isCorrecting ? String(localized: "Correction") : match.state.title,
                              color: isCorrecting ? Theme.warning : match.state.color)
                }

                HStack(spacing: 12) {
                    teamPanel(.teamA, team: match.teamA, value: scoreA, tournament: tournament, editable: editable)
                    Text("–")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.secondary)
                    teamPanel(.teamB, team: match.teamB, value: scoreB, tournament: tournament, editable: editable)
                }

                feedbackLine(tournament)

                if editable {
                    keypad(maximum: maximumScore(tournament))
                }

                actions(tournament, match)
            }
            .padding(16)
        }
    }

    private func teamPanel(_ side: Side, team: Team, value: Int?, tournament: Tournament, editable: Bool) -> some View {
        let isSelected = editable && selected == side
        return Button {
            selected = side
            replaceOnNextDigit = true
        } label: {
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    ForEach(team.players, id: \.self) { id in
                        Text(tournament.player(id)?.name ?? "?")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Text(value.map { "\($0)" } ?? "–")
                    .font(.system(size: 60, weight: .black).width(.condensed).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
                if editable {
                    HStack(spacing: 16) {
                        stepButton("minus", side: side, delta: -1, tournament: tournament)
                        stepButton("plus", side: side, delta: 1, tournament: tournament)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(teamLabel(team, tournament: tournament, value: value))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, side: Side, delta: Int, tournament: Tournament) -> some View {
        Button {
            selected = side
            let current = (side == .teamA ? scoreA : scoreB) ?? 0
            setScore(max(0, min(maximumScore(tournament), current + delta)), for: side, tournament: tournament)
            replaceOnNextDigit = true
        } label: {
            Image(systemName: "\(symbol).circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(delta > 0 ? "Plus un" : "Moins un")
    }

    @ViewBuilder
    private func feedbackLine(_ tournament: Tournament) -> some View {
        if let score = currentScore {
            if case .invalid(let error) = tournament.validation(of: score) {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                    .font(.subheadline)
            } else {
                Label(outcomeText(score), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.subheadline)
            }
        } else {
            Text(hint(for: tournament.settings.scoring))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func keypad(maximum: Int) -> some View {
        let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
        return VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
                        } else {
                            Button {
                                press(key, maximum: maximum)
                            } label: {
                                Group {
                                    if key == "⌫" {
                                        Image(systemName: "delete.left")
                                    } else {
                                        Text(key)
                                    }
                                }
                                .font(.title2.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.card)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key == "⌫" ? "Effacer" : key)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ tournament: Tournament, _ match: Match) -> some View {
        let isValid = currentScore.map { tournament.validation(of: $0).isValid } ?? false
        if match.state != .completed {
            Button(action: validate) {
                Label("Valider le résultat", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isValid || isSaving)
        } else if isCorrecting {
            Button {
                isConfirmingCorrection = true
            } label: {
                Label("Enregistrer la correction", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isValid || isSaving || currentScore == match.score)
            .confirmationDialog("Corriger le score ?", isPresented: $isConfirmingCorrection, titleVisibility: .visible) {
                Button("Remplacer le score") { saveCorrection() }
                Button("Annuler", role: .cancel) {}
            } message: {
                if let old = match.score, let new = currentScore {
                    Text("\(old.teamA)–\(old.teamB) sera remplacé par \(new.teamA)–\(new.teamB). Le classement sera recalculé.")
                }
            }

            Button("Abandonner la correction") {
                isCorrecting = false
                loadFields()
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
            Button {
                isCorrecting = true
                selected = .teamA
                replaceOnNextDigit = true
            } label: {
                Label("Corriger le score", systemImage: "pencil")
            }
            .buttonStyle(SecondaryButtonStyle())

            if tournament.canReopen(match.id) {
                Button("Annuler la validation", role: .destructive) {
                    isConfirmingReopen = true
                }
                .confirmationDialog("Annuler la validation ?", isPresented: $isConfirmingReopen, titleVisibility: .visible) {
                    Button("Annuler la validation", role: .destructive) { reopen(match.id) }
                    Button("Garder le score", role: .cancel) {}
                } message: {
                    Text("Le match repassera « en cours » et son score sera retiré du classement.")
                }
            }
        }
    }

    private func undoBanner(_ id: Match.ID) -> some View {
        HStack {
            Label("Score validé", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Annuler") { undo(id) }
                .font(.subheadline.weight(.semibold))
        }
        .cardStyle()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var navigationButtons: some View {
        let matches = tournament?.orderedMatches ?? []
        let index = matches.firstIndex { $0.id == matchID }
        Button {
            if let index, index > 0 { matchID = matches[index - 1].id }
        } label: {
            Label("Match précédent", systemImage: "chevron.left")
        }
        .disabled(index == nil || index == 0)
        Spacer()
        if let index {
            Text(verbatim: "\(index + 1) / \(matches.count)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel(String(localized: "Match \(index + 1) sur \(matches.count)"))
        }
        Spacer()
        Button {
            if let index, index + 1 < matches.count { matchID = matches[index + 1].id }
        } label: {
            Label("Match suivant", systemImage: "chevron.right")
        }
        .disabled(index == nil || index == matches.count - 1)
    }

    // MARK: - Saisie

    private var currentScore: Score? {
        guard let scoreA, let scoreB else { return nil }
        return Score(scoreA, scoreB)
    }

    private func maximumScore(_ tournament: Tournament) -> Int {
        tournament.settings.scoring.points ?? ScoringRule.maxFreeScore
    }

    private func press(_ key: String, maximum: Int) {
        guard let tournament else { return }
        let current = selected == .teamA ? scoreA : scoreB
        if key == "⌫" {
            let shortened = (current ?? 0) / 10
            setScore(current == nil || current! < 10 ? nil : shortened, for: selected, tournament: tournament)
            replaceOnNextDigit = false
            return
        }
        guard let digit = Int(key) else { return }
        var value = replaceOnNextDigit ? digit : (current ?? 0) * 10 + digit
        if value > maximum { value = digit }
        setScore(value, for: selected, tournament: tournament)
        replaceOnNextDigit = false
    }

    /// Met à jour un score et déduit l'autre quand la règle le permet.
    private func setScore(_ value: Int?, for side: Side, tournament: Tournament) {
        markInProgressIfNeeded()
        withAnimation(.snappy(duration: 0.15)) {
            if side == .teamA { scoreA = value } else { scoreB = value }
            guard let value else { return }
            let other: Int?
            switch tournament.settings.scoring {
            case .fixedTotal(let points):
                other = points - value
            case .raceTo(let points):
                other = value < points ? points : nil
            case .free:
                other = nil
            }
            if let other {
                if side == .teamA { scoreB = other } else { scoreA = other }
            }
        }
    }

    private func loadFields() {
        let score = match?.score
        scoreA = score?.teamA
        scoreB = score?.teamB
        selected = .teamA
        replaceOnNextDigit = true
        isCorrecting = false
    }

    private func markInProgressIfNeeded() {
        guard let match, match.state == .scheduled else { return }
        try? library.modify(id: tournamentID) { t, date in try t.markInProgress(match.id, now: date) }
    }

    // MARK: - Actions

    private func validate() {
        guard !isSaving, let score = currentScore else { return }
        isSaving = true
        defer { isSaving = false }
        let validatedID = matchID
        do {
            try library.modify(id: tournamentID) { t, date in try t.validateScore(validatedID, score: score, now: date) }
            validationCount += 1
            showUndo(for: validatedID)
            if let next = nextPendingMatch(after: validatedID) {
                matchID = next
            } else {
                loadFields()
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func saveCorrection() {
        guard !isSaving, let score = currentScore else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try library.modify(id: tournamentID) { t, date in try t.correctScore(matchID, score: score, now: date) }
            validationCount += 1
            isCorrecting = false
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func reopen(_ id: Match.ID) {
        do {
            try library.modify(id: tournamentID) { t, date in try t.reopenMatch(id, now: date) }
            loadFields()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func undo(_ id: Match.ID) {
        undoMatchID = nil
        do {
            try library.modify(id: tournamentID) { t, date in try t.reopenMatch(id, now: date) }
            matchID = id
            loadFields()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func showUndo(for id: Match.ID) {
        withAnimation { undoMatchID = id }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undoMatchID == id {
                withAnimation { undoMatchID = nil }
            }
        }
    }

    /// Prochain match non terminé après celui-ci (dans l'ordre de jeu), sinon le premier non terminé.
    private func nextPendingMatch(after id: Match.ID) -> Match.ID? {
        guard let matches = tournament?.orderedMatches else { return nil }
        let start = (matches.firstIndex { $0.id == id } ?? -1) + 1
        let pending = matches[start...].first { $0.state != .completed } ?? matches.first { $0.state != .completed }
        return pending?.id
    }

    // MARK: - Textes

    private func teamLabel(_ team: Team, tournament: Tournament, value: Int?) -> String {
        let names = team.players.compactMap { tournament.player($0)?.name }.formatted(.list(type: .and))
        if let value {
            return String(localized: "\(names) : \(value) points")
        }
        return String(localized: "\(names) : pas de score")
    }

    private func outcomeText(_ score: Score) -> String {
        switch score.outcome {
        case .teamAWins, .teamBWins: String(localized: "Score valide.")
        case .draw: String(localized: "Score valide : match nul.")
        }
    }

    private func hint(for rule: ScoringRule) -> String {
        switch rule {
        case .fixedTotal(let points):
            String(localized: "Tapez le score d'une équipe : l'autre est calculé (total \(points)).")
        case .raceTo(let points):
            String(localized: "Tapez le score du perdant : le gagnant reçoit \(points).")
        case .free:
            String(localized: "Tapez le score de chaque équipe.")
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? ScoreEntryError else {
            return String(localized: "L'enregistrement a échoué. Les scores précédents sont intacts.")
        }
        switch error {
        case .alreadyValidated:
            return String(localized: "Ce match a déjà été validé. Utilisez « Corriger le score » pour le modifier.")
        case .invalidScore(let scoreError):
            return scoreError.message
        case .roundLocked:
            return String(localized: "Le tour suivant a déjà été composé avec ce résultat : corrigez le score plutôt que d'annuler la validation.")
        case .notValidated:
            return String(localized: "Ce match n'a pas encore été validé.")
        case .matchNotFound, .tournamentNotStarted:
            return String(localized: "Ce match n'est plus disponible.")
        }
    }
}

extension ScoreError {
    var message: String {
        switch self {
        case .negative:
            String(localized: "Un score ne peut pas être négatif.")
        case .totalMustEqual(let points):
            String(localized: "Les deux scores doivent totaliser \(points) points.")
        case .winnerMustReach(let points):
            String(localized: "L'équipe gagnante doit atteindre \(points) points.")
        case .noDrawAllowed:
            String(localized: "Pas de match nul avec cette règle : une seule équipe atteint le score.")
        case .empty:
            String(localized: "Saisissez au moins un point.")
        case .tooHigh(let maximum):
            String(localized: "Score trop élevé (\(maximum) maximum).")
        }
    }
}
