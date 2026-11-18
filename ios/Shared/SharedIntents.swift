// SharedIntents.swift – App Intents, die App und Widget-Erweiterung kennen müssen (Kontrollzentrum, Widget-Knöpfe,
// Live-Aktivität). Sie laufen immer in der App (Vordergrund bzw. LiveActivityIntent); die Erweiterung kompiliert
// nur die Beschreibung, daher die Teile mit `InterpreterModel` hinter `#if !WIDGET_EXT`.
import ActivityKit
import AppIntents
import Foundation

struct StartInterpreterIntent: AppIntent {
    static let title: LocalizedStringResource = "Start interpreting"
    static let description = IntentDescription("Opens Dolmetscher and starts listening.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        InterpreterModel.shared.start()
        #endif
        return .result()
    }
}

/// Knopf „Stopp“ in der Live-Aktivität und der Dynamic Island.
struct StopListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop interpreting"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        InterpreterModel.shared.stop()
        #endif
        return .result()
    }
}

/// Satz aus dem eingebauten Satzbuch vorlesen (Schnellsätze-Widget). Öffnet die App: nur sie kann sprechen.
struct SayPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "Say phrase"
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Phrase")
    var phraseID: String

    init() {}
    init(phraseID: String) { self.phraseID = phraseID }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        InterpreterModel.shared.sayBuiltIn(phraseID)
        #endif
        return .result()
    }
}

/// Steuerelement/Kurzbefehl „Sprachpaar wechseln“ (meine Sprache und Partnersprache tauschen). Öffnet die App, damit
/// die laufende Sitzung das neue Paar sofort übernimmt.
struct SwapLanguagePairIntent: AppIntent {
    static let title: LocalizedStringResource = "Swap language pair"
    static let description = IntentDescription("Swaps your language and your partner's language.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !WIDGET_EXT
        let m = InterpreterModel.shared
        m.pair = PairSwitch.swapped(m.pair)
        return .result(dialog: "\(String(format: T("sc_swapped"), m.pair.mine.flag + " → " + m.pair.partner.flag))")
        #else
        return .result(dialog: "")
        #endif
    }
}

/// Steuerelement/Kurzbefehl „Letzte Übersetzung vorlesen“ (liest den jüngsten übersetzten Satz noch einmal vor).
struct SpeakLastTranslationIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak last translation"
    static let description = IntentDescription("Reads the last translation out loud again.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        InterpreterModel.shared.speakLast()
        #endif
        return .result()
    }
}

/// Live-Aktivität beim Zuhören: letzter Satz und Mikrofonstatus. Daten kommen über ActivityKit (kein App Group).
struct ListeningActivityAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable, Sendable { case listening, hearing, speaking, paused, ready, interrupted }

    struct ContentState: Codable, Hashable, Sendable {
        var status: Status
        /// Bereits in der Oberflächensprache der App
        var statusText: String
        var source: String
        var translation: String
        var srcFlag: String
        var dstFlag: String
        /// Gerät gesperrt: Sätze ausgelassen, nur der Status (optional, damit ältere Zustände lesbar bleiben).
        var hidden: Bool? = nil
    }

    /// „🇬🇧 ⇄ 🇹🇭“
    var pair: String
}

extension ListeningActivityAttributes.Status {
    var symbol: String {
        switch self {
        case .listening: return "mic.fill"
        case .hearing: return "waveform"
        case .speaking: return "speaker.wave.2.fill"
        case .paused: return "pause.fill"
        case .ready: return "hand.tap.fill"
        case .interrupted: return "phone.down.fill"
        }
    }
}
