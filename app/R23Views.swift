// R23Views.swift – kleine Ansichten der Runde 23: Übersteuerungs-Warnung, Latenz-Sparkline, Auswahlleiste für Blasen.
// Die Regeln selbst stehen in ConversationUILogic.swift (getestet); hier nur Darstellung und Verdrahtung.
import SwiftUI

/// „Zu laut“-Hinweis neben dem Pegelbalken: erscheint, wenn der Pegel rund eine Sekunde am Anschlag liegt.
struct ClipBadge: View {
    @ObservedObject var meter: LevelMeter
    @State private var detector = ClippingDetector()
    @State private var warned = false

    var body: some View {
        Group {
            if warned {
                HStack(spacing: 3) {
                    Image(systemName: "waveform.badge.exclamationmark").accessibilityHidden(true)
                    Text(L.r23("clip_short"))
                }
                .font(.caption.bold()).foregroundStyle(LangStyle.warning)
                .help(L.r23("clip_warn"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.r23("clip_warn"))
            }
        }
        .onChange(of: meter.rms) {
            detector.feed(meter.rms)
            if detector.warned != warned {
                warned = detector.warned
                if warned { Announcer.post(L.r23("clip_warn")) }
            }
        }
        .onChange(of: meter.voice) { if !meter.voice && meter.rms == 0 { detector.reset(); warned = false } }
    }
}

/// Mini-Verlauf der letzten Latenzen als Blockzeichen mit Trendpfeil (Zahl steht immer im Median daneben).
struct LatencySparkline: View {
    let history: [Double]

    var body: some View {
        let line = LatencySpark.line(history)
        if history.count >= 3, !line.isEmpty {
            let trend = LatencySpark.trend(history)
            HStack(spacing: 2) {
                Text(line).font(.system(size: 10, design: .monospaced))
                if trend != .flat {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(trend == .up ? LangStyle.warning : LangStyle.success)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.secondary)
            .help(L.r23("latency_recent") + ": " + history.suffix(10).map { fmtSeconds($0) }.joined(separator: ", "))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.r23("latency_recent") + (trend == .up ? ", " + L.r23("latency_trend_up")
                                                            : trend == .down ? ", " + L.r23("latency_trend_down") : ""))
        }
    }
}

/// Leiste über dem Verlauf, solange Blasen ausgewählt werden: kopieren, exportieren, löschen, beenden.
struct SelectionBar: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject private var ui = UIDrafts.shared
    let shown: [Utterance]
    @State private var confirmDelete = false

    private var order: [String] { shown.map { $0.id.uuidString } }
    private var chosen: [Utterance] {
        let ids = Set(ui.selection.ordered(order))
        return shown.filter { ids.contains($0.id.uuidString) }
    }

    private func copyChosen(times: Bool) {
        var opts = ExportOptions(); opts.includeTimes = times
        let text = chosen.map { u -> String in
            let body = BubbleCopy.text(original: u.text, translation: u.out, mode: .both, translated: u.translated)
            return times ? BubbleCopy.withMeta(body, speaker: u.speaker, date: u.date)
                         : ExportSelection.stamp(u.date, options: opts) + (u.speaker.map { $0 + ": " } ?? "") + body
        }.joined(separator: "\n\n")
        copyToPasteboard(text)
        Announcer.post(L.t("copied"))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(L.r23f("selected_n", ui.selection.count)).font(.callout.bold()).monospacedDigit()
                .accessibilityAddTraits(.updatesFrequently)
            Button(L.r23("select_all")) { ui.selection.selectAll(order) }
                .keyboardShortcut("a", modifiers: .command)
            Button(L.r23("select_none")) { ui.selection.clear() }.disabled(ui.selection.isEmpty)
            Spacer(minLength: 0)
            Menu {
                Button(L.r23("select_copy")) { copyChosen(times: true) }
                Button(L.r23("select_copy") + " – " + L.r23("export_no_times")) { copyChosen(times: false) }
            } label: { Label(L.r23("select_copy"), systemImage: "doc.on.doc") }
                .menuStyle(.borderlessButton).fixedSize().disabled(chosen.isEmpty)
            Menu {
                Button(L.r23("select_export")) { exportConversation(m, only: chosen) }
                ForEach(Langs.pair, id: \.self) { code in
                    Button(L.r23f("export_only_lang", code.uppercased())) {
                        var o = ExportOptions(); o.onlyLang = code
                        exportConversation(m, only: ExportSelection.filter(chosen, options: o, lang: { $0.lang }))
                    }
                }
            } label: { Label(L.r23("select_export"), systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).fixedSize().disabled(chosen.isEmpty)
            Button(role: .destructive) { confirmDelete = true } label: { Label(L.r23("select_delete"), systemImage: "trash") }
                .disabled(chosen.isEmpty || m.viewingSession != nil)
            Button(L.r23("select_done")) { ui.selecting = false; ui.selection.clear() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .confirmationDialog(L.r23f("selected_n", ui.selection.count) + " – " + L.r23("select_delete") + "?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L.r23("select_delete"), role: .destructive) {
                for u in chosen { m.deleteItem(u) }
                ui.selection.clear()
            }
            Button(L.t("cancel"), role: .cancel) {}
        }
    }
}
