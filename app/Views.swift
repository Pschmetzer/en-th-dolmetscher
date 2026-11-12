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
    static let defaultPhrases = ["How much is this?", "Where is the toilet?", "Thank you very much", "Too expensive",
                                 "Can you help me?", "I don't understand", "Please speak slowly", "The bill, please"]
                                .joined(separator: "\n")
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
    @AppStorage("uiLang") private var uiLang = "de"

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(showProfiles: $showProfiles)
            if showQuick { QuickPhraseBar() }
            Divider()
            if let log = m.crashLog { CrashBanner(log: log) }
            conversation
            if m.pushToTalk && m.running { PushToTalkButton().padding(14) }
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(WindowAccessor { w in
            w.level = onTop ? .floating : .normal
        })
        .sheet(isPresented: $showTips) { TipsSheet { tipsSeen = true; showTips = false } }
        .sheet(isPresented: $showProfiles) { ProfilesView().environmentObject(m) }
        .sheet(item: $correcting) { CorrectSheet(u: $0).environmentObject(m) }
        .id(uiLang)                                   // Oberflächensprache sofort umschalten
        .onChange(of: uiLang) { if !m.active { m.status = L.t("stopped") } }
        .onAppear { if !tipsSeen { showTips = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showTips)) { _ in showTips = true }
    }

    private var conversation: some View {
        ScrollViewReader { sv in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if m.items.isEmpty {
                        Text(L.t("empty") + "\n\n" + L.t("commands_hint"))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                            .padding(.top, 80)
                    }
                    ForEach(m.items) { u in
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

/// Kopfzeile: Start/Stopp, Status mit Pegel/Rückstand/Netz, Werkzeugknöpfe.
struct MainToolbar: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage("uiLang") private var uiLang = "de"
    @Binding var showProfiles: Bool

    var body: some View {
        HStack(spacing: 12) {
            startButton
            StatusCluster()
            Spacer()
            tools
        }
        .padding(14)
    }

    private var startButton: some View {
        Button(action: m.toggle) {
            Label(m.active ? L.t("stop") : L.t("start"), systemImage: m.active ? "stop.fill" : "mic.fill")
                .font(.title2.bold()).frame(width: 130, height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(m.active ? .red : .green)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(m.active ? L.t("stop_engine") : L.t("start_engine"))
        .accessibilityHint("Leertaste, ⌃⌥D")
    }

    @ViewBuilder private var tools: some View {
        Button { m.stopSpeaking() } label: { Image(systemName: "speaker.slash") }
            .disabled(!m.running)
            .help(L.t("stop_speaking"))
            .accessibilityLabel(L.t("stop_speaking"))
        Button { showProfiles = true } label: { Label(L.t("profiles"), systemImage: "person.crop.circle.badge.plus") }
            .help(L.t("profiles"))
            .accessibilityLabel(L.t("profiles"))
        Picker("", selection: $uiLang) {
            ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
        }.labelsHidden().fixedSize().help(L.t("ui_language")).accessibilityLabel(L.t("ui_language"))
        Button { openWindow(id: "partner") } label: { Image(systemName: "person.2.wave.2") }
            .help(L.t("partner_view") + " (⇧⌘P)")
            .accessibilityLabel(L.t("partner_view"))
        Toggle(isOn: $onTop) { Image(systemName: onTop ? "pin.fill" : "pin") }
            .toggleStyle(.button)
            .help(L.t("always_on_top"))
            .accessibilityLabel(L.t("always_on_top"))
        Button { exportConversation(m) } label: { Image(systemName: "square.and.arrow.up") }
            .disabled(m.items.isEmpty)
            .help(L.t("export") + " (⇧⌘E)")
            .accessibilityLabel(L.t("export"))
        Button { m.items.removeAll() } label: { Image(systemName: "trash") }
            .disabled(m.items.isEmpty)
            .help(L.t("clear"))
            .accessibilityLabel(L.t("clear"))
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
            if m.running { LevelBar(meter: m.meter) }
            Text(m.status).font(.headline).lineLimit(2)
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
            if m.busy || m.state == .starting {
                ProgressView().controlSize(.small).accessibilityLabel(L.t("working"))
            }
        }
    }
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

/// Leiste mit Schnellsätzen: Klick → Engine übersetzt und liest vor.
struct QuickPhraseBar: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.defaultPhrases

    var body: some View {
        let phrases = Prefs.phrases(raw)
        if !phrases.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(phrases.enumerated()), id: \.offset) { _, p in
                        Button(p) { m.say(p) }
                            .buttonStyle(.bordered)
                            .help(L.t("quick_phrase_help"))
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
            .disabled(!m.running)
            .accessibilityLabel(L.t("quick_phrases"))
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
