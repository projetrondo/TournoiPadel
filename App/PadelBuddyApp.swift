import PadelCore
import SwiftUI

@main
struct PadelBuddyApp: App {
    @State private var library: TournamentLibrary

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let store: any TournamentStore
        if arguments.contains("-ui-testing") {
            // Tests d'interface et captures d'écran : aucune donnée réelle n'est lue ni écrite.
            store = InMemoryTournamentStore(arguments.contains("-demo-data") ? DemoData.tournaments() : [])
        } else {
            let directory = URL.applicationSupportDirectory
                .appending(path: "Tournaments", directoryHint: .isDirectory)
            store = FileTournamentStore(directory: directory)
        }
        _library = State(initialValue: TournamentLibrary(store: store))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(library)
                .tint(Theme.green)
                .task { library.loadIfNeeded() }
        }
    }
}
