import SwiftUI
import UIKit

/// Identité EAGLE — « OWN THE COURT. »
///
/// Base noir carbone (l'app est toujours en mode sombre), vert électrique pour les actions,
/// or réservé à l'Aigle (le numéro 1), argent et bronze pour les 2ᵉ et 3ᵉ places.
/// Contrastes vérifiés (WCAG AA ≥ 4,5:1) : texte blanc, vert, or, argent et bronze sur fond
/// carbone et sur cartes ; texte carbone sur bouton vert (15:1).
enum Theme {
    // Palette de marque
    static var carbon: Color { Color(hex: 0x0B0D10) }
    static var graphite: Color { Color(hex: 0x171A20) }
    static var accent: Color { Color(hex: 0xC6FF00) }
    static var ink: Color { Color(hex: 0xF5F7FA) }
    static var gold: Color { Color(hex: 0xFFC857) }
    static var silver: Color { Color(hex: 0xD6DCE4) }
    static var bronze: Color { Color(hex: 0xD9945B) }

    // Or « premium » : reflets clair → profond, pour l'Aigle et les bordures dorées.
    static var goldLight: Color { Color(hex: 0xFFE29A) }
    static var goldDeep: Color { Color(hex: 0xB8862B) }
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Rôles
    static var background: Color { carbon }
    static var card: Color { graphite }
    /// Bordure discrète des cartes.
    static var stroke: Color { Color.white.opacity(0.08) }
    /// Texte posé sur le vert électrique.
    static var onAccent: Color { carbon }
    static var secondaryText: Color { Color(hex: 0xA4ACB9) }
    static var warning: Color { Color(hex: 0xFFB020) }
    static var error: Color { Color(hex: 0xFF6B6B) }

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
            .background(Theme.background)
    }
}
