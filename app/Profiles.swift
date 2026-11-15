// Stimmprofile: anlegen (8 Sätze vorlesen), Wörter pflegen, löschen.
// Die Oberfläche folgt der App-Sprache; der Aufnahme-Assistent spricht die Sprache des Profils
// (ein Thai-Profil führt komplett auf Thai durch, auch wenn die App auf Englisch steht).
import SwiftUI

struct VoiceProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lang: String
    let created: String
    let errorRate: Double?
    var vocab: [String]
}

enum EngineRunner {
    static func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }

    static let helperLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Dolmetscher/helper.log")

    /// stderr der Hilfsaufrufe (Profile, Mikrofonliste, Verlaufs-Export) anhängen statt verwerfen –
    /// sonst endet ein Fehler (falsches Python, fehlendes Paket) nur in „beendet“ ohne Ursache. Ab 512 KB neu.
    private static func helperLog(_ args: [String]) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: helperLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? fm.attributesOfItem(atPath: helperLogURL.path)[.size] as? Int, size > 512_000 {
            try? fm.removeItem(at: helperLogURL)
        }
        let fd = open(helperLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return nil }
        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        try? fh.write(contentsOf: Data("\n=== \(ts) \(args.first ?? "")\n".utf8))   // nur die Option, keine Namen
        return fh
    }

    /// Letzte Zeilen von helper.log (für Fehlermeldungen im Profil-Fenster).
    static func helperLogTail(_ n: Int = 6) -> String {
        guard let d = try? Data(contentsOf: helperLogURL) else { return "" }
        let lines = String(decoding: d.suffix(16_384), as: UTF8.self).split(separator: "\n")
        return lines.suffix(n).joined(separator: "\n")
    }

    /// Startet dolmetscher.py; ruft onEvent für jede JSON-Zeile (Main-Thread, in Reihenfolge).
    /// `timeout`: nach so vielen Sekunden wird der Prozess beendet (nil = kein Limit, z. B. beim Aufnehmen).
    /// `request`: Profilname/Wörter als JSON-Zeile auf stdin (`--profile-stdin`) statt als Argument –
    /// Argumente sieht jeder lokale Nutzer in der Prozessliste.
    static func run(_ args: [String], request: [String: Any]? = nil, timeout: TimeInterval? = nil,
                    onEvent: @escaping ([String: Any]) -> Void,
                    onExit: @escaping () -> Void = {}) -> Process? {
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = ["-u", script, "--json"] + (request != nil ? ["--profile-stdin"] : []) + args
        p.environment = Paths.engineEnvironment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = helperLog(args) ?? FileHandle.nullDevice
        let inp = Pipe()
        p.standardInput = inp
        var buf = Data()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                buf.append(d)
                if buf.count > 1_000_000 { buf = Data(); return }   // Zeile ohne Ende: verwerfen statt wachsen
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = buf.subdata(in: buf.startIndex..<nl)
                    buf.removeSubrange(buf.startIndex...nl)
                    if let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onEvent(o) }
                }
            }
        }
        p.terminationHandler = { _ in DispatchQueue.main.async { onExit() } }
        do { try p.run() } catch { return nil }
        if let request, var line = try? JSONSerialization.data(withJSONObject: request) {
            line.append(0x0A)
            let h = inp.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                try? h.write(contentsOf: line)
                try? h.close()
            }
        }
        if let timeout {
            let pp = p
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard pp.isRunning else { return }
                NSLog("Dolmetscher: %@ nach %.0f s abgebrochen (Zeitüberschreitung)", args.first ?? "?", timeout)
                pp.terminate()
            }
        }
        return p
    }
}

@MainActor
final class ProfilesModel: ObservableObject {
    @Published var profiles: [VoiceProfile] = []
    @Published var enrolling = false
    @Published var enrollLang = "th"
    @Published var step = 0
    @Published var steps = 8
    @Published var sentence = ""
    @Published var heard = ""
    @Published var hint = ""
    @Published var finished: VoiceProfile?
    @Published var failed: String?
    private var proc: Process?
    /// Zähler je Aufnahme: das späte Ende einer abgebrochenen Aufnahme darf die neue nicht stören.
    private var enrollGen = 0

    /// Name so, wie die Engine ihn als Dateinamen bereinigt (profiles._safe, ungefähr): „Anna!“ == „Anna“.
    static func normalized(_ name: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits).subtracting(.nonBaseCharacters)
            .union(CharacterSet(charactersIn: "_- "))
        let kept = name.precomposedStringWithCanonicalMapping.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Vorhandenes Profil mit (bereinigt) gleichem Namen – wird beim Anlegen überschrieben.
    func existing(_ name: String) -> VoiceProfile? {
        let n = Self.normalized(name)
        return n.isEmpty ? nil : profiles.first { Self.normalized($0.name) == n }
    }

    /// Wörter an das Vokabular eines Profils anhängen (Vorschlag nach einer Korrektur).
    /// Liest die Profile frisch, weil `--vocab` die ganze Liste ersetzt.
    static func appendVocab(profile name: String, words: [String], done: @escaping (Bool) -> Void) {
        _ = EngineRunner.run(["--profiles"], timeout: 30, onEvent: { o in
            guard o["event"] as? String == "profiles", let arr = o["profiles"] as? [[String: Any]],
                  let p = arr.map(parse).first(where: { $0.name == name }) else { return }
            var list = p.vocab
            for w in words where !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { list.append(w) }
            let r = EngineRunner.run([], request: ["vocab": [p.name, list.joined(separator: ", ")]], timeout: 30,
                                     onEvent: { _ in }, onExit: {
                NotificationCenter.default.post(name: .profilesChanged, object: nil)
                done(true)
            })
            if r == nil { done(false) }
        })
    }

    func reload() {
        _ = EngineRunner.run(["--profiles"], timeout: 30, onEvent: { [weak self] o in
            guard o["event"] as? String == "profiles", let arr = o["profiles"] as? [[String: Any]] else { return }
            self?.profiles = arr.map(Self.parse)
            NotificationCenter.default.post(name: .profilesChanged, object: nil)
        })
    }

    static func parse(_ d: [String: Any]) -> VoiceProfile {
        VoiceProfile(name: d["name"] as? String ?? "?", lang: d["lang"] as? String ?? "en",
                     created: d["created"] as? String ?? "", errorRate: d["error_rate"] as? Double,
                     vocab: d["vocab"] as? [String] ?? [])
    }

    func delete(_ p: VoiceProfile) {
        _ = EngineRunner.run([], request: ["delete_profile": p.name], timeout: 30, onEvent: { _ in },
                             onExit: { [weak self] in self?.reload() })
    }

    func saveVocab(_ p: VoiceProfile, _ text: String) {
        _ = EngineRunner.run([], request: ["vocab": [p.name, text]], timeout: 30, onEvent: { _ in },
                             onExit: { [weak self] in self?.reload() })
    }

    /// Thai-Profil -> Assistent auf Thai; sonst App-Sprache (Englisch, falls die App auf Thai steht).
    var forced: UILang { enrollLang == "th" ? .th : (L.lang == .th ? .en : L.lang) }

    /// `onDone` läuft, sobald der Aufnahme-Prozess beendet ist (Mikrofon wieder frei).
    func startEnroll(name: String, lang: String, model: String, onDone: @escaping () -> Void = {}) {
        enrolling = true; enrollLang = lang; step = 0; sentence = ""; heard = ""; finished = nil; failed = nil
        hint = L.t("prep", forced)
        enrollGen += 1
        let gen = enrollGen
        proc = EngineRunner.run(["--model", model], request: ["enroll": name, "enroll_lang": lang],
                                onEvent: { [weak self] o in
                                    guard let self, self.enrollGen == gen else { return }
                                    self.handle(o)
                                },
                                onExit: { [weak self] in
                                    guard let self else { return }
                                    // Abgebrochen und schon neu gestartet: Ende der alten Aufnahme ignorieren
                                    // (deren onDone gäbe sonst das Mikrofon mitten in der neuen Aufnahme zurück).
                                    guard self.enrollGen == gen else { return }
                                    if self.finished == nil && self.failed == nil && self.enrolling {
                                        let tail = EngineRunner.helperLogTail(3)
                                        self.failed = L.t("ended", self.forced) + (tail.isEmpty ? "" : "\n" + tail)
                                    }
                                    self.proc = nil; self.reload()
                                    onDone()
                                })
        if proc == nil { failed = L.t("engine_missing", forced); onDone() }
    }

    func cancel() { proc?.terminate(); proc = nil; enrolling = false }

    private func handle(_ o: [String: Any]) {
        switch o["event"] as? String {
        case "enroll_prompt":
            step = o["i"] as? Int ?? step; steps = o["n"] as? Int ?? steps
            sentence = o["sentence"] as? String ?? ""; heard = ""; hint = L.t("tip_quiet", forced)
        case "hearing": hint = "👂 …"
        case "enroll_heard": heard = o["heard"] as? String ?? ""
        case "enroll_retry": hint = L.t("again", forced)
        case "enroll_failed": failed = o["reason"] as? String ?? "?"
        case "enroll_done": if let p = o["profile"] as? [String: Any] { finished = Self.parse(p) }
        case "error": failed = o["msg"] as? String
        default: break
        }
    }
}

struct ProfilesView: View {
    @StateObject var pm = ProfilesModel()
    @EnvironmentObject var m: EngineModel
    @Environment(\.dismiss) var dismiss
    @AppStorage(L.key) var uiLang = L.defaultCode
    @State private var newName = ""
    @State private var newLang = "th"
    @State private var vocabEdit: [String: String] = [:]
    @State private var confirmDelete: VoiceProfile?
    /// Neues Profil trägt (bereinigt) den Namen eines vorhandenen: erst fragen, dann ersetzen.
    @State private var confirmReplace: VoiceProfile?

    private func record() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        m.lendMic()                      // Mikrofon freigeben (Engine bleibt geladen)
        pm.startEnroll(name: name, lang: newLang, model: m.model, onDone: { m.returnMic() })
        newName = ""
    }

    var body: some View {
        let _ = L.sync(uiLang)
        Group { if pm.enrolling { EnrollView(pm: pm) } else { list } }
            .frame(width: 660, height: 500)
            .onAppear { pm.reload() }
            .onDisappear { pm.cancel(); m.returnMic() }   // Fenster zu: Aufnahme beenden, Zuhören wiederherstellen
            .id(uiLang)
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("profiles")).font(.largeTitle.bold())
                Spacer()
                Picker(L.t("ui_language"), selection: $uiLang) {
                    ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().frame(width: 140).help(L.t("ui_language"))
                Button(L.t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(L.t("profiles_intro")).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    if pm.profiles.isEmpty { Text(L.t("no_profiles")).foregroundStyle(.secondary).padding() }
                    ForEach(pm.profiles) { p in row(p) }
                }
            }
            Divider()
            Text(L.t("new_profile")).font(.headline)
            HStack {
                TextField(L.t("name"), text: $newName).frame(width: 200)
                Picker(L.t("speaks"), selection: $newLang) {
                    Text("🇹🇭 " + L.t("thai")).tag("th"); Text("🇬🇧 " + L.t("english")).tag("en")
                }.frame(width: 230)
                Spacer()
                Button {
                    if let p = pm.existing(newName) { confirmReplace = p } else { record() }
                } label: { Label(L.t("record"), systemImage: "record.circle") }
                .buttonStyle(.borderedProminent)
                .disabled(ProfilesModel.normalized(newName).isEmpty)
            }
        }
        .padding(22)
        .confirmationDialog(L.t("delete_confirm"), isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L.t("delete"), role: .destructive) { if let p = confirmDelete { pm.delete(p) }; confirmDelete = nil }
            Button(L.t("cancel"), role: .cancel) { confirmDelete = nil }
        }
        .confirmationDialog(L.f("profile_replace", confirmReplace?.name ?? ""), isPresented: Binding(
            get: { confirmReplace != nil }, set: { if !$0 { confirmReplace = nil } }), titleVisibility: .visible) {
            Button(L.t("replace"), role: .destructive) { confirmReplace = nil; record() }
            Button(L.t("cancel"), role: .cancel) { confirmReplace = nil }
        }
    }

    func row(_ p: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(p.lang == "th" ? "🇹🇭" : "🇬🇧").font(.title)
                VStack(alignment: .leading) {
                    Text(p.name).font(.title3.bold())
                    if let e = p.errorRate {
                        Text("\(Int(max(0, 1 - e) * 100)) % \(L.t("understood")) · \(p.created)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(L.t("redo")) {
                    m.lendMic()
                    pm.startEnroll(name: p.name, lang: p.lang, model: m.model, onDone: { m.returnMic() })
                }
                Button(role: .destructive) { confirmDelete = p } label: { Image(systemName: "trash") }
                    .help(L.t("delete"))
                    .accessibilityLabel(L.t("delete") + " " + p.name)
            }
            HStack {
                TextField(L.t("vocab"), text: Binding(
                    get: { vocabEdit[p.name] ?? p.vocab.joined(separator: ", ") },
                    set: { vocabEdit[p.name] = $0 }))
                Button(L.t("save")) { pm.saveVocab(p, vocabEdit[p.name] ?? ""); vocabEdit[p.name] = nil }
                    .disabled(vocabEdit[p.name] == nil)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Großer, einfacher Assistent – in der Sprache des Profils, damit die Person ihn selbst bedienen kann.
struct EnrollView: View {
    @ObservedObject var pm: ProfilesModel
    var body: some View {
        let f = pm.forced
        VStack(spacing: 22) {
            if let p = pm.finished {
                Spacer()
                Text("✅").font(.system(size: 64))
                Text(L.t("done", f)).font(.largeTitle.bold())
                if let e = p.errorRate {
                    Text("\(Int(max(0, 1 - e) * 100)) % \(L.t("understood", f))").font(.title2)
                }
                Spacer()
                Button(L.t("close", f)) { pm.enrolling = false }.buttonStyle(.borderedProminent).controlSize(.large)
            } else if let err = pm.failed {
                Spacer()
                Text("⚠️ " + L.t("failed", f)).font(.title.bold())
                Text(err).foregroundStyle(.secondary)
                Spacer()
                Button(L.t("close", f)) { pm.enrolling = false }.controlSize(.large)
            } else {
                HStack {
                    Text("\(L.t("sentence", f)) \(max(pm.step, 1)) \(L.t("of", f)) \(pm.steps)").font(.headline)
                    Spacer()
                    Button(L.t("cancel", f)) { pm.cancel() }
                }
                ProgressView(value: Double(max(pm.step - 1, 0)), total: Double(pm.steps))
                Spacer()
                if pm.sentence.isEmpty {
                    ProgressView()
                    Text(pm.hint).foregroundStyle(.secondary)
                } else {
                    Text(L.t("read_this", f)).font(.title3).foregroundStyle(.secondary)
                    Text(pm.sentence)
                        .font(.system(size: 40, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    Text(pm.hint).font(.title3)
                    if !pm.heard.isEmpty {
                        Text(L.t("heard", f) + " " + pm.heard).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(28)
    }
}

extension Notification.Name {
    static let profilesChanged = Notification.Name("DolmetscherProfilesChanged")
}
