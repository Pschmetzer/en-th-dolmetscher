// SettingsTransfer.swift – Einstellungen als Datei sichern/einspielen (Vorschau vor dem Übernehmen) und
// „Zuletzt geändert“. Die Regeln selbst stehen in SettingsLogic.swift; hier nur UserDefaults, Dateidialoge und Ansicht.
import SwiftUI

/// Liest den aktuellen Stand aus UserDefaults (dort speichert die App jede Einstellung).
enum SettingsStore {
    static func snapshot() -> [String: SettingValue] {
        let ud = UserDefaults.standard
        var out: [String: SettingValue] = [:]
        for sp in SettingsLogic.specs { out[sp.key] = read(sp, ud) }
        return out
    }

    private static func read(_ sp: SettingSpec, _ ud: UserDefaults) -> SettingValue {
        if sp.key == "mineLang" { return .text(Langs.mine) }
        if sp.key == "partnerLang" { return .text(Langs.partner) }
        if sp.key == "uiLang" { return .text(L.lang.rawValue) }
        guard let raw = ud.object(forKey: sp.key) else { return sp.fallback }
        switch sp.fallback {
        case .bool: return (raw as? Bool).map { .bool($0) } ?? sp.fallback
        case .number: return (raw as? Double).map { .number($0) } ?? sp.fallback
        case .text: return (raw as? String).map { .text($0) } ?? sp.fallback
        }
    }

    static func profile(glossary: String) -> SettingsProfile {
        let phrases = UserDefaults.standard.string(forKey: Prefs.quickPhrases) ?? Prefs.pairDefaults
        return SettingsProfile(quickPhrases: phrases, glossary: glossary)
    }
}

/// Merkt, wann sich welche Einstellung zuletzt geändert hat (nur Zeitstempel, nie die Werte).
@MainActor
final class SettingsTracker: ObservableObject {
    static let shared = SettingsTracker()
    private static let logKey = "settingsChangedAt", snapKey = "settingsSnapshot"
    @Published private(set) var log: [String: Date] = [:]
    private var last: [String: SettingValue]?
    private var started = false

    /// Beim App-Start: Stand von der letzten Sitzung laden, Änderungen seitdem stempeln, danach UserDefaults beobachten.
    func start() {
        guard !started else { return }
        started = true
        let ud = UserDefaults.standard
        let times = ud.dictionary(forKey: Self.logKey) as? [String: Double] ?? [:]
        log = times.mapValues { Date(timeIntervalSince1970: $0) }
        if let d = ud.data(forKey: Self.snapKey) { last = try? JSONDecoder().decode([String: SettingValue].self, from: d) }
        refresh()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// `glossary` nur angeben, wenn der aktuelle Text bekannt ist (er liegt in einer Datei, nicht in UserDefaults).
    func refresh(glossary: String? = nil) {
        var now = SettingsStore.snapshot()
        let ud = UserDefaults.standard
        now[SettingsLogic.profilePhrasesKey] = .text(ud.string(forKey: Prefs.quickPhrases) ?? Prefs.pairDefaults)
        if let g = glossary { now[SettingsLogic.profileGlossaryKey] = .text(g) }
        else if let old = last?[SettingsLogic.profileGlossaryKey] { now[SettingsLogic.profileGlossaryKey] = old }
        if let last, last == now { return }
        let next = SettingsLogic.noteChanges(old: last, new: now, log: log, now: Date())
        last = now
        if next != log {
            log = next
            ud.set(next.mapValues { $0.timeIntervalSince1970 }, forKey: Self.logKey)
        }
        if let d = try? JSONEncoder().encode(now) { ud.set(d, forKey: Self.snapKey) }
    }

    func date(_ key: String) -> Date? { log[key] }
}

extension EngineModel {
    /// Übernimmt geprüfte Werte über dieselben Eigenschaften wie die Oberfläche (damit die Engine sie sofort erfährt).
    func applyImported(_ imp: SettingsImport) {
        let v = imp.settings
        applyPair(v)
        applyEngineValues(v)
        applyAppValues(v)
        if let p = imp.profile.quickPhrases { UserDefaults.standard.set(p, forKey: Prefs.quickPhrases) }
        if let g = imp.profile.glossary { glossary = g }
        SettingsTracker.shared.refresh(glossary: glossary)
    }

    private func applyPair(_ v: [String: SettingValue]) {
        let mine = str(v, "mineLang") ?? mineLang
        let partner = str(v, "partnerLang") ?? partnerLang
        guard mine != partner else { return }
        if mineLang != mine { mineLang = mine }
        if partnerLang != partner { partnerLang = partner }
    }

    private func flag(_ v: [String: SettingValue], _ k: String) -> Bool? {
        if case .bool(let b)? = v[k] { return b }
        return nil
    }
    private func num(_ v: [String: SettingValue], _ k: String) -> Double? {
        if case .number(let d)? = v[k] { return d }
        return nil
    }
    private func str(_ v: [String: SettingValue], _ k: String) -> String? {
        if case .text(let t)? = v[k] { return t }
        return nil
    }

    private func applyEngineValues(_ v: [String: SettingValue]) {
        if let x = str(v, "lang") { lang = x }
        if let x = str(v, "model") { model = x }
        if let x = flag(v, "trEN") { trEN = x }
        if let x = flag(v, "trTH") { trTH = x }
        if let x = num(v, "silence") { silence = x }
        if let x = str(v, "sensitivity") { sensitivity = x }
        if let x = flag(v, "denoise") { denoise = x }
        if let x = flag(v, "twoPerson") { twoPerson = x }
        if let x = flag(v, "fastEndpointV2") { fastEndpoint = x }
        if let x = flag(v, "partialText") { partialText = x }
        if let x = flag(v, "pushToTalk") { pushToTalk = x }
        if let x = flag(v, "earcons") { earcons = x }
        if let x = flag(v, "slowMode") { slowMode = x }
        if let x = num(v, "letFinish") { letFinish = x }
        if let x = str(v, "catchUp") { catchUp = x }
        if let x = num(v, "beam") { beam = Int(x) }
        if let x = flag(v, "backTranslate") { backTranslate = x }
        if let x = flag(v, "learnGlossary") { learnGlossary = x }
        if let x = flag(v, "offlineMT") { offlineMT = x }
        if let x = flag(v, "privateMode") { privateMode = x }
        applyVoiceAndTranslation(v)
    }

    private func applyVoiceAndTranslation(_ v: [String: SettingValue]) {
        if let x = flag(v, "speak") { speak = x }
        if let x = str(v, "polite") { polite = x }
        if let x = num(v, "rate") { rate = Int(x) }
        if let x = num(v, "volume") { volume = x }
        if let x = num(v, "ttsRace") { ttsRace = x }
        if let x = flag(v, "llm") { llm = x }
        if let x = str(v, "llmModel") { llmModel = x }
        if let x = str(v, "llmStyle") { llmStyle = x }
        if let x = num(v, "llmBudget") { llmBudget = x }
        if let x = str(v, "preset") { preset = x }
    }

    /// Reine App-Einstellungen: direkt in UserDefaults, die Ansichten lesen sie per @AppStorage.
    private func applyAppValues(_ v: [String: SettingValue]) {
        let ud = UserDefaults.standard
        for sp in SettingsLogic.specs where Self.appOnlyKeys.contains(sp.key) {
            switch v[sp.key] {
            case .bool(let b)?: ud.set(b, forKey: sp.key)
            case .number(let d)?: ud.set(d, forKey: sp.key)
            default: break
            }
        }
        if case .text(let code)? = v["uiLang"] { ud.set(code, forKey: L.key); _ = L.sync(code) }
    }

    private static let appOnlyKeys: Set<String> = [
        "showMenuBar", "spaceToggle", "announceTranslations", "hideFromCapture", "stopMicOnClose", "hotkeyHUD",
        "listenOnLaunch", "fontScale", "alwaysOnTop", "showDetails", "translit", "showQuickPhrases",
    ]
}

/// Abschnitt „Einstellungen sichern“ (Allgemein-Reiter): Datei speichern, Datei laden mit Vorschau, Zuletzt geändert.
struct SettingsTransferSection: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var tracker = SettingsTracker.shared
    @State private var pending: SettingsImport?
    @State private var changes: [SettingChange] = []
    @State private var note = ""

    var body: some View {
        Section {
            HStack {
                Button(L.t("sx_export")) { exportFile() }
                    .help(L.t("sx_export_help"))
                Button(L.t("sx_import")) { chooseFile() }
                    .help(L.t("sx_import_help"))
            }
            Text(L.t("sx_note")).font(.caption).foregroundStyle(.secondary)
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            if pending != nil { preview }
            recentList
        } header: { Text(L.t("sx_title")) }
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(changes.isEmpty ? L.t("sx_nothing") : L.f("sx_preview", changes.count)).font(.headline)
            ForEach(changes, id: \.key) { c in
                Text(Self.describe(c)).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(skipped.enumerated()), id: \.offset) { _, i in
                Text(Self.describe(i)).font(.caption).foregroundStyle(LangStyle.warning)
            }
            HStack {
                Button(L.t("sx_apply")) { apply() }.disabled(changes.isEmpty)
                Button(L.t("cancel"), role: .cancel) { pending = nil; changes = [] }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var skipped: [SettingsIssue] { pending?.issues.filter { !$0.isFatal } ?? [] }

    @ViewBuilder private var recentList: some View {
        let items = SettingsLogic.recent(tracker.log, limit: 5)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("sx_recent")).font(.subheadline)
                ForEach(items, id: \.key) { it in
                    Text(Self.label(it.key) + "  ·  " + Self.when(it.date)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Aktionen

    private func exportFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Dolmetscher-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = SettingsLogic.export(values: SettingsStore.snapshot(),
                                        profile: SettingsStore.profile(glossary: m.glossary), exportedAt: Date())
        do {
            try data.write(to: url, options: .atomic)
            note = L.t("done_short")
        } catch {
            note = L.t("export_failed")
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        note = ""
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { note = L.t("sx_unreadable"); return }
        let imp = SettingsLogic.parse(data, languages: Set(Langs.codes))
        if let f = imp.fatal { pending = nil; changes = []; note = Self.describe(f); return }
        pending = imp
        changes = SettingsLogic.diff(current: SettingsStore.snapshot(),
                                     currentProfile: SettingsStore.profile(glossary: m.glossary), imported: imp)
    }

    private func apply() {
        guard let imp = pending else { return }
        m.applyImported(imp)
        pending = nil; changes = []
        note = L.t("sx_applied")
    }

    // MARK: Texte

    static func label(_ key: String) -> String {
        if key == SettingsLogic.profilePhrasesKey { return L.t("quick_phrases") }
        if key == SettingsLogic.profileGlossaryKey { return L.t("glossary") }
        return SettingsLogic.spec(key).map { L.t($0.labelKey) } ?? key
    }

    static func when(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L.lang.rawValue)
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    private static func show(_ v: SettingValue?, key: String) -> String {
        switch v {
        case nil: return "–"
        case .bool(let b)?: return L.t(b ? "on" : "off")
        case .number(let d)?: return d == d.rounded() ? String(Int(d)) : String(format: "%.2g", d)
        case .text(let t)?:
            if key.hasPrefix("profile.") { return L.f("sx_lines", SettingsLogic.lineCount(t)) }
            return t.isEmpty ? "–" : t
        }
    }

    static func describe(_ c: SettingChange) -> String {
        label(c.key) + ": " + show(c.old, key: c.key) + " → " + show(c.new, key: c.key)
    }

    static func describe(_ i: SettingsIssue) -> String {
        switch i.kind {
        case .notJSON: return L.t("sx_err_json")
        case .wrongFormat: return L.t("sx_err_format")
        case .badVersion: return L.t("sx_err_version")
        case .newerVersion(let n): return L.f("sx_err_newer", n)
        case .unknownKey: return L.f("sx_skip_unknown", i.key)
        case .sensitiveKey: return L.f("sx_skip_sensitive", i.key)
        case .invalidValue: return L.f("sx_skip_invalid", label(i.key))
        case .sameLanguages: return L.t("sx_skip_same")
        }
    }
}
