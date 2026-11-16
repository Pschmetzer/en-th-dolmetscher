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

    /// Startschriftgröße aus Fenstergröße und Textlänge (minimumScaleFactor fängt den Rest ab).
    private func fontSize(for text: String, in size: CGSize) -> CGFloat {
        let n = CGFloat(max(text.count, 1))
        let w = max(size.width - 96, 100), h = max(size.height * 0.6, 100)
        let byArea = (w * h / (n * 0.9)).squareRoot()
        return min(max(byArea, 28), min(h, 160))
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

    var body: some View {
        let _ = L.sync(uiLang)
        ZStack {
            Color.black.ignoresSafeArea()
            if !m.running {
                Text(L.t("partner_not_started"))
                    .font(.system(size: 48, weight: .semibold))
                    .minimumScaleFactor(0.3)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(48)
            } else if let u = m.items.last(where: { $0.translated && !$0.pending }) ?? m.items.last(where: { !$0.pending }) {
                GeometryReader { geo in
                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    let fs = fontSize(for: u.out, in: geo.size)
                    Text(u.out)
                        .font(.system(size: fs, weight: .bold))
                        .minimumScaleFactor(0.15)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(u.translated ? LangStyle.onBlack(u.to) : .white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(Text(a11yAttributed([("\(LangStyle.name(u.to)): ", nil), (u.out, u.to)])))
                    if translit, u.translated, let latin = u.outLatin, !latin.isEmpty {
                        Text(latin)
                            .font(.system(size: fs * 0.4))
                            .minimumScaleFactor(0.3)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(white: 0.7))
                            .frame(maxWidth: .infinity)
                    }
                    if u.translated {
                        Text(LangStyle.flag(u.lang) + "  " + u.text)
                            .font(.system(size: 44, weight: .medium))
                            .minimumScaleFactor(0.3)
                            .lineLimit(4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(LangStyle.onBlack(u.lang).opacity(0.9))
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
                        .foregroundStyle(LangStyle.onBlack(m.partnerLang))
                        .accessibilityLabel(Text(a11yAttributed([(pleaseSpeak(m.partnerLang), m.partnerLang)])))
                    Text(pleaseSpeak(m.mineLang)).font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(LangStyle.onBlack(m.mineLang))
                        .accessibilityLabel(Text(a11yAttributed([(pleaseSpeak(m.mineLang), m.mineLang)])))
                }
                .minimumScaleFactor(0.3)
                .padding(48)
            }
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: stateIcon.name).foregroundStyle(stateIcon.color).font(.title3)
                        .accessibilityLabel(L.t("status") + ": " + m.status)
                    Spacer()
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
                Spacer()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: m.items.last(where: { $0.translated && !$0.pending })?.id)
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowAccessor { w in
            if window !== w {
                w.collectionBehavior.insert(.fullScreenPrimary)
                w.backgroundColor = .black
                window = w
            }
        })
        // Bildschirm wachhalten, solange die Partnerin mitliest und zugehört wird
        .onAppear { m.partnerVisible = true }
        .onDisappear { m.partnerVisible = false }
        .overlay(alignment: .bottom) { pendingLine }
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
