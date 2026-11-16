// Intents.swift – Kurzbefehle/Siri/Spotlight/Action-Taste: Dolmetscher starten, Satzbuch, Text übersetzen, Notruf-Satz.
import AppIntents
import Foundation

struct StartInterpreterIntent: AppIntent {
    static let title: LocalizedStringResource = "Start interpreting"
    static let description = IntentDescription("Opens Dolmetscher and starts listening.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        InterpreterModel.shared.start()
        return .result()
    }
}

struct OpenPhrasebookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open phrasebook"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        InterpreterModel.shared.sheet = .phrasebook
        return .result()
    }
}

/// Übersetzt zwischen den beiden Sprachen des eingestellten Paars (Standard Englisch ⇄ Thai).
struct TranslateTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate text"
    static let description = IntentDescription("Translates a text between your language and your partner's language (default English ⇄ Thai).")

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let d = UserDefaults.standard
        let pair = InterpreterModel.pairSetting(d)
        let src = LanguagePick.ofTyped(text, pair: pair)
        let online = InterpreterModel.allowOnlineSetting(d)
        var out = try await Translator().translate(text, from: src, to: pair.other(src), allowOnline: online).text
        if pair.other(src) == .th {
            let form = Politeness(rawValue: d.string(forKey: "politeness") ?? "") ?? .male
            out = form.adjust(out)
        }
        return .result(value: out, dialog: "\(out)")
    }
}

/// Notruf in Thailand: öffnet die Notrufnummern und sagt laut „Hilfe! Ich brauche die Polizei“ auf Thai.
/// Gilt unabhängig vom eingestellten Sprachpaar – der Satz ist für Menschen in Thailand gedacht.
struct EmergencyPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "Emergency phrase (Thai)"
    static let description = IntentDescription("Says \"Help, I need the police\" out loud in Thai and shows the Thai emergency numbers 1155 / 1669 / 191.")
    static let supportedModes: IntentModes = .foreground

    static let phrase = "ช่วยด้วย ต้องการตำรวจ"

    @MainActor
    func perform() async throws -> some IntentResult {
        let m = InterpreterModel.shared
        m.sheet = .emergency
        m.announce(Self.phrase, lang: .th)
        return .result()
    }
}

struct DolmetscherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartInterpreterIntent(),
                    phrases: ["Start \(.applicationName)", "Open \(.applicationName) and listen"],
                    shortTitle: "Start interpreting", systemImageName: "mic.fill")
        AppShortcut(intent: OpenPhrasebookIntent(),
                    phrases: ["Open \(.applicationName) phrasebook"],
                    shortTitle: "Phrasebook", systemImageName: "book")
        AppShortcut(intent: TranslateTextIntent(),
                    phrases: ["Translate with \(.applicationName)"],
                    shortTitle: "Translate text", systemImageName: "character.bubble")
        AppShortcut(intent: EmergencyPhraseIntent(),
                    phrases: ["\(.applicationName) emergency", "Emergency with \(.applicationName)"],
                    shortTitle: "Emergency phrase", systemImageName: "sos")
    }
}
