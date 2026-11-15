// Intents.swift – Kurzbefehle/Siri/Spotlight/Action-Taste: Dolmetscher starten, Satzbuch, Text übersetzen.
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

struct TranslateTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate English ⇄ Thai"
    static let description = IntentDescription("Translates a text between English and Thai.")

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let src = LanguagePick.ofTyped(text)
        let online = UserDefaults.standard.object(forKey: "allowOnline") as? Bool ?? true
        var out = try await Translator().translate(text, from: src, allowOnline: online).text
        if src == .en {
            let form = Politeness(rawValue: UserDefaults.standard.string(forKey: "politeness") ?? "") ?? .male
            out = form.adjust(out)
        }
        return .result(value: out, dialog: "\(out)")
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
    }
}
