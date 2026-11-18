// SettingsView.swift – Einstellungsfenster (⌘,). Eine Unteransicht pro Reiter/Abschnitt,
// damit der Typprüfer schnell bleibt.
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(L.key) private var uiLang = L.defaultCode
    @State private var tab = 0
    @State private var query = ""

    /// Suchindex: Einstellung (L10n-Schlüssel ihrer Beschriftung) -> Reiter (0 Allgemein, 1 Stimme, 2 Übersetzung, 3 Anzeige).
    static let index: [(key: String, tab: Int)] = [
        ("lang_pair", 0), ("lang_mine", 0), ("lang_partner", 0), ("mic", 0), ("output_device", 0),
        ("recognition_lang", 0), ("sensitivity", 0), ("fast_endpoint", 0), ("denoise", 0), ("beam", 0),
        ("catch_up", 0), ("slow_mode", 0), ("push_to_talk", 0), ("space_toggle", 0), ("hotkey_hud", 0),
        ("hide_capture", 0), ("private_mode", 0), ("menubar_icon", 0), ("login_item", 0), ("history", 0),
        ("maintenance", 0), ("offline_mt", 0), ("model_label", 0), ("earcons", 0), ("announce_toggle", 0),
        ("learn_glossary", 0), ("back_translate", 0), ("let_finish", 0), ("listen_on_launch", 0),
        ("stop_mic_on_close", 0),
        ("polite_label", 1), ("speak_toggle", 1), ("rate", 1), ("volume", 1), ("tts_race", 1),
        ("glossary", 2), ("llm", 2), ("llm_budget", 2), ("llm_model", 2), ("preset", 2), ("style", 2), ("api_key", 2),
        ("font_size", 3), ("always_on_top", 3), ("show_details", 3), ("translit", 3),
        ("quick_phrases", 3), ("show_quick", 3),
    ]

    /// Treffer für den Suchtext (ohne Groß-/Kleinschreibung), höchstens 6.
    static func matches(_ q: String) -> [(key: String, tab: Int)] {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return [] }
        return Array(index.filter { L.t($0.key).localizedCaseInsensitiveContains(t) }.prefix(6))
    }

    private var tabNames: [String] { ["tab_general", "tab_voice", "tab_translation", "tab_display"] }

    var body: some View {
        let _ = L.sync(uiLang)
        let hits = Self.matches(query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L.t("settings_search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L.t("settings_search"))
                    .onSubmit { if let h = hits.first { tab = h.tab } }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if hits.isEmpty {
                        Text(L.t("settings_search_none")).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                            Button { tab = h.tab } label: {
                                Text(L.t(h.key) + "  ·  " + L.t(tabNames[h.tab])).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            TabView(selection: $tab) {
                GeneralSettings().tabItem { Label(L.t("tab_general"), systemImage: "gearshape") }.tag(0)
                VoiceSettings().tabItem { Label(L.t("tab_voice"), systemImage: "speaker.wave.2") }.tag(1)
                TranslationSettings().tabItem { Label(L.t("tab_translation"), systemImage: "character.bubble") }.tag(2)
                DisplaySettings().tabItem { Label(L.t("tab_display"), systemImage: "textformat.size") }.tag(3)
            }
        }
        // Größenveränderbar (Szene: .windowResizability(.contentMinSize)); größere Schrift oder Thai-Texte brauchen Platz
        .frame(minWidth: 540, idealWidth: 540, maxWidth: 900, minHeight: 460, idealHeight: 600, maxHeight: 1000)
        .id(uiLang)
        .onChange(of: m.glossary) { _, g in SettingsTracker.shared.refresh(glossary: g) }
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
    @AppStorage(Prefs.listenOnLaunch) private var listenOnLaunch = false
    @AppStorage(Prefs.announce) private var announce = true
    @AppStorage(Prefs.hideFromCapture) private var hideCapture = false
    @AppStorage(Prefs.stopMicOnClose) private var stopMicOnClose = true
    @AppStorage(Prefs.hotkeyHUD) private var hotkeyHUD = true

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
                .help(L.t("sh_model"))
                // Nr. 356: schon im Cache oder lädt beim ersten Start nach?
                Text(ModelCache.hint(model: m.model, thai: Langs.hasThai))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L.t("model_header")) } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("model_footer") + " " + L.t("restart_note"))
                    if m.model == "auto", let hw = m.hwInfo { Text(hw) }
                }
                .foregroundStyle(.secondary)
            }
            MicSection()
            OutputSection()
            RecognitionSection()
            Section {
                Toggle(L.t("push_to_talk"), isOn: $m.pushToTalk)
                    .help(L.t("push_to_talk_help"))
                Toggle(L.t("earcons"), isOn: $m.earcons)
                    .help(L.t("sh_earcons"))
                Toggle(isOn: $m.slowMode) {
                    VStack(alignment: .leading) {
                        Text(L.t("slow_mode"))
                        Text(L.t("slow_mode_help")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                // Runde 6: Ausreden lassen (69), Rückstand (171), Schnell/Genau (176)
                Picker(L.t("let_finish"), selection: $m.letFinish) {
                    Text(L.t("off")).tag(0.0)
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { Text(fmtSeconds($0)).tag($0) }
                }
                .help(L.t("let_finish_help"))
                Picker(L.t("catch_up"), selection: $m.catchUp) {
                    Text(L.t("catch_up_skip")).tag("skip")
                    Text(L.t("catch_up_fast")).tag("fast")
                    Text(L.t("catch_up_off")).tag("off")
                }
                .help(L.t("catch_up_help"))
                Picker(L.t("beam"), selection: $m.beam) {
                    Text(L.t("beam_auto")).tag(0)
                    Text(L.t("beam_fast")).tag(1)
                    Text(L.t("beam_balanced")).tag(3)
                    Text(L.t("beam_accurate")).tag(5)
                }
                .help(L.t("beam_help"))
                Toggle(L.t("back_translate"), isOn: $m.backTranslate)
                    .help(L.t("back_translate_help"))
                Toggle(L.t("learn_glossary"), isOn: $m.learnGlossary)
                    .help(L.t("learn_glossary_help"))
                Toggle(isOn: $m.offlineMT) {
                    VStack(alignment: .leading) {
                        Text(L.t("offline_mt"))
                        Text(L.t(Paths.bundledTranslateHelper == nil ? "offline_mt_missing_help" : "offline_mt_help"))
                            .font(.caption).foregroundStyle(.secondary)
                        RestartNote()
                    }
                }
                .disabled(Paths.bundledTranslateHelper == nil)
                if Paths.bundledTranslateHelper != nil { OfflinePackRow() }   // Nr. 25/26
                Toggle(isOn: $m.logText) {
                    VStack(alignment: .leading) { Text(L.t("log_text")); RestartNote() }
                }
                Toggle(isOn: $m.privateMode) {
                    VStack(alignment: .leading) {
                        Text(L.t("private_mode"))
                        Text(L.t("private_mode_help")).font(.caption).foregroundStyle(.secondary)
                        RestartNote()
                    }
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
                Toggle(L.t("hide_capture"), isOn: $hideCapture)          // Nr. 17
                    .help(L.t("hide_capture_help"))
                Toggle(L.t("stop_mic_on_close"), isOn: $stopMicOnClose)  // Nr. 18
                    .help(L.t("stop_mic_on_close_help"))
                Toggle(L.t("hotkey_hud"), isOn: $hotkeyHUD)              // Nr. 32
                    .help(L.t("sh_hotkey_hud"))
                Toggle(L.t("listen_on_launch"), isOn: $listenOnLaunch)   // Nr. 377
                    .help(L.t("listen_on_launch_help"))
                LoginItemToggle()
            }
            HistorySection()
            SettingsTransferSection()
            MaintenanceSection()
        }
        .formStyle(.grouped)
    }
}

/// Nr. 377: „Beim Anmelden starten“ über SMAppService (macOS 13+). Der Zustand kommt vom System, nicht aus
/// UserDefaults; scheitert die Anmeldung (z. B. Ad-hoc-Signatur), steht der Grund darunter.
private struct LoginItemToggle: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    @State private var note: String?

    private func refresh() {
        let st = SMAppService.mainApp.status
        on = st == .enabled
        note = st == .requiresApproval ? L.t("login_item_approve") : nil
    }

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { want in
            do {
                if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                note = SMAppService.mainApp.status == .requiresApproval ? L.t("login_item_approve") : nil
            } catch {
                note = L.t("login_item_failed") + " " + error.localizedDescription
            }
            on = SMAppService.mainApp.status == .enabled
        })) {
            VStack(alignment: .leading) {
                Text(L.t("login_item"))
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
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
                var ok = false   // Nr. 387: nur mit Antwort der Engine „Fertig“ (nicht bei Fehler/Zeitlimit)
                let p = EngineRunner.run(["--history-clear"], timeout: 30, onEvent: { o in
                    if o["deleted"] != nil { ok = true }
                }, onExit: { note = ok ? L.t("done_short") : L.t("history_clear_failed") })
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
        var ok = false   // Nr. 388: Erfolg nur mit `exported` der Engine – eine schon vorhandene Datei zählt nicht
        let started = EngineRunner.run(["--history-export", fmt, "--out", url.path], timeout: 60, onEvent: { o in
            if o["exported"] as? Bool == true { ok = true }
        }, onExit: {
            if ok && FileManager.default.fileExists(atPath: url.path) {
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
    @Environment(\.openWindow) private var openWindow
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
                if copied { Label(L.t("diag_copied"), systemImage: "checkmark").foregroundStyle(LangStyle.success) }
                Spacer()
                Button(L.t("show_log")) { NSWorkspace.shared.activateFileViewerSelecting([EngineModel.logURL]) }
            }
            HStack {
                // Eigene venv neu aufbauen (z. B. nach audio_missing); ein Entwickler-Python bleibt unberührt.
                Button(L.t("envsetup_redo")) {
                    EnvSetupModel.shared.redo()
                    openWindow(id: "main")
                }
                .disabled(EnvSetupModel.shared.running)
                Spacer()
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
            // „Systemstandard“ hat keinen Namen; Wechsel live ohne Neustart (Steuerfeld `mic`)
            m.selectMic(index: new, name: mics.first { $0.index == new }?.name ?? "")
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
            // Nr. 413: Live-Pegel zum Prüfen des gewählten Mikrofons (kommt nur, solange zugehört wird)
            HStack(spacing: 8) {
                Text(L.t("level"))
                if m.micOn {
                    LevelBar(meter: m.meter)
                } else {
                    Text(L.t("mic_level_off")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if mics.isEmpty { load() } }
        .onReceive(NotificationCenter.default.publisher(for: .audioDevicesChanged)) { _ in load() }   // Nr. 27
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

/// Ausgabegerät (Nr. 24/357): Liste aus CoreAudio, Wechsel live ohne Neustart (Steuerfeld `output_device`).
private struct OutputSection: View {
    @EnvironmentObject var m: EngineModel
    @State private var outputs: [AudioOutputs.Device] = []

    private var selection: Binding<String> {
        Binding(get: { m.outputDevice }, set: { new in
            m.outputDeviceName = outputs.first { $0.uid == new }?.name ?? ""
            m.outputDevice = new
        })
    }

    var body: some View {
        Section {
            HStack {
                Picker(L.t("output_device"), selection: selection) {
                    Text(L.t("output_default")).tag("")
                    ForEach(outputs, id: \.uid) { Text($0.name).tag($0.uid) }
                    if !m.outputDevice.isEmpty && !outputs.contains(where: { $0.uid == m.outputDevice }) {
                        Text(m.outputDeviceName.isEmpty ? m.outputDevice : m.outputDeviceName).tag(m.outputDevice)
                    }
                }
                .accessibilityLabel(L.t("output_device"))
                .help(L.t("output_device_help"))
                Button { outputs = AudioOutputs.list() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(L.t("mic_reload"))
                    .accessibilityLabel(L.t("mic_reload"))
            }
        }
        .onAppear { outputs = AudioOutputs.list() }
        .onReceive(NotificationCenter.default.publisher(for: .audioDevicesChanged)) { _ in outputs = AudioOutputs.list() }   // Nr. 27
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
                    .help(L.t("silence_help"))
                    .accessibilityLabel(L.t("silence"))
                    .accessibilityHint(L.t("silence_help"))
                    .accessibilityValue(fmtSeconds(m.silence))
                Text(fmtSeconds(m.silence)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Picker(L.t("sensitivity"), selection: $m.sensitivity) {
                Text(L.t("sens_low")).tag("low")
                Text(L.t("normal")).tag("normal")
                Text(L.t("sens_high")).tag("high")
            }
            .accessibilityLabel(L.t("sensitivity"))
            .help(L.t("sensitivity_help"))
            Toggle(isOn: $m.denoise) {
                VStack(alignment: .leading) { Text(L.t("denoise")); RestartNote() }
            }
            .help(L.t("sh_denoise"))
            Toggle(L.tp("two_person", [Langs.name(Langs.meLang), Langs.name(Langs.target(Langs.meLang))]), isOn: $m.twoPerson)
                .help(L.t("two_person_help"))
            Toggle(L.t("fast_endpoint"), isOn: $m.fastEndpoint)
                .help(L.t("fast_endpoint_help"))
            Toggle(L.t("partial_text"), isOn: $m.partialText)
                .help(L.t("sh_partial_text"))
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
                    .help(L.t("sh_speak"))
                    .accessibilityLabel(L.t("speak_toggle"))
                if m.mineLang == "th" || m.partnerLang == "th" {   // Thai-Höflichkeit nur mit Thai im Paar
                    Picker(L.t("polite_label"), selection: $m.polite) {
                        Text(L.t("polite_krub")).tag("krub")
                        Text(L.t("polite_ka")).tag("ka")
                    }
                    .help(L.t("sh_polite"))
                    .accessibilityLabel(L.t("polite_a11y"))
                }
            }
            Section {
                HStack {
                    Text(L.t("rate"))
                    Slider(value: rateBinding, in: -50...50, step: 5)
                        .accessibilityLabel(L.t("rate"))
                        .help(L.t("sh_rate"))
                        .accessibilityValue("\(m.rate) %")
                    Text(fmtNumber(Double(m.rate), digits: 0, plus: true) + " %").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text(L.t("volume"))
                    Slider(value: $m.volume, in: 0.2...2.0, step: 0.1)
                        .accessibilityLabel(L.t("volume"))
                        .help(L.t("sh_volume"))
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
    @State private var showGlossaryEditor = false
    var body: some View {
        Form {
            Section {
                Toggle(L.t("llm"), isOn: $m.llm)
                    .help(L.t("sh_llm"))
                if m.running && m.llm {
                    Label(m.llmActive ? L.t("llm_active") : L.t("llm_inactive"),
                          systemImage: m.llmActive ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(m.llmActive ? LangStyle.success : LangStyle.warning)
                }
                Picker(selection: $m.llmModel) {
                    ForEach(EngineModel.llmModels, id: \.self) { Text($0).tag($0) }
                    if !EngineModel.llmModels.contains(m.llmModel) { Text(m.llmModel).tag(m.llmModel) }
                } label: {
                    VStack(alignment: .leading) { Text(L.t("llm_model")); RestartNote() }
                }
                .accessibilityLabel(L.t("llm_model"))
                .help(L.t("sh_llm_model"))
                // Nr. 38: ungefähre Kosten je Modell (Preise wie in der Engine, ca. 300 Eingabe- + 40 Ausgabe-Token je Satz)
                Label(L.f("llm_price_hint", EngineModel.costPer1000(m.llmModel)),
                      systemImage: m.llmModel.contains("opus") ? "exclamationmark.triangle" : "dollarsign.circle")
                    .font(.caption).foregroundStyle(m.llmModel.contains("opus") ? LangStyle.warning : .secondary)
                Picker(L.t("style"), selection: $m.llmStyle) {
                    ForEach(["casual", "neutral", "polite"], id: \.self) { Text(L.t("style_" + $0)).tag($0) }
                }
                .help(L.t("sh_style"))
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
                    LabeledContent(L.t("llm_cost"), value: "≈ $" + fmtNumber(m.llmCostUSD, digits: 3))
                }
                // Kostenbremse (Nr. 16): darüber übersetzt Google bis Monatsende
                LabeledContent {
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField(L.t("llm_budget"), value: $m.llmBudget, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing).frame(width: 80).labelsHidden()
                            .accessibilityLabel(L.t("llm_budget"))
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(L.t("llm_budget"))
                        Text(m.llmMonthUSD > 0 ? L.f("llm_budget_month", m.llmMonthUSD) : L.t("llm_budget_help"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(L.t("gl_open")) { showGlossaryEditor = true }
                    .help(L.t("gl_open_help"))
                TextEditor(text: $m.glossary)
                    .font(.body.monospaced()).frame(minHeight: 90)
                    .accessibilityLabel(L.t("glossary"))
                    .help(L.t("sh_glossary"))
            } header: { Text(L.t("glossary")) } footer: { Text(L.t("glossary_hint")) }
            APIKeySection()
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showGlossaryEditor) { GlossaryEditorSheet().environmentObject(m) }
    }
}

/// API-Schlüssel eingeben und im Schlüsselbund speichern (Rückfall: Datei 0600). Er wird nie angezeigt oder geloggt.
/// Ein „Schlüssel testen“-Knopf fehlt absichtlich: Er würde den Schlüssel lesen und an die API senden.
private struct APIKeySection: View {
    @EnvironmentObject var m: EngineModel
    @State private var key = ""
    @State private var exists = APIKeyStore.exists
    @State private var failed = false
    @State private var formatWarn = false

    var body: some View {
        Section {
            SecureField(L.t("api_key"), text: $key)
                .onSubmit(save)
            HStack {
                if failed {
                    Label(L.t("key_failed"), systemImage: "xmark.octagon").foregroundStyle(.red)
                } else if exists && formatWarn {
                    Label(L.t("key_format_warn"), systemImage: "exclamationmark.triangle").foregroundStyle(LangStyle.warning)
                } else if exists {
                    Label(L.t("key_saved"), systemImage: "key.fill").foregroundStyle(LangStyle.success)
                } else {
                    Text(L.t("key_missing")).foregroundStyle(.secondary)
                }
                Spacer()
                if exists {
                    Button(L.t("key_remove"), role: .destructive) {
                        APIKeyStore.remove(); exists = APIKeyStore.exists; formatWarn = false; m.keyVersion += 1
                    }
                }
                Button(L.t("save"), action: save).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            RestartNote()
        } header: { Text(L.t("api_key")) }
    }

    private func save() {
        formatWarn = !APIKeyStore.looksValid(key)   // Nr. 390: trotzdem speichern, nur warnen
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
                        .help(L.t("sh_font_size"))
                        .accessibilityLabel(L.t("font_size"))
                        .accessibilityValue("\(Int(scale * 100)) %")
                    Text("\(Int(scale * 100)) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle(L.t("always_on_top"), isOn: $onTop)
                    .help(L.t("sh_always_on_top"))
                Toggle(L.t("show_details"), isOn: $showDetails)
                    .help(L.t("sh_show_details"))
                Toggle(L.t("translit"), isOn: $translit)
                    .help(L.t("sh_translit"))
                Button(L.t("reset_display")) { scale = 1.0; onTop = false; showDetails = false; translit = true }
            }
            QuickPhraseSettings()
        }
        .formStyle(.grouped)
    }
}

private struct QuickPhraseSettings: View {
    @AppStorage(Prefs.showQuick) private var showQuick = true
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.pairDefaults

    var body: some View {
        Section(L.t("quick_phrases")) {
            Toggle(L.t("show_quick"), isOn: $showQuick)
                .help(L.t("sh_show_quick"))
            Text(L.tp("quick_edit")).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $raw)
                .font(.body)
                .frame(minHeight: 140)
                .accessibilityLabel(L.tp("quick_edit"))
            HStack {
                Spacer()
                Button(L.t("quick_reset")) { raw = Prefs.pairDefaults }
                    .disabled(raw == Prefs.pairDefaults)
            }
        }
    }
}
