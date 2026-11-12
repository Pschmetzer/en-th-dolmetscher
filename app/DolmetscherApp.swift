// Dolmetscher – SwiftUI-Oberfläche für die Python-Engine (dolmetscher.py).
import SwiftUI
import AVFoundation

struct Utterance: Identifiable {
    let id = UUID()
    var translated = true
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
    @Published var paused = false
    private static let ud = UserDefaults.standard
    @Published var speak = ud.object(forKey: "speak") as? Bool ?? true { didSet { Self.ud.set(speak, forKey: "speak"); send(["speak": speak]) } }
    @Published var trEN = ud.object(forKey: "trEN") as? Bool ?? true { didSet { Self.ud.set(trEN, forKey: "trEN"); send(["tr_en": trEN]) } }
    @Published var trTH = ud.object(forKey: "trTH") as? Bool ?? true { didSet { Self.ud.set(trTH, forKey: "trTH"); send(["tr_th": trTH]) } }
    @Published var polite = ud.string(forKey: "polite") ?? "krub" { didSet { Self.ud.set(polite, forKey: "polite"); send(["polite": polite]) } }
    @Published var model = EngineModel.initialModel() { didSet { Self.ud.set(model, forKey: "model") } }
    @Published var lang = ud.string(forKey: "lang") ?? "auto" { didSet { Self.ud.set(lang, forKey: "lang"); send(["lang": lang]) } }
    private var stdin: Pipe?

    /// Einstellung live an die laufende Engine schicken (eine JSON-Zeile auf stdin).
    private func send(_ d: [String: Any]) {
        guard running, let h = stdin?.fileHandleForWriting,
              var data = try? JSONSerialization.data(withJSONObject: d) else { return }
        data.append(0x0A)
        try? h.write(contentsOf: data)
    }

    /// Einmalige Umstellung alter Installationen von "small" auf das genauere "medium".
    private static func initialModel() -> String {
        if !ud.bool(forKey: "migratedToMedium") {
            ud.set(true, forKey: "migratedToMedium")
            if ud.string(forKey: "model") == nil || ud.string(forKey: "model") == "small" {
                ud.set("medium", forKey: "model")
            }
        }
        return ud.string(forKey: "model") ?? "medium"
    }

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
        var args = ["-u", script, "--json", "--model", model, "--polite", polite, "--lang", lang]
        if !speak { args.append("--mute") }
        if !trEN { args.append("--no-en") }
        if !trTH { args.append("--no-th") }
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let ff = info("DolmetscherFFmpeg") { env["DOLMETSCHER_FFMPEG"] = ff }
        p.environment = env

        let out = Pipe()
        p.standardOutput = out
        let inp = Pipe()
        p.standardInput = inp
        stdin = inp
        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dolmetscher")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let errURL = logDir.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        p.standardError = (try? FileHandle(forWritingTo: errURL)) ?? FileHandle.nullDevice
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
            proc = p; running = true; paused = false; status = "Starte …"
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
        case "ready": status = "Modell geladen (" + (o["device"] as? String == "mps" ? "Apple-GPU" : "CPU") + ")"
        case "calibrating": status = "Kalibriere Mikrofon – kurz still sein …"
        case "listening":
            status = paused ? "⏸ Pausiert – sag „Translator, resume“" : "🎙 Hört zu – einfach Englisch oder Thai sprechen"
            busy = false
        case "hearing": status = "👂 Höre …"
        case "thinking": status = "⏳ Übersetze …"; busy = true
        case "speaking": status = "🔊 Spricht …"
        case "error": status = "⚠️ " + (o["msg"] as? String ?? "Fehler")
        case "command":
            if o["clear"] as? Bool == true { items.removeAll() }
            if let l = o["lang"] as? String { lang = l }
            if let p = o["polite"] as? String { polite = p }
            if let v = o["tr_en"] as? Bool, v != trEN { trEN = v }
            if let v = o["tr_th"] as? Bool, v != trTH { trTH = v }
            paused = o["paused"] as? Bool ?? false
            let reply = o["reply"] as? String ?? ""
            status = paused ? "⏸ Pausiert – sag „Translator, resume“" : "🗣 " + (reply.isEmpty ? "Wiederhole …" : reply)
        case "dropped" where paused:
            status = "⏸ Pausiert – sag „Translator, resume“"; busy = false
        case "dropped": status = "🤷 " + (o["reason"] as? String ?? "nicht verstanden") + " – bitte lauter/länger sprechen"; busy = false
        case "utt":
            let secs = (o["stt"] as? Double ?? 0) + (o["tr"] as? Double ?? 0)
            items.append(Utterance(translated: o["translated"] as? Bool ?? true,
                                   lang: o["lang"] as? String ?? "en",
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
            Text((en ? "🇬🇧 " : "🇹🇭 ") + (u.translated ? u.text : "nicht übersetzt"))
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
                Picker("", selection: $m.lang) {
                    Text("Auto").tag("auto"); Text("🇬🇧 nur EN").tag("en"); Text("🇹🇭 nur TH").tag("th")
                }.frame(width: 110).help("Sprache fest einstellen, falls Auto falsch erkennt")
                Toggle("🇬🇧→🇹🇭", isOn: $m.trEN).help("Englisch ins Thai übersetzen (aus = Englisch bleibt Englisch)")
                Toggle("🇹🇭→🇬🇧", isOn: $m.trTH).help("Thai ins Englische übersetzen (aus = Thai bleibt Thai)")
                Toggle("Vorlesen", isOn: $m.speak)
                Picker("", selection: $m.polite) {
                    Text("ครับ (m)").tag("krub"); Text("ค่ะ (w)").tag("ka")
                }.frame(width: 110)
                Picker("", selection: $m.model) {
                    Text("Schnell").tag("small"); Text("Normal").tag("medium"); Text("Beste (Englisch+)").tag("best")
                }.frame(width: 130).disabled(m.running)
                Button { m.items.removeAll() } label: { Image(systemName: "trash") }
                    .help("Verlauf leeren")
            }
            .padding(14)
            Divider()
            ScrollViewReader { sv in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if m.items.isEmpty {
                            Text("Start drücken und einfach sprechen.\nEnglisch wird auf Thai übersetzt, Thai auf Englisch.\n\nSprachbefehle: „Translator, pause / resume / repeat / slower / faster /\nlouder / quieter / Thai only / English only / auto / female voice / male voice / clear / help“")
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
