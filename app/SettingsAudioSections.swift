// SettingsAudioSections.swift – Abschnitte „Mikrofon“, „Ausgabegerät“ und „Neural-Stimme zu langsam“ des Einstellungsfensters
// (aus SettingsView.swift herausgelöst, Runde 25).
import SwiftUI

/// Mikrofonwahl: Liste per `dolmetscher.py --list-mics` (gleicher Python wie die Engine).
/// Gespeichert werden Index und Name; beim Start gilt der Name (Indizes ändern sich beim Ein-/Ausstecken).
struct MicSection: View {
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
            // Modifier an der ersten Zeile, nicht an der Section (dort greifen sie je nach Container mehrfach oder gar nicht)
            .onAppear { if mics.isEmpty { load() } }
            .onReceive(NotificationCenter.default.publisher(for: .audioDevicesChanged)) { _ in load() }   // Nr. 27
            .onDisappear { proc?.terminate(); proc = nil }
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
struct OutputSection: View {
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
            .onAppear { outputs = AudioOutputs.list() }   // an der Zeile, nicht an der Section
            .onReceive(NotificationCenter.default.publisher(for: .audioDevicesChanged)) { _ in outputs = AudioOutputs.list() }   // Nr. 27
        }
    }
}

/// Neural-Stimme zu langsam → nach … s spricht die macOS-Ersatzstimme (0 = aus).
struct TTSRaceSection: View {
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
