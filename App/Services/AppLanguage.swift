import Foundation

/// Langue de l'app (français ou anglais), choisie avec les drapeaux de l'accueil.
///
/// Le choix s'applique immédiatement : les textes SwiftUI suivent la langue de
/// l'environnement, et les textes construits dans le code passent par `Bundle.appLanguage`.
/// Les noms de marque (EAGLE, OWN THE COURT.) ne sont pas traduits.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case fr
    case en

    static let storageKey = "eagle.language"

    var id: String { rawValue }

    /// Choix enregistré, sinon la langue de l'iPhone (anglais si l'iPhone est en anglais, français sinon).
    static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: stored) {
            return language
        }
        return Locale.preferredLanguages.first?.hasPrefix("en") == true ? .en : .fr
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        // Pour les textes du système (boutons Apple, alertes) dès le prochain lancement.
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    var locale: Locale {
        Locale(identifier: self == .fr ? "fr_FR" : "en_GB")
    }

    var flag: String {
        self == .fr ? "🇫🇷" : "🇬🇧"
    }

    /// Nom de la langue dans cette langue (pour VoiceOver).
    var name: String {
        self == .fr ? "Français" : "English"
    }

    fileprivate var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

extension Bundle {
    private static let languageBundles = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { ($0, $0.bundle) })

    /// Traductions de la langue choisie dans l'app.
    static var appLanguage: Bundle {
        languageBundles[AppLanguage.current] ?? .main
    }
}

extension Locale {
    /// Formats (dates, nombres, listes) de la langue choisie dans l'app.
    static var appLanguage: Locale { AppLanguage.current.locale }
}
