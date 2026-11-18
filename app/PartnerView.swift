// PartnerView.swift – Vollbild-Ansicht für die Gesprächspartnerin: nur die letzte Übersetzung, sehr groß.
import SwiftUI
import AppKit

struct PartnerView: View {
    @EnvironmentObject var m: EngineModel
    @State private var window: NSWindow?
    @State private var screenCount = NSScreen.screens.count
    @AppStorage(Prefs.translit) private var translit = true
    @AppStorage(L.key) private var uiLang = L.defaultCode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nr. 385: Gespräch am Tisch (Laptop zwischen beiden) – Inhalt um 180° drehen; eigene Schriftgröße.
    @AppStorage("partnerRotated") private var rotated = false
    @AppStorage("partnerZoom") private var zoom = 1.0
    /// Wie viele Übersetzungen zurückgeblättert wird (0 = die neueste); springt bei neuer Übersetzung zurück.
    @State private var back = 0
    @AppStorage(Prefs.hideFromCapture) private var hideCapture = false
    private static let zoomRange = PartnerLogic.zoomRange
    /// Hoher Kontrast: reines Weiß auf Schwarz, Zahlen gelb; die Sprachfarben fallen weg (Name steht ohnehin als Text da).
    @AppStorage("partnerContrast") private var highContrast = false
    /// Präsentationsmodus: Leiste ausgeblendet, nur Text und die beiden Bitten.
    @State private var presentation = false
    @AppStorage("partnerFullscreen") private var wasFullscreen = false

    /// Startschriftgröße aus Fenstergröße und Textlänge (minimumScaleFactor fängt den Rest ab).
    private func fontSize(for text: String, in size: CGSize) -> CGFloat {
        CGFloat(PartnerLogic.fontSize(length: text.count, width: size.width, height: size.height)) * CGFloat(zoom)
    }

    private func langColor(_ code: String) -> Color { highContrast ? .white : LangStyle.onBlack(code) }

    /// Text mit hervorgehobenen Zahlen (fett, unterstrichen, gelb), damit Preise und Uhrzeiten sofort auffallen.
    private func numbered(_ text: String, base: Color) -> Text {
        var out = Text("")
        for seg in PartnerLogic.segments(text) {
            if seg.isNumber {
                out = out + Text(seg.text).fontWeight(.black).underline().foregroundColor(Color(red: 1, green: 0.9, blue: 0.2))
            } else {
                out = out + Text(seg.text).foregroundColor(base)
            }
        }
        return out
    }

    /// „Bitte sprechen“ in einer Sprache des Paars; Thai mit dem Höflichkeitswort der Einstellung.
    private func pleaseSpeak(_ code: String) -> String {
        let s = Langs.info(code)?.pleaseSpeak ?? "Please speak"
        return code == "th" ? s + (m.polite == "ka" ? "ค่ะ" : "ครับ") : s
    }

    /// Zustand nicht nur als Farbe: jedes Symbol hat eine eigene Form.
    private var stateIcon: (name: String, color: Color) {
        if !m.running { return ("stop.circle.fill", .gray) }
        if m.paused { return ("pause.circle.fill", .gray) }
        if m.busy { return ("ellipsis.circle.fill", Color(red: 1, green: 0.66, blue: 0.30)) }
        return m.micOn ? ("mic.circle.fill", .green) : ("mic.slash.circle.fill", .gray)
    }

    /// Pause oder Mikrofon aus: großes Band statt nur grauem Symbol (Nr. 347), damit die Partnerin sieht,
    /// dass gerade nicht übersetzt wird. Text-Schlüssel der L10n.
    private var stopBanner: (icon: String, key: String)? {
        guard m.running else { return nil }
        if m.paused { return ("pause.circle.fill", "partner_banner_paused") }
        if !m.micOn { return ("mic.slash.circle.fill", "partner_banner_mic_off") }
        return nil
    }

    private var finished: [Utterance] { m.items.filter { $0.translated && !$0.pending } }
    /// Angezeigte Übersetzung: die neueste oder, nach Zurückblättern, eine ältere.
    private var shownItem: Utterance? {
        let f = finished
        if f.isEmpty { return m.items.last(where: { !$0.pending }) }
        return f[max(0, f.count - 1 - min(back, f.count - 1))]
    }

    /// Partnersprache, wenn die Oberfläche sie kann (de/en/th), sonst die eingestellte Oberflächensprache.
    private var partnerUI: UILang? { UILang(rawValue: m.partnerLang) }

    /// Große Schaltfläche, Beschriftung in der Partnersprache (de/en/th, sonst Englisch) und darunter in meiner.
    @ViewBuilder private func partnerButton(_ key: String, icon: String, shortcut: KeyEquivalent, action: @escaping () -> Void) -> some View {
        let main = L.t(key, partnerUI ?? .en)
        Button(action: action) {
            VStack(spacing: 2) {
                Label(main, systemImage: icon).font(.system(size: 30, weight: .bold))
                if L.t(key) != main { Text(L.t(key)).font(.system(size: 18)).opacity(0.8) }
            }
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [])
        .help(main + " (" + shortcut.character.uppercased() + ")")
        .accessibilityLabel(main)
    }

    @ViewBuilder private func stopBannerView(_ b: (icon: String, key: String)) -> some View {
        let main = L.t(b.key, partnerUI)
        let mine = L.t(b.key)
        VStack(spacing: 6) {
            Label(main, systemImage: b.icon)
                .font(.system(size: 40, weight: .bold))
            if mine != main {
                Text(mine).font(.system(size: 24, weight: .semibold)).opacity(0.85)
            }
        }
        .minimumScaleFactor(0.4)
        .multilineTextAlignment(.center)
        .foregroundStyle(.black)
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(red: 1, green: 0.78, blue: 0.30), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    var body: some View {
        let _ = L.sync(uiLang)
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
            if !m.running {
                Text(L.t("partner_not_started"))
                    .font(.system(size: 48, weight: .semibold))
                    .minimumScaleFactor(0.3)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(48)
            } else if let u = shownItem {
                GeometryReader { geo in
                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    let fs = fontSize(for: u.out, in: geo.size)
                    Text(LangStyle.flag(u.to) + " " + LangStyle.name(u.to))   // Sprache auch als Text, nicht nur als Farbe
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(white: highContrast ? 1 : 0.7))
                        .accessibilityHidden(true)
                    numbered(u.out, base: u.translated ? langColor(u.to) : .white)
                        .font(.system(size: fs, weight: .bold))
                        .minimumScaleFactor(0.15)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(Text(a11yAttributed([("\(LangStyle.name(u.to)): ", nil), (u.out, u.to)])))
                    if translit, u.translated, let latin = u.outLatin, !latin.isEmpty {
                        Text(latin)
                            .font(.system(size: fs * 0.4))
                            .minimumScaleFactor(0.3)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(white: highContrast ? 1 : 0.7))
                            .frame(maxWidth: .infinity)
                    }
                    if u.translated {
                        (Text(LangStyle.flag(u.lang) + "  ") + numbered(u.text, base: langColor(u.lang).opacity(highContrast ? 1 : 0.9)))
                            .font(.system(size: 44 * zoom, weight: .medium))
                            .minimumScaleFactor(0.3)
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Text(a11yAttributed([(L.t("original") + " \(LangStyle.name(u.lang)): ", nil), (u.text, u.lang)])))
                    }
                    Spacer(minLength: 0)
                }
                .padding(48)
                }
                .id(u.id)
                .transition(reduceMotion ? .identity : .opacity)
            } else {
                VStack(spacing: 20) {
                    // groß in der Partnersprache (Thai mit Höflichkeitswort), darunter in meiner Sprache
                    Text(pleaseSpeak(m.partnerLang)).font(.system(size: 64, weight: .bold))
                        .foregroundStyle(langColor(m.partnerLang))
                        .accessibilityLabel(Text(a11yAttributed([(pleaseSpeak(m.partnerLang), m.partnerLang)])))
                    Text(pleaseSpeak(m.mineLang)).font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(langColor(m.mineLang))
                        .accessibilityLabel(Text(a11yAttributed([(pleaseSpeak(m.mineLang), m.mineLang)])))
                }
                .minimumScaleFactor(0.3)
                .padding(48)
            }
            }
            .rotationEffect(.degrees(rotated ? 180 : 0))
            VStack {
                if !presentation {
                HStack(spacing: 10) {
                    Image(systemName: stateIcon.name).foregroundStyle(stateIcon.color).font(.title3)
                        .accessibilityLabel(L.t("status") + ": " + m.status)
                    Spacer()
                    Button { back = min(back + 1, max(0, finished.count - 1)) } label: { Image(systemName: "chevron.left") }
                        .disabled(back >= finished.count - 1)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .help(L.t("partner_prev")).accessibilityLabel(L.t("partner_prev"))
                    Button { back = max(0, back - 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(back == 0)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .help(L.t("partner_next")).accessibilityLabel(L.t("partner_next"))
                    Button { zoom = max(Self.zoomRange.lowerBound, zoom - 0.1) } label: { Image(systemName: "textformat.size.smaller") }
                        .help(L.t("font_smaller")).accessibilityLabel(L.t("font_smaller"))
                    Button { zoom = min(Self.zoomRange.upperBound, zoom + 0.1) } label: { Image(systemName: "textformat.size.larger") }
                        .help(L.t("font_bigger")).accessibilityLabel(L.t("font_bigger"))
                    Button { highContrast.toggle() } label: { Image(systemName: "circle.lefthalf.filled") }
                        .help(L.t("partner_contrast")).accessibilityLabel(L.t("partner_contrast"))
                        .accessibilityValue(highContrast ? L.t("on") : L.t("off"))
                    Button { presentation = true } label: { Image(systemName: "rectangle.on.rectangle") }
                        .keyboardShortcut("p", modifiers: [])
                        .help(L.t("partner_presentation") + " (P)").accessibilityLabel(L.t("partner_presentation"))
                    Button { rotated.toggle() } label: { Image(systemName: "rotate.right") }
                        .help(L.t("partner_rotate")).accessibilityLabel(L.t("partner_rotate"))
                        .accessibilityValue(rotated ? L.t("on") : L.t("off"))
                    if screenCount > 1 {
                        Button { moveToOtherScreen() } label: { Image(systemName: "display.2") }
                            .help(L.t("partner_other_screen"))
                            .accessibilityLabel(L.t("partner_other_screen"))
                    }
                    Button { window?.toggleFullScreen(nil) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                    .help(L.t("partner_fullscreen") + " (⌃⌘F)")
                    .accessibilityLabel(L.t("partner_fullscreen"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.gray)
                .font(.title2)
                .padding(14)
                }
                if let b = stopBanner { stopBannerView(b) }
                Spacer()
                if presentation {   // Esc holt die Leiste zurück
                    Button { presentation = false } label: { Image(systemName: "xmark.circle") }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.borderless).foregroundStyle(.gray).font(.title2)
                        .help(L.t("partner_presentation_end")).accessibilityLabel(L.t("partner_presentation_end"))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 14)
                }
                if m.running {   // Nr. 36: die Partnerin kann um Wiederholung / langsameres Sprechen bitten
                    HStack(spacing: 16) {
                        partnerButton("partner_again", icon: "arrow.counterclockwise", shortcut: "r") { m.replayLast() }
                        partnerButton("partner_slower", icon: "tortoise", shortcut: "s") { m.partnerAsks("partner_asks_slower") }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 18)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: m.items.last(where: { $0.translated && !$0.pending })?.id)
        .frame(minWidth: 480, minHeight: 320)
        .onChange(of: m.items.last(where: { $0.translated && !$0.pending })?.id) { back = 0 }
        .background(WindowAccessor { w in
            if window !== w {
                w.collectionBehavior.insert(.fullScreenPrimary)
                w.backgroundColor = .black
                w.setFrameAutosaveName("PartnerWindow")   // Größe und Bildschirm merken (zweiter Bildschirm)
                if wasFullscreen, !w.styleMask.contains(.fullScreen) {
                    DispatchQueue.main.async { w.toggleFullScreen(nil) }
                }
                w.sharingType = hideCapture ? .none : .readOnly
                window = w
            }
        })
        // Bildschirm wachhalten, solange die Partnerin mitliest und zugehört wird
        .onAppear { m.partnerVisible = true }
        .onDisappear { m.partnerVisible = false }
        .overlay(alignment: .bottom) { pendingLine }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in wasFullscreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in wasFullscreen = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenCount = NSScreen.screens.count
        }
    }

    /// Neuer Satz wird gerade erkannt/übersetzt: Originaltext (bzw. Teiltext) abgeblendet unten zeigen,
    /// damit die alte Übersetzung nicht wie die Antwort auf den neuen Satz wirkt.
    @ViewBuilder private var pendingLine: some View {
        if m.running, let u = m.items.last, u.pending {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small).tint(.gray)
                if let p = u.partial, !p.isEmpty {
                    Text(LangStyle.flag(u.lang) + "  " + p)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(LangStyle.onBlack(u.lang).opacity(u.heard ? 0.8 : 0.55))
                        .lineLimit(2).minimumScaleFactor(0.5)
                } else {
                    Text("…").font(.system(size: 28, weight: .bold)).foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("translating_placeholder"))
        }
    }

    /// Fenster auf den Bildschirm verschieben, auf dem es gerade nicht liegt, und dort Vollbild.
    private func moveToOtherScreen() {
        guard let w = window else { return }
        let current = w.screen ?? NSScreen.main
        guard let target = NSScreen.screens.first(where: { $0 != current }) else { return }
        let wasFull = w.styleMask.contains(.fullScreen)
        if wasFull { w.toggleFullScreen(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasFull ? 0.8 : 0)) {
            w.setFrame(target.visibleFrame, display: true)
            DispatchQueue.main.async { w.toggleFullScreen(nil) }
        }
    }
}
