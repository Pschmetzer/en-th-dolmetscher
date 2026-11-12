// PartnerView.swift – Vollbild-Ansicht für die Gesprächspartnerin: nur die letzte Übersetzung, sehr groß.
import SwiftUI
import AppKit

struct PartnerView: View {
    @EnvironmentObject var m: EngineModel
    @State private var window: NSWindow?
    @State private var screenCount = NSScreen.screens.count
    @AppStorage(Prefs.translit) private var translit = true

    /// Startschriftgröße aus Fenstergröße und Textlänge (minimumScaleFactor fängt den Rest ab).
    private func fontSize(for text: String, in size: CGSize) -> CGFloat {
        let n = CGFloat(max(text.count, 1))
        let w = max(size.width - 96, 100), h = max(size.height * 0.6, 100)
        let byArea = (w * h / (n * 0.9)).squareRoot()
        return min(max(byArea, 28), min(h, 160))
    }

    private var stateColor: Color {
        if !m.running || m.paused { return .gray }
        if m.busy { return .orange }
        return m.micOn ? .green : .gray
    }

    var body: some View {
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
                        .foregroundStyle(u.translated ? LangStyle.color(u.to) : .white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("\(LangStyle.name(u.to)): \(u.out)")
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
                            .foregroundStyle(LangStyle.color(u.lang).opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Original \(LangStyle.name(u.lang)): \(u.text)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(48)
                }
                .id(u.id)
                .transition(.opacity)
            } else {
                VStack(spacing: 20) {
                    Text("กรุณาพูดได้เลย" + (m.polite == "ka" ? "ค่ะ" : "ครับ")).font(.system(size: 64, weight: .bold)).foregroundStyle(.orange)
                    Text("Please speak").font(.system(size: 48, weight: .semibold)).foregroundStyle(.blue)
                }
                .minimumScaleFactor(0.3)
                .padding(48)
            }
            VStack {
                HStack(spacing: 10) {
                    Circle().fill(stateColor).frame(width: 10, height: 10)
                        .accessibilityLabel(m.status)
                    Spacer()
                    if screenCount > 1 {
                        Button { moveToOtherScreen() } label: { Image(systemName: "display.2") }
                            .help("Auf den anderen Bildschirm (Vollbild)")
                            .accessibilityLabel("Auf den anderen Bildschirm verschieben")
                    }
                    Button { window?.toggleFullScreen(nil) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                    .help("Vollbild an/aus (⌃⌘F)")
                    .accessibilityLabel("Vollbild umschalten")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.gray)
                .font(.title2)
                .padding(14)
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: m.items.last(where: { $0.translated && !$0.pending })?.id)
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowAccessor { w in
            if window !== w {
                w.collectionBehavior.insert(.fullScreenPrimary)
                w.backgroundColor = .black
                window = w
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenCount = NSScreen.screens.count
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
