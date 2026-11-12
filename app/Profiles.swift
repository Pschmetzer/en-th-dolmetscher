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

    /// Startet dolmetscher.py; ruft onEvent für jede JSON-Zeile (Main-Thread, in Reihenfolge).
    static func run(_ args: [String], onEvent: @escaping ([String: Any]) -> Void,
                    onExit: @escaping () -> Void = {}) -> Process? {
        guard let script = Bundle.main.path(forResource: "dolmetscher", ofType: "py") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = ["-u", script, "--json"] + args
        p.environment = Paths.engineEnvironment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = Pipe()
        var buf = Data()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                buf.append(d)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = buf.subdata(in: buf.startIndex..<nl)
                    buf.removeSubrange(buf.startIndex...nl)
                    if let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onEvent(o) }
                }
            }
        }
        p.terminationHandler = { _ in DispatchQueue.main.async { onExit() } }
        do { try p.run() } catch { return nil }
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

    func reload() {
        _ = EngineRunner.run(["--profiles"], onEvent: { [weak self] o in
            guard o["event"] as? String == "profiles", let arr = o["profiles"] as? [[String: Any]] else { return }
            self?.profiles = arr.map(Self.parse)
        })
    }

    static func parse(_ d: [String: Any]) -> VoiceProfile {
        VoiceProfile(name: d["name"] as? String ?? "?", lang: d["lang"] as? String ?? "en",
                     created: d["created"] as? String ?? "", errorRate: d["error_rate"] as? Double,
                     vocab: d["vocab"] as? [String] ?? [])
    }

    func delete(_ p: VoiceProfile) {
        _ = EngineRunner.run(["--delete-profile", p.name], onEvent: { _ in }, onExit: { [weak self] in self?.reload() })
    }

    func saveVocab(_ p: VoiceProfile, _ text: String) {
        _ = EngineRunner.run(["--vocab", p.name, text], onEvent: { _ in }, onExit: { [weak self] in self?.reload() })
    }

    /// Thai-Profil -> Assistent auf Thai; sonst App-Sprache (Englisch, falls die App auf Thai steht).
    var forced: UILang { enrollLang == "th" ? .th : (L.lang == .th ? .en : L.lang) }

    func startEnroll(name: String, lang: String, model: String) {
        enrolling = true; enrollLang = lang; step = 0; sentence = ""; heard = ""; finished = nil; failed = nil
        hint = L.t("prep", forced)
        proc = EngineRunner.run(["--enroll", name, "--enroll-lang", lang, "--model", model],
                                onEvent: { [weak self] o in self?.handle(o) },
                                onExit: { [weak self] in
                                    guard let self else { return }
                                    if self.finished == nil && self.failed == nil && self.enrolling {
                                        self.failed = L.t("ended", self.forced)
                                    }
                                    self.proc = nil; self.reload()
                                })
        if proc == nil { failed = "dolmetscher.py?" }
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
    @AppStorage("uiLang") var uiLang = "de"
    @State private var newName = ""
    @State private var newLang = "th"
    @State private var vocabEdit: [String: String] = [:]
    @State private var confirmDelete: VoiceProfile?

    var body: some View {
        Group { if pm.enrolling { EnrollView(pm: pm) } else { list } }
            .frame(width: 660, height: 500)
            .onAppear { pm.reload() }
            .id(uiLang)
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("profiles")).font(.largeTitle.bold())
                Spacer()
                Picker("", selection: $uiLang) {
                    ForEach(UILang.allCases) { Text($0.label).tag($0.rawValue) }
                }.frame(width: 140).help(L.t("ui_language"))
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
                    m.stop()                         // Mikrofon freigeben
                    pm.startEnroll(name: newName.trimmingCharacters(in: .whitespaces), lang: newLang, model: m.model)
                    newName = ""
                } label: { Label(L.t("record"), systemImage: "record.circle") }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .confirmationDialog(L.t("delete_confirm"), isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L.t("delete"), role: .destructive) { if let p = confirmDelete { pm.delete(p) }; confirmDelete = nil }
            Button(L.t("cancel"), role: .cancel) { confirmDelete = nil }
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
                Button(L.t("redo")) { m.stop(); pm.startEnroll(name: p.name, lang: p.lang, model: m.model) }
                Button(role: .destructive) { confirmDelete = p } label: { Image(systemName: "trash") }
                    .help(L.t("delete"))
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
