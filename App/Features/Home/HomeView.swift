import PadelCore
import SwiftUI

enum HomeRoute: Hashable {
    case tournament(Tournament.ID)
    case finishedList
}

struct HomeView: View {
    @Environment(TournamentLibrary.self) private var library
    @State private var path: [HomeRoute] = []
    @State private var isCreating = false
    @State private var isJoining = false

    /// Nombre de tournois terminés affichés directement sur l'accueil.
    private let finishedPreviewCount = 3

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LogoView()
                        .padding(.top, 8)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .tournament(let id):
                    TournamentDetailView(tournamentID: id)
                case .finishedList:
                    TournamentListView(title: String(localized: "Tournois terminés"), tournaments: library.finishedTournaments)
                }
            }
            .task {
                library.loadIfNeeded()
                if let status = LaunchOptions.openStatus, path.isEmpty,
                   let tournament = library.tournaments.first(where: { $0.status == status }) {
                    path = [.tournament(tournament.id)]
                }
            }
            .sheet(isPresented: $isCreating) {
                CreateTournamentView { tournament in
                    path.append(.tournament(tournament.id))
                }
            }
            .sheet(isPresented: $isJoining) {
                JoinTournamentView()
            }
            .alert(
                "Erreur",
                isPresented: Binding(
                    get: { library.failure != nil },
                    set: { if !$0 { library.failure = nil } }
                ),
                presenting: library.failure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !library.hasLoaded {
            ProgressView("Chargement…")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if library.tournaments.isEmpty {
            ContentUnavailableView {
                Label("Aucun tournoi", systemImage: "trophy")
            } description: {
                Text("Créez votre premier tournoi en quelques secondes, ou rejoignez celui d'un ami.")
            }
            .frame(minHeight: 300)
        } else {
            if library.unreadableFileCount > 0 {
                Label(
                    "\(library.unreadableFileCount) tournoi(s) n'ont pas pu être lus. Ils sont conservés à part.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(Theme.warning)
            }
            if !library.activeTournaments.isEmpty {
                section(title: String(localized: "En cours"), tournaments: library.activeTournaments)
            }
            if !library.finishedTournaments.isEmpty {
                section(
                    title: String(localized: "Terminés"),
                    tournaments: Array(library.finishedTournaments.prefix(finishedPreviewCount))
                )
                if library.finishedTournaments.count > finishedPreviewCount {
                    NavigationLink(value: HomeRoute.finishedList) {
                        Text("Voir les \(library.finishedTournaments.count) tournois terminés")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func section(title: String, tournaments: [Tournament]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(tournaments) { tournament in
                NavigationLink(value: HomeRoute.tournament(tournament.id)) {
                    TournamentRow(tournament: tournament)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Actions principales en bas d'écran, accessibles au pouce.
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                isCreating = true
            } label: {
                Label("Créer un tournoi", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                isJoining = true
            } label: {
                Label("Rejoindre un tournoi", systemImage: "person.2.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

struct TournamentRow: View {
    let tournament: Tournament

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tournament.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    BadgeView(text: tournament.format.title)
                    Text("\(tournament.players.count) joueurs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(tournament.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tournament.statusColor)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(tournament.updatedAt, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TournamentListView: View {
    let title: String
    let tournaments: [Tournament]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(tournaments) { tournament in
                    NavigationLink(value: HomeRoute.tournament(tournament.id)) {
                        TournamentRow(tournament: tournament)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle(title)
    }
}

#Preview {
    HomeView()
        .previewLoaded()
        .environment(TournamentLibrary(store: InMemoryTournamentStore(DemoData.tournaments())))
}

extension View {
    /// Les aperçus n'exécutent pas `PadelBuddyApp` : on déclenche le chargement nous-mêmes.
    func previewLoaded() -> some View {
        modifier(PreviewLoader())
    }
}

private struct PreviewLoader: ViewModifier {
    @Environment(TournamentLibrary.self) private var library

    func body(content: Content) -> some View {
        content.task { library.loadIfNeeded() }
    }
}
