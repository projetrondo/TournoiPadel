import PadelCore
import SwiftUI

/// Saisie du score d'un match, pensée pour le bord du terrain.
///
/// On touche une équipe, puis son score parmi les cases 0, 1, 2… jusqu'au maximum possible.
/// Quand la règle permet de déduire l'autre score (total fixe, ou perdant en « premier à N »),
/// le match est enregistré aussitôt ; sinon on choisit ensuite le score de l'autre équipe.
/// Après l'enregistrement, retour à la liste des matchs.
struct ScoreEntryView: View {
    enum Side: Hashable {
        case teamA
        case teamB

        var other: Side { self == .teamA ? .teamB : .teamA }
    }

    let tournamentID: Tournament.ID

    @Environment(TournamentLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var matchID: Match.ID
    @State private var scoreA: Int?
    @State private var scoreB: Int?
    @State private var selected: Side = .teamA
    /// Équipes dont le score a été choisi pendant cette saisie (score libre : il faut les deux).
    @State private var picked: Set<Side> = []
    /// Score libre : cases jusqu'à 99 au lieu de 40.
    @State private var showsHighScores = false
    @State private var isCorrecting = false
    @State private var isSaving = false
    @State private var isConfirmingReopen = false
    @State private var validationCount = 0
    @State private var errorMessage: String?

    /// Score libre : cases affichées d'emblée (les matchs au temps dépassent rarement 40).
    private static let usualFreeMaximum = 40

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
            .eagleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: validationCount)
            .onAppear { loadFields() }
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
                HStack {
                    Text("Tour \(round) · Terrain \(match.court)")
                        .font(.headline)
                    Spacer()
                    BadgeView(text: isCorrecting ? String(localized: "Correction", bundle: .appLanguage) : match.state.title,
                              color: isCorrecting ? Theme.warning : match.state.color)
                }

                HStack(spacing: 12) {
                    teamPanel(.teamA, team: match.teamA, value: scoreA, tournament: tournament, editable: editable)
                    Text("–")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.secondary)
                    teamPanel(.teamB, team: match.teamB, value: scoreB, tournament: tournament, editable: editable)
                }

                if editable {
                    numberPicker(tournament, match)
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
        } label: {
            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    ForEach(team.players, id: \.self) { id in
                        Text(tournament.player(id)?.name ?? "?")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Text(value.map { "\($0)" } ?? "–")
                    .font(.system(size: 52, weight: .black).width(.condensed).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.10) : Theme.card)
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

    /// Cases 0, 1, 2… jusqu'au score maximum, pour l'équipe sélectionnée.
    private func numberPicker(_ tournament: Tournament, _ match: Match) -> some View {
        let team = selected == .teamA ? match.teamA : match.teamB
        let names = team.players.compactMap { tournament.player($0)?.name }.formatted(.list(type: .and).locale(.appLanguage))
        let current = selected == .teamA ? scoreA : scoreB
        let isFree = tournament.settings.scoring.points == nil
        let maximum = isFree && !showsHighScores ? Self.usualFreeMaximum : maximumScore(tournament)
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Score de \(names)")
                    .font(Theme.display(.headline, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                Text("Touchez une équipe, puis son score.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let score = currentScore, case .invalid(let error) = tournament.validation(of: score) {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                    .font(.subheadline)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(0...maximum, id: \.self) { value in
                    let isCurrent = current == value
                    Button {
                        pick(value)
                    } label: {
                        Text(verbatim: "\(value)")
                            .font(.system(size: 24, weight: .heavy).width(.condensed).monospacedDigit())
                            .foregroundStyle(isCurrent ? Theme.onAccent : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isCurrent ? Theme.accent : Theme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .accessibilityLabel(String(localized: "\(names) : \(value) points", bundle: .appLanguage))
                }
            }
            if isFree, !showsHighScores {
                Button("Plus de \(Self.usualFreeMaximum) points") { showsHighScores = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func actions(_ tournament: Tournament, _ match: Match) -> some View {
        if isCorrecting {
            Button("Abandonner la correction") {
                isCorrecting = false
                loadFields()
            }
            .buttonStyle(SecondaryButtonStyle())
        } else if match.state == .completed {
            Button {
                isCorrecting = true
                picked = []
                selected = .teamA
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

    // MARK: - Saisie

    private var currentScore: Score? {
        guard let scoreA, let scoreB else { return nil }
        return Score(scoreA, scoreB)
    }

    private func maximumScore(_ tournament: Tournament) -> Int {
        tournament.settings.scoring.points ?? ScoringRule.maxFreeScore
    }

    /// Score choisi pour l'équipe sélectionnée : l'autre est déduit quand la règle le permet,
    /// puis le match est enregistré s'il est complet ; sinon on passe à l'autre équipe.
    private func pick(_ value: Int) {
        guard let tournament, let match, !isSaving else { return }
        markInProgressIfNeeded()
        let side = selected
        var deducedOther = false
        withAnimation(.snappy(duration: 0.15)) {
            set(value, for: side)
            switch tournament.settings.scoring {
            case .fixedTotal(let points):
                set(points - value, for: side.other)
                deducedOther = true
            case .raceTo(let points):
                if value < points {
                    set(points, for: side.other)
                    deducedOther = true
                } else if self.value(for: side.other) == points {
                    // Les deux équipes ne peuvent pas atteindre N : il reste à choisir le perdant.
                    set(nil, for: side.other)
                }
            case .free:
                break
            }
        }
        picked.insert(side)
        if deducedOther { picked.insert(side.other) }

        guard picked.count == 2, let score = currentScore, tournament.validation(of: score).isValid else {
            selected = side.other
            return
        }
        if match.state == .completed {
            guard score != match.score else {
                isCorrecting = false
                return
            }
            saveCorrection(score)
        } else {
            validate(score)
        }
    }

    private func value(for side: Side) -> Int? {
        side == .teamA ? scoreA : scoreB
    }

    private func set(_ value: Int?, for side: Side) {
        if side == .teamA { scoreA = value } else { scoreB = value }
    }

    private func loadFields() {
        let score = match?.score
        scoreA = score?.teamA
        scoreB = score?.teamB
        selected = .teamA
        picked = []
        isCorrecting = false
    }

    private func markInProgressIfNeeded() {
        guard let match, match.state == .scheduled else { return }
        try? library.modify(id: tournamentID) { t, date in try t.markInProgress(match.id, now: date) }
    }

    // MARK: - Actions

    private func validate(_ score: Score) {
        isSaving = true
        defer { isSaving = false }
        let id = matchID
        do {
            try library.modify(id: tournamentID) { t, date in try t.validateScore(id, score: score, now: date) }
            validationCount += 1
            // Retour à la liste des matchs pour saisir les suivants.
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func saveCorrection(_ score: Score) {
        isSaving = true
        defer { isSaving = false }
        let id = matchID
        do {
            try library.modify(id: tournamentID) { t, date in try t.correctScore(id, score: score, now: date) }
            validationCount += 1
            isCorrecting = false
            dismiss()
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

    // MARK: - Textes

    private func teamLabel(_ team: Team, tournament: Tournament, value: Int?) -> String {
        let names = team.players.compactMap { tournament.player($0)?.name }.formatted(.list(type: .and).locale(.appLanguage))
        if let value {
            return String(localized: "\(names) : \(value) points", bundle: .appLanguage)
        }
        return String(localized: "\(names) : pas de score", bundle: .appLanguage)
    }

    static func message(for error: Error) -> String {
        guard let error = error as? ScoreEntryError else {
            return String(localized: "L'enregistrement a échoué. Les scores précédents sont intacts.", bundle: .appLanguage)
        }
        switch error {
        case .alreadyValidated:
            return String(localized: "Ce match a déjà été validé. Utilisez « Corriger le score » pour le modifier.", bundle: .appLanguage)
        case .invalidScore(let scoreError):
            return scoreError.message
        case .roundLocked:
            return String(localized: "Le tour suivant a déjà été composé avec ce résultat : corrigez le score plutôt que d'annuler la validation.", bundle: .appLanguage)
        case .notValidated:
            return String(localized: "Ce match n'a pas encore été validé.", bundle: .appLanguage)
        case .matchNotFound, .tournamentNotStarted:
            return String(localized: "Ce match n'est plus disponible.", bundle: .appLanguage)
        }
    }
}

extension ScoreError {
    var message: String {
        switch self {
        case .negative:
            String(localized: "Un score ne peut pas être négatif.", bundle: .appLanguage)
        case .totalMustEqual(let points):
            String(localized: "Les deux scores doivent totaliser \(points) points.", bundle: .appLanguage)
        case .winnerMustReach(let points):
            String(localized: "L'équipe gagnante doit atteindre \(points) points.", bundle: .appLanguage)
        case .noDrawAllowed:
            String(localized: "Pas de match nul avec cette règle : une seule équipe atteint le score.", bundle: .appLanguage)
        case .empty:
            String(localized: "Saisissez au moins un point.", bundle: .appLanguage)
        case .tooHigh(let maximum):
            String(localized: "Score trop élevé (\(maximum) maximum).", bundle: .appLanguage)
        }
    }
}
