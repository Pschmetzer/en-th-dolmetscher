// ViewsToolbar.swift – Werkzeugleiste, Gesprächsleiste, Statusanzeige (aus Views.swift herausgelöst, Runde 26; unverändert).
import SwiftUI
import AppKit

/// Kopfzeile: Start/Stopp, Status mit Pegel/Rückstand/Netz, Werkzeugknöpfe.
struct MainToolbar: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.spaceToggle) private var spaceToggle = true
    @AppStorage(L.key) private var uiLang = L.defaultCode
    @Binding var showProfiles: Bool
    @State private var showCommands = false
    @State private var confirmClear = false

    /// Breites Fenster: alle Werkzeuge einzeln. Schmales Fenster (ViewThatFits): nur Start, Status und ein Überlauf-Menü –
    /// nichts wird mehr abgeschnitten, der Status behält Platz.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                startButton
                StatusCluster().frame(maxWidth: 300, alignment: .leading).layoutPriority(1)
                Spacer(minLength: 0)
                tools
            }
            HStack(spacing: 12) {
                startButton
                StatusCluster().layoutPriority(1)
                Spacer(minLength: 0)
                compactMenu
            }
            // Sehr schmal: Start + Menü in der ersten Zeile, der Status bekommt die ganze zweite Zeile.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    startButton
                    Spacer(minLength: 0)
                    compactMenu
                }
                StatusCluster()
            }
        }
        .padding(14)
        .popover(isPresented: $showCommands, arrowEdge: .bottom) {
            ScrollView { CommandsList().padding(20) }
                .frame(minWidth: 320, idealWidth: 520, maxWidth: 560, minHeight: 200, idealHeight: 420, maxHeight: 560)
        }
        .confirmationDialog(L.t("clear_confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("clear"), role: .destructive) { m.clearAll(); m.resetTrimmed() }
            Button(L.t("cancel"), role: .cancel) {}
        }
    }

    /// Alle Werkzeuge in einem Menü (schmales Fenster).
    private var compactMenu: some View {
        Menu {
            Button(L.t("stop_speaking")) { m.stopSpeaking() }.disabled(!m.running)
            Button(L.t("replay_last") + " (⌘R)") { if let u = lastReplayable { m.replay(u) } }.disabled(lastReplayable == nil)
            Button(L.t("commands")) { showCommands = true }
            if !PresetCatalog.all.isEmpty {
                Picker(L.t("preset"), selection: $m.preset) {
                    Text(L.t("preset_none")).tag("")
                    ForEach(PresetCatalog.all) { Text($0.name).tag($0.id) }
                }
            }
            Button(L.t("profiles")) { showProfiles = true }
            Button(L.t("partner_view") + " (⇧⌘P)") { openWindow(id: "partner") }
            Button(L.t("mini_title") + " (⌥⌘M)") { openWindow(id: "mini") }
            Divider()
            moreItems
            Button(L.t("settings") + " (⌘,)") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L.t("more_tools_help"))
            .accessibilityLabel(L.t("more"))
    }

    private var startButton: some View {
        // Start während des Ladens vorgemerkt: orange mit Fortschritt statt rot („läuft“ wäre gelogen)
        let queued = m.active && !m.micOn && m.loadingModel
        let stateText = queued ? L.t("start_queued") : m.active ? L.t("state_listening") : L.t("stopped")
        return Button(action: m.toggle) {
            HStack(spacing: 8) {
                if queued {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: m.active ? "stop.fill" : "mic.fill").accessibilityHidden(true)
                }
                Text(queued ? L.t("start_queued") : m.active ? L.t("stop") : L.t("start"))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.title2.bold()).frame(minWidth: 110, minHeight: 34).padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(queued ? LangStyle.fillOrange : m.active ? LangStyle.fillRed : LangStyle.fillGreen)   // Nr. 371
        .accessibilityLabel(m.active ? L.t("stop_engine") : L.t("start_engine"))
        .accessibilityValue(stateText)
        .accessibilityHint(L.t(spaceToggle ? "start_hint" : "start_hint_nospace"))
    }

    private var lastReplayable: Utterance? { m.lastReplayable }

    @ViewBuilder private var moreItems: some View {
            Picker(L.t("ui_language"), selection: $uiLang) {
                ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .help(L.t("sh_ui_language"))
            Toggle(L.t("always_on_top"), isOn: $onTop)
            Button(L.t("font_bigger")) { scale = Prefs.zoomed(scale, 0.1) }
            Button(L.t("font_smaller")) { scale = Prefs.zoomed(scale, -0.1) }
            Divider()
            Button(L.t("find") + " (⌘F)") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
            Button(UIDrafts.shared.selecting ? L.r23("select_done") : L.r23("select_mode")) {
                UIDrafts.shared.selecting.toggle(); UIDrafts.shared.selection.clear()
            }.disabled(m.items.isEmpty)
            Button(L.t("export") + " (⇧⌘E)") { exportConversation(m) }.disabled(m.items.isEmpty)
            Button(L.t("clear")) { confirmClear = true }.disabled(m.items.isEmpty)
            Button(L.t("open_log")) { openLog() }
    }

    @ViewBuilder private var tools: some View {
        Button { m.stopSpeaking() } label: { Image(systemName: "stop.circle") }   // eigenes Symbol: speaker.slash heißt „stumm“
            .disabled(!m.running)
            .help(L.t("stop_speaking"))
            .accessibilityLabel(L.t("stop_speaking"))
        Button { if let u = lastReplayable { m.replay(u) } } label: { Image(systemName: "arrow.counterclockwise.circle") }
            .disabled(lastReplayable == nil)
            .help(L.t("replay_last"))
            .accessibilityLabel(L.t("replay_last"))
        Button { showCommands.toggle() } label: { Image(systemName: "text.bubble") }
            .help(L.t("commands"))
            .accessibilityLabel(L.t("commands"))
        if !PresetCatalog.all.isEmpty { PresetMenu() }
        Button { showProfiles = true } label: { Label(L.t("profiles"), systemImage: "person.crop.circle.badge.plus") }
            .help(L.t("profiles"))
            .accessibilityLabel(L.t("profiles"))
        Button { openWindow(id: "partner") } label: { Image(systemName: "person.2.wave.2") }
            .help(L.t("partner_view") + " (⇧⌘P)")
            .accessibilityLabel(L.t("partner_view"))
        // Seltene Aktionen im Menü, damit bei schmalem Fenster der Status Platz behält
        Menu {
            moreItems
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L.t("more"))
            .accessibilityLabel(L.t("more"))
        SettingsLink { Image(systemName: "gearshape") }
            .help(L.t("settings") + " (⌘,)")
            .accessibilityLabel(L.t("settings"))
    }
}

/// Zweite Kopfzeile (Nr. 344/345): Richtung (Auto / nur eine Sprache des Paars), Vorlesen an/aus und
/// ein Feld für frei getippte Sätze (übersetzen und vorlesen wie ein Schnellsatz, für laute Umgebungen).
struct ConversationBar: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var ui = UIDrafts.shared   // Entwurf übersteht den Sprachwechsel (.id(uiLang))
    private var draft: String { get { ui.typedDraft } nonmutating set { ui.typedDraft = newValue } }
    @FocusState private var typing: Bool

    private func send() {
        let sent = draft
        if m.sayTyped(draft) { ui.inputHistory.push(sent); draft = "" }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker(L.t("direction"), selection: $m.lang) {
                Text(L.t("dir_auto")).tag("auto")
                ForEach(Langs.pair, id: \.self) { c in
                    Text(Langs.flag(c) + " " + L.f("dir_only", c.uppercased())).tag(c)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help(L.t("direction_help"))
            GroupSpeakerMenu(r: m.r26)
            .accessibilityLabel(L.t("direction"))
            Toggle(isOn: $m.speak) {
                Image(systemName: m.speak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(m.speak ? Color.primary : LangStyle.warning)   // „stumm“ auf einen Blick sichtbar
            }
            .toggleStyle(.button)
            .help(L.t("speak_toggle"))
            .accessibilityLabel(L.t("speak_toggle"))
            .accessibilityValue(m.speak ? L.t("on") : L.t("off"))
            if m.mineLang == "th" || m.partnerLang == "th" {   // Nr. 374: Höflichkeitsform direkt im Hauptfenster
                Picker(L.t("polite_label"), selection: $m.polite) {
                    Text("ครับ").tag("krub")
                    Text("ค่ะ").tag("ka")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help(L.t("polite_a11y"))
                .accessibilityLabel(L.t("polite_a11y"))
            }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            TextField(L.t(m.engineReady ? "type_prompt" : "type_wait"), text: $ui.typedDraft)   // sichtbarer Platzhalter statt stummem Feld
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onSubmit(send)
                .onKeyPress(.upArrow) {   // ↑/↓ holt frühere Sätze zurück (Entwurf bleibt erhalten)
                    guard let s = ui.inputHistory.up(current: draft) else { return .ignored }
                    draft = s; return .handled
                }
                .onKeyPress(.downArrow) {
                    guard let s = ui.inputHistory.down() else { return .ignored }
                    draft = s; return .handled
                }
                .disabled(!m.engineReady)
                .help(m.engineReady ? L.t("type_prompt") : L.t("type_wait"))
                .accessibilityLabel(L.t("type_prompt"))
                .accessibilityHint(m.engineReady ? "" : L.t("type_wait"))
                .onChange(of: draft) { if draft.count > 1000 { draft = String(draft.prefix(1000)) } }
            if draft.count > 900 {   // Limit 1000 Zeichen: vorher warnen statt still zu kürzen
                Text("\(draft.count)/1000").font(.caption).monospacedDigit()
                    .foregroundStyle(draft.count >= 1000 ? LangStyle.warning : Color.secondary)
            }
            Button(action: send) { Image(systemName: "paperplane.fill") }
                .disabled(!m.engineReady || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(L.t("type_send"))
                .accessibilityLabel(L.t("type_send"))
        }
    }

    /// Eine Zeile, wenn sie passt; sonst Bedienelemente oben und Eingabefeld darunter (nichts läuft mehr rechts raus).
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { controls; field.frame(minWidth: 200) }
            VStack(alignment: .leading, spacing: 8) { controls; field }
        }
        .scaledFont(13)
        .padding(.horizontal, 14).padding(.bottom, 8)
        .onReceive(NotificationCenter.default.publisher(for: .focusTyping)) { _ in typing = true }
    }
}

/// Szenario-Preset wählen (Stil, Glossar, Schnellsätze für Hotel, Taxi, Arzt …).
struct PresetMenu: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        Menu {
            Picker(L.t("preset"), selection: $m.preset) {
                Text(L.t("preset_none")).tag("")
                ForEach(PresetCatalog.all) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            let ids = ScenarioSuggest.suggest(hour: Calendar.current.component(.hour, from: Date()),
                                              available: Set(PresetCatalog.all.map { $0.id }))
            if m.preset.isEmpty && !ids.isEmpty {
                Divider()
                Text(L.t("preset_suggest"))
                ForEach(ids, id: \.self) { id in
                    if let p = PresetCatalog.all.first(where: { $0.id == id }) { Button(p.name) { m.preset = id } }
                }
            }
        } label: {
            Label(m.activePresetName ?? L.t("preset"), systemImage: "theatermasks")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(L.t("preset_help"))
        .accessibilityLabel(L.t("preset"))
        .accessibilityValue(m.activePresetName ?? L.t("preset_none"))
    }
}

/// Status, Pegel, „2 warten“, Offline-Hinweis, Fortschritt.
struct StatusCluster: View {
    @EnvironmentObject var m: EngineModel

    private var offlineHelp: String {
        let parts = m.netDown.sorted().map { $0 == "tts" ? L.t("offline_tts") : L.t("offline_translate") }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 8) {
            if m.micOn { LevelBar(meter: m.meter); ClipBadge(meter: m.meter) }
            // Frischer Fehler (< 30 s) überschreibt den Status; ein Takt blendet ihn nach Ablauf wieder aus.
            TimelineView(.periodic(from: .now, by: 5)) { ctx in
                let age: TimeInterval = m.lastError.map { ctx.date.timeIntervalSince($0.date) } ?? 0
                let parts = StatusIcon.split(StatusLine.compose(error: m.lastError?.msg, errorAge: age, base: m.status, latency: nil))
                HStack(spacing: 5) {
                    if let sym = parts.symbol { Image(systemName: sym.name).foregroundStyle(sym.tint).accessibilityHidden(true) }
                    Text(parts.text).lineLimit(2)
                }
                .scaledFont(13, .semibold).help(parts.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.t("status") + ": " + parts.text)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if m.backlog > 0 {
                Text("\(m.backlog) " + L.t("waiting"))
                    .font(.caption.bold()).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LangStyle.warning.opacity(0.2), in: Capsule())
                    .help(L.t("backlog_help") + " (\(m.backlogSTT) / \(m.backlogTTS))")
            }
            if !m.netDown.isEmpty {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.red)
                    .help(offlineHelp)
                    .accessibilityLabel(L.t("offline") + ": " + offlineHelp)
            }
            if m.loadSlow {
                // Nr. 368: nicht nur ein Etikett – Log und Neustart direkt anbieten
                Menu {
                    Button(L.t("show_log")) { openLog() }
                    Button(L.t("restart")) { m.restart() }
                } label: {
                    Label(L.t("load_slow"), systemImage: "hourglass")
                        .font(.caption).foregroundStyle(LangStyle.warning)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(L.t("load_slow_help"))
                .accessibilityLabel(L.t("load_slow") + ". " + L.t("load_slow_help"))
            }
            if let med = m.latencyMedian { LatencyBadge(median: med, history: m.latencyHistory) }
            if m.llm && m.engineReady && !m.llmActive {
                SettingsLink {
                    Label(L.t("llm_missing"), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(LangStyle.warning)
                }
                .buttonStyle(.plain)
                .help(L.t("llm_missing_help"))
                .accessibilityLabel(L.t("llm_missing") + ". " + L.t("llm_missing_help"))
            }
            if m.llm && m.llmCostUSD > 0 {
                Text("≈ $" + fmtNumber(m.llmCostUSD))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .help(L.t("llm_cost") + (m.llmBudget > 0 ? "\n" + L.f("budget_progress", m.llmMonthUSD, m.llmBudget) : ""))
            }
            if let d = m.download, let f = EnvLogic.downloadFraction(done: d.done, total: d.total) {
                ProgressView(value: f).frame(width: 64)
                    .help(L.f("envsetup_model_progress", d.model, d.done, d.total ?? 0))
                    .accessibilityLabel(L.t("load_progress"))
                    .accessibilityValue("\(Int(f * 100)) %")
            } else if m.busy || m.loadingModel {
                ProgressView().controlSize(.small).accessibilityLabel(L.t("working"))
            }
        }
    }
}

/// Median der letzten 10 Latenzen (Äußerungsende → erster Ton), klein in der Kopfzeile.
struct LatencyBadge: View {
    let median: Double
    var history: [Double] = []
    var body: some View {
        HStack(spacing: 4) { badge; LatencySparkline(history: history) }
    }

    @ViewBuilder private var badge: some View {
        let text = "⏱ " + fmtSeconds(median)
        // bis 2 s fühlt sich das Gespräch flüssig an, ab 4 s stockt es (Zahl steht immer dabei, nicht nur Farbe)
        let color: Color = median <= 2 ? LangStyle.success : median <= 4 ? .secondary : LangStyle.warning
        Text(text)
            .font(.caption).monospacedDigit().foregroundStyle(color)
            .help(L.t("latency_help"))
            .accessibilityLabel(L.t("latency_help") + ": " + fmtSeconds(median))
    }
}

/// Sekunden für die Anzeige, mit Dezimalzeichen der Oberflächensprache („2,1 s“).
func fmtSeconds(_ v: Double) -> String {
    let loc = Locale(identifier: uiNumberLocale)
    return String(format: "%.1f " + L.t("unit_seconds"), locale: loc, v)
}

/// Kleiner Pegelbalken (eigenes ObservableObject → nur diese Ansicht zeichnet ~7×/s neu).
struct LevelBar: View {
    @ObservedObject var meter: LevelMeter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.secondary.opacity(0.2))
            Capsule().fill(meter.voice ? LangStyle.success : Color.secondary)
                .frame(height: max(2, 22 * LevelScale.display(meter.rms)))
        }
        .frame(width: 6, height: 22)
        .animation(reduceMotion ? nil : .linear(duration: 0.12), value: meter.rms)
        .help(L.t("level"))
        .accessibilityElement()
        .accessibilityLabel(L.t("level"))
        .accessibilityValue("\(Int(meter.rms * 100)) %")
        .accessibilityAddTraits(.updatesFrequently)   // wechselt ~7×/s: VoiceOver nicht fluten
    }
}

/// Statuszeilen enthalten führende Emoji (🎙 ⏸ 👂 ⏳ 🔊 🤷 ⚠️ 🗣): in der Anzeige durch SF-Symbole ersetzt
/// (einheitliche Darstellung, VoiceOver liest kein „Warnzeichen“ mehr mit). Der Status-String selbst bleibt unverändert.
enum StatusIcon {
    static let map: [(String, String, Color)] = [
        ("⚠️", "exclamationmark.triangle.fill", LangStyle.warning), ("🎙", "mic.fill", LangStyle.success),
        ("⏸", "pause.fill", .secondary), ("👂", "ear", .secondary), ("⏳", "hourglass", .secondary),
        ("🔊", "speaker.wave.2.fill", .secondary), ("🤷", "questionmark.circle", .secondary),
        ("🗣", "bubble.left.fill", .secondary),
    ]
    static func split(_ s: String) -> (symbol: (name: String, tint: Color)?, text: String) {
        for (emoji, name, tint) in map where s.unicodeScalars.starts(with: emoji.unicodeScalars) {
            var sc = s.unicodeScalars.dropFirst(emoji.unicodeScalars.count)
            while let f = sc.first, f == "\u{FE0F}" || f == " " { sc = sc.dropFirst() }   // Variantenselektor, Leerzeichen
            return ((name, tint), String(String.UnicodeScalarView(sc)))
        }
        return (nil, s)
    }
}

/// Anzeigeskala des Pegels: leise Sprache (rms 0,02–0,1) bleibt sichtbar (logarithmisch, −50…0 dBFS).
enum LevelScale {
    static func display(_ rms: Double) -> Double {
        guard rms > 0.0001 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 50) / 50))
    }
}
