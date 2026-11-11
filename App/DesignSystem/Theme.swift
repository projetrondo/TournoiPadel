import SwiftUI
import UIKit

/// Identité EAGLE — « OWN THE COURT. »
///
/// Base noir carbone (mode sombre, sauf avec le fond blanc), vert électrique pour les actions,
/// or réservé à l'Aigle (le numéro 1), argent et bronze pour les 2ᵉ et 3ᵉ places.
/// Contrastes vérifiés (WCAG AA ≥ 4,5:1) : texte blanc, vert, or, argent et bronze sur fond
/// carbone et sur cartes ; texte carbone sur bouton vert (15:1).
enum Theme {
    // Palette de marque. Chaque couleur a une variante claire, utilisée avec le fond blanc
    // (l'app passe alors en apparence claire) : mêmes rôles, contrastes adaptés au blanc.
    static var carbon: Color { Color(hex: 0x0B0D10) }
    static var graphite: Color { dynamic(dark: 0x171A20, light: 0xFFFFFF) }
    static var accent: Color { dynamic(dark: 0xC6FF00, light: 0x3F7D00) }
    static var ink: Color { dynamic(dark: 0xF5F7FA, light: 0x111418) }
    static var gold: Color { dynamic(dark: 0xFFC857, light: 0x946200) }
    static var silver: Color { dynamic(dark: 0xD6DCE4, light: 0x5F6B7A) }
    static var bronze: Color { dynamic(dark: 0xD9945B, light: 0x9A5626) }

    // Or « premium » : reflets clair → profond, pour l'Aigle et les bordures dorées.
    static var goldLight: Color { dynamic(dark: 0xFFE29A, light: 0xB07A10) }
    static var goldDeep: Color { dynamic(dark: 0xB8862B, light: 0x6E4A00) }
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Rôles
    static var card: Color { graphite }
    /// Fond de base des dégradés (noir carbone, ou blanc en apparence claire).
    static var surface: Color { dynamic(dark: 0x0B0D10, light: 0xF2F3F5) }
    /// Bordure discrète des cartes.
    static var stroke: Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor.black.withAlphaComponent(0.10) : UIColor.white.withAlphaComponent(0.08) })
    }
    /// Texte posé sur le vert des boutons.
    static var onAccent: Color { dynamic(dark: 0x0B0D10, light: 0xFFFFFF) }
    /// Chiffre posé sur les médailles argent et bronze.
    static var onMedal: Color { dynamic(dark: 0x0B0D10, light: 0xFFFFFF) }
    static var secondaryText: Color { dynamic(dark: 0xA4ACB9, light: 0x5B6472) }
    static var warning: Color { dynamic(dark: 0xFFB020, light: 0x9A5C00) }
    static var error: Color { dynamic(dark: 0xFF6B6B, light: 0xC0392B) }

    /// Couleur qui suit l'apparence (sombre par défaut, claire avec le fond blanc).
    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }

    static let cornerRadius: CGFloat = 14
    /// Hauteur minimale des boutons principaux : confortable au pouce, au bord du terrain.
    static let buttonHeight: CGFloat = 56

    /// Typographie sportive : grotesque condensée et grasse pour les titres.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .black) -> Font {
        .system(style, design: .default, weight: weight).width(.condensed)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Formulaires et listes système sur le fond carbone de la marque.
    func eagleScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .eagleBackground()
    }
}
