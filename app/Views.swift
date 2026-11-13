// Views.swift – Hauptfenster: Werkzeugleiste, Verlauf, Absturz-Hinweis, Erststart-Tipps.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Prefs {
    static let fontScale = "fontScale"
    static let alwaysOnTop = "alwaysOnTop"
    static let tipsSeen = "tipsSeen"
    static let showDetails = "showDetails"
    static let translit = "translit"
    static let showQuick = "showQuickPhrases"
    static let quickPhrases = "quickPhrases"
    static let fontRange = 0.6...2.5
    static let defaultPhrases = ""
    static func phrases(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Farben für beide Sprachen – im Hauptfenster und in der Partner-Ansicht gleich.
enum LangStyle {
    static func color(_ lang: String) -> Color { lang == "th" ? .orange : .blue }
    static func flag(_ lang: String) -> String { lang == "th" ? "🇹🇭" : "🇬🇧" }
    static func name(_ lang: String) -> String { lang == "th" ? "Thai" : "Englisch" }
}

/// Gibt Zugriff auf das NSWindow, in dem eine SwiftUI-Ansicht liegt.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
    }
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

@MainActor
func exportConversation(_ m: EngineModel) {
    let md = UTType(filenameExtension: "md") ?? .plainText
    let panel = NSSavePanel()
    panel.title = "Gespräch exportieren"
    panel.message = "Endung .md für Markdown, .txt für reinen Text"
    panel.allowedContentTypes = [md, .plainText]
    panel.allowsOtherFileTypes = true
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH-mm"
    panel.nameFieldStringValue = "Gespräch \(df.string(from: Date())).md"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let markdown = url.pathExtension.lowercased() != "txt"
    do { try m.transcript(markdown: markdown).write(to: url, atomically: true, encoding: .utf8) }
    catch { NSAlert(error: error).runModal() }
}

struct ContentView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.tipsSeen) private var tipsSeen = false
    @AppStorage(Prefs.showQuick) private var showQuick = true
    @State private var showTips = false
    @State private var showProfiles = false
    @State private var correcting: Utterance?
    @State private var query = ""
    @AppStorage("uiLang") private var uiLang = "de"

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(showProfiles: $showProfiles)
            if showQuick { QuickPhraseBar() }
            Divider()
            if let log = m.crashLog { CrashBanner(log: log) }
            if m.items.count > 5 || !query.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L.t("search"), text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            conversation
            if m.pushToTalk && m.micOn { PushToTalkButton().padding(14) }
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(WindowAccessor { w in
            w.level = onTop ? .floating : .normal
            let t = "Dolmetscher · " + m.status
            if w.title != t { w.title = t }
        })
        .sheet(isPresented: $showTips) { TipsSheet { tipsSeen = true; showTips = false } }
        .sheet(isPresented: $showProfiles) { ProfilesView().environmentObject(m) }
        .sheet(item: $correcting) { CorrectSheet(u: $0).environmentObject(m) }
        .id(uiLang)                                   // Oberflächensprache sofort umschalten
        .onChange(of: m.items.isEmpty) { if m.items.isEmpty { query = "" } }
        .onChange(of: uiLang) { m.refreshStatus() }
        .onAppear { if !tipsSeen { showTips = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showTips)) { _ in showTips = true }
    }

    private var conversation: some View {
        ScrollViewReader { sv in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if m.items.isEmpty { EmptyState() }
                    ForEach(m.items.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)
                                                 || $0.out.localizedCaseInsensitiveContains(query) }) { u in
                        Bubble(u: u, scale: scale, onCorrect: { correcting = $0 }).id(u.id)
                    }
                }.padding(16)
            }
            .onChange(of: m.items.last?.id) {   // auch wenn ein Platzhalter durch die fertige Blase ersetzt wird
                if let last = m.items.last { withAnimation { sv.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}

/// Leerer Verlauf: Richtung, Ladezustand, Beispiel und Sprachbefehle.
struct EmptyState: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Text("🇬🇧 English").foregroundStyle(LangStyle.color("en"))
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("🇹🇭 ไทย").foregroundStyle(LangStyle.color("th"))
            }
            .font(.system(size: 26, weight: .semibold))
            if m.loadingModel {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("empty_loading"))
                }
                .foregroundStyle(.secondary)
            } else {
                Text(L.t("empty")).foregroundStyle(.secondary)
            }
            Text(L.t("empty_example"))
                .font(.title3)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1), in: Capsule())
            Text(L.t("commands_hint")).font(.callout).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 520)
        .padding(.top, 70)
        .accessibilityElement(children: .combine)
    }
}

/// Kopfzeile: Start/Stopp, Status mit Pegel/Rückstand/Netz, Werkzeugknöpfe.
struct MainToolbar: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage("uiLang") private var uiLang = "de"
    @Binding var showProfiles: Bool

    var body: some View {
        HStack(spacing: 12) {
            startButton
            StatusCluster().layoutPriority(1)
            Spacer(minLength: 0)
            tools
        }
        .padding(14)
    }

    private var startButton: some View {
        // Start während des Ladens vorgemerkt: orange mit Fortschritt statt rot („läuft“ wäre gelogen)
        let queued = m.active && !m.micOn && m.loadingModel
        return Button(action: m.toggle) {
            HStack(spacing: 8) {
                if queued {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: m.active ? "stop.fill" : "mic.fill")
                }
                Text(queued ? L.t("start_queued") : m.active ? L.t("stop") : L.t("start"))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .font(.title2.bold()).frame(width: 130, height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(queued ? .orange : m.active ? .red : .green)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(m.active ? L.t("stop_engine") : L.t("start_engine"))
        .accessibilityHint("Leertaste, ⌃⌥D")
    }

    private var lastReplayable: Utterance? {
        m.items.last { !$0.pending && !$0.out.isEmpty }
    }

    @ViewBuilder private var tools: some View {
        Button { m.stopSpeaking() } label: { Image(systemName: "speaker.slash") }
            .disabled(!m.running)
            .help(L.t("stop_speaking"))
            .accessibilityLabel(L.t("stop_speaking"))
        Button { if let u = lastReplayable { m.replay(u) } } label: { Image(systemName: "arrow.counterclockwise.circle") }
            .disabled(lastReplayable == nil)
            .help(L.t("replay_last"))
            .accessibilityLabel(L.t("replay_last"))
        Button { showProfiles = true } label: { Label(L.t("profiles"), systemImage: "person.crop.circle.badge.plus") }
            .help(L.t("profiles"))
            .accessibilityLabel(L.t("profiles"))
        Button { openWindow(id: "partner") } label: { Image(systemName: "person.2.wave.2") }
            .help(L.t("partner_view") + " (⇧⌘P)")
            .accessibilityLabel(L.t("partner_view"))
        // Seltene Aktionen im Menü, damit bei schmalem Fenster der Status Platz behält
        Menu {
            Picker(L.t("ui_language"), selection: $uiLang) {
                ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle(L.t("always_on_top"), isOn: $onTop)
            Button(L.t("font_bigger")) { scale = min(Prefs.fontRange.upperBound, ((scale + 0.1) * 10).rounded() / 10) }
            Button(L.t("font_smaller")) { scale = max(Prefs.fontRange.lowerBound, ((scale - 0.1) * 10).rounded() / 10) }
            Divider()
            Button(L.t("export") + " (⇧⌘E)") { exportConversation(m) }.disabled(m.items.isEmpty)
            Button(L.t("clear")) { m.items.removeAll() }.disabled(m.items.isEmpty)
            Button(L.t("open_log")) {
                NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/Dolmetscher/engine.log")])
            }
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L.t("more"))
            .accessibilityLabel(L.t("more"))
        SettingsLink { Image(systemName: "gearshape") }
            .help(L.t("settings") + " (⌘,)")
            .accessibilityLabel(L.t("settings"))
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
            if m.micOn { LevelBar(meter: m.meter) }
            Text(m.status).font(.headline).lineLimit(2).help(m.status)
                .accessibilityLabel(L.t("status") + ": " + m.status)
            if m.backlog > 0 {
                Text("\(m.backlog) " + L.t("waiting"))
                    .font(.caption.bold()).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .help(L.t("backlog_help") + " (\(m.backlogSTT) / \(m.backlogTTS))")
            }
            if !m.netDown.isEmpty {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.red)
                    .help(offlineHelp)
                    .accessibilityLabel(L.t("offline") + ": " + offlineHelp)
            }
            if let med = m.latencyMedian { LatencyBadge(median: med) }
            if m.llm && m.engineReady && !m.llmActive {
                SettingsLink {
                    Label(L.t("llm_missing"), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(L.t("llm_missing_help"))
                .accessibilityLabel(L.t("llm_missing") + ". " + L.t("llm_missing_help"))
            }
            if m.llm && m.llmCostUSD > 0 {
                Text(String(format: "≈ $%.2f", m.llmCostUSD))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .help(L.t("llm_cost"))
            }
            if m.busy || m.loadingModel {
                ProgressView().controlSize(.small).accessibilityLabel(L.t("working"))
            }
        }
    }
}

/// Median der letzten 10 Latenzen (Äußerungsende → erster Ton), klein in der Kopfzeile.
struct LatencyBadge: View {
    let median: Double
    var body: some View {
        let text = "⏱ " + fmtSeconds(median)
        // bis 2 s fühlt sich das Gespräch flüssig an, ab 4 s stockt es
        let color: Color = median <= 2 ? .green : median <= 4 ? .secondary : .orange
        Text(text)
            .font(.caption).monospacedDigit().foregroundStyle(color)
            .help(L.t("latency_help"))
            .accessibilityLabel(L.t("latency_help") + ": " + fmtSeconds(median))
    }
}

/// Sekunden für die Anzeige, mit Dezimalzeichen der Oberflächensprache („2,1 s“).
func fmtSeconds(_ v: Double) -> String {
    let loc = Locale(identifier: L.lang == .de ? "de_DE" : "en_US")
    return String(format: "%.1f s", locale: loc, v)
}

/// Kleiner Pegelbalken (eigenes ObservableObject → nur diese Ansicht zeichnet ~7×/s neu).
struct LevelBar: View {
    @ObservedObject var meter: LevelMeter
    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.secondary.opacity(0.2))
            Capsule().fill(meter.voice ? Color.green : Color.secondary)
                .frame(height: max(2, 22 * meter.rms))
        }
        .frame(width: 6, height: 22)
        .animation(.linear(duration: 0.12), value: meter.rms)
        .help(L.t("level"))
        .accessibilityElement()
        .accessibilityLabel(L.t("level"))
        .accessibilityValue("\(Int(meter.rms * 100)) %")
    }
}

/// Leiste mit Schnellsätzen: Klick → Engine übersetzt und liest vor. „+“ legt eigene an, Rechtsklick löscht.
struct QuickPhraseBar: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.defaultPhrases
    @State private var adding = false
    @State private var draft = ""

    var body: some View {
        let phrases = Prefs.phrases(raw)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { draft = ""; adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .help("Eigenen Schnellsatz hinzufügen")
                ForEach(Array(phrases.enumerated()), id: \.offset) { i, p in
                    Button(p) { m.say(p) }
                        .buttonStyle(.bordered)
                        .disabled(!m.running)
                        .help(L.t("quick_phrase_help"))
                        .contextMenu {
                            Button("Löschen", role: .destructive) {
                                var l = phrases; l.remove(at: i); raw = l.joined(separator: "\n")
                            }
                        }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
        .accessibilityLabel(L.t("quick_phrases"))
        .alert("Neuer Schnellsatz (Englisch)", isPresented: $adding) {
            TextField("Satz", text: $draft)
            Button("Hinzufügen") {
                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { raw = (phrases + [t]).joined(separator: "\n") }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

/// Großer Knopf für Push-to-Talk: gedrückt halten = zuhören, loslassen = nach 0,9 s Pause.
struct PushToTalkButton: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        let holding = m.pttHolding
        Label(holding ? L.t("talking") : L.t("hold_to_talk"), systemImage: holding ? "mic.fill" : "mic")
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(holding ? Color.red : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in m.pttDown() }
                .onEnded { _ in m.pttUp() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("hold_to_talk"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if m.pttHolding { m.pttUp() } else { m.pttDown() } }
    }
}

struct CrashBanner: View {
    @EnvironmentObject var m: EngineModel
    let log: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.t("crash_banner"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.red)
            ScrollView {
                Text(log).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(L.t("restart")) { m.restart() }
                    .buttonStyle(.borderedProminent)
                Button(L.t("show_log")) { NSWorkspace.shared.activateFileViewerSelecting([EngineModel.logURL]) }
                Button(L.t("copy")) { copyToPasteboard(log) }
                Spacer()
                Button(L.t("hide")) { m.crashLog = nil }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.08))
    }
}

struct TipsSheet: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Willkommen beim Dolmetscher").font(.title.bold())
            tip("mic.fill", "Mikrofon erlauben",
                "Beim ersten Start fragt macOS nach dem Mikrofon. Bitte erlauben – sonst hört der Dolmetscher nichts. Später änderbar unter Systemeinstellungen → Datenschutz → Mikrofon.")
            tip("waveform", "Einfach sprechen",
                "Die Sprache wird automatisch erkannt: Englisch wird ins Thai übersetzt, Thai ins Englische. Erkennt er falsch, die Sprache in den Einstellungen (⌘,) fest einstellen.")
            tip("text.bubble", "Sprachbefehle mit „Translator“",
                "„Translator, pause“ · „Translator, resume“ · „Translator, repeat“ · „Translator, English off“ · „Translator, Thai only“ · „Translator, help“")
            HStack {
                Spacer()
                Button("Los geht’s", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
    private func tip(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension Notification.Name {
    static let showTips = Notification.Name("DolmetscherShowTips")
}
