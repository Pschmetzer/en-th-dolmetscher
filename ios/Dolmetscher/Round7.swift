// Round7.swift – kleine, testbare Bausteine der Runde 7 (Barrierefreiheit).
import SwiftUI
import UIKit

/// „Bewegung reduzieren“: Animationen entfallen, Inhalte springen direkt.
enum Motion {
    static func animation(_ a: Animation? = .default, reduce: Bool) -> Animation? { reduce ? nil : a }
}

/// VoiceOver-Beschreibung einer Blase. Quelle und Übersetzung tragen ihre eigene Sprache
/// (Sprachattribut der Bedienungshilfen), sonst läse VoiceOver Thai oder Japanisch mit der Stimme der Oberflächensprache.
enum A11yLabel {
    static func build(src: Lang, text: String, target: Lang, translation: String?, extras: [String], uiLang: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func plain(_ s: String) { out.append(NSAttributedString(string: s)) }
        func spoken(_ s: String, _ lang: Lang) {
            out.append(NSAttributedString(string: s, attributes: [.accessibilitySpeechLanguage: lang.voiceLocale]))
        }
        plain("\(src.name(in: uiLang)): "); spoken(text, src)
        if let translation {
            plain(". \(target.name(in: uiLang)): "); spoken(translation, target)
        }
        for e in extras where !e.isEmpty { plain(". " + e) }
        return out
    }

    /// Für `.accessibilityLabel`; fällt bei einem Umwandlungsfehler auf reinen Text zurück.
    static func text(_ ns: NSAttributedString) -> Text {
        if let a = try? AttributedString(ns, including: \.accessibility) { return Text(a) }
        return Text(ns.string)
    }
}
