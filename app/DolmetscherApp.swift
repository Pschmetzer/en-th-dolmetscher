// Dolmetscher – SwiftUI-Oberfläche für die Python-Engine (dolmetscher.py).
import SwiftUI
import AVFoundation

struct Utterance: Identifiable {
    let id = UUID()
    let lang: String
    let text: String
    let out: String
    let secs: Double
}

@MainActor
final class EngineModel: ObservableObject {
    @Published var items: [Utterance] = []
    @Published var status = "Gestoppt"
    @Published var running = false
    @Published var busy = false
    private static let ud = UserDefaults.standard
    @Published var speak = ud.object(forKey: "speak") as? Bool ?? true { didSet { Self.ud.set(speak, forKey: "speak") } }
    @Published var polite = ud.string(forKey: "polite") ?? "krub" { didSet { Self.ud.set(polite, forKey: "polite") } }
    @Published var model = ud.string(forKey: "model") ?? "small" { didSet { Self.ud.set(model, forKey: "model") } }

    private var proc: Process?
    private var buffer = Data()

    private func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    func toggle() { running ? stop() : start() }

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Task { @MainActor in
                if ok { self.launch() }
                else { self.status = "Kein Mikrofon-Zugriff – Systemeinstellungen → Datenschutz → Mikrofon" }
            }
        }
    }

    private func launch() {
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else {
            status = "dolmetscher.py fehlt im App-Bundle"; return
        }
        let python = info("DolmetscherPython") ?? "/usr/bin/python3"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        var args = ["-u", script, "--json", "--model", model, "--polite", polite]
        if !speak { args.append("--mute") }
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let ff = info("DolmetscherFFmpeg") { env["DOLMETSCHER_FFMPEG"] = ff }
        p.environment = env

        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        buffer = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self, weak p] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            Task { @MainActor in
                guard let self, let p, self.proc === p else { return }
                self.consume(d)
            }
        }
        p.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.proc === ended else { return }   // nur der aktuelle Prozess
                if self.running { self.status = "Engine beendet" }
                self.running = false; self.busy = false; self.proc = nil
            }
        }
        do {
            try p.run()
            proc = p; running = true; status = "Starte …"
        } catch {
            status = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func stop() {
        running = false
        if let p = proc {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminate()
        }
        proc = nil
        buffer = Data()
        busy = false
        status = "Gestoppt"
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ev = obj["event"] as? String else { continue }
            handle(ev, obj)
        }
    }

    private func handle(_ ev: String, _ o: [String: Any]) {
        switch ev {
        case "loading": status = "Lade Sprachmodell …"
        case "ready": status = "Modell geladen"
        case "calibrating": status = "Kalibriere Mikrofon – kurz still sein …"
        case "listening": status = "🎙 Hört zu – einfach Englisch oder Thai sprechen"; busy = false
        case "hearing": status = "👂 Höre …"
        case "thinking": status = "⏳ Übersetze …"; busy = true
        case "speaking": status = "🔊 Spricht …"
        case "error": status = "⚠️ " + (o["msg"] as? String ?? "Fehler")
        case "utt":
            let secs = (o["stt"] as? Double ?? 0) + (o["tr"] as? Double ?? 0)
            items.append(Utterance(lang: o["lang"] as? String ?? "en",
                                   text: o["text"] as? String ?? "",
                                   out: o["out"] as? String ?? "", secs: secs))
        default: break
        }
    }
}

struct Bubble: View {
    let u: Utterance
    var body: some View {
        let en = u.lang == "en"
        VStack(alignment: en ? .leading : .trailing, spacing: 6) {
            Text((en ? "🇬🇧 " : "🇹🇭 ") + u.text)
                .font(.system(size: 15)).foregroundStyle(.secondary)
            Text(u.out)
                .font(.system(size: 30, weight: .semibold))
                .multilineTextAlignment(en ? .leading : .trailing)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: en ? .leading : .trailing)
        .background((en ? Color.blue : Color.orange).opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ContentView: View {
    @EnvironmentObject var m: EngineModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: m.toggle) {
                    Label(m.running ? "Stopp" : "Start", systemImage: m.running ? "stop.fill" : "mic.fill")
                        .font(.title2.bold()).frame(width: 130, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(m.running ? .red : .green)
                .keyboardShortcut(.space, modifiers: [])
                Text(m.status).font(.headline).lineLimit(2)
                if m.busy { ProgressView().controlSize(.small) }
                Spacer()
                Toggle("Vorlesen", isOn: $m.speak).disabled(m.running)
                Picker("", selection: $m.polite) {
                    Text("ครับ (m)").tag("krub"); Text("ค่ะ (w)").tag("ka")
                }.frame(width: 110).disabled(m.running)
                Picker("", selection: $m.model) {
                    Text("Schnell").tag("base"); Text("Normal").tag("small"); Text("Genau").tag("medium")
                }.frame(width: 100).disabled(m.running)
                Button { m.items.removeAll() } label: { Image(systemName: "trash") }
                    .help("Verlauf leeren")
            }
            .padding(14)
            Divider()
            ScrollViewReader { sv in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if m.items.isEmpty {
                            Text("Start drücken und einfach sprechen.\nEnglisch wird auf Thai übersetzt, Thai auf Englisch.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                                .padding(.top, 80)
                        }
                        ForEach(m.items) { Bubble(u: $0).id($0.id) }
                    }.padding(16)
                }
                .onChange(of: m.items.count) {
                    if let last = m.items.last { withAnimation { sv.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: EngineModel?
    func applicationWillTerminate(_ n: Notification) { MainActor.assumeIsolated { model?.stop() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@main
struct DolmetscherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = EngineModel()
    var body: some Scene {
        WindowGroup("Dolmetscher EN ⇄ TH") {
            ContentView().environmentObject(model)
                .onAppear { delegate.model = model }
        }
    }
}
