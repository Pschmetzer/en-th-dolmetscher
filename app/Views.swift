// Views.swift – Hauptfenster: Werkzeugleiste, Verlauf, Absturz-Hinweis, Erststart-Tipps.
import SwiftUI
import AppKit

enum Prefs {
    static let fontScale = "fontScale"
    static let alwaysOnTop = "alwaysOnTop"
    static let tipsSeen = "tipsSeen"
    static let tipsRemindUntil = "tipsRemindUntil"   // „Später erinnern“: Willkommensseite bis dahin ruhen lassen
    static let showDetails = "showDetails"
    static let translit = "translit"
    static let showQuick = "showQuickPhrases"
    static let quickPhrases = "quickPhrases"
    static let showMenuBar = "showMenuBar"
    static let spaceToggle = "spaceToggle"
    static let announce = "announceTranslations"
    static let listenOnLaunch = "listenOnLaunch"   // Nr. 377: beim App-Start gleich zuhören
    static let fontRange = 0.6...2.5
    /// Kennung des Hauptfensters (Leertaste-Kürzel, Scroll-Überwachung).
    static let mainWindowID = NSUserInterfaceItemIdentifier("dolmetscher.main")
    /// Schlüssel, die „Alle Einstellungen zurücksetzen“ löscht (Willkommensseite und Sprache bleiben bzw. werden gesetzt).
    static let resettableKeys = [fontScale, alwaysOnTop, showDetails, translit, showQuick, quickPhrases,
                                 showMenuBar, spaceToggle, announce, "partnerRotated", "partnerZoom", listenOnLaunch]

    /// Nr. 40: Standard-Schnellsätze für das aktive Paar: Sätze in beiden Paarsprachen (en/th: die feste Liste).
    /// Sprachen ohne Tabelle liefern keine Sätze (nie fremdsprachige Sätze als „meine Sprache“ vorgeben).
    static func phrasesForPair(mine: String, partner: String) -> String {
        if mine == "en" && partner == "th" || mine == "th" && partner == "en" { return defaultPhrases }
        let table: [String: [String]] = [
            "en": ["Hello!", "Thank you very much", "Where is the toilet?", "How much is it?",
                   "Could you say that again, please?", "I don't understand"],
            "de": ["Hallo!", "Vielen Dank", "Wo ist die Toilette?", "Wie viel kostet das?",
                   "Können Sie das bitte wiederholen?", "Ich verstehe nicht"],
            "th": ["สวัสดี", "ขอบคุณมาก", "ช่วยพูดช้าๆ หน่อย", "ไม่เข้าใจ"],
        ]
        return ((table[mine] ?? []) + (table[partner] ?? [])).joined(separator: "\n")
    }
    /// Standardliste für das gerade aktive Paar (Startwert des Speichers und „Standard wiederherstellen“).
    static var pairDefaults: String { phrasesForPair(mine: Langs.mine, partner: Langs.partner) }

    /// Schnellsätze beim ersten Start: englische Sätze (werden ins Thai übersetzt) und thailändische (ins Englische).
    /// Wer die Liste später leert, behält sie leer; nur ein nie gespeicherter Schlüssel zeigt diese Standardliste.
    static let defaultPhrases = [
        "Hello!", "Thank you very much", "Where is the toilet?", "How much is it?",
        "Could you say that again, please?", "I don't understand",
        "สวัสดี", "ขอบคุณมาก", "ช่วยพูดช้าๆ หน่อย", "ไม่เข้าใจ",
    ].joined(separator: "\n")

    static func phrases(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Sprache eines Schnellsatzes nach Schrift, nur zwischen den zwei Sprachen des Paars (Standard: Thai-Zeichen →
    /// "th", sonst "en"); Speicherformat bleibt eine Zeile pro Satz.
    static func phraseLang(_ p: String) -> String { Langs.guessLang(p) }

    /// Schriftgröße mit eigenem Zoom (⌘+/⌘−) – für alle Bereiche, nicht nur die Sprechblasen (Nr. 353).
    static func scaled(_ base: CGFloat, _ scale: Double) -> CGFloat {
        base * CGFloat(min(fontRange.upperBound, max(fontRange.lowerBound, scale)))
    }

    /// Schriftzoom um `d` ändern, auf 0,1 gerundet und auf den erlaubten Bereich begrenzt.
    static func zoomed(_ scale: Double, _ d: Double) -> Double {
        min(fontRange.upperBound, max(fontRange.lowerBound, ((scale + d) * 10).rounded() / 10))
    }
}

/// Farben für beide Sprachen – im Hauptfenster und in der Partner-Ansicht gleich.
/// Im Hellmodus dunklere Töne (Text auf hellem Grund ≥ 4,5:1), im Dunkelmodus hellere; mit
/// „Kontrast erhöhen“ jeweils noch kräftiger.
enum LangStyle {
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(light: UInt32, lightHC: UInt32, dark: UInt32, darkHC: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            switch ap.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .some(.darkAqua): return rgb(dark)
            case .some(.accessibilityHighContrastDarkAqua): return rgb(darkHC)
            case .some(.accessibilityHighContrastAqua): return rgb(lightHC)
            default: return rgb(light)
            }
        })
    }
    private static let orange = adaptive(light: 0xB45309, lightHC: 0x8A3F06, dark: 0xFFA94D, darkHC: 0xFFC285)
    private static let blue = adaptive(light: 0x1D4ED8, lightHC: 0x1E3A8A, dark: 0x6EA8FF, darkHC: 0x9CC2FF)
    /// Warnhinweise (kleiner Text auf getönter Blase).
    static let warning = adaptive(light: 0xB45309, lightHC: 0x8A3F06, dark: 0xFFA94D, darkHC: 0xFFC285)
    /// Nr. 370: „gut“-Grün für Text und Pegel (System-Grün hat auf hellem Grund nur ~2,3:1).
    static let success = adaptive(light: 0x15803D, lightHC: 0x14532D, dark: 0x4ADE80, darkHC: 0x86EFAC)
    /// Nr. 371: feste, dunkle Füllfarben für Knöpfe mit weißer Schrift (≥ 4,5:1 in beiden Modi).
    static let fillGreen = Color(nsColor: rgb(0x15803D))
    static let fillOrange = Color(nsColor: rgb(0xB45309))
    static let fillRed = Color(nsColor: rgb(0xB91C1C))
    static let fillBlue = Color(nsColor: rgb(0x1D4ED8))

    /// Farbe nach Seite: Partnersprache orange, meine Sprache blau (Standard: Thai orange, Englisch blau).
    static func color(_ lang: String) -> Color { Langs.isMine(lang) ? blue : orange }
    /// Auf schwarzem Grund (Partner-Ansicht ist immer dunkel).
    static func onBlack(_ lang: String) -> Color {
        Langs.isMine(lang) ? Color(red: 0.43, green: 0.66, blue: 1) : Color(red: 1, green: 0.66, blue: 0.30)
    }
    static func flag(_ lang: String) -> String { Langs.flag(lang) }
    static func name(_ lang: String) -> String { Langs.name(lang) }
}

/// Text für VoiceOver mit Sprachkennung je Abschnitt (Thai-Abschnitte als "th"). SwiftUI kennt auf macOS kein
/// `accessibilityLanguage`; die Kennung ist ein Hinweis (`languageIdentifier`), die automatische Spracherkennung von
/// VoiceOver bleibt der Rückfall.
func a11yAttributed(_ parts: [(String, String?)]) -> AttributedString {
    var out = AttributedString()
    for (text, lang) in parts {
        var a = AttributedString(text)
        if let lang { a.languageIdentifier = lang }
        out += a
    }
    return out
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

/// Hält das Scroll-Ereignis-Token (Klasse, damit @State es ohne Neuzeichnen verändern kann).
private final class ScrollMonitorBox {
    var token: Any?
    var lastWheelUp = Date.distantPast
    /// Letzte Änderung am Inhalt (neue/wachsende Blase): verschwindet die Endmarke kurz danach, war es der Inhalt,
    /// sonst hat der Nutzer gescrollt – egal ob Mausrad, Scrollbalken oder Tastatur (Nr. 352).
    var lastContentChange = Date.distantPast
}

/// Schrift mit dem eigenen Zoom (⌘+/⌘−) für Statuszeile, Hinweisbänder, Schnellsätze, Leerzustand (Nr. 353).
struct ScaledFont: ViewModifier {
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    let base: CGFloat
    let weight: Font.Weight
    init(_ base: CGFloat, _ weight: Font.Weight = .regular) { self.base = base; self.weight = weight }
    func body(content: Content) -> some View { content.font(.system(size: Prefs.scaled(base, scale), weight: weight)) }
}

extension View {
    func scaledFont(_ base: CGFloat, _ weight: Font.Weight = .regular) -> some View { modifier(ScaledFont(base, weight)) }
}

/// Reine Regel (testbar ohne Ansicht): Endmarke verschwunden – hat der Nutzer hochgescrollt?
enum AutoScroll {
    static let contentGrace: TimeInterval = 0.5
    static func userScrolledAway(now: Date, lastWheelUp: Date, lastContentChange: Date) -> Bool {
        now.timeIntervalSince(lastWheelUp) < 0.6 || now.timeIntervalSince(lastContentChange) > contentGrace
    }
}

struct ContentView: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var setup = EnvSetupModel.shared
    @ObservedObject private var hotKeys = HotKeys.shared
    @State private var hotKeysDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    @AppStorage(Prefs.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.tipsSeen) private var tipsSeen = false
    @AppStorage(Prefs.tipsRemindUntil) private var tipsRemindUntil = 0.0
    @AppStorage(Prefs.hideFromCapture) private var hideCapture = false
    @State private var whatsNew: [String] = []
    @AppStorage(Prefs.showQuick) private var showQuick = true
    @State private var showTips = false
    private var tipsDue: Bool {
        !tipsSeen && OnboardingLogic.remindDue(until: tipsRemindUntil, now: Date().timeIntervalSince1970)
    }
    @State private var bigText: Utterance?
    @State private var showGlossaryAdd = false
    @State private var showShortcuts = false
    @State private var showSelfTest = false
    @State private var showProfiles = false
    /// Hinweis „Zwei-Personen-Modus ohne Profil“ für diese Sitzung weggeklickt.
    @State private var twoPersonHintClosed = false
    @State private var correcting: Utterance?
    @State private var query = ""
    @State private var langFilter = ""          // "" = alle, sonst eine Sprache des Paars
    @State private var searchOpen = false
    @State private var userScrolledUp = false   // Auto-Scroll pausiert, bis der Nutzer wieder unten ist
    @State private var bottomVisible = true
    @State private var scrollBox = ScrollMonitorBox()
    @FocusState private var searchFocused: Bool
    @AppStorage(L.key) private var uiLang = L.defaultCode

    @State private var budgetHintClosed = false
    private var filtering: Bool { !query.isEmpty || !langFilter.isEmpty }

    var body: some View {
        let _ = L.sync(uiLang)
        VStack(spacing: 0) {
          if setup.visible {
            EnvSetupView(s: setup)        // Erststart / nach App-Update: Umgebung + Modelle
          } else {
            MainToolbar(showProfiles: $showProfiles)
            ConversationBar()
            if showQuick { QuickPhraseBar() }
            Divider()
            if m.micDenied { MicDeniedBanner() }
            if let log = m.crashLog { CrashBanner(log: log) }
            if let pv = m.protocolMismatch {
                NoticeBanner(icon: "exclamationmark.triangle.fill", tint: .red,
                             text: L.f("protocol_mismatch", pv, EngineModel.protocolVersion))
            }
            if m.restartDeferred && m.needsRestart {
                NoticeBanner(icon: "arrow.clockwise.circle", tint: LangStyle.warning, text: L.t("restart_deferred"),
                             action: (L.t("reload_now"), { m.restart() }))
            }
            if m.engineHung && m.running {
                NoticeBanner(icon: "exclamationmark.octagon.fill", tint: .red, text: L.t("engine_hung"),
                             action: (L.t("reload_now"), { m.restart() }))
            }
            if let v = m.viewingSession { ViewingBanner(title: v.title) }
            if let d = m.download { DownloadBanner(d: d) }
            if !hotKeys.failures.isEmpty && !hotKeysDismissed {   // Nr. 378: einmal sichtbar, nicht nur in den Einstellungen
                NoticeBanner(icon: "keyboard.badge.exclamationmark", tint: LangStyle.warning,
                             text: L.t("hotkeys_failed") + " " + hotKeys.failures.joined(separator: ", "),
                             action: (L.t("retry"), { HotKeys.shared.retryIfNeeded() }),
                             onClose: { hotKeysDismissed = true })
            }
            if !m.degradedModels.isEmpty {
                NoticeBanner(icon: "gauge.with.dots.needle.33percent", tint: LangStyle.warning,
                             text: L.f("degraded_models", m.degradedModels.map { L.t($0 == "thai_model" ? "degraded_thai"
                                 : $0 == "detect_model" ? "degraded_detect" : "degraded_other") }.joined(separator: ", ")),
                             action: (L.t("show_log"), { openLog() }), onClose: { m.degradedModels = [] })
            }
            if let e = m.lastError { ErrorBanner(error: e) }
            if !m.netDown.isEmpty { NetDownBanner() }
            if m.llm && m.llmBudget > 0 && m.llmMonthUSD >= m.llmBudget * 0.8 && !budgetHintClosed {   // Nr. 37
                let over = m.llmMonthUSD >= m.llmBudget
                NoticeBanner(icon: "dollarsign.circle", tint: LangStyle.warning,
                             text: L.f(over ? "budget_over" : "budget_near", m.llmMonthUSD, m.llmBudget),
                             onClose: { budgetHintClosed = true })
            }
            if let r = m.partnerRequest {   // Nr. 36
                NoticeBanner(icon: "person.wave.2", tint: LangStyle.warning, text: L.t(r), onClose: { m.partnerRequest = nil })
            }
            if m.fileBusy {   // Nr. 51
                NoticeBanner(icon: "waveform.badge.magnifyingglass", tint: .accentColor, text: L.t("file_working"))
            }
            if m.deletedBubble != nil {   // Nr. 34
                NoticeBanner(icon: "trash", tint: .secondary, text: L.t("bubble_deleted_undo"),
                             action: (L.t("undo_delete"), { m.undoDelete() }), onClose: { m.deletedBubble = nil })
            }
            if let v = m.vocabSuggestion { VocabSuggestionBanner(words: v.words, profile: v.profile) }
            if let u = m.unsureDrop {
                NoticeBanner(icon: "questionmark.bubble", tint: LangStyle.warning,
                             text: L.f("unsure_offer", String(u.text.prefix(120))),
                             action: (L.t("translate_anyway"), { m.translateUnsure() }), onClose: { m.unsureDrop = nil })
            }
            if let f = m.failedDrop {
                NoticeBanner(icon: "arrow.clockwise.circle", tint: LangStyle.warning,
                             text: L.f("failed_offer", String(f.text.prefix(120))),
                             action: (L.t("retry"), { m.retryFailed() }), onClose: { m.failedDrop = nil })
            }
            if let h = m.missedHint {
                NoticeBanner(icon: "ear.trianglebadge.exclamationmark", tint: LangStyle.warning, text: h,
                             onClose: { m.missedHint = nil })
            }
            if m.twoPersonIneffective && !twoPersonHintClosed {
                NoticeBanner(icon: "person.2.slash", tint: LangStyle.warning, text: L.t("two_person_no_profile"),
                             action: (L.t("profiles"), { showProfiles = true }), onClose: { twoPersonHintClosed = true })
            }
            if searchOpen || filtering || m.items.count > 5 { searchBar }
            conversation
            if m.pushToTalk && m.micOn { PushToTalkButton().padding(14) }
          }
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(WindowAccessor { w in
            w.identifier = Prefs.mainWindowID
            if w.frameAutosaveName.isEmpty { w.setFrameAutosaveName("DolmetscherMainWindow") }   // Größe/Ort merken
            w.level = onTop ? .floating : .normal
            w.sharingType = hideCapture ? .none : .readOnly      // Nr. 17
            let t = "Dolmetscher · " + m.status
            if w.title != t { w.title = t }
        })
        .sheet(isPresented: $showTips) {
            TipsSheet(engine: m, done: { tipsSeen = true; showTips = false },
                      later: { tipsRemindUntil = OnboardingLogic.remindUntil(now: Date().timeIntervalSince1970); showTips = false })
        }
        .sheet(isPresented: Binding(get: { !whatsNew.isEmpty }, set: { if !$0 { whatsNew = []; WhatsNew.markSeen() } })) {
            WhatsNewSheet(items: whatsNew) { whatsNew = []; WhatsNew.markSeen() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in   // Nr. 51: Audiodatei auf das Fenster ziehen
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { m.translateFile(url) } }
            }
            return true
        }
        .sheet(isPresented: $showProfiles) { ProfilesView().environmentObject(m) }
        .sheet(item: $correcting) { CorrectSheet(u: $0).environmentObject(m) }
        .sheet(item: $bigText) { BigTextSheet(u: $0) }
        .sheet(isPresented: $showGlossaryAdd) { GlossaryAddSheet().environmentObject(m) }
        .sheet(isPresented: $showShortcuts) { ShortcutsSheet() }
        .sheet(isPresented: $showSelfTest) { SelfTestSheet().environmentObject(m) }
        .onReceive(NotificationCenter.default.publisher(for: .showBigText)) { n in
            if let id = n.object as? UUID { bigText = m.items.first { $0.id == id } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGlossaryAdd)) { _ in showGlossaryAdd = true }
        .onReceive(NotificationCenter.default.publisher(for: .showShortcuts)) { _ in showShortcuts = true }
        .onReceive(NotificationCenter.default.publisher(for: .showSelfTest)) { _ in showSelfTest = true }
        .id(uiLang)                                   // Oberflächensprache sofort umschalten
        .onChange(of: m.items.isEmpty) { if m.items.isEmpty { query = ""; langFilter = ""; userScrolledUp = false } }
        .onChange(of: uiLang) { m.refreshStatus() }
        .onChange(of: setup.visible) { if !setup.visible && tipsDue { showTips = true } }
        .onAppear {
            if tipsDue && !setup.visible { showTips = true }
            if tipsSeen && !setup.visible { whatsNew = WhatsNew.pending() } else { _ = WhatsNew.pending() }
            installScrollMonitor()
        }
        .onDisappear { if let t = scrollBox.token { NSEvent.removeMonitor(t); scrollBox.token = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .showTips)) { _ in showTips = true }
        .onReceive(NotificationCenter.default.publisher(for: .showProfiles)) { _ in showProfiles = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchOpen = true
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// Erkennt Hochscrollen mit Mausrad/Trackpad: pausiert das automatische Mitscrollen.
    private func installScrollMonitor() {
        guard scrollBox.token == nil else { return }
        let box = scrollBox
        scrollBox.token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard e.window?.identifier == Prefs.mainWindowID else { return e }
            let dy = e.scrollingDeltaY
            if dy > 0.5 {                       // Inhalt wandert nach unten = nach oben gescrollt
                box.lastWheelUp = Date()
                if !bottomVisible { userScrolledUp = true }
            } else if dy < -0.5, bottomVisible {
                userScrolledUp = false
            }
            return e
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L.t("search"), text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel(L.t("search"))
            Picker(L.t("language_filter"), selection: $langFilter) {
                Text(L.t("filter_all")).tag("")
                ForEach(Langs.pair, id: \.self) { Text($0.uppercased()).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            .accessibilityLabel(L.t("language_filter"))
            if filtering {
                Text(L.f("results_count", shown.count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button { exportConversation(m, only: shown) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless).disabled(shown.isEmpty)
                    .help(L.t("export_hits")).accessibilityLabel(L.t("export_hits"))
            }
            if searchOpen || filtering {
                Button { query = ""; langFilter = ""; searchOpen = false; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(L.t("close")).accessibilityLabel(L.t("close"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .onExitCommand { query = ""; langFilter = ""; searchOpen = false; searchFocused = false }
    }

    /// Verlauf, ggf. nach Suchtext und Sprache gefiltert.
    private var shown: [Utterance] {
        let source = m.viewingSession?.items ?? m.items
        guard filtering else { return source }
        return source.filter { u in
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]   // „cafe“ findet „café“
            return (langFilter.isEmpty || u.lang == langFilter)
                && (query.isEmpty || u.text.range(of: query, options: opts) != nil
                    || u.out.range(of: query, options: opts) != nil)
        }
    }

    private func scrollToEnd(_ sv: ScrollViewProxy, animated: Bool, last: Utterance? = nil) {
        guard let last = last ?? shown.last else { return }
        if animated && !reduceMotion { withAnimation { sv.scrollTo(last.id, anchor: .bottom) } }
        else { sv.scrollTo(last.id, anchor: .bottom) }
    }

    private var conversation: some View {
        ScrollViewReader { sv in
            let shown = self.shown   // Nr. 369: Filter (bis 500 Blasen, localizedCaseInsensitive) einmal je Durchlauf
            ScrollView {
                LazyVStack(spacing: 12) {
                    if m.items.isEmpty { EmptyState() }
                    if !m.items.isEmpty && shown.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(L.t("no_results")).font(.headline)
                            Text(L.t("no_results_hint")).foregroundStyle(.secondary)
                            Button(L.t("reset_filter")) { query = ""; langFilter = ""; searchFocused = true }
                        }
                        .padding(.top, 40).frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(shown) { u in
                        Bubble(m: m, u: u, scale: scale,
                               playing: m.replayingID == u.id || (u.uid.map { m.speakingIDs.contains($0) } ?? false),
                               running: m.running, twoPerson: m.twoPerson, pairKey: m.mineLang + m.partnerLang,
                               onCorrect: { if m.viewingSession == nil { correcting = $0 } })
                            .equatable()
                            .id(u.id)
                    }
                    // Marke am Ende: sichtbar = der Nutzer ist unten; verschwindet sie nach Hochscrollen, pausiert das Mitscrollen.
                    Color.clear.frame(height: 1)
                        .onAppear { bottomVisible = true; userScrolledUp = false }
                        .onDisappear {
                            bottomVisible = false
                            // einen Durchlauf später prüfen: Inhalts-/Größenänderung desselben Layouts zählt mit
                            DispatchQueue.main.async {
                                if !bottomVisible, AutoScroll.userScrolledAway(
                                    now: Date(), lastWheelUp: scrollBox.lastWheelUp,
                                    lastContentChange: scrollBox.lastContentChange) {
                                    userScrolledUp = true
                                }
                            }
                        }
                }.padding(16)
            }
            // Sichtfeld wird kleiner (Hinweisband erscheint, Fenster schrumpft): kein Hochscrollen des Nutzers
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.size.height) { scrollBox.lastContentChange = Date() }
            })
            .onChange(of: shown.last) { scrollBox.lastContentChange = Date() }   // Text/Übersetzung wächst
            .onChange(of: shown.count) { scrollBox.lastContentChange = Date() }
            .onChange(of: scale) { scrollBox.lastContentChange = Date() }
            .onChange(of: shown.last?.id) {   // neue Blase
                if !userScrolledUp { scrollToEnd(sv, animated: true, last: shown.last) }
            }
            .onChange(of: shown.last?.pending) {   // Platzhalter wird zur fertigen Blase (gleiche id)
                if !userScrolledUp { scrollToEnd(sv, animated: true, last: shown.last) }
            }
            .onChange(of: shown.last?.partial) {   // Teiltext wächst: unten bleiben (ohne Animation, kommt oft)
                if !userScrolledUp, let last = shown.last, last.pending { scrollToEnd(sv, animated: false, last: last) }
            }
            .overlay(alignment: .bottomTrailing) {
                if userScrolledUp && !m.items.isEmpty {
                    Button {
                        userScrolledUp = false
                        scrollToEnd(sv, animated: true)
                    } label: {
                        Label(L.t("jump_latest"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(14)
                    .accessibilityLabel(L.t("jump_latest"))
                }
            }
        }
    }
}

/// Alle Sprachbefehle, gut lesbar: Befehl groß und in voller Textfarbe, Bedeutung daneben.
/// Steht im leeren Verlauf und jederzeit hinter dem Sprechblasen-Knopf in der Kopfzeile.
struct CommandsList: View {
    @AppStorage(Prefs.fontScale) private var scale = 1.0
    static let rows: [(cmd: String, key: String)] = [
        ("pause", "cmd_pause"), ("resume", "cmd_resume"), ("repeat", "cmd_repeat"),
        ("slower · faster", "cmd_slower"), ("louder · quieter", "cmd_louder"),
        ("English only · Thai only · auto", "cmd_only"),
        ("English off · Thai off · … on", "cmd_off"),
        ("male voice · female voice", "cmd_voice"), ("clear", "cmd_clear"), ("help", "cmd_help"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L.t("commands"), systemImage: "text.bubble")
                .font(.system(size: 17 * scale, weight: .bold))
            Text(L.t("commands_say"))
                .font(.system(size: 14 * scale)).foregroundStyle(.secondary)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 7) {
                ForEach(Self.rows, id: \.key) { row in
                    GridRow {
                        Text("“Translator, \(row.cmd)”")
                            .font(.system(size: 15 * scale, weight: .semibold))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        Text(L.t(row.key))
                            .font(.system(size: 14 * scale)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Leerer Verlauf: Richtung, Ladezustand, Beispiel und Sprachbefehle.
struct EmptyState: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(Langs.flag(m.mineLang)).accessibilityHidden(true)
                    Text(m.mineLang == "en" ? "English" : Langs.name(m.mineLang)).foregroundStyle(LangStyle.color(m.mineLang))
                }
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                HStack(spacing: 6) {
                    Text(Langs.flag(m.partnerLang)).accessibilityHidden(true)
                    Text(m.partnerLang == "th" ? "ไทย" : Langs.name(m.partnerLang))
                        .foregroundStyle(LangStyle.color(m.partnerLang))
                }
            }
            .scaledFont(26, .semibold)
            if m.loadingModel {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if m.download == nil { ProgressView().controlSize(.small) }
                        Text(L.t("empty_loading"))
                    }
                    ModelLoadProgress().frame(maxWidth: 360)
                }
                .foregroundStyle(.secondary)
            } else {
                Text(L.tp("empty")).foregroundStyle(.secondary)
                Text(L.t("chat_empty_start")).font(.callout).foregroundStyle(.secondary)
            }
            // Nr. 399: Beispielsatz anklickbar – Probe-Übersetzung prüft Übersetzung und Lautsprecher ohne Mikrofon
            Button { m.say("Where is the toilet?", lang: "en") } label: {
                Label(L.t("empty_example"), systemImage: "play.circle")
                    .scaledFont(15)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!m.engineReady || !(m.mineLang == "en" || m.partnerLang == "en"))
            .help(L.t("empty_example_help"))
            .accessibilityHint(L.t("empty_example_help"))
            CommandsList()
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .scaledFont(13)
        .frame(maxWidth: 640)
        .padding(.top, 40)
    }
}

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
        }
        .padding(14)
        .popover(isPresented: $showCommands, arrowEdge: .bottom) {
            CommandsList().padding(20).frame(minWidth: 520)
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
                    Image(systemName: m.active ? "stop.fill" : "mic.fill")
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
            Button(L.t("export") + " (⇧⌘E)") { exportConversation(m) }.disabled(m.items.isEmpty)
            Button(L.t("clear")) { confirmClear = true }.disabled(m.items.isEmpty)
            Button(L.t("open_log")) { openLog() }
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
    @State private var draft = ""
    @FocusState private var typing: Bool

    private func send() {
        if m.sayTyped(draft) { draft = "" }
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
            .accessibilityLabel(L.t("direction"))
            Toggle(isOn: $m.speak) {
                Image(systemName: m.speak ? "speaker.wave.2.fill" : "speaker.slash.fill")
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
            TextField(L.t("type_prompt"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onSubmit(send)
                .disabled(!m.engineReady)
                .help(m.engineReady ? L.t("type_prompt") : L.t("type_wait"))
                .accessibilityLabel(L.t("type_prompt"))
                .accessibilityHint(m.engineReady ? "" : L.t("type_wait"))
                .onChange(of: draft) { if draft.count > 1000 { draft = String(draft.prefix(1000)) } }
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
            if m.micOn { LevelBar(meter: m.meter) }
            Text(m.status).scaledFont(13, .semibold).lineLimit(2).help(m.status)
                .accessibilityLabel(L.t("status") + ": " + m.status)
                .accessibilityAddTraits(.updatesFrequently)
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
            if let med = m.latencyMedian { LatencyBadge(median: med) }
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
    var body: some View {
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
    let loc = Locale(identifier: L.lang == .de ? "de_DE" : "en_US")
    return String(format: "%.1f s", locale: loc, v)
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

/// Anzeigeskala des Pegels: leise Sprache (rms 0,02–0,1) bleibt sichtbar (logarithmisch, −50…0 dBFS).
enum LevelScale {
    static func display(_ rms: Double) -> Double {
        guard rms > 0.0001 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 50) / 50))
    }
}

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
                        let text = useTH ? ph.th : ph.en
                        Button { m.say(text, lang: useTH ? "th" : "en") } label: {
                            if ph.critical { Label(text, systemImage: "exclamationmark.triangle.fill") } else { Text(text) }
                        }
                            .lineLimit(1).frame(maxWidth: 260)
                            .buttonStyle(.bordered).tint(ph.critical ? .red : .accentColor)
                            .disabled(!m.engineReady || !(Langs.hasEnglish || Langs.hasThai))
                            .help(text + "\n" + (useTH ? ph.en : ph.th))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("welcome_title")).font(.title.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tip("waveform", L.t("tip_speak_title"), L.tp("tip_speak_text"))
                    tip("text.bubble", L.t("tip_cmd_title"), L.t("tip_cmd_text"))
                    tip("lock.shield", L.t("privacy_title"), L.t("privacy_text"))
                    OnboardingSteps(m: engine)
                    SetupChecklist(model: model, thai: thai)
                }
                .padding(.trailing, 8)
            }
            HStack {
                Button(L.t("onb_later")) { later() }.help(L.t("onb_later_help")).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L.t("lets_go"), action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 580, height: 680)
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
