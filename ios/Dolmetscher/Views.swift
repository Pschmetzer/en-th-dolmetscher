// Views.swift – Hauptansicht: Kopf mit Sprachen und Status, Sprechblasen-Verlauf, Start-Knopf und Texteingabe.
import StoreKit
import SwiftUI

enum LangStyle {
    /// Meine Sprache blau, Partnersprache orange (wie bisher Englisch/Thai).
    static func color(_ l: Lang, _ pair: LangPair) -> Color { l == pair.partner ? partnerColor : .blue }
    /// 584: Orange auf hellem Grund hat nur ca. 2:1 Kontrast – im hellen Modus ein dunkleres Orange (ca. 4,6:1).
    static let partnerColor = Color(UIColor { $0.userInterfaceStyle == .dark ? .systemOrange
        : UIColor(red: 0.70, green: 0.33, blue: 0.0, alpha: 1) })
    static func flag(_ l: Lang) -> String { l.flag }
    static func name(_ l: Lang) -> String { l.native }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(InterpreterModel.self) private var m
    @State private var showPartner = false
    @State private var big: Entry?
    @State private var editing: Entry?
    @State private var draft = ""
    @State private var confirmClear = false
    @State private var atEnd = true
    @State private var unseen = false
    @State private var askPoliteness = false
    /// 592: zuletzt beanstandeter Text – ein zweites Senden geht dann durch.
    @State private var warnedDraft: String?
    @ScaledMetric(relativeTo: .title3) private var roundButton: CGFloat = 52
    @AppStorage("politenessAsked") private var politenessAsked = false
    @AppStorage("prepShown") private var prepShown = false
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("onboardingLater") private var onboardingLater = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var typing: Bool

    /// iPad (breit): Gespräch links, Werkzeuge rechts (eigene Spalte außerhalb des NavigationStack).
    var body: some View {
        HStack(spacing: 0) {
            main
            if sizeClass == .regular {
                Divider().ignoresSafeArea()
                ToolsPanel().frame(minWidth: 320, idealWidth: 380, maxWidth: IPadLayout.toolsMaxWidth)
            }
        }
    }

    private var main: some View {
        @Bindable var m = m
        return NavigationStack {
            conversation
            // VoiceOver: Doppeltippen mit zwei Fingern startet und beendet das Dolmetschen.
            .accessibilityAction(.magicTap) { m.toggle() }
            // iPad mit Tastatur: ⌘↩ startet und beendet, ⌘B öffnet das Satzbuch.
            .background {
                Button("") { m.toggle() }.keyboardShortcut(.return, modifiers: .command)
                Button("") { m.sheet = .phrasebook }.keyboardShortcut("b", modifiers: .command)
                Button("") { m.sheet = .help }.keyboardShortcut("/", modifiers: .command)
            }
            .accessibilityHidden(false)
            .navigationTitle("Dolmetscher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showPartner = true } label: { Image(systemName: "person.2.wave.2") }
                        .accessibilityLabel(T("partner"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { m.sheet = .phrasebook } label: { Label(T("phrasebook"), systemImage: "book") }
                        Button { m.sheet = .photo } label: { Label(T("photo_text"), systemImage: "text.viewfinder") }
                        Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
                        Button { m.sheet = .places } label: { Label(T("places"), systemImage: "mappin.and.ellipse") }
                        Button { m.sheet = .learn } label: { Label(T("learn"), systemImage: "rectangle.stack") }
                        if m.features.thaiExtras {
                            Button { m.sheet = .helpNow } label: { Label(T("help_now"), systemImage: "sos") }
                            Button { m.sheet = .baht } label: { Label(T("baht_calc"), systemImage: "bahtsign.circle") }
                        }
                        Button { m.sheet = .prep } label: { Label(T("prep_title"), systemImage: "checklist") }
                        if m.features.voiceCommands {
                            Button { m.sheet = .help } label: { Label(T("commands"), systemImage: "text.bubble") }
                        }
                        ShareSummaryItems()
                        Button(role: .destructive) { confirmClear = true } label: { Label(T("clear"), systemImage: "trash") }
                            .disabled(m.visibleEntries.isEmpty)
                        Divider()
                        Button { m.sheet = .settings } label: { Label(T("settings"), systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(T("more"))
                }
            }
            .sheet(item: $m.sheet) { s in sheetView(s).modifier(ShieldWhenInactive()) }
            .confirmationDialog(T("clear_confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(T("clear"), role: .destructive) { m.clear() }
                Button(T("cancel"), role: .cancel) {}
            }
            .alert(T("cellular_title"), isPresented: $m.cellularDownloadPrompt) {
                Button(T("cellular_go")) { m.startAllowingCellular() }
                Button(T("cellular_wait"), role: .cancel) {}
            } message: { Text(T("cellular_msg")) }
            .fullScreenCover(isPresented: $showPartner) { PartnerView().modifier(ShieldWhenInactive()) }
            .modifier(ReviewPrompt(covered: showPartner || big != nil))
            #if DEBUG
            .task { DebugScreens.apply(m, partner: $showPartner) }
            #endif
            .fullScreenCover(item: $big) { e in BigTextView(entryID: e.id).modifier(ShieldWhenInactive()) }
            .onChange(of: m.bigRequest) { _, id in showRequested(id) }
            .task { firstLaunch() }
            // 587: nach der Reise-Vorbereitung (erster Start) einmal nach der Höflichkeitsform fragen.
            .onChange(of: m.sheet) { _, s in if s == nil { askPolitenessOnce() } }
            .confirmationDialog(T("politeness_ask"), isPresented: $askPoliteness, titleVisibility: .visible) {
                Button(T("pol_male")) { m.politeness = .male }
                Button(T("pol_female")) { m.politeness = .female }
                Button(T("pol_off")) { m.politeness = .off }
            } message: { Text(T("politeness_note")) }
            .alert(T("edit_text"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                EditAlert(entry: editing) { text in if let e = editing { m.edit(e.id, text: text) } }
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let id = m.cultureHint, let p = Phrasebook.packs.first(where: { $0.id == id }) {
                CultureHintBanner(pack: p, open: {
                    m.phrasebookStart = p.key
                    m.cultureHint = nil
                    m.sheet = .phrasebook
                }, close: { m.cultureHint = nil })
                .padding(.top, 8)
            }
            PermissionBanner()
            history
            bottomBar
        }
    }

    /// Kurzbefehl „Letzte Übersetzung groß“.
    private func showRequested(_ id: UUID?) {
        guard let id, let e = m.entries.first(where: { $0.id == id }) else { return }
        m.bigRequest = nil
        big = e
    }

    /// Aus der Hilfe: Willkommensfluss noch einmal (erst die Hilfe schließen, dann öffnen).
    private func replayWelcome() {
        m.sheet = nil
        Task { try? await Task.sleep(for: .milliseconds(450)); m.sheet = .welcome }
    }

    /// Beim ersten Start einmal den Willkommensfluss zeigen (Offline-Pakete, Berechtigungen).
    private func firstLaunch() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["DOLMETSCHER_SCREEN"] != nil || env["DOLMETSCHER_DEMO"] != nil || env["XCTestConfigurationFilePath"] != nil { return }
        #endif
        if prepShown { askPolitenessOnce() }
        guard !prepShown else { return }
        prepShown = true
        if OnboardingPolicy.shouldShowAtLaunch(completed: onboardingDone, deferred: onboardingLater, existingUser: false), m.sheet == nil {
            m.sheet = .welcome
        }
    }

    /// 587: Höflichkeitsform einmal fragen statt still „männlich“ – nicht, wenn schon eine gewählt ist.
    private func askPolitenessOnce() {
        guard !politenessAsked, m.features.thaiExtras else { return }
        politenessAsked = true
        if UserDefaults.standard.object(forKey: "politeness") == nil { askPoliteness = true }
    }

    @ViewBuilder private func sheetView(_ s: AppSheet) -> some View {
        switch s {
        case .prep: TravelPrepView()
        case .welcome: OnboardingView()
        case .places: PlacesView()
        case .learn: LearnView()
        case .helpNow: HelpNowView()
        #if DEBUG
        case .widgetPreview: WidgetPreviewScreen()
        #endif
        case .settings: SettingsView()
        case .phrasebook: PhrasebookView()
        case .photo: PhotoTextView()
        case .emergency: EmergencyView()
        case .baht: BahtCalculatorView()
        case .summary: SummaryView()
        case .allergy: AllergyCardView()
        case .privacy:
            NavigationStack {
                PrivacyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.sheet = nil } } }
            }
        case .help:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HelpGuideCard(); CommandsCard()
                        Button { replayWelcome() } label: { Label(T("ob_replay"), systemImage: "hand.wave") }.buttonStyle(.bordered)
                    }.padding()
                }
                .navigationTitle(T("help_title"))
                .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { m.sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Kopf

    private var header: some View {
        @Bindable var m = m
        return VStack(spacing: 10) {
            let p = m.pair
            Menu {
                // Schnellwechsel: die zuletzt benutzten Paare, ohne in die Einstellungen zu gehen.
                ForEach(Array(RecentPairs.load(from: UserDefaults.standard).filter { $0 != p }.enumerated()), id: \.offset) { _, q in
                    Button("\(q.mine.flag) \(q.mine.native) ⇄ \(q.partner.flag) \(q.partner.native)") { m.pair = q }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("\(p.mine.flag) \(p.mine.native)").foregroundStyle(LangStyle.color(p.mine, p))
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                    Text("\(p.partner.flag) \(p.partner.native)").foregroundStyle(LangStyle.color(p.partner, p))
                }
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .disabled(m.isBusy || RecentPairs.load(from: UserDefaults.standard).filter { $0 != p }.isEmpty)
            .accessibilityElement(children: .combine)
            Picker(T("direction"), selection: $m.mode) {
                if p.distinguishable { Text(T("mode_auto")).tag(Direction.auto) }
                Text("\(p.mine.flag) → \(p.partner.flag)").tag(Direction.mine)
                Text("\(p.partner.flag) → \(p.mine.flag)").tag(Direction.partner)
            }
            .pickerStyle(.segmented)
            .disabled(m.isBusy)
            if !p.distinguishable {
                // Gleiche Schrift (z. B. en/de): die Sprache lässt sich nicht sicher erkennen.
                Text(T("same_script_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            statusLine
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        if m.idleWarning { return "💤 " + T("idle_warn") }
        if let n = m.notice { return n }
        switch m.phase {
        case .idle: return T("idle")
        case .loading:
            if m.whisperPreparing { return T("whisper_preparing") }
            guard let d = m.download else { return T("loading") }
            return "\(T("downloading")) \(LangStyle.flag(d.lang)) \(Int(d.fraction * 100)) %"
        case .failed(let e): return "⚠️ " + e
        case .listening:
            if m.interrupted { return "📞 " + T("interrupted") }
            if m.paused { return "⏸ " + T(m.features.voiceCommands ? "paused" : "paused_plain") }
            if m.speakingID != nil { return "🔊 " + T("speaking") }
            if m.hearing { return "🎙 " + T("hearing") }
            return m.offline && m.allowOnline ? "📵 " + T("net_offline_hint") : T("listening")
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if m.isBusy { ProgressView().controlSize(.small) }
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if m.idleWarning {
                Button(T("idle_continue")) { m.touch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            if m.canUndoClear {
                Button(T("undo")) { m.undoClear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if m.micDenied, case .failed = m.phase, let url = URL(string: UIApplication.openSettingsURLString) {
                Button(T("open_settings")) { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .animation(Motion.animation(reduce: reduceMotion), value: statusText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Verlauf

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if m.hiddenCount > 0 {
                        Button { m.unlockHistory() } label: {
                            Label(String(format: T("lock_hidden"), m.hiddenCount), systemImage: "lock.fill")
                                .font(.footnote)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if m.visibleEntries.isEmpty && m.partial.isEmpty && m.hiddenCount == 0 {
                        // 641: Beispiel nur zeigen, nicht gleich laut vorlesen (leise Räume).
                        EmptyState { m.submit(T("example_sentence"), speak: false) }
                    }
                    ForEach(m.visibleEntries) { e in
                        Bubble(entry: e, onBig: { big = e }, onEdit: { editing = e }).id(e.id)
                    }
                    if !m.partial.isEmpty {
                        PartialLine(text: m.partial, finishing: m.finishing).id("partial")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            // Nur mitlaufen, wenn man ohnehin unten ist – sonst „Neu“-Knopf statt Sprung beim Lesen.
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 80
            } action: { _, end in
                atEnd = end
                if end { unseen = false }
            }
            .onChange(of: m.entries.count) { follow(proxy, animated: true) }
            .onChange(of: m.entries.last?.translation) { follow(proxy, animated: true) }
            .onChange(of: m.partial) { follow(proxy, animated: false) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .overlay(alignment: .bottom) {
                if unseen {
                    Button {
                        unseen = false
                        withAnimation(Motion.animation(reduce: reduceMotion)) { proxy.scrollTo("end", anchor: .bottom) }
                    } label: { Label(T("new_below"), systemImage: "arrow.down") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard atEnd else { unseen = true; return }
        if animated { withAnimation(Motion.animation(reduce: reduceMotion)) { proxy.scrollTo("end", anchor: .bottom) } } else { proxy.scrollTo("end", anchor: .bottom) }
    }

    // MARK: Fuß

    private var suggestions: [Phrase] {
        m.features.thaiExtras ? Phrasebook.suggestions(draft) : []
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            if !suggestions.isEmpty {
                SuggestionChips(phrases: suggestions) { p in
                    m.say(p)
                    draft = ""
                }
            }
            HStack(spacing: 8) {
                Button { m.sheet = .phrasebook } label: { Image(systemName: "book").font(.title3).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(T("phrasebook"))
                Button { m.sheet = .photo } label: { Image(systemName: "text.viewfinder").font(.title3).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(T("photo_text"))
                TextField(T("type_hint"), text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                if draft.isEmpty {
                    // 591: Chat-Antwort (Line, Grab) einfügen und gleich übersetzen.
                    PasteButton(payloadType: String.self) { items in
                        guard let text = items.first else { return }
                        Task { @MainActor in m.submit(text) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(T("paste_translate"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .accessibilityLabel(T("translate"))
                }
            }
            .padding(.horizontal)
            HStack(spacing: 16) {
                leftButton
                if m.pushToTalk {
                    TalkButton { typing = false }
                } else {
                    MicButton { typing = false }
                }

                Button {
                    m.speakingID != nil ? m.stopSpeaking() : m.run(.repeat)
                } label: {
                    Image(systemName: m.speakingID != nil ? "speaker.slash.fill" : "arrow.counterclockwise")
                        .frame(width: roundButton, height: roundButton)
                        .background(.quaternary, in: Circle())
                }
                .disabled(m.entries.isEmpty)
                .accessibilityLabel(m.speakingID != nil ? T("stop_speaking") : T("cmd_repeat"))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    /// Pause/Weiter; bei Push-to-talk stattdessen „Zuhören beenden“.
    @ViewBuilder private var leftButton: some View {
        if m.pushToTalk {
            Button { m.stop() } label: {
                Image(systemName: "stop.fill")
                    .frame(width: roundButton, height: roundButton)
                    .background(.quaternary, in: Circle())
            }
            .disabled(!m.isListening && !m.isBusy)
            .accessibilityLabel(T("stop"))
        } else {
            Button {
                m.run(m.paused ? .resume : .pause)
            } label: {
                Image(systemName: m.paused ? "play.fill" : "pause.fill")
                    .frame(width: roundButton, height: roundButton)
                    .background(.quaternary, in: Circle())
            }
            .disabled(!m.isListening)
            .accessibilityLabel(m.paused ? T("resume") : T("pause"))
        }
    }

    private func send() {
        // 592: dritte Sprache (z. B. Deutsch bei Englisch ⇄ Thai) – einmal warnen, beim zweiten Senden übersetzen.
        if warnedDraft != draft, let code = TypedLanguageCheck.foreign(draft, pair: m.pair) {
            warnedDraft = draft
            let name = Locale(identifier: m.uiLang).localizedString(forLanguageCode: code) ?? code
            m.flash("⚠️ " + String(format: T("typed_foreign"), name, m.pair.mine.name(in: m.uiLang), m.pair.partner.name(in: m.uiLang)), seconds: 6)
            return
        }
        warnedDraft = nil
        m.submit(draft)
        draft = ""
    }
}

/// Live-Vorschau; nach Satzende mit „Übersetze …“, bis die Blase erscheint.
struct PartialLine: View {
    let text: String
    let finishing: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(text).font(.callout).foregroundStyle(.secondary)
            if finishing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(T("translating")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.isEmpty ? T("translating") : String(format: T("hearing_now"), text))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Satzbuch-Vorschläge beim Tippen: geprüfte Thai-Fassung mit einem Tipp.
struct SuggestionChips: View {
    let phrases: [Phrase]
    var pick: (Phrase) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(phrases) { p in
                    Button { pick(p) } label: {
                        Label(p.gloss, systemImage: "book.closed")
                            .font(.footnote)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(T("suggest_hint"))
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Push-to-talk: halten = zuhören, loslassen = übersetzen.
struct TalkButton: View {
    @Environment(InterpreterModel.self) private var m
    var before: () -> Void = {}

    private var held: Bool { m.pttHeld }
    private var label: String { held ? T("ptt_release") : (m.isBusy ? T("loading") : T("ptt_hold")) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: held ? "waveform" : "mic.fill")
            Text(label).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.title3.bold())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(held ? Color.red : Color.blue, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: held ? CGFloat(m.level) * 6 : 0))
        .modifier(PushGesture(tapMode: m.pttTapMode, held: held,
                              press: { before(); m.pttPress() }, release: { m.pttRelease() }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { held ? m.pttRelease() : m.pttPress() }
    }
}

/// Bewertungsbitte nur, wenn nichts läuft und nichts offen ist (nie mitten im Gespräch).
struct ReviewPrompt: ViewModifier {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.requestReview) private var requestReview
    let covered: Bool

    private var ready: Bool { m.canAskReview && !covered }

    func body(content: Content) -> some View {
        content.onChange(of: ready) { _, ok in
            guard ok else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard ready else { return }
                m.reviewAsked()
                requestReview()
            }
        }
    }
}

/// Start/Stopp mit Pegel-Rand. Eigene View, damit der häufig wechselnde Pegel nur sie neu zeichnet.
struct MicButton: View {
    @Environment(InterpreterModel.self) private var m
    var before: () -> Void = {}

    var body: some View {
        let active = m.isListening || m.isBusy
        Button { before(); m.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: active ? "stop.fill" : "mic.fill")
                Text(active ? T("stop") : T("start"))
            }
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(active ? Color.red : Color.green, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: m.isListening ? CGFloat(m.level) * 6 : 0))
        }
        .accessibilityLabel(active ? T("stop") : T("start"))
        .accessibilityInputLabels(active ? [T("stop"), "Stop", "Stopp"] : [T("start"), "Start", "Listen"])
    }
}

private struct EditAlert: View {
    let entry: Entry?
    var onSave: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(T("edit_text"), text: $text)
            .onAppear { text = entry?.text ?? "" }
        Button(T("translate")) { onSave(text) }
        Button(T("cancel"), role: .cancel) {}
    }
}

struct ProviderBadge: View {
    let provider: String?
    var body: some View {
        switch provider {
        case "apple": Image(systemName: "iphone").accessibilityLabel(T("prov_offline"))
        case "phrasebook": Image(systemName: "book.closed").accessibilityLabel(T("phrasebook"))
        case "google", "mymemory": Image(systemName: "globe").accessibilityLabel(T("prov_online"))
        case "card": Image(systemName: "hand.tap").accessibilityLabel(T("answer_cards"))
        default: EmptyView()
        }
    }
}

struct Bubble: View {
    @Environment(InterpreterModel.self) private var m
    let entry: Entry
    var onBig: () -> Void
    var onEdit: () -> Void
    @AppStorage("fxRate") private var fxRate = FXDefaults.rate(for: FXDefaults.code())
    @AppStorage("fxCode") private var fxCode = FXDefaults.code()

    var body: some View {
        let color: Color = LangStyle.color(entry.target, m.pair)
        let fromPartner: Bool = entry.src == m.pair.partner
        HStack {
            if fromPartner { Spacer(minLength: 36) }
            accessible(card(color))
            if !fromPartner { Spacer(minLength: 36) }
        }
    }

    // Aufgeteilt in kleine Teile mit festen Typen – sonst braucht der Compiler zu lange (CI-Fehler).

    @ViewBuilder private func translationPart(_ color: Color) -> some View {
        if let t = entry.translation {
            Text(t)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            RomanLine(text: roman, approximate: m.showRoman && entry.romanIsApproximate)
            if m.features.thaiExtras { PriceLine(text: entry.text + " " + t) }
            if m.backCheck, let b = entry.back { BackLine(text: b, deviates: entry.backDeviates) }
        } else if let err = entry.error {
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠️ " + err).font(.callout).foregroundStyle(.red)
                HStack {
                    Button(T("retry")) { m.retry(entry.id) }.buttonStyle(.bordered).controlSize(.small)
                    switch ErrorAdvice.action(for: err) {
                    case .appSettings:
                        Button(T("settings")) { m.sheet = .settings }.buttonStyle(.bordered).controlSize(.small)
                    case .systemSettings:
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Button(T("open_settings")) { UIApplication.shared.open(url) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    case .none: EmptyView()
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(T("translating")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func card(_ color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        let ring: Double = m.speakingID == entry.id ? 0.8 : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(LangStyle.flag(entry.src)) \(entry.text)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            translationPart(color)
            actions
        }
        .padding(12)
        .background(color.opacity(0.12), in: shape)
        .overlay(shape.stroke(color.opacity(ring), lineWidth: 2))
        .contentShape(shape)
        .onTapGesture { if entry.translation != nil { onBig() } }
        .contextMenu { menu }
    }

    /// VoiceOver: eine Blase = ein Element; die Knöpfe als Aktionen.
    private func accessible<V: View>(_ v: V) -> some View {
        let done: Bool = entry.translation != nil
        let traits: AccessibilityTraits = done ? .isButton : []
        let hint: String = done ? T("show_big") : ""
        return v
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)
            .accessibilityAddTraits(traits)
            .accessibilityHint(hint)
            .accessibilityAction { if done { onBig() } }
            .accessibilityActions { a11yActions }
    }

    private var roman: String? { m.showRoman ? entry.romanized : entry.roman }

    private var a11yLabel: Text {
        var extras: [String] = []
        if entry.translation != nil {
            if m.backCheck, entry.backDeviates { extras.append(T("back_deviates")) }
            // RomanLine und PriceLine fehlen sonst für VoiceOver und Sprachsteuerung.
            if m.features.thaiExtras, let t = entry.translation,
               let price = PriceSpotter.line(PriceSpotter.amounts(in: entry.text + " " + t), rate: fxRate, code: fxCode,
                                             locale: Locale(identifier: L10n.lang)) { extras.append(price) }
        } else if let err = entry.error { extras.append(err) }
        else { extras.append(T("translating")) }
        return A11yLabel.text(A11yLabel.build(src: entry.src, text: entry.text, target: entry.target,
                                              translation: entry.translation, extras: extras, uiLang: L10n.lang))
    }

    @ViewBuilder private var a11yActions: some View {
        if entry.translation != nil {
            Button(T("replay")) { m.speak(entry) }
            Button(T("replay_slow")) { m.speak(entry, slow: true) }
            if let t = entry.translation { Button(T("copy")) { m.copy(t) } }
            Button(m.isFavorite(entry) ? T("unfavorite") : T("favorite")) { m.toggleFavorite(entry) }
        }
        if entry.error != nil { Button(T("retry")) { m.retry(entry.id) } }
        if entry.alt?.isEmpty == false { Button(T("swap")) { m.swapLanguage(entry.id) } }
        Button(T("edit_text"), action: onEdit)
        Button(T("delete")) { m.delete(entry.id) }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if entry.translation != nil {
                Button {
                    m.speakingID == entry.id ? m.stopSpeaking() : m.speak(entry)
                } label: {
                    Image(systemName: m.speakingID == entry.id ? "stop.circle.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(m.speakingID == entry.id ? T("stop_speaking") : T("replay"))
                Button { m.speak(entry, slow: true) } label: { Image(systemName: "tortoise") }
                    .accessibilityLabel(T("replay_slow"))
                Button { m.toggleFavorite(entry) } label: {
                    Image(systemName: m.isFavorite(entry) ? "star.fill" : "star")
                        .foregroundStyle(m.isFavorite(entry) ? Color.yellow : Color.secondary)
                }
                .accessibilityLabel(m.isFavorite(entry) ? T("unfavorite") : T("favorite"))
            }
            if let alt = entry.alt, !alt.isEmpty {
                Button { m.swapLanguage(entry.id) } label: {
                    Label(LangStyle.flag(entry.target), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel(T("swap"))
            }
            Spacer(minLength: 0)
            ProviderBadge(provider: entry.provider).font(.caption)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var menu: some View {
        if let t = entry.translation {
            Button { m.copy(t) } label: { Label(T("copy"), systemImage: "doc.on.doc") }
            ShareLink(item: "\(entry.text)\n\(t)") { Label(T("share_one"), systemImage: "square.and.arrow.up") }
            Button(action: onBig) { Label(T("show_big"), systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        Button(action: onEdit) { Label(T("edit_text"), systemImage: "pencil") }
        if entry.alt?.isEmpty == false {
            Button { m.swapLanguage(entry.id) } label: { Label(T("swap"), systemImage: "arrow.triangle.2.circlepath") }
        }
        Button(role: .destructive) { m.delete(entry.id) } label: { Label(T("delete"), systemImage: "trash") }
    }
}

/// Eine Übersetzung bildschirmfüllend – zum Zeigen (Taxifahrer, Kellner).
struct BigTextView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled72: CGFloat = 72
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var flipped = false

    var body: some View {
        let e = m.entries.first { $0.id == entryID }
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(e?.translation ?? "")
                    .font(.system(size: scaled72, weight: .bold))
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LangStyle.color(e?.target ?? m.pair.partner, m.pair))
                RomanLine(text: m.showRoman ? e?.romanized : e?.roman, font: .title3)
                Text(e?.text ?? "").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            // Kein Schließen per Tipp: wer dem Fahrer das Handy reicht, schließt sonst versehentlich.
            Divider()
            HStack(spacing: 28) {
                Button { flipped.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel(T("flip"))
                Button { if let e { m.speak(e) } } label: { Image(systemName: "speaker.wave.2.fill") }
                    .accessibilityLabel(T("replay"))
                Button { if let e { m.speak(e, slow: true) } } label: { Image(systemName: "tortoise.fill") }
                    .accessibilityLabel(T("replay_slow"))
                Spacer()
                Button(T("done")) { dismiss() }
            }
            .font(.title2)
            .padding()
        }
        .persistentSystemOverlays(.hidden)
        .modifier(FullBrightness())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; m.touch() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = m.isListening }
    }
}

struct EmptyState: View {
    @Environment(InterpreterModel.self) private var m
    var tryExample: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(String(format: T("empty_hint_pair"), m.pair.mine.name(in: L10n.lang), m.pair.partner.name(in: L10n.lang)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // Beispielsatz nur, wenn die Sprache der Oberfläche im Paar ist (sonst würde er falsch erkannt).
            if let ui = L10n.asLang, m.pair.contains(ui) {
            Button(action: tryExample) {
                Text(String(format: T("empty_example_fmt"), T("example_sentence")))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { m.sheet = .phrasebook } label: { Label(T("phrasebook"), systemImage: "book") }
                Button { m.sheet = .photo } label: { Label(T("photo_text"), systemImage: "text.viewfinder") }
                Button { m.sheet = .emergency } label: { Label(T("emergency"), systemImage: "cross.case") }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            .font(.footnote)
            if !m.offlineReady {
                Button { m.sheet = .prep } label: {
                    Label(T(m.allowOnline ? "online_hint" : "offline_hint"), systemImage: m.allowOnline ? "globe" : "arrow.down.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            if m.features.voiceCommands { CommandsCard() }
        }
        .padding(.top, 8)
    }
}

struct CommandsCard: View {
    private let rows: [(String, String)] = [
        ("pause", "cmd_pause"), ("resume", "cmd_resume"), ("repeat", "cmd_repeat"),
        ("slower · faster", "cmd_slower"), ("louder · quieter", "cmd_louder"), ("clear", "cmd_clear"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(T("commands"), systemImage: "text.bubble").font(.headline)
            Text(T("commands_say")).font(.subheadline).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("“Translator, \(row.0)”").font(.callout.weight(.semibold))
                    Text(T(row.1)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Umschrift unter einer Übersetzung (eigene View: hält den Ausdruck in `Bubble` für den Compiler klein).
struct RomanLine: View {
    let text: String?
    var font: Font = .caption
    /// Maschinelle Umschrift: „≈“ davor, als grobe Lautschrift erkennbar.
    var approximate = false
    var body: some View {
        if let text { Text((approximate ? "≈ " : "") + text).font(font).italic().foregroundStyle(.secondary) }
    }
}

/// Rückübersetzung, bei Abweichung orange mit Warnzeichen.
struct BackLine: View {
    let text: String
    let deviates: Bool

    private var icon: String { deviates ? "exclamationmark.triangle.fill" : "arrow.uturn.backward" }
    private var tint: Color { deviates ? LangStyle.partnerColor : .secondary }
    private var label: String {
        let head: String = T("back_label") + ": " + text
        return deviates ? T("back_deviates") + ". " + head : head
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Menüeinträge „Teilen“ (581: Text erst beim Teilen gebaut) und „Zusammenfassung“ (nur wenn verfügbar).
private struct ShareSummaryItems: View {
    @Environment(InterpreterModel.self) private var m

    var body: some View {
        let export = TranscriptExport(entries: m.visibleEntries, lang: m.uiLang)
        ShareLink(item: export, preview: SharePreview(T("share"))) { Label(T("share"), systemImage: "square.and.arrow.up") }
            .disabled(m.visibleEntries.isEmpty)
        ShareLink(item: TranscriptCSV(entries: m.visibleEntries), preview: SharePreview("Dolmetscher.csv")) {
            Label(T("export_csv"), systemImage: "tablecells")
        }
        .disabled(m.visibleEntries.isEmpty)
        Button { m.copy(m.transcript) } label: { Label(T("copy_all"), systemImage: "doc.on.doc") }
            .disabled(m.visibleEntries.isEmpty)
        if m.summaryEnabled && ConversationSummary.available(for: m.pair.mine) {
            Button { m.sheet = .summary } label: { Label(T("summary"), systemImage: "text.append") }
                .disabled(m.visibleEntries.count < 2)
        }
    }
}
