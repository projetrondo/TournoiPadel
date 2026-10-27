import PadelCore
import SwiftUI

@main
struct PadelBuddyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: TournamentLibrary
    @State private var sync: SyncCoordinator
    @State private var sessions: SessionLibrary

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let store: any TournamentStore
        let sessionStore: any SessionStore
        let service: any TournamentSyncService
        if arguments.contains("-ui-testing") {
            // Tests d'interface et captures d'écran : aucune donnée réelle n'est lue ni écrite,
            // et le serveur de partage est simulé en mémoire.
            store = InMemoryTournamentStore(arguments.contains("-demo-data") ? DemoData.tournaments() : [])
            sessionStore = InMemorySessionStore(arguments.contains("-demo-data") ? DemoData.sessions() : [])
            service = InMemorySyncService()
        } else {
            let directory = URL.applicationSupportDirectory
                .appending(path: "Tournaments", directoryHint: .isDirectory)
            store = FileTournamentStore(directory: directory)
            sessionStore = FileSessionStore(directory: URL.applicationSupportDirectory
                .appending(path: "Sessions", directoryHint: .isDirectory))
            service = SyncConfiguration.makeService()
        }
        let library = TournamentLibrary(store: store)
        _library = State(initialValue: library)
        _sessions = State(initialValue: SessionLibrary(store: sessionStore))
        _sync = State(initialValue: SyncCoordinator(library: library, service: service, deviceID: DeviceIdentity.current))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(library)
                .environment(sessions)
                .environment(sync)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .task {
                    library.loadIfNeeded()
                    sessions.loadIfNeeded()
                    sync.startMonitoringNetwork()
                    sync.publishAllPending()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.publishAllPending() }
        }
    }
}

/// Activation du partage CloudKit, pilotée par les réglages de compilation
/// (`CLOUDKIT_ENABLED`, `CLOUDKIT_CONTAINER` dans project.yml) recopiés dans Info.plist.
/// Sans compte Apple Developer, le partage reste désactivé : l'app fonctionne entièrement
/// en local et l'explique à l'utilisateur.
enum SyncConfiguration {
    static var isEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PBCloudKitEnabled") as? String)?.uppercased() == "YES"
    }

    static var containerIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "PBCloudKitContainer") as? String,
              value.hasPrefix("iCloud.") else { return nil }
        return value
    }

    static func makeService() -> any TournamentSyncService {
        guard isEnabled, let containerIdentifier else { return UnavailableSyncService() }
        return CloudKitSyncService(containerIdentifier: containerIdentifier)
    }
}
