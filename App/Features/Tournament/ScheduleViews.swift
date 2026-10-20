import PadelCore
import SwiftUI

/// Programme complet : un bloc par tour, une carte par match.
struct ScheduleView: View {
    let tournament: Tournament
    /// Action au toucher d'un match (ouvre la saisie du score).
    var onSelect: ((Match) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tour en cours en premier pour un accès immédiat au bord du terrain.
            ForEach(orderedRounds, id: \.index) { round in
                RoundSection(
                    tournament: tournament,
                    round: round,
                    isCurrent: round.index == tournament.currentRound?.index,
                    onSelect: onSelect
                )
            }
        }
    }

    private var orderedRounds: [Round] {
        guard let current = tournament.currentRound?.index else { return tournament.rounds }
        let upcoming = tournament.rounds.filter { $0.index >= current }
        let played = tournament.rounds.filter { $0.index < current }.reversed()
        return upcoming + played
    }
}

struct RoundSection: View {
    let tournament: Tournament
    let round: Round
    let isCurrent: Bool
    var onSelect: ((Match) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tour \(round.index)")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if isCurrent {
                    BadgeView(text: String(localized: "En cours"))
                } else if round.isComplete {
                    BadgeView(text: String(localized: "Terminé"), color: .secondary)
                }
            }
            ForEach(round.matches.sorted { $0.court < $1.court }) { match in
                if let onSelect {
                    Button {
                        onSelect(match)
                    } label: {
                        MatchCard(tournament: tournament, match: match)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(match.state == .completed ? "Voir ou corriger le score" : "Saisir le score")
                } else {
                    MatchCard(tournament: tournament, match: match)
                }
            }
            if !round.resting.isEmpty {
                Label {
                    Text("En pause : \(names(round.resting))")
                } icon: {
                    Image(systemName: "cup.and.saucer.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func names(_ ids: [Player.ID]) -> String {
        ids.compactMap { tournament.player($0)?.name }.formatted(.list(type: .and))
    }
}

struct MatchCard: View {
    let tournament: Tournament
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Terrain \(match.court)", systemImage: "square.split.2x1")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.green)
                Spacer()
                BadgeView(text: match.state.title, color: match.state.color)
            }
            HStack(alignment: .center, spacing: 12) {
                teamView(match.teamA, alignment: .leading)
                VStack(spacing: 2) {
                    if let score = match.score {
                        Text("\(score.teamA) – \(score.teamB)")
                            .font(.title2.weight(.heavy).monospacedDigit())
                    } else {
                        Text("contre")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 64)
                teamView(match.teamB, alignment: .trailing)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func teamView(_ team: Team, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            ForEach(team.players, id: \.self) { id in
                Text(tournament.player(id)?.name ?? "?")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// Compromis du planning, expliqués simplement.
struct CompromiseNotice: View {
    let compromises: [ScheduleCompromise]

    var body: some View {
        if !compromises.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(compromises, id: \.self) { compromise in
                    Label(compromise.message, systemImage: "info.circle.fill")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .cardStyle()
        }
    }
}

extension MatchState {
    var title: String {
        switch self {
        case .scheduled: String(localized: "À jouer")
        case .inProgress: String(localized: "En cours")
        case .completed: String(localized: "Terminé")
        }
    }

    var color: Color {
        switch self {
        case .scheduled: .secondary
        case .inProgress: Theme.warning
        case .completed: Theme.green
        }
    }
}

extension ScheduleCompromise {
    var message: String {
        switch self {
        case .unequalMatches(let range):
            String(localized: "Selon les joueurs, \(range.lowerBound) ou \(range.upperBound) matchs : le nombre de tours ne permet pas une répartition parfaite.")
        case .repeatedPartners(let pairs, let maxTimes):
            String(localized: "\(pairs) duo(s) joueront ensemble jusqu'à \(maxTimes) fois. Le programme limite ces répétitions au strict nécessaire.")
        }
    }
}
