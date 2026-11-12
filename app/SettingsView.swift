// SettingsView.swift – Einstellungsfenster (⌘,). Eine Unteransicht pro Reiter/Abschnitt,
// damit der Typprüfer schnell bleibt.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage("uiLang") private var uiLang = "de"

    var body: some View {
        VStack(spacing: 0) {
            if m.needsRestart { RestartBar() }
            TabView {
                GeneralSettings().tabItem { Label(L.t("tab_general"), systemImage: "gearshape") }
                VoiceSettings().tabItem { Label(L.t("tab_voice"), systemImage: "speaker.wave.2") }
                TranslationSettings().tabItem { Label(L.t("tab_translation"), systemImage: "character.bubble") }
                DisplaySettings().tabItem { Label(L.t("tab_display"), systemImage: "textformat.size") }
            }
        }
        .frame(width: 540, height: 600)
        .id(uiLang)
    }
}

/// Hinweis + Knopf, wenn Einstellungen erst nach einem Neustart der Engine wirken.
struct RestartBar: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        HStack {
            Label(L.t("needs_restart"), systemImage: "arrow.clockwise.circle")
            Spacer()
            Button(L.t("restart")) { m.restart() }.buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
    }
}

/// Kleiner Zusatz an Einstellungen, die einen Neustart brauchen.
private struct RestartNote: View {
    var body: some View {
        Text(L.t("restart_note")).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: Allgemein

private struct GeneralSettings: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        Form {
            Section(L.t("tab_translation")) {
                Toggle("🇬🇧 → 🇹🇭  Englisch ins Thai übersetzen", isOn: $m.trEN)
                    .help("Aus = Englisch bleibt Englisch")
                    .accessibilityLabel("Englisch ins Thai übersetzen")
                Toggle("🇹🇭 → 🇬🇧  Thai ins Englische übersetzen", isOn: $m.trTH)
                    .help("Aus = Thai bleibt Thai")
                    .accessibilityLabel("Thai ins Englische übersetzen")
                Picker("Spracherkennung", selection: $m.lang) {
                    Text("Automatisch").tag("auto")
                    Text("🇬🇧 nur Englisch").tag("en")
                    Text("🇹🇭 nur Thai").tag("th")
                }
                .help("Sprache fest einstellen, falls Auto falsch erkennt")
                .accessibilityLabel("Spracherkennung")
            }
            Section {
                Picker("Erkennungsmodell", selection: $m.model) {
                    Text("Schnell (small)").tag("small")
                    Text("Normal (medium)").tag("medium")
                    Text("Beste (Englisch+)").tag("best")
                }
                .accessibilityLabel("Erkennungsmodell")
            } header: { Text("Modell") } footer: {
                Text(m.active ? L.t("needs_restart") : "Größere Modelle erkennen genauer, brauchen aber länger.")
                    .foregroundStyle(.secondary)
            }
            MicSection()
            RecognitionSection()
            Section {
                Toggle(L.t("push_to_talk"), isOn: $m.pushToTalk)
                Toggle(L.t("earcons"), isOn: $m.earcons)
                Toggle(isOn: $m.logText) {
                    VStack(alignment: .leading) { Text(L.t("log_text")); RestartNote() }
                }
            } footer: {
                Text(L.t("hotkeys_note")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Mikrofonwahl: Liste per `dolmetscher.py --list-mics` (gleicher Python wie die Engine).
private struct MicSection: View {
    @EnvironmentObject var m: EngineModel
    @State private var mics: [(index: String, name: String)] = []
    @State private var loading = false
    @State private var proc: Process?

    var body: some View {
        Section {
            HStack {
                Picker(L.t("mic"), selection: $m.mic) {
                    Text(L.t("mic_default")).tag("")
                    ForEach(mics, id: \.index) { Text($0.name).tag($0.index) }
                    if !m.mic.isEmpty && !mics.contains(where: { $0.index == m.mic }) {
                        Text("#\(m.mic)").tag(m.mic)
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
        proc = EngineRunner.run(["--list-mics"], onEvent: { o in
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
                    .accessibilityValue(String(format: "%.1f s", m.silence))
                Text(String(format: "%.1f s", m.silence)).monospacedDigit().frame(width: 44, alignment: .trailing)
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
        }
    }
}

// MARK: Stimme & Audio

private struct VoiceSettings: View {
    @EnvironmentObject var m: EngineModel
    private var rateBinding: Binding<Double> {
        Binding(get: { Double(m.rate) }, set: { m.rate = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Übersetzung vorlesen", isOn: $m.speak)
                    .accessibilityLabel("Übersetzung vorlesen")
                Picker("Höflichkeitspartikel (Thai)", selection: $m.polite) {
                    Text("ครับ – männlich").tag("krub")
                    Text("ค่ะ – weiblich").tag("ka")
                }
                .accessibilityLabel("Thai-Höflichkeitspartikel: männlich krub oder weiblich ka")
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
                Picker(L.t("voice_en"), selection: $m.voiceEN) {
                    Text(L.t("voice_default")).tag("")
                    ForEach(EngineModel.voicesEN, id: \.self) { Text($0).tag($0) }
                    if !m.voiceEN.isEmpty && !EngineModel.voicesEN.contains(m.voiceEN) { Text(m.voiceEN).tag(m.voiceEN) }
                }
                .accessibilityLabel(L.t("voice_en"))
                Picker(L.t("voice_th"), selection: $m.voiceTH) {
                    Text(L.t("voice_th_default")).tag("")
                    ForEach(EngineModel.voicesTH, id: \.self) { Text($0).tag($0) }
                    if !m.voiceTH.isEmpty && !EngineModel.voicesTH.contains(m.voiceTH) { Text(m.voiceTH).tag(m.voiceTH) }
                }
                .accessibilityLabel(L.t("voice_th"))
            }
        }
        .formStyle(.grouped)
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
                        .foregroundStyle(m.llmActive ? .green : .orange)
                }
                Picker(selection: $m.llmModel) {
                    ForEach(EngineModel.llmModels, id: \.self) { Text($0).tag($0) }
                } label: {
                    VStack(alignment: .leading) { Text(L.t("llm_model")); RestartNote() }
                }
                .accessibilityLabel(L.t("llm_model"))
            }
            APIKeySection()
        }
        .formStyle(.grouped)
    }
}

/// API-Schlüssel eingeben und als Datei (0600) speichern. Der Schlüssel wird nie angezeigt oder geloggt.
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
                        .accessibilityValue("\(Int(scale * 100)) Prozent")
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
