import PadelCore
import SwiftUI

@main
struct PadelBuddyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: TournamentLibrary
    @State private var sync: SyncCoordinator
    @State private var sessions: SessionLibrary
    @State private var accounts: AccountCenter
    /// Langue choisie avec les drapeaux de l'accueil ; changer de langue reconstruit l'interface.
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.current.rawValue

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let store: any TournamentStore
        let sessionStore: any SessionStore
        let service: any TournamentSyncService
        if arguments.contains("-ui-testing") {
            // Captures d'écran : français, sauf `-demo-language en`.
            AppLanguage.select(LaunchOptions.language ?? .fr)
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
        let sessions = SessionLibrary(store: sessionStore)
        _sessions = State(initialValue: sessions)
        if arguments.contains("-ui-testing") {
            // Compte simulé : `-demo-account` affiche un compte connecté, sans réseau.
            let signedIn = arguments.contains("-demo-account")
            _accounts = State(initialValue: AccountCenter(
                backend: InMemoryBackend(signedIn: signedIn),
                library: library,
                sessions: sessions,
                defaults: UserDefaults(suiteName: "ui-testing") ?? .standard,
                storedRefreshToken: signedIn ? "jeton-demo" : nil
            ))
        } else {
            _accounts = State(initialValue: AccountCenter(
                backend: AccountConfiguration.apiURL.map { EagleAPI(baseURL: $0) },
                library: library,
                sessions: sessions,
                storedRefreshToken: Keychain.refreshToken(),
                saveRefreshToken: { Keychain.setRefreshToken($0) }
            ))
        }
        _sync = State(initialValue: SyncCoordinator(library: library, service: service, deviceID: DeviceIdentity.current))
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .fr
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.locale, language.locale)
                .id(language)
                .environment(library)
                .environment(sessions)
                .environment(accounts)
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
            if phase == .active {
                sync.publishAllPending()
                accounts.scheduleBackup(after: .zero)
            }
        }
    }
}

/// Adresse de l'API EAGLE (comptes et sauvegarde), réglage `EAGLE_API_URL` de project.yml
/// recopié dans Info.plist. Vide : pas de compte, l'app reste entièrement locale.
enum AccountConfiguration {
    static var apiURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "EagleAPIURL") as? String,
              value.hasPrefix("https://"), let url = URL(string: value.hasSuffix("/") ? value : value + "/") else { return nil }
        return url
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
