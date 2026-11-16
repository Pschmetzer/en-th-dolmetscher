// SettingsView.swift – Einstellungsfenster (⌘,). Eine Unteransicht pro Reiter/Abschnitt,
// damit der Typprüfer schnell bleibt.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(L.key) private var uiLang = L.defaultCode

    var body: some View {
        let _ = L.sync(uiLang)
        VStack(spacing: 0) {
            TabView {
                GeneralSettings().tabItem { Label(L.t("tab_general"), systemImage: "gearshape") }
                VoiceSettings().tabItem { Label(L.t("tab_voice"), systemImage: "speaker.wave.2") }
                TranslationSettings().tabItem { Label(L.t("tab_translation"), systemImage: "character.bubble") }
                DisplaySettings().tabItem { Label(L.t("tab_display"), systemImage: "textformat.size") }
            }
        }
        // Größenveränderbar (Szene: .windowResizability(.contentMinSize)); größere Schrift oder Thai-Texte brauchen Platz
        .frame(minWidth: 540, idealWidth: 540, maxWidth: 900, minHeight: 460, idealHeight: 600, maxHeight: 1000)
        .id(uiLang)
    }
}

/// Kleiner Zusatz an Einstellungen, deren Änderung die Engine neu startet (automatisch).
private struct RestartNote: View {
    var body: some View {
        Text(L.t("restart_note")).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: Allgemein

private struct GeneralSettings: View {
    @EnvironmentObject var m: EngineModel

    /// Übersetzen-Schalter je Sprache des Paars (en/th mit den bisherigen Texten).
    @ViewBuilder private func trToggle(_ code: String) -> some View {
        let to = code == m.mineLang ? m.partnerLang : m.mineLang
        let label = code == "en" && to == "th" ? L.t("tr_en_toggle") : code == "th" && to == "en" ? L.t("tr_th_toggle")
            : L.f("tr_lang_toggle", Langs.name(code), Langs.name(to))
        let help = code == "en" && to == "th" ? L.t("tr_en_help") : code == "th" && to == "en" ? L.t("tr_th_help")
            : L.f("tr_lang_help", Langs.name(code))
        Toggle(Langs.flag(code) + " → " + Langs.flag(to) + "  " + label,
               isOn: Binding(get: { m.tr(code) }, set: { m.setTr(code, $0) }))
            .help(help)
            .accessibilityLabel(label)
    }

    private func onlyLabel(_ code: String) -> String {
        code == "en" ? L.t("only_en") : code == "th" ? L.t("only_th") : L.f("only_lang", Langs.flag(code), Langs.name(code))
    }
    @ObservedObject private var hk = HotKeys.shared
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.spaceToggle) private var spaceToggle = true
    @AppStorage(Prefs.announce) private var announce = true

    var body: some View {
        Form {
            Section(L.t("lang_pair")) {
                Picker(L.t("lang_mine"), selection: $m.mineLang) {
                    ForEach(Langs.codes, id: \.self) { Text(Langs.label($0)).tag($0) }
                }
                .help(L.t("lang_mine_help"))
                .accessibilityLabel(L.t("lang_mine"))
                Picker(L.t("lang_partner"), selection: $m.partnerLang) {
                    ForEach(Langs.codes, id: \.self) { Text(Langs.label($0)).tag($0) }
                }
                .help(L.t("lang_partner_help"))
                .accessibilityLabel(L.t("lang_partner"))
                if !Langs.hasEnglish {
                    Text(L.t("lang_no_commands")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section(L.t("tab_translation")) {
                ForEach([m.mineLang, m.partnerLang], id: \.self) { code in
                    trToggle(code)
                }
                Picker(L.t("recognition_lang"), selection: $m.lang) {
                    Text(L.t("auto")).tag("auto")
                    ForEach([m.mineLang, m.partnerLang], id: \.self) { code in
                        Text(onlyLabel(code)).tag(code)
                    }
                }
                .help(L.t("recognition_lang_help"))
                .accessibilityLabel(L.t("recognition_lang"))
            }
            Section {
                Picker(L.t("model_label"), selection: $m.model) {
                    Text(L.t("model_auto")).tag("auto")
                    Text(L.t("model_small")).tag("small")
                    Text(L.t("model_medium")).tag("medium")
                    Text(L.t("model_best")).tag("best")
                }
                .accessibilityLabel(L.t("model_label"))
            } header: { Text(L.t("model_header")) } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("model_footer") + " " + L.t("restart_note"))
                    if m.model == "auto", let hw = m.hwInfo { Text(hw) }
                }
                .foregroundStyle(.secondary)
            }
            MicSection()
            RecognitionSection()
            Section {
                Toggle(L.t("push_to_talk"), isOn: $m.pushToTalk)
                    .help(L.t("push_to_talk_help"))
                Toggle(L.t("earcons"), isOn: $m.earcons)
                Toggle(isOn: $m.logText) {
                    VStack(alignment: .leading) { Text(L.t("log_text")); RestartNote() }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("hotkeys_note")).foregroundStyle(.secondary)
                    if !hk.failures.isEmpty {
                        Label(L.t("hotkeys_failed") + " " + hk.failures.joined(separator: ", "),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(LangStyle.warning)
                    }
                }
            }
            Section(L.t("app_section")) {
                Toggle(L.t("menubar_icon"), isOn: $showMenuBar)
                    .help(L.t("menubar_icon_help"))
                Toggle(L.t("space_toggle"), isOn: $spaceToggle)
                    .help(L.t("space_toggle_help"))
                Toggle(L.t("announce_toggle"), isOn: $announce)
                    .help(L.t("announce_help"))
            }
            HistorySection()
            MaintenanceSection()
        }
        .formStyle(.grouped)
    }
}

/// Gesprächsverlauf (lokal, Standard aus): an/aus, exportieren, löschen. Die Engine schreibt und exportiert.
private struct HistorySection: View {
    @EnvironmentObject var m: EngineModel
    @State private var confirmClear = false
    @State private var note = ""
    private static let formats = ["md", "csv", "srt", "vtt", "json", "anki"]

    var body: some View {
        Section {
            Toggle(L.t("history"), isOn: $m.history)
            HStack {
                Menu(L.t("history_export")) {
                    ForEach(Self.formats, id: \.self) { f in
                        Button(f == "anki" ? "Anki (TSV)" : f.uppercased()) { export(f) }
                    }
                }
                .fixedSize()
                Button(L.t("history_clear"), role: .destructive) { confirmClear = true }
                Spacer()
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        } header: { Text(L.t("history_header")) } footer: {
            Text(L.t("history_footer")).foregroundStyle(.secondary)
        }
        .confirmationDialog(L.t("history_clear_confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("clear"), role: .destructive) {
                note = ""
                let p = EngineRunner.run(["--history-clear"], timeout: 30, onEvent: { _ in }, onExit: { note = L.t("done_short") })
                if p == nil { note = Paths.pythonIsFallback ? L.t("python_missing") : L.t("script_missing") }
            }
            Button(L.t("cancel"), role: .cancel) {}
        }
    }

    private func export(_ fmt: String) {
        let panel = NSSavePanel()
        let ext = fmt == "anki" ? "txt" : fmt
        panel.nameFieldStringValue = "Dolmetscher-history." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        note = ""
        let started = EngineRunner.run(["--history-export", fmt, "--out", url.path], timeout: 60, onEvent: { _ in },
                                       onExit: {
            if FileManager.default.fileExists(atPath: url.path) {
                note = L.t("done_short")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                note = L.t("export_failed")
            }
        })
        if started == nil { note = Paths.pythonIsFallback ? L.t("python_missing") : L.t("export_failed") }
    }
}

/// Diagnosebericht kopieren, Einstellungen zurücksetzen, Log zeigen.
private struct MaintenanceSection: View {
    @EnvironmentObject var m: EngineModel
    @State private var confirmReset = false
    @State private var copied = false
    @State private var checking = false

    var body: some View {
        Section(L.t("maintenance")) {
            HStack {
                Button(L.t("diag_copy")) {
                    checking = true
                    Paths.checkPython { result in
                        copyToPasteboard(m.diagnosticReport(python: result))
                        checking = false; copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { copied = false }
                    }
                }
                .disabled(checking)
                .help(L.t("diag_help"))
                if checking { ProgressView().controlSize(.small) }
                if copied { Label(L.t("diag_copied"), systemImage: "checkmark").foregroundStyle(.green) }
                Spacer()
                Button(L.t("show_log")) { NSWorkspace.shared.activateFileViewerSelecting([EngineModel.logURL]) }
            }
            HStack {
                Button(L.t("reset_all"), role: .destructive) { confirmReset = true }
                Spacer()
            }
            Text(L.t("reset_note")).font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog(L.t("reset_confirm"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L.t("reset_all"), role: .destructive) { m.resetAllSettings() }
            Button(L.t("cancel"), role: .cancel) {}
        }
    }
}

/// Mikrofonwahl: Liste per `dolmetscher.py --list-mics` (gleicher Python wie die Engine).
/// Gespeichert werden Index und Name; beim Start gilt der Name (Indizes ändern sich beim Ein-/Ausstecken).
private struct MicSection: View {
    @EnvironmentObject var m: EngineModel
    @State private var mics: [(index: String, name: String)] = []
    @State private var loading = false
    @State private var proc: Process?

    private var selection: Binding<String> {
        Binding(get: { m.mic }, set: { new in
            m.mic = new
            m.micName = mics.first { $0.index == new }?.name ?? ""   // „Systemstandard“ hat keinen Namen
        })
    }

    var body: some View {
        Section {
            HStack {
                Picker(L.t("mic"), selection: selection) {
                    Text(L.t("mic_default")).tag("")
                    ForEach(mics, id: \.index) { Text($0.name).tag($0.index) }
                    if !m.mic.isEmpty && !mics.contains(where: { $0.index == m.mic }) {
                        Text(m.micName.isEmpty ? "#\(m.mic)" : m.micName).tag(m.mic)
                    }
                }
                .accessibilityLabel(L.t("mic"))
                if loading {
                    ProgressView().controlSize(.small).accessibilityLabel(L.t("mic_loading"))
                } else {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help(L.t("mic_reload"))
                        .accessibilityLabel(L.t("mic_reload"))
                }
            }
            RestartNote()
        }
        .onAppear { if mics.isEmpty { load() } }
        .onDisappear { proc?.terminate(); proc = nil }
    }

    private func load() {
        guard !loading else { return }
        loading = true
        proc = EngineRunner.run(["--list-mics"], timeout: 15, onEvent: { o in
            guard o["event"] as? String == "mics", let list = o["mics"] as? [[String: Any]] else { return }
            mics = list.compactMap { d in
                let idx = (d["index"] as? String) ?? (d["index"] as? NSNumber)?.stringValue
                guard let idx else { return nil }
                return (idx, d["name"] as? String ?? "#\(idx)")
            }
        }, onExit: { loading = false; proc = nil })
        if proc == nil { loading = false }
    }
}

/// Satzende-Pause, Empfindlichkeit, Rauschunterdrückung.
private struct RecognitionSection: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        Section {
            HStack {
                Text(L.t("silence"))
                Slider(value: $m.silence, in: 0.4...2.0, step: 0.1)
                    .accessibilityLabel(L.t("silence"))
                    .accessibilityValue(fmtSeconds(m.silence))
                Text(fmtSeconds(m.silence)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Picker(L.t("sensitivity"), selection: $m.sensitivity) {
                Text(L.t("sens_low")).tag("low")
                Text(L.t("normal")).tag("normal")
                Text(L.t("sens_high")).tag("high")
            }
            .accessibilityLabel(L.t("sensitivity"))
            Toggle(isOn: $m.denoise) {
                VStack(alignment: .leading) { Text(L.t("denoise")); RestartNote() }
            }
            Toggle(L.t("two_person"), isOn: $m.twoPerson)
                .help(L.t("two_person_help"))
            Toggle(L.t("fast_endpoint"), isOn: $m.fastEndpoint)
                .help(L.t("fast_endpoint_help"))
            Toggle(L.t("partial_text"), isOn: $m.partialText)
        }
    }
}

// MARK: Stimme & Audio

private struct VoiceSettings: View {
    @EnvironmentObject var m: EngineModel

    /// Stimmenauswahl je Sprache des Paars (en/th mit den bisherigen Texten; Thai-Standard nach Höflichkeitsform).
    @ViewBuilder private func voicePicker(_ code: String) -> some View {
        let title = code == "en" ? L.t("voice_en") : code == "th" ? L.t("voice_th") : L.f("voice_lang", Langs.name(code))
        let list = EngineModel.voices(code)
        let cur = m.voice(code)
        Picker(title, selection: Binding(get: { m.voice(code) }, set: { m.setVoice(code, $0) })) {
            Text(code == "en" ? L.t("voice_default") : code == "th" ? L.t("voice_th_default") : L.t("voice_lang_default"))
                .tag("")
            ForEach(list, id: \.self) { Text(EngineModel.voiceLabel($0)).tag($0) }
            if !cur.isEmpty && !list.contains(cur) { Text(EngineModel.voiceLabel(cur)).tag(cur) }
        }
        .accessibilityLabel(title)
        // Stimme sofort probehören (Beispielsatz in dieser Sprache, ohne Übersetzung)
        Button { m.testVoice(code) } label: { Label(L.t("voice_test"), systemImage: "play.circle") }
            .disabled(!m.canTestVoice)
            .help(m.canTestVoice ? L.t("voice_test") : L.t("voice_test_needs_engine"))
    }
    private var rateBinding: Binding<Double> {
        Binding(get: { Double(m.rate) }, set: { m.rate = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            Section {
                Toggle(L.t("speak_toggle"), isOn: $m.speak)
                    .accessibilityLabel(L.t("speak_toggle"))
                if m.mineLang == "th" || m.partnerLang == "th" {   // Thai-Höflichkeit nur mit Thai im Paar
                    Picker(L.t("polite_label"), selection: $m.polite) {
                        Text(L.t("polite_krub")).tag("krub")
                        Text(L.t("polite_ka")).tag("ka")
                    }
                    .accessibilityLabel(L.t("polite_a11y"))
                }
            }
            Section {
                HStack {
                    Text(L.t("rate"))
                    Slider(value: rateBinding, in: -50...50, step: 5)
                        .accessibilityLabel(L.t("rate"))
                        .accessibilityValue("\(m.rate) %")
                    Text(String(format: "%+d %%", m.rate)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text(L.t("volume"))
                    Slider(value: $m.volume, in: 0.2...2.0, step: 0.1)
                        .accessibilityLabel(L.t("volume"))
                        .accessibilityValue("\(Int(m.volume * 100)) %")
                    Text("\(Int((m.volume * 100).rounded())) %").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            Section {
                ForEach([m.mineLang, m.partnerLang], id: \.self) { code in voicePicker(code) }
            }
            TTSRaceSection()
        }
        .formStyle(.grouped)
    }
}

/// Neural-Stimme zu langsam → nach … s spricht die macOS-Ersatzstimme (0 = aus).
private struct TTSRaceSection: View {
    @EnvironmentObject var m: EngineModel
    private var valueText: String { m.ttsRace <= 0 ? L.t("off") : fmtSeconds(m.ttsRace) }
    var body: some View {
        Section {
            HStack {
                Text(L.t("tts_race"))
                Slider(value: $m.ttsRace, in: 0...3, step: 0.1)
                    .accessibilityLabel(L.t("tts_race"))
                    .accessibilityValue(valueText)
                Text(valueText).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        } footer: {
            Text(L.t("tts_race_help")).foregroundStyle(.secondary)
        }
    }
}

// MARK: Übersetzung (Claude)

private struct TranslationSettings: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        Form {
            Section {
                Toggle(L.t("llm"), isOn: $m.llm)
                if m.running && m.llm {
                    Label(m.llmActive ? L.t("llm_active") : L.t("llm_inactive"),
                          systemImage: m.llmActive ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(m.llmActive ? Color.green : LangStyle.warning)
                }
                Picker(selection: $m.llmModel) {
                    ForEach(EngineModel.llmModels, id: \.self) { Text($0).tag($0) }
                    if !EngineModel.llmModels.contains(m.llmModel) { Text(m.llmModel).tag(m.llmModel) }
                } label: {
                    VStack(alignment: .leading) { Text(L.t("llm_model")); RestartNote() }
                }
                .accessibilityLabel(L.t("llm_model"))
                Picker(L.t("style"), selection: $m.llmStyle) {
                    ForEach(["casual", "neutral", "polite"], id: \.self) { Text(L.t("style_" + $0)).tag($0) }
                }
                if !PresetCatalog.all.isEmpty {
                    Picker(L.t("preset"), selection: $m.preset) {
                        Text(L.t("preset_none")).tag("")
                        ForEach(PresetCatalog.all) { Text($0.name).tag($0.id) }
                        if !m.preset.isEmpty && !PresetCatalog.all.contains(where: { $0.id == m.preset }) {
                            Text(m.preset).tag(m.preset)
                        }
                    }
                    .help(L.t("preset_help"))
                }
                if m.llmCostUSD > 0 {
                    LabeledContent(L.t("llm_cost"), value: String(format: "≈ $%.3f", m.llmCostUSD))
                }
            }
            Section {
                TextEditor(text: $m.glossary)
                    .font(.body.monospaced()).frame(minHeight: 90)
                    .accessibilityLabel(L.t("glossary"))
            } header: { Text(L.t("glossary")) } footer: { Text(L.t("glossary_hint")) }
            APIKeySection()
        }
        .formStyle(.grouped)
    }
}

/// API-Schlüssel eingeben und als Datei (0600) speichern. Der Schlüssel wird nie angezeigt oder geloggt.
/// Ein „Schlüssel testen“-Knopf fehlt absichtlich: Er würde den Schlüssel lesen und an die API senden.
private struct APIKeySection: View {
    @EnvironmentObject var m: EngineModel
    @State private var key = ""
    @State private var exists = APIKeyStore.exists
    @State private var failed = false

    var body: some View {
        Section {
            SecureField(L.t("api_key"), text: $key)
                .onSubmit(save)
            HStack {
                if failed {
                    Label(L.t("key_failed"), systemImage: "xmark.octagon").foregroundStyle(.red)
                } else if exists {
                    Label(L.t("key_saved"), systemImage: "key.fill").foregroundStyle(.green)
                } else {
                    Text(L.t("key_missing")).foregroundStyle(.secondary)
                }
                Spacer()
                if exists {
                    Button(L.t("key_remove"), role: .destructive) {
                        APIKeyStore.remove(); exists = APIKeyStore.exists; m.keyVersion += 1
                    }
                }
                Button(L.t("save"), action: save).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            RestartNote()
        } header: { Text(L.t("api_key")) }
    }

    private func save() {
        let ok = APIKeyStore.save(key)
        key = ""                      // Eingabe sofort verwerfen
        failed = !ok
        exists = APIKeyStore.exists
        if ok { m.keyVersion += 1 }
    }
}

// MARK: Anzeige

private struct DisplaySettings: View {
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.showDetails) private var showDetails = false
    @AppStorage(Prefs.translit) private var translit = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L.t("font_size"))
                    Slider(value: $scale, in: Prefs.fontRange, step: 0.1)
                        .accessibilityLabel(L.t("font_size"))
                        .accessibilityValue("\(Int(scale * 100)) %")
                    Text("\(Int(scale * 100)) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle(L.t("always_on_top"), isOn: $onTop)
                Toggle(L.t("show_details"), isOn: $showDetails)
                Toggle(L.t("translit"), isOn: $translit)
            }
            QuickPhraseSettings()
        }
        .formStyle(.grouped)
    }
}

private struct QuickPhraseSettings: View {
    @AppStorage(Prefs.showQuick) private var showQuick = true
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.defaultPhrases

    var body: some View {
        Section(L.t("quick_phrases")) {
            Toggle(L.t("show_quick"), isOn: $showQuick)
            Text(L.t("quick_edit")).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $raw)
                .font(.body)
                .frame(minHeight: 140)
                .accessibilityLabel(L.t("quick_edit"))
            HStack {
                Spacer()
                Button(L.t("quick_reset")) { raw = Prefs.defaultPhrases }
                    .disabled(raw == Prefs.defaultPhrases)
            }
        }
    }
}
