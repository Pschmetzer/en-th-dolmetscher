// Intents.swift – Kurzbefehle/Siri/Spotlight/Action-Taste: Dolmetscher starten, Satzbuch, Text übersetzen, Notruf-Satz.
import AppIntents
import Foundation

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
        let online = OfflineMode.allowsOnline(allowOnline: InterpreterModel.allowOnlineSetting(d), offlineOnly: OfflineMode.setting(d))
        var out: String
        do {
            out = try await Translator().translate(text, from: src, to: pair.other(src), allowOnline: online).text
        } catch {
            // Kurzbefehle zeigen sonst nur „Der Vorgang konnte nicht abgeschlossen werden“.
            throw TranslateIntentError(message: (error as? LocalizedError)?.errorDescription ?? T("err_translate"))
        }
        if pair.other(src) == .th {
            let form = Politeness(rawValue: d.string(forKey: "politeness") ?? "") ?? .male
            out = form.adjust(out)
        }
        return .result(value: out, dialog: "\(out)")
    }
}

/// Fehler für Kurzbefehle mit verständlichem Text (Sprachpaket fehlt, kein Netz, …).
struct TranslateIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
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

/// Sagt einen Text laut in der Partnersprache (Taxi, Kellner): übersetzt aus meiner Sprache und liest vor.
/// Öffnet die App, damit Ausgabe und Verlauf sicher funktionieren.
struct SayInPartnerLanguageIntent: AppIntent {
    static let title: LocalizedStringResource = "Say in partner's language"
    static let description = IntentDescription("Translates a text from your language into your partner's language and says it out loud.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        InterpreterModel.shared.sayInPartner(text)
        return .result()
    }
}

/// Öffnet die Notfallkarte (Allergien, Medizinisches, Kontakt – in der Partnersprache übersetzt).
struct OpenEmergencyCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open emergency card"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        InterpreterModel.shared.sheet = .emergency
        return .result()
    }
}

/// Zeigt die letzte Übersetzung bildschirmfüllend (Taxi: Aktionstaste drücken, Handy hinhalten).
struct ShowLastTranslationIntent: AppIntent {
    static let title: LocalizedStringResource = "Show last translation"
    static let description = IntentDescription("Shows the last translation full screen, ready to show someone.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        InterpreterModel.shared.showLastBig()
        return .result()
    }
}

/// Sagt einen Satz aus dem Satzbuch (eingebaut oder Favorit), gefunden über ein Stichwort („Danke“, „Wie viel kostet das“).
struct SayPhrasebookPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "Say phrasebook phrase"
    static let description = IntentDescription("Finds a phrase in the phrasebook by keyword and says it out loud in the partner's language.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Phrase")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard InterpreterModel.shared.sayPhrasebook(query) else {
            throw TranslateIntentError(message: T("sc_no_phrase"))
        }
        return .result(dialog: "\(String(format: T("sc_said"), query))")
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
        AppShortcut(intent: SayInPartnerLanguageIntent(),
                    phrases: ["Say with \(.applicationName)", "Say it in my partner's language with \(.applicationName)"],
                    shortTitle: "Say in partner's language", systemImageName: "speaker.wave.2.bubble")
        AppShortcut(intent: OpenEmergencyCardIntent(),
                    phrases: ["Open \(.applicationName) emergency card", "Show my \(.applicationName) emergency card"],
                    shortTitle: "Emergency card", systemImageName: "cross.case")
        AppShortcut(intent: ShowLastTranslationIntent(),
                    phrases: ["Show last \(.applicationName) translation", "Show it big with \(.applicationName)"],
                    shortTitle: "Show last translation", systemImageName: "arrow.up.left.and.arrow.down.right")
        AppShortcut(intent: SpeakLastTranslationIntent(),
                    phrases: ["Read it again with \(.applicationName)", "Speak last \(.applicationName) translation"],
                    shortTitle: "Speak last translation", systemImageName: "speaker.wave.2")
        AppShortcut(intent: SwapLanguagePairIntent(),
                    phrases: ["Swap languages with \(.applicationName)", "Switch \(.applicationName) language pair"],
                    shortTitle: "Swap language pair", systemImageName: "arrow.left.arrow.right")
        AppShortcut(intent: SayPhrasebookPhraseIntent(),
                    phrases: ["Say a phrase with \(.applicationName)", "Say a \(.applicationName) phrasebook phrase"],
                    shortTitle: "Say phrasebook phrase", systemImageName: "text.bubble")
        AppShortcut(intent: EmergencyPhraseIntent(),
                    phrases: ["\(.applicationName) emergency", "Emergency with \(.applicationName)"],
                    shortTitle: "Emergency phrase", systemImageName: "sos")
    }
}
