// StatusColor.swift – Statusfarben mit geprüftem Kontrast (Runde 13). Die systemGreen/-Orange/-Red-Töne erreichen auf
// hellem Grund nur ca. 2:1 bis 3:1; hier gilt je Modus mindestens 4,5:1 gegen weiß und den grauen Gruppengrund.
// tests/test_runde13_ios_a11y.py rechnet die Zahlen unten nach. Die Farbe trägt nie allein den Zustand: Symbol und Text stehen daneben.
import SwiftUI
import UIKit

enum StatusColor {
    typealias RGB = (r: Double, g: Double, b: Double)
    static let okLight: RGB = (0.0, 0.42, 0.18)
    static let okDark: RGB = (0.19, 0.82, 0.35)
    static let warningLight: RGB = (0.66, 0.30, 0.0)
    static let warningDark: RGB = (1.0, 0.62, 0.04)
    static let errorLight: RGB = (0.78, 0.0, 0.07)
    static let errorDark: RGB = (1.0, 0.27, 0.23)
    static let infoLight: RGB = (0.0, 0.35, 0.85)
    static let infoDark: RGB = (0.04, 0.52, 1.0)

    private static func dynamic(_ light: RGB, _ dark: RGB) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: dark.r, green: dark.g, blue: dark.b, alpha: 1)
            : UIColor(red: light.r, green: light.g, blue: light.b, alpha: 1) })
    }

    static let ok = dynamic(okLight, okDark)
    static let warning = dynamic(warningLight, warningDark)
    static let error = dynamic(errorLight, errorDark)
    static let info = dynamic(infoLight, infoDark)
}

extension StatusColor {
    /// Flächen mit weißer Schrift (Mikrofon-Knopf): in beiden Modi die dunkle Variante, sonst fällt Weiß auf Hellgrün durch.
    static let okFill = Color(red: okLight.r, green: okLight.g, blue: okLight.b)
    static let errorFill = Color(red: errorLight.r, green: errorLight.g, blue: errorLight.b)
    static let infoFill = Color(red: infoLight.r, green: infoLight.g, blue: infoLight.b)
}
