import SwiftUI
import UIKit

/// Identité visuelle : vert des terrains de padel, jaune de la balle, fonds système iOS.
/// Contrastes vérifiés (WCAG AA, ≥ 4,5:1) : texte vert sur fond clair 5,8 ; texte blanc sur
/// bouton 5,8 (clair) et 5,0 (sombre) ; avertissement orange 5,1 sur fond clair.
enum Theme {
    /// Texte et accents.
    static var green: Color { Color(light: 0x137445, dark: 0x34C77B) }
    /// Fond des boutons principaux (texte blanc).
    static var buttonFill: Color { Color(light: 0x137445, dark: 0x17804A) }
    static var deepGreen: Color { Color(light: 0x0F5132, dark: 0x0B3D26) }
    static var ball: Color { Color(light: 0xC6DC00, dark: 0xDDF23A) }
    static var warning: Color { Color(light: 0xC24400, dark: 0xFF9F0A) }
    static var error: Color { Color(light: 0xC4161C, dark: 0xFF6961) }

    static var background: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    static let cornerRadius: CGFloat = 16
    /// Hauteur minimale des boutons principaux : confortable au pouce, au bord du terrain.
    static let buttonHeight: CGFloat = 56
}

extension Color {
    /// Couleur qui s'adapte au mode clair / sombre, à partir de valeurs hexadécimales.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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
