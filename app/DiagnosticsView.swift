// DiagnosticsView.swift – Selbsttest-Fenster (Hilfe-Menü, Einstellungen): Mikrofon, Lautsprecher, Netz, Modelle, Engine.
import SwiftUI
import AVFoundation
import Network

extension Notification.Name {
    static let showSelfTest = Notification.Name("DolmetscherShowSelfTest")
}

/// Erster Pfad-Update zählt, spätere werden ignoriert.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; let first = !used; used = true; return first }
}

@MainActor
final class SelfTestModel: ObservableObject {
    typealias Row = DiagnosticsLogic.Row
    @Published var rows: [Row] = []
    @Published var running = false

    func run(outputDevice: String) {
        guard !running else { return }
        running = true
        var r: [Row] = [micRow(), speakerRow(outputDevice)]
        networkRow { net in
            r.append(net)
            r.append(self.modelsRow())
            Paths.checkPython { py in
                switch py {
                case .ok(let v): r.append(Row(id: "python", status: .ok, detail: v))
                case .noModule: r.append(Row(id: "python", status: .fail, detail: "faster_whisper fehlt"))
                case .failed(let e): r.append(Row(id: "python", status: .fail, detail: String(e.prefix(200))))
                }
                self.rows = r; self.running = false
            }
        }
    }

    private func micRow() -> Row {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            let has = AVCaptureDevice.default(for: .audio) != nil
            return Row(id: "mic", status: has ? .ok : .fail, detail: has ? "authorized" : "no input device")
        case .notDetermined: return Row(id: "mic", status: .warn, detail: "not asked")
        default: return Row(id: "mic", status: .fail, detail: "denied or restricted")
        }
    }

    private func speakerRow(_ saved: String) -> Row {
        let outs = AudioOutputs.list()
        if outs.isEmpty { return Row(id: "speaker", status: .fail, detail: "no output device") }
        if !saved.isEmpty, !outs.contains(where: { $0.uid == saved }) {
            return Row(id: "speaker", status: .warn, detail: "saved output missing")
        }
        return Row(id: "speaker", status: .ok, detail: "\(outs.count) output(s)")
    }

    private func networkRow(_ done: @escaping (Row) -> Void) {
        let mon = NWPathMonitor()
        let q = DispatchQueue(label: "selftest.net")
        let once = OnceFlag()
        mon.pathUpdateHandler = { path in
            guard once.take() else { return }
            mon.cancel()
            let ok = path.status == .satisfied
            DispatchQueue.main.async { done(Row(id: "network", status: ok ? .ok : .fail, detail: ok ? "online" : "offline")) }
        }
        mon.start(queue: q)
    }

    private func modelsRow() -> Row {
        let n = ModelCache.cached().count
        return Row(id: "models", status: n > 0 ? .ok : .fail, detail: "\(n) cached")
    }
}

struct SelfTestSheet: View {
    @EnvironmentObject var m: EngineModel
    @StateObject private var model = SelfTestModel()
    @Environment(\.dismiss) private var dismiss

    private func icon(_ s: DiagnosticsLogic.Status) -> (String, Color) {
        switch s {
        case .ok: return ("checkmark.circle.fill", LangStyle.success)
        case .warn: return ("exclamationmark.triangle.fill", .orange)
        case .fail: return ("xmark.octagon.fill", .red)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("selftest_title")).font(.title2).bold().accessibilityAddTraits(.isHeader)
            if model.running { HStack { ProgressView().controlSize(.small); Text(L.t("selftest_running")) } }
            ForEach(model.rows, id: \.id) { r in
                let (sym, color) = icon(r.status)
                VStack(alignment: .leading, spacing: 2) {
                    Label(L.t(DiagnosticsLogic.titleKeys[r.id] ?? "diag_row_mic"), systemImage: sym).foregroundStyle(color).font(.headline)
                    if let k = DiagnosticsLogic.suggestionKey(id: r.id, status: r.status) {
                        Text(L.t(k)).font(.callout).foregroundStyle(.secondary).padding(.leading, 24)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !model.rows.isEmpty && !model.running {
                Text(L.t(DiagnosticsLogic.overallKeys[DiagnosticsLogic.overall(model.rows)] ?? "selftest_ok")).font(.callout).bold()
            }
            HStack {
                Button(L.t("selftest_run")) { model.run(outputDevice: m.outputDevice) }.disabled(model.running)
                Button(L.t("diag_copy")) {
                    Paths.checkPython { result in copyToPasteboard(m.diagnosticReport(python: result, selfTest: model.rows)) }
                }
                Button(L.t("selftest_help")) {
                    if let u = URL(string: DiagnosticsLogic.helpURL) { NSWorkspace.shared.open(u) }
                }
                Spacer()
                Button(L.t("hide")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(minWidth: 460)
        .onAppear { model.run(outputDevice: m.outputDevice) }
    }
}
