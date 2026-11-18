// Setup.swift – Erststart-Checkliste (Nr. 355) und Modell-Cache-Hinweis in der Modellwahl (Nr. 356).
import AVFoundation
import SwiftUI

/// Welche Modelle eine Modellwahl lädt (wie Engine.__init__ in dolmetscher.py) und ob sie schon im Cache liegen.
enum ModelCache {
    struct Repo: Hashable { let id: String; let gb: Double }
    static let small = Repo(id: "Systran/faster-whisper-small", gb: 0.5)
    static let medium = Repo(id: "Systran/faster-whisper-medium", gb: 1.5)
    static let turbo = Repo(id: "mobiuslabsgmbh/faster-whisper-large-v3-turbo", gb: 1.6)
    static let thai = Repo(id: "Vinxscribe/biodatlab-whisper-th-medium-faster", gb: 1.5)

    /// Modelle der Wahl; nil bei "auto" (hängt von der Hardware ab). small lädt kein Thai-Modell.
    static func needed(model: String, thai: Bool) -> [Repo]? {
        switch model {
        case "small": return [small]
        case "medium": return [medium, small] + (thai ? [Self.thai] : [])
        case "best": return [turbo, small] + (thai ? [Self.thai] : [])
        default: return nil
        }
    }

    /// Cache-Ordner wie huggingface_hub: HF_HUB_CACHE, dann HF_HOME/hub, dann XDG_CACHE_HOME/huggingface/hub (Nr. 4).
    static func hubDir(env: [String: String] = ProcessInfo.processInfo.environment,
                       home: String = NSHomeDirectory()) -> String {
        func set(_ k: String) -> String? { env[k].flatMap { $0.isEmpty ? nil : $0 } }
        if let d = set("HF_HUB_CACHE") { return d }
        if let h = set("HF_HOME") { return h + "/hub" }
        if let x = set("XDG_CACHE_HOME") { return x + "/huggingface/hub" }
        return home + "/.cache/huggingface/hub"
    }
    static var hubDir: String { hubDir() }

    /// Ein Modellordner gilt erst als geladen, wenn ein Snapshot mit Inhalt da ist und kein Blob mehr
    /// `.incomplete` heißt (Nr. 3): der Ordner entsteht schon beim Start des Downloads.
    static func isComplete(modelDir: String) -> Bool {
        let fm = FileManager.default
        let blobs = (try? fm.contentsOfDirectory(atPath: modelDir + "/blobs")) ?? []
        if blobs.contains(where: { $0.hasSuffix(".incomplete") }) { return false }
        let snaps = (try? fm.contentsOfDirectory(atPath: modelDir + "/snapshots")) ?? []
        return snaps.contains { !((try? fm.contentsOfDirectory(atPath: modelDir + "/snapshots/" + $0)) ?? []).isEmpty }
    }

    /// Repo-IDs im Hugging-Face-Cache ("models--Org--Name" -> "Org/Name"), nur vollständig geladene.
    static func cached(in dir: String = hubDir) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return Set(names.filter { $0.hasPrefix("models--") && isComplete(modelDir: dir + "/" + $0) }
            .map { String($0.dropFirst(8)).replacingOccurrences(of: "--", with: "/") })
    }

    /// Noch herunterzuladende GB (0 = alles da); nil bei "auto".
    static func missingGB(model: String, thai: Bool, cached: Set<String>) -> Double? {
        needed(model: model, thai: thai).map { $0.filter { !cached.contains($0.id) }.reduce(0) { $0 + $1.gb } }
    }

    /// Kurzer Hinweis für die Modellwahl: „geladen“ oder „lädt beim ersten Start ≈ X GB“.
    static func hint(model: String, thai: Bool, cached: Set<String> = cached()) -> String {
        guard let gb = missingGB(model: model, thai: thai, cached: cached) else { return L.t("model_cache_auto") }
        return gb == 0 ? L.t("model_cache_ready") : L.f("model_cache_download", gb)
    }
}

/// „Alles bereit?“ im Willkommensdialog: Python-Umgebung, Modelle, Mikrofon, Claude-Schlüssel (Audio über PyAV, kein ffmpeg).
struct SetupChecklist: View {
    let model: String
    let thai: Bool
    @State private var cached = ModelCache.cached()

    private struct Row: Identifiable {
        let id: String
        let ok: Bool?            // nil = optional/Hinweis
        let text: String
    }

    private var rows: [Row] {
        let gb = ModelCache.missingGB(model: model, thai: thai, cached: cached)
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        return [
            Row(id: "python", ok: !Paths.pythonIsFallback, text: L.t(Paths.pythonIsFallback ? "setup_python_missing" : "setup_python_ok")),
            Row(id: "models", ok: gb.map { $0 == 0 }, text: ModelCache.hint(model: model, thai: thai, cached: cached)),
            Row(id: "mic", ok: mic == .authorized ? true : mic == .notDetermined ? nil : false,
                text: L.t(mic == .authorized ? "setup_mic_ok" : mic == .notDetermined ? "setup_mic_ask" : "setup_mic_denied")),
            Row(id: "key", ok: APIKeyStore.exists ? true : nil, text: L.t(APIKeyStore.exists ? "setup_key_ok" : "setup_key_optional")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("setup_title")).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(rows) { r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: r.ok == true ? "checkmark.circle.fill" : r.ok == false ? "xmark.octagon.fill" : "info.circle")
                        .foregroundStyle(r.ok == true ? LangStyle.success : r.ok == false ? Color.red : Color.secondary)
                        .accessibilityHidden(true)
                    Text(r.text).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel((r.ok == true ? "✓ " : r.ok == false ? "✗ " : "") + r.text)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { cached = ModelCache.cached() }
    }
}
