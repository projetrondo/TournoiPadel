import SwiftUI
import UIKit

/// Identité visuelle : vert des terrains de padel, jaune de la balle, fonds système iOS.
enum Theme {
    static var green: Color { Color(light: 0x1E9E5A, dark: 0x34C77B) }
    static var deepGreen: Color { Color(light: 0x0F5132, dark: 0x0B3D26) }
    static var ball: Color { Color(light: 0xC6DC00, dark: 0xDDF23A) }
    static var warning: Color { Color.orange }
    static var error: Color { Color.red }

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
