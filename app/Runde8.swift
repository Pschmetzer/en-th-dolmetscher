// Runde 8 (Mac): Fehlerhilfe mit Handlungsvorschlag, Großanzeige, Glossar-Schnelleingabe, Kürzel-Übersicht,
// Verlaufs-Menü der Menüleiste. Nutzt nur Engine-Funktionen, die docs/PROTOKOLL.md kennt.
import SwiftUI
import AppKit

extension Notification.Name {
    static let showBigText = Notification.Name("DolmetscherShowBigText")
    static let showGlossaryAdd = Notification.Name("DolmetscherShowGlossaryAdd")
    static let showShortcuts = Notification.Name("DolmetscherShowShortcuts")
}

/// Einstellungsfenster öffnen (aus Hinweisbändern und Menüs).
@MainActor
func openSettingsWindow() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}

// MARK: Fehlerhilfe

/// Zu jedem Fehlercode der Engine ein konkreter nächster Schritt (Knöpfe im Hinweisband). Regeln: ErrorAdviceLogic.
enum ErrorAdvice {
    typealias Step = ErrorAdviceLogic.Step

    static func advice(for code: String?) -> (hintKey: String, steps: [Step])? {
        ErrorAdviceLogic.advice(for: code).map { ($0.hintKey, $0.steps) }
    }

    static func label(_ s: Step) -> String {
        switch s {
        case .micSettings: return L.t("open_mic_settings")
        case .appSettings: return L.t("settings")
        case .restart: return L.t("restart")
        case .log: return L.t("show_log")
        case .retryAfterNetwork: return L.t("retry")
        case .networkSettings: return R25T.t("open_network_settings")
        case .storageSettings: return R25T.t("open_storage_settings")
        case .help: return R25T.t("open_error_help")
        }
    }

    @MainActor static func run(_ s: Step, _ m: EngineModel) {
        switch s {
        case .micSettings: m.openMicrophoneSettings()
        case .appSettings: openSettingsWindow()
        case .restart, .retryAfterNetwork: m.restart()
        case .log: openLog()
        case .networkSettings, .storageSettings, .help:
            if let u = ErrorAdviceLogic.url(for: s) { NSWorkspace.shared.open(u) }
        }
    }
}

/// Letzter Fehler als Band: Meldung, Handlungsvorschlag und bis zu zwei Knöpfe (statt nur „Log zeigen“).
struct ErrorBanner: View {
    @EnvironmentObject var m: EngineModel
    let error: (msg: String, date: Date)

    private var advice: (hintKey: String, steps: [ErrorAdvice.Step])? {
        guard let code = m.lastErrorCode, m.lastErrorCodeDate == error.date else { return nil }
        return ErrorAdvice.advice(for: code)
    }

    var body: some View {
        let adv = advice
        let time: String = error.date.formatted(date: .omitted, time: .standard)
        var text: String = time + " · " + error.msg
        if let adv { text += " " + R25T.any(adv.hintKey) }
        let firstStep: ErrorAdvice.Step? = adv?.steps.first
        let extra: [ErrorAdvice.Step] = Array((adv?.steps ?? []).dropFirst())
        let mainAction: (String, () -> Void) = firstStep.map { st in
            (ErrorAdvice.label(st), { ErrorAdvice.run(st, m) })
        } ?? (L.t("show_log"), { openLog() })
        return VStack(spacing: 0) {
            NoticeBanner(icon: "exclamationmark.circle.fill", tint: LangStyle.warning, text: text,
                         action: mainAction, onClose: { m.lastError = nil })
            if !extra.isEmpty {
                HStack {
                    Spacer()
                    ForEach(extra, id: \.self) { st in
                        Button(ErrorAdvice.label(st)) { ErrorAdvice.run(st, m) }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 6)
                .background(LangStyle.warning.opacity(0.1))
            }
        }
    }
}

/// Kein Netz: welche Dienste betroffen sind und was jetzt hilft (Ersatzstimme, Offline-Übersetzung).
struct NetDownBanner: View {
    @EnvironmentObject var m: EngineModel
    @State private var hidden = false   // Schließen gilt, bis sich die Menge der betroffenen Dienste ändert
    var body: some View {
        let parts = m.netDown.sorted().map { $0 == "tts" ? L.t("offline_tts") : L.t("offline_translate") }
        Group {
            if !hidden {
                NoticeBanner(icon: "wifi.slash", tint: LangStyle.warning,
                             text: L.t("offline") + ": " + parts.joined(separator: ", ") + ". " + L.t("advice_net"),
                             action: (L.t("settings"), { openSettingsWindow() }), onClose: { hidden = true })
            }
        }
        .onChange(of: m.netDown) { _, _ in hidden = false }
    }
}

// MARK: Großanzeige einer Übersetzung

/// Übersetzung groß lesbar (zum Zeigen über den Tisch), mit Original darunter.
struct BigTextSheet: View {
    let u: Utterance
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    var body: some View {
        VStack(spacing: 16) {
            Text(u.out.isEmpty ? u.text : u.out)
                .font(.system(size: 56 * zoom, weight: .bold))
                .minimumScaleFactor(0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(LangStyle.color(u.out.isEmpty ? u.lang : u.to))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .textSelection(.enabled)
            if !u.out.isEmpty {
                Text(u.text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
            }
            HStack {
                Button { zoom = max(0.5, zoom - 0.15) } label: { Image(systemName: "textformat.size.smaller") }
                    .help(L.t("font_smaller")).accessibilityLabel(L.t("font_smaller"))
                Button { zoom = min(2, zoom + 0.15) } label: { Image(systemName: "textformat.size.larger") }
                    .help(L.t("font_bigger")).accessibilityLabel(L.t("font_bigger"))
                Spacer()
                Button(L.t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 520, idealWidth: 720, minHeight: 300, idealHeight: 420)
    }
}

// MARK: Glossar-Schnelleingabe

/// Namen oder Fachwort ohne Umweg über die Einstellungen ins Glossar (eine Zeile `Wort => Übersetzung`).
struct GlossaryAddSheet: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var translation = ""

    /// Zeile für das Glossar; leer, wenn kein Wort eingegeben ist. Zeilenumbrüche und „=>“ im Wort würden
    /// das Format zerstören und werden entfernt.
    static func line(word: String, translation: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "=>", with: " ").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let w = clean(word), t = clean(translation)
        guard !w.isEmpty else { return "" }
        return t.isEmpty ? w : w + " => " + t
    }

    private func add() {
        let l = Self.line(word: word, translation: translation)
        guard !l.isEmpty else { return }
        m.glossary += (m.glossary.isEmpty || m.glossary.hasSuffix("\n") ? "" : "\n") + l + "\n"
        m.flushGlossary()
        Announcer.post(L.f("glossary_learned", word))
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("glossary_add_title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(L.t("glossary_add_hint")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(L.t("glossary_word"), text: $word).textFieldStyle(.roundedBorder).onSubmit(add)
                .accessibilityLabel(L.t("glossary_word"))
            TextField(L.t("glossary_translation"), text: $translation).textFieldStyle(.roundedBorder).onSubmit(add)
                .accessibilityLabel(L.t("glossary_translation"))
            HStack {
                Spacer()
                Button(L.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L.t("add"), action: add).keyboardShortcut(.defaultAction)
                    .disabled(Self.line(word: word, translation: translation).isEmpty)
            }
        }
        .padding(24).frame(width: 440)
    }
}

// MARK: Kürzel-Übersicht

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private static let baseRows: [(keys: String, key: String)] = [
        ("⌘↩", "shortcut_startstop"), ("⌘P", "pause"), ("⌘.", "stop_speaking"), ("⌘R", "replay_last"),
        ("⌘L", "focus_typing"), ("⌥⌘S", "speak_toggle"), ("⌥⌘L", "direction_cycle"),
        ("⇧⌘C", "copy_last"), ("⌥⌘G", "glossary_add_title"), ("⌘F", "find"), ("⇧⌘E", "export"),
        ("⇧⌘P", "partner_view"), ("⌘1–9", "quick_phrases"), ("⌥⌘1–9", "preset_phrases_short"),
        ("⌘+ / ⌘− / ⌘0", "font_size"), ("⌥⌘Z", "undo_delete"),
        ("Space", "shortcut_startstop"), ("⌥⌘M", "mini_title"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("shortcuts_title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, r in
                        GridRow {
                            Text(r.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                            Text(L.t(r.key))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            HStack { Spacer(); Button(L.t("close")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(minWidth: 460, idealWidth: 540, maxWidth: 720, minHeight: 360, idealHeight: 520, maxHeight: 640)
    }
    /// Feste Kürzel plus die (einstellbaren) globalen Kürzel mit ihren aktuellen Buchstaben.
    static var rows: [(keys: String, key: String)] {
        let g = HotKeyLogic.configured()
        let global: [(keys: String, key: String)] = HotKeyLogic.actions.compactMap { a in
            g[a.id].map { (HotKeyLogic.display($0), a.labelKey) }
        }
        return baseRows + [("⌘/", "shortcuts_title")] + global
    }
}

// MARK: Menüleiste: letzte Übersetzungen

/// Die letzten Übersetzungen zum schnellen Kopieren, ohne das Fenster zu öffnen.
struct RecentTranslationsMenu: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        let recent = Array(m.items.filter { !$0.pending && !$0.out.isEmpty }.suffix(5).reversed())
        if recent.isEmpty {
            Text(L.t("menu_no_history"))
        } else {
            Menu(L.t("menu_recent")) {
                ForEach(recent) { u in
                    Button(String(u.out.prefix(60))) { copyToPasteboard(u.out) }
                }
            }
        }
    }
}
