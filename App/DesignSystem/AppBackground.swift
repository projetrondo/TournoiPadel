import SwiftUI

/// Fond d'écran de l'app, choisi dans les réglages : une couleur unie.
///
/// Les teintes de couleur sont foncées pour que le texte clair reste lisible ; avec le blanc,
/// l'app passe en apparence claire (texte foncé, couleurs adaptées).
enum AppBackground: String, CaseIterable, Identifiable, Sendable {
    case carbon
    case white
    case gray
    case blue
    case green
    case red
    case orange
    case yellow
    case purple
    case pink

    static let storageKey = "eagle.background"

    /// Fond clair : l'app s'affiche en apparence claire.
    var isLight: Bool { self == .white }

    /// Fond enregistré (noir si aucun choix).
    static var current: AppBackground {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppBackground.init(rawValue:)) ?? .carbon
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carbon: String(localized: "Noir", bundle: .appLanguage)
        case .white: String(localized: "Blanc", bundle: .appLanguage)
        case .gray: String(localized: "Gris", bundle: .appLanguage)
        case .blue: String(localized: "Bleu", bundle: .appLanguage)
        case .green: String(localized: "Vert", bundle: .appLanguage)
        case .red: String(localized: "Rouge", bundle: .appLanguage)
        case .orange: String(localized: "Orange", bundle: .appLanguage)
        case .yellow: String(localized: "Jaune", bundle: .appLanguage)
        case .purple: String(localized: "Violet", bundle: .appLanguage)
        case .pink: String(localized: "Rose", bundle: .appLanguage)
        }
    }

    var color: Color {
        switch self {
        case .carbon: Theme.carbon
        case .white: Color(hex: 0xF2F3F5)
        case .gray: Color(hex: 0x2A2E35)
        case .blue: Color(hex: 0x0F2A5C)
        case .green: Color(hex: 0x0E3B26)
        case .red: Color(hex: 0x5A1414)
        case .orange: Color(hex: 0x6B3410)
        case .yellow: Color(hex: 0x5C4A0E)
        case .purple: Color(hex: 0x3A1E5E)
        case .pink: Color(hex: 0x5E1E44)
        }
    }
}

/// Le fond choisi, en plein écran (noir si aucun choix ou ancien réglage inconnu).
struct EagleBackgroundView: View {
    @AppStorage(AppBackground.storageKey) private var stored = AppBackground.carbon.rawValue

    var body: some View {
        (AppBackground(rawValue: stored) ?? .carbon).color
            .accessibilityHidden(true)
    }
}

extension View {
    /// Fond d'écran choisi dans les réglages, sous tout l'écran.
    func eagleBackground() -> some View {
        background { EagleBackgroundView().ignoresSafeArea() }
    }
}
