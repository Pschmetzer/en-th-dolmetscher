// MiniView.swift – Mini-Modus: kompaktes, immer sichtbares Fenster mit Status, letztem Satz und Start/Stopp.
import SwiftUI
import AppKit

struct MiniView: View {
    @EnvironmentObject var m: EngineModel
    @AppStorage(L.key) private var uiLang = L.defaultCode
    @AppStorage("miniOnTop") private var onTop = true
    @AppStorage("miniShowOriginal") private var showOriginal = false

    var body: some View {
        let _ = L.sync(uiLang)
        let last = m.items.last { !$0.pending && !$0.out.isEmpty }
        let parts = StatusIcon.split(m.status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: m.toggle) {
                    Image(systemName: m.active ? "stop.fill" : "mic.fill").frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .tint(m.active ? LangStyle.fillRed : LangStyle.fillGreen)
                .keyboardShortcut(.return, modifiers: .command)
                .help(L.t(m.active ? "stop_engine" : "start_engine"))
                .accessibilityLabel(L.t(m.active ? "stop_engine" : "start_engine"))
                .accessibilityValue(parts.text)
                if m.micOn { LevelBar(meter: m.meter) }
                HStack(spacing: 4) {
                    if let sym = parts.symbol { Image(systemName: sym.name).foregroundStyle(sym.tint).accessibilityHidden(true) }
                    Text(parts.text).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .help(parts.text)
                Spacer(minLength: 0)
                Button { m.stopSpeaking() } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.borderless).disabled(!m.running)
                    .help(L.t("stop_speaking")).accessibilityLabel(L.t("stop_speaking"))
                Button { if let u = last { m.replay(u) } } label: { Image(systemName: "arrow.counterclockwise.circle") }
                    .buttonStyle(.borderless).disabled(last == nil)
                    .help(L.t("replay_last")).accessibilityLabel(L.t("replay_last"))
            }
            if let last {
                Text(last.out)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LangStyle.color(last.to))
                    .lineLimit(4).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(a11yAttributed([(last.out, last.to)])))
                if showOriginal {
                    Text(last.text).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L.t("chat_empty_start")).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 280, minHeight: 100)
        .background(WindowAccessor { w in
            let level: NSWindow.Level = onTop ? .floating : .normal
            if w.level != level { w.level = level }
            if w.frameAutosaveName.isEmpty { w.setFrameAutosaveName("DolmetscherMiniWindow") }
        })
        .contextMenu {
            Toggle(L.t("always_on_top"), isOn: $onTop)
            Toggle(L.t("caption_original"), isOn: $showOriginal)
        }
    }
}
