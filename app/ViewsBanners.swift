// ViewsBanners.swift – Schnellsätze, Push-to-Talk, Hinweisbänder, Tipps, Blasen-Dekor (aus Views.swift herausgelöst, Runde 26; unverändert).
import SwiftUI
import AppKit

/// Leiste mit Schnellsätzen: Klick → Engine übersetzt und liest vor (Thai-Sätze ins Englische).
/// „+“ legt eigene an, Rechtsklick (oder VoiceOver-Aktion) löscht.
struct QuickPhraseBar: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(Prefs.quickPhrases) private var raw = Prefs.pairDefaults
    @State private var adding = false
    @State private var draft = ""
    @State private var showNote = false

    private func remove(_ i: Int) {
        var l = Prefs.phrases(raw)
        guard l.indices.contains(i) else { return }
        l.remove(at: i)
        raw = l.joined(separator: "\n")
    }

    private func moveToFront(_ i: Int) {
        var l = Prefs.phrases(raw)
        guard l.indices.contains(i) else { return }
        l.insert(l.remove(at: i), at: 0)
        raw = l.joined(separator: "\n")
    }

    var body: some View {
        let phrases = Prefs.phrases(raw)
        ScrollView(.horizontal, showsIndicators: true) {   // sichtbare Leiste: mit der Maus ohne Shift-Rad erreichbar
            HStack(spacing: 8) {
                Button { draft = ""; adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .help(L.t("phrase_add_help"))
                    .accessibilityLabel(L.t("phrase_add_help"))
                if let pr = PresetCatalog.all.first(where: { $0.id == m.preset }), m.activePreset != nil {
                    // Hinweis und Sätze aus dem Ereignis der Engine, sonst aus der Datei (z. B. nach Neuverbinden).
                    let fromEvent = m.activePreset?.id == pr.id
                    let note = Preset.noteText((fromEvent ? m.activePresetNote : nil) ?? pr.note)
                    let list = (fromEvent ? m.activePresetPhrases : nil) ?? pr.phrases
                    if let note {
                        Button { showNote.toggle() } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.bordered)
                            .help(note)
                            .accessibilityLabel(L.t("preset_note"))
                            .popover(isPresented: $showNote) {
                                Text(note).padding(12).frame(width: 320, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                    }
                    // Preset-Sätze gibt es auf Englisch und Thai: nur mit einer der beiden Sprachen im Paar.
                    // Kritische Sätze (Notfall, Allergie …) zuerst, rot und mit Warnsymbol.
                    let ordered = list.filter(\.critical) + list.filter { !$0.critical }
                    ForEach(Array(ordered.enumerated()), id: \.offset) { _, ph in
                        let useTH = !Langs.hasEnglish && Langs.hasThai
                        let text: String = useTH ? ph.th : ph.en
                        let altText: String = useTH ? ph.en : ph.th
                        let tip: String = text + "\n" + altText   // einzeln gebildet: lange Ausdrücke bremsen den Typprüfer
                        Button { m.say(text, lang: useTH ? "th" : "en") } label: {
                            if ph.critical { Label(text, systemImage: "exclamationmark.triangle.fill") } else { Text(text) }
                        }
                            .lineLimit(1).frame(maxWidth: 260)
                            .buttonStyle(.bordered).tint(ph.critical ? .red : .accentColor)
                            .disabled(!m.engineReady || !(Langs.hasEnglish || Langs.hasThai))
                            .help(tip)
                            .accessibilityLabel(ph.critical ? L.t("preset_critical") + ": " + text : text)
                            .accessibilityHint(L.t("preset_phrase_help"))
                    }
                    Divider().frame(height: 18)
                }
                if phrases.isEmpty && m.activePreset == nil {
                    Text(L.t("phrases_empty_hint")).foregroundStyle(.secondary)
                }
                ForEach(Array(phrases.enumerated()), id: \.offset) { i, p in
                    Button(p) { m.say(p, lang: Prefs.phraseLang(p)) }
                        .lineLimit(1).frame(maxWidth: 260)
                        .buttonStyle(.bordered)
                        .disabled(!m.engineReady)
                        .help(p + "\n" + L.t("quick_phrase_help"))
                        .contextMenu {
                            if i > 0 { Button(L.t("move_first")) { moveToFront(i) } }
                            Button(L.t("delete"), role: .destructive) { remove(i) }
                        }
                        .accessibilityAction(named: L.t("delete")) { remove(i) }
                }
            }
            .padding(.leading, 14).padding(.trailing, 34).padding(.bottom, 10)   // Platz für den Rand-Verlauf
            .scaledFont(13)
        }
        .mask(HStack(spacing: 0) {   // weicher Rand rechts: zeigt, dass es weiter läuft
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 20)
        })
        .accessibilityLabel(L.t("quick_phrases"))
        .alert(L.tp("phrase_new_title"), isPresented: $adding) {
            TextField(L.t("sentence"), text: $draft)
            Button(L.t("add")) {
                let t = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
                if !t.isEmpty, !phrases.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {   // keine Dubletten
                    raw = (phrases + [t]).joined(separator: "\n")
                }
            }
            Button(L.t("cancel"), role: .cancel) {}
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
            .background(holding ? LangStyle.fillRed : LangStyle.fillBlue, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in m.pttDown() }
                .onEnded { _ in m.pttUp() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("hold_to_talk"))
            .accessibilityValue(holding ? L.t("talking") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if m.pttHolding { m.pttUp() } else { m.pttDown() } }
    }
}

/// Engine-Log im Finder zeigen: engine.log (Ereignisse), sonst stderr.log, sonst den Log-Ordner
/// (gibt es noch keine Datei, passierte vorher beim Klick gar nichts).
@MainActor func openLog() {
    let dir = EngineModel.logURL.deletingLastPathComponent()
    let fm = FileManager.default
    if let f = [dir.appendingPathComponent("engine.log"), EngineModel.logURL].first(where: { fm.fileExists(atPath: $0.path) }) {
        NSWorkspace.shared.activateFileViewerSelecting([f])
    } else {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

/// Schmaler Hinweis unter der Kopfzeile, optional mit einem Knopf und Schließen-Kreuz.
/// Ladezustand mit Zahlen: Balken und „Modell: x von y MB“ aus `download_progress`; ohne Download nur der Hinweis,
/// dass das Laden aus dem Cache kurz dauert. Bei langsamem Laden mit Handlungsvorschlag.
struct ModelLoadProgress: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        VStack(spacing: 4) {
            if let d = m.download {
                if let f = EnvLogic.downloadFraction(done: d.done, total: d.total) {
                    ProgressView(value: f)
                        .accessibilityLabel(L.t("load_progress"))
                        .accessibilityValue("\(Int(f * 100)) %")
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(L.f("envsetup_model_progress", d.model, d.done, d.total ?? 0))
                    .font(.caption).monospacedDigit()
            } else if m.loadingModel {
                ProgressView().progressViewStyle(.linear).accessibilityLabel(L.t("working"))
            }
            if m.loadSlow {
                Text(L.t("load_slow_action")).font(.caption).foregroundStyle(LangStyle.warning)
            }
        }
    }
}

struct NoticeBanner: View {
    let icon: String
    let tint: Color
    let text: String
    var action: (String, () -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).scaledFont(12).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            if let action { Button(action.0, action: action.1) }
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(L.t("close")).accessibilityLabel(L.t("close"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(tint.opacity(0.1))
        .accessibilityElement(children: .contain)
        .onAppear { Announcer.post(text) }   // Nr. 367: VoiceOver erfährt vom neuen Hinweis
        .onChange(of: text) { _, new in Announcer.post(new) }   // auch wenn sich der Text eines Hinweises ändert
    }
}

/// Nach einer Korrektur: geänderte Wörter ins Vokabular des Stimmprofils übernehmen? (Engine schlägt nur vor.)
struct VocabSuggestionBanner: View {
    @EnvironmentObject var m: EngineModel
    let words: [String]
    let profile: String
    @State private var saving = false

    var body: some View {
        NoticeBanner(icon: "text.badge.plus", tint: .accentColor,
                     text: L.f("vocab_suggest", words.joined(separator: ", "), profile),
                     action: (saving ? L.t("saving") : L.t("add"), {
                        guard !saving else { return }
                        saving = true
                        ProfilesModel.appendVocab(profile: profile, words: words) { _ in
                            saving = false
                            m.vocabSuggestion = nil
                        }
                     }),
                     onClose: { m.vocabSuggestion = nil })
    }
}

/// Mikrofon verweigert: Hinweis mit Knopf zu den Systemeinstellungen.
struct MicDeniedBanner: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(L.t("nomic"), systemImage: "mic.slash.fill")
                    .font(.headline).foregroundStyle(.red)
                    .accessibilityAddTraits(.isHeader)
                Text(L.t("nomic_action")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L.t("open_mic_settings")) { m.openMicrophoneSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.red.opacity(0.08))
        .accessibilityElement(children: .contain)
        .onAppear { Announcer.post(L.t("nomic") + ". " + L.t("nomic_action"), force: true) }
    }
}

struct CrashBanner: View {
    @EnvironmentObject var m: EngineModel
    let log: String
    @State private var diagCopied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.t("crash_banner"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.red)
                .accessibilityAddTraits(.isHeader)
            Text(m.status).font(.callout)
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
                Button(L.t("show_log")) { openLog() }
                Button(L.t("copy")) { copyToPasteboard(log) }
                Button(diagCopied ? L.t("diag_copied") : L.t("diag_copy")) {   // Nr. 372: genau hier gebraucht
                    Paths.checkPython { result in
                        copyToPasteboard(m.diagnosticReport(python: result))
                        diagCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { diagCopied = false }
                    }
                }
                .help(L.t("diag_help"))
                Spacer()
                Button(L.t("hide")) { m.crashLog = nil }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.08))
    }
}

/// Willkommen beim ersten Start: Mikrofon, Bedienung, Sprachbefehle und – wichtig – welche Dienste Text erhalten.
struct TipsSheet: View {
    @ObservedObject var engine: EngineModel
    var done: () -> Void
    var later: () -> Void
    private var model: String { engine.model }
    private var thai: Bool { Langs.hasThai }
    /// Seiten: 0 Tipps, 1 Erste Schritte, 2 Checkliste (statt einer langen Scrollfläche).
    @State private var page = 0
    private static let pageCount = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("welcome_title")).font(.title.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case 0:
                        tip("waveform", L.t("tip_speak_title"), L.tp("tip_speak_text"))
                        tip("text.bubble", L.t("tip_cmd_title"), L.t("tip_cmd_text"))
                        tip("lock.shield", L.t("privacy_title"), L.t("privacy_text"))
                    case 1: OnboardingSteps(m: engine)
                    default: SetupChecklist(model: model, thai: thai)
                    }
                }
                .padding(.trailing, 8)
            }
            HStack {
                Button(L.t("onb_later")) { later() }.help(L.t("onb_later_help")).keyboardShortcut(.cancelAction)
                Spacer()
                HStack(spacing: 6) {   // Fortschrittspunkte
                    ForEach(0..<Self.pageCount, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.f("onb_page_of", page + 1, Self.pageCount))
                Spacer()
                if page > 0 { Button(L.t("onb_back")) { page -= 1 } }
                if page < Self.pageCount - 1 {
                    Button(L.t("onb_next")) { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L.t("lets_go"), action: done).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 480, idealWidth: 580, maxWidth: 640, minHeight: 360, idealHeight: 680, maxHeight: 760)
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
    static let focusSearch = Notification.Name("DolmetscherFocusSearch")
    static let focusTyping = Notification.Name("DolmetscherFocusTyping")
    static let showProfiles = Notification.Name("DolmetscherShowProfiles")
}

/// Band im Hauptfenster, solange eine gespeicherte Sitzung nur gelesen wird.
struct ViewingBanner: View {
    @EnvironmentObject var m: EngineModel
    let title: String
    var body: some View {
        NoticeBanner(icon: "clock.arrow.circlepath", tint: LangStyle.warning,
                     text: L.f("hist_viewing", title),
                     action: (L.t("hist_back_live"), { m.viewingSession = nil }))
    }
}


/// Dezenter Zeit-Trenner zwischen Blasen nach einer Pause (≥ 10 min) oder beim Tageswechsel.
struct TimeDividerRow: View {
    let date: Date
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            Text(TimeDivider.label(date)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("time_divider_a11y") + ": " + TimeDivider.label(date))
    }
}

/// Außen an der (Equatable) Blase: Hervorhebung des aktuellen Suchtreffers, Auswahlrahmen/-klick und VoiceOver-Position.
/// Liegt bewusst außerhalb von `Bubble`, damit nicht jede Blase neu zeichnet, wenn nur die Gesamtzahl wächst.
struct BubbleDecor: ViewModifier {
    let hit: Bool
    let selecting: Bool
    let selected: Bool
    let position: String?
    let toggle: () -> Void
    let extend: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if hit { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.yellow, lineWidth: 3).allowsHitTesting(false) }
                if selected { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 3).allowsHitTesting(false) }
            }
            .overlay(alignment: .topLeading) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .padding(8).accessibilityHidden(true)
                }
            }
            .overlay {   // Auswahlmodus: ein Klick wählt (Umschalt: Bereich), statt in den Text zu klicken
                if selecting {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { if NSEvent.modifierFlags.contains(.shift) { extend() } else { toggle() } }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(Text([position.map { L.r23f("bubble_position", $0) },
                                      hit ? L.r23("current_hit") : nil,
                                      selected ? L.r23("selected_state") : nil].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// Treffer-Position und Auswahl an den sichtbaren Verlauf binden: neue Suche/Filter setzt den Treffer zurück,
/// verschwundene Blasen verlassen die Auswahl.
struct SearchSelectionSync: ViewModifier {
    @ObservedObject private var ui = UIDrafts.shared
    let ids: [String]

    func body(content: Content) -> some View {
        content
            .onChange(of: ui.query) { ui.hitIndex = nil }
            .onChange(of: ui.langFilter) { ui.hitIndex = nil }
            .onChange(of: ids) { ui.selection.prune(keeping: ids) }
    }
}
