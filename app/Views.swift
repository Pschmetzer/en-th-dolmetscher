// Views.swift – Hauptfenster: Werkzeugleiste, Verlauf, Absturz-Hinweis, Erststart-Tipps.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Prefs {
    static let fontScale = "fontScale"
    static let alwaysOnTop = "alwaysOnTop"
    static let tipsSeen = "tipsSeen"
    static let fontRange = 0.6...2.5
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

struct Bubble: View {
    @EnvironmentObject var m: EngineModel
    let u: Utterance
    let scale: Double
    /// Kopfzeile der Sprechblase: Flagge, ggf. Sprechername, Originaltext.
    private var headerLine: String {
        let who: String = u.speaker.map { "\($0): " } ?? ""
        let original: String = u.translated ? u.text : L.t("not_translated")
        return LangStyle.flag(u.lang) + " " + who + original
    }

    var body: some View {
        let en = u.lang == "en"
        let playing = m.replayingID == u.id
        VStack(alignment: en ? .leading : .trailing, spacing: 6) {
            HStack(spacing: 6) {
                if !en { Spacer(minLength: 0) }
                Text(headerLine)
                    .font(.system(size: 15 * scale)).foregroundStyle(.secondary)
                    .multilineTextAlignment(en ? .leading : .trailing)
                if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary) }
                if en { Spacer(minLength: 0) }
            }
            Text(u.out)
                .font(.system(size: 30 * scale, weight: .semibold))
                .foregroundStyle(u.translated ? LangStyle.color(u.to) : .primary)
                .multilineTextAlignment(en ? .leading : .trailing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background(LangStyle.color(u.lang).opacity(playing ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { m.replay(u) }
        .help("Klicken zum erneuten Vorlesen")
        .contextMenu {
            Button("Übersetzung kopieren") { copyToPasteboard(u.out) }
            Button("Original kopieren") { copyToPasteboard(u.text) }
            Button("Beides kopieren") { copyToPasteboard(u.text + "\n" + u.out) }
            Divider()
            Button("Vorlesen") { m.replay(u) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(LangStyle.name(u.lang)): \(u.text). " + (u.translated ? "\(LangStyle.name(u.to)): \(u.out)" : "nicht übersetzt"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Zum Vorlesen aktivieren")
        .accessibilityAction(named: "Vorlesen") { m.replay(u) }
        .accessibilityAction(named: "Übersetzung kopieren") { copyToPasteboard(u.out) }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: EngineModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.tipsSeen) private var tipsSeen = false
    @State private var showTips = false
    @State private var showProfiles = false
    @AppStorage("uiLang") private var uiLang = "de"

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let log = m.crashLog { CrashBanner(log: log) }
            ScrollViewReader { sv in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if m.items.isEmpty {
                            Text(L.t("empty") + "\n\n" + L.t("commands_hint"))
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                .padding(.top, 80)
                        }
                        ForEach(m.items) { Bubble(u: $0, scale: scale).id($0.id) }
                    }.padding(16)
                }
                .onChange(of: m.items.count) {
                    if let last = m.items.last { withAnimation { sv.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(WindowAccessor { w in
            w.level = onTop ? .floating : .normal
        })
        .sheet(isPresented: $showTips) { TipsSheet { tipsSeen = true; showTips = false } }
        .sheet(isPresented: $showProfiles) { ProfilesView().environmentObject(m) }
        .id(uiLang)                                   // Oberflächensprache sofort umschalten
        .onChange(of: uiLang) { if !m.active { m.status = L.t("stopped") } }
        .onAppear { if !tipsSeen { showTips = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showTips)) { _ in showTips = true }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: m.toggle) {
                Label(m.active ? L.t("stop") : L.t("start"), systemImage: m.active ? "stop.fill" : "mic.fill")
                    .font(.title2.bold()).frame(width: 130, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(m.active ? .red : .green)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(m.active ? "Dolmetscher stoppen" : "Dolmetscher starten")
            .accessibilityHint("Leertaste")
            Text(m.status).font(.headline).lineLimit(2)
                .accessibilityLabel("Status: \(m.status)")
            if m.busy || m.state == .starting {
                ProgressView().controlSize(.small).accessibilityLabel("Arbeitet")
            }
            Spacer()
            Button { showProfiles = true } label: { Label(L.t("profiles"), systemImage: "person.crop.circle.badge.plus") }
                .help(L.t("profiles"))
                .accessibilityLabel(L.t("profiles"))
            Picker("", selection: $uiLang) {
                ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
            }.labelsHidden().fixedSize().help(L.t("ui_language")).accessibilityLabel(L.t("ui_language"))
            Button { openWindow(id: "partner") } label: { Image(systemName: "person.2.wave.2") }
                .help("Partner-Ansicht öffnen (⇧⌘P)")
                .accessibilityLabel("Partner-Ansicht öffnen")
            Toggle(isOn: $onTop) { Image(systemName: onTop ? "pin.fill" : "pin") }
                .toggleStyle(.button)
                .help("Immer im Vordergrund")
                .accessibilityLabel("Immer im Vordergrund")
            Button { exportConversation(m) } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(m.items.isEmpty)
                .help("Gespräch exportieren (⇧⌘E)")
                .accessibilityLabel("Gespräch exportieren")
            Button { m.items.removeAll() } label: { Image(systemName: "trash") }
                .disabled(m.items.isEmpty)
                .help("Verlauf leeren")
                .accessibilityLabel("Verlauf leeren")
            SettingsLink { Image(systemName: "gearshape") }
                .help("Einstellungen (⌘,)")
                .accessibilityLabel("Einstellungen")
        }
        .padding(14)
    }
}

struct CrashBanner: View {
    @EnvironmentObject var m: EngineModel
    let log: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Die Engine wurde unerwartet beendet. Letzte Zeilen aus stderr.log:", systemImage: "exclamationmark.triangle.fill")
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
                Button("Neu starten") { m.restart() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Engine neu starten")
                Button("Log im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([EngineModel.logURL]) }
                Button("Kopieren") { copyToPasteboard(log) }
                Spacer()
                Button("Ausblenden") { m.crashLog = nil }
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
