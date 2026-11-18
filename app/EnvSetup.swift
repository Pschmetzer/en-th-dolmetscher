// EnvSetup.swift – Erststart-Bildschirm: Python-Umgebung (setup-env.sh mit mitgeliefertem uv) und
// Sprachmodelle (Engine-Start mit `download_progress`). Größe/Freiplatz, Fortschritt, Abbrechen,
// Wiederholen, Offline-Meldung. Reine Logik: EnvLogic.swift.
import AppKit
import SwiftUI

@MainActor
final class EnvSetupModel: ObservableObject {
    static let shared = EnvSetupModel()
    enum Phase: Equatable {
        case idle                     // noch nicht gestartet (Größe/Freiplatz anzeigen)
        case env(step: String)        // setup-env.sh läuft
        case models                   // Engine lädt fehlende Modelle
        case failed(kind: String)     // offline | disk | integrity | arch | cancelled | failed | missing_parts | no_space
        case done
    }

    @Published private(set) var phase: Phase = .idle
    /// Bildschirm zeigen: Umgebung fehlt/veraltet, oder der Nutzer hat „neu einrichten“ gewählt,
    /// oder die Einrichtung läuft gerade bis zu den Modellen.
    @Published private(set) var visible: Bool
    @Published private(set) var pkgProgress: Int?     // Nr. 23
    private var proc: Process?
    private var buffer = Data()
    static let logURL = Paths.support.appendingPathComponent("setup.log")

    private init() {
        visible = Paths.pythonIsFallback
    }

    /// Eine vorhandene, aber veraltete venv (anderer Lock nach App-Update) – anderer Einleitungstext.
    var isUpdate: Bool { FileManager.default.fileExists(atPath: Paths.venvPython) && !Paths.venvStampOK }

    var envMissing: Bool { Paths.pythonIsFallback }

    /// Freier Platz auf dem Volume von Application Support (für wichtige Daten, wie macOS ihn berechnet).
    static func freeBytes() -> Int64? { freeBytes(at: Paths.support) }

    /// Nächster vorhandener Ordner oberhalb von `url` (der Zielordner entsteht erst bei der Einrichtung).
    private static func existing(_ u: URL) -> URL {
        var url = u
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" { url.deleteLastPathComponent() }
        return url
    }
    static func freeBytes(at u: URL) -> Int64? {
        try? existing(u).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
    /// Nr. 24: Umgebung (Application Support) und Modelle (Hugging-Face-Cache) können auf verschiedenen Volumes liegen.
    static var modelsURL: URL { URL(fileURLWithPath: ModelCache.hubDir) }
    static var separateVolumes: Bool {
        let k: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let a = try? existing(Paths.support).resourceValues(forKeys: k).volumeIdentifier as? NSObject,
              let b = try? existing(modelsURL).resourceValues(forKeys: k).volumeIdentifier as? NSObject else { return false }
        return !a.isEqual(b)
    }
    /// Reicht der Platz? Gleiches Volume: Summe; getrennte Volumes: jeder Teil für sich.
    static func spaceOK(envMissing: Bool, modelsGB: Double) -> Bool {
        let envGB = EnvLogic.requiredGB(envMissing: envMissing, modelsGB: 0)
        let mGB = EnvLogic.requiredGB(envMissing: false, modelsGB: modelsGB)
        if separateVolumes {
            return EnvLogic.enoughSpace(freeBytes: freeBytes(), requiredGB: envGB)
                && EnvLogic.enoughSpace(freeBytes: freeBytes(at: modelsURL), requiredGB: mGB)
        }
        return EnvLogic.enoughSpace(freeBytes: freeBytes(), requiredGB: EnvLogic.requiredGB(envMissing: envMissing, modelsGB: modelsGB))
    }

    /// Fehlende Modelle in GB für die aktuelle Wahl; bei „auto“ die Schätzung für medium.
    static func modelsGB(model: String, thai: Bool) -> Double {
        ModelCache.missingGB(model: model, thai: thai, cached: ModelCache.cached())
            ?? ModelCache.missingGB(model: "medium", thai: thai, cached: ModelCache.cached()) ?? 0
    }

    func show() { visible = true; if case .done = phase { phase = .idle } }

    /// Einrichtung starten: erst die Umgebung (falls nötig), dann die Modelle über die Engine.
    func start(engine: EngineModel) {
        if case .env = phase { return }
        if proc?.isRunning == true { return }     // Nr. 2: altes Skript räumt noch auf – nie zwei zugleich
        guard Self.spaceOK(envMissing: envMissing || visibleRedo,
                           modelsGB: Self.modelsGB(model: engine.model, thai: Langs.hasThai)) else {
            phase = .failed(kind: "no_space"); return
        }
        if envMissing || visibleRedo { runEnvSetup(engine: engine) } else { startModels(engine: engine) }
    }

    /// „Neu einrichten“ aus den Einstellungen: Umgebung auch bei passendem Stempel neu aufbauen.
    @Published private(set) var visibleRedo = false
    func redo() { visibleRedo = true; phase = .idle; visible = true }

    private func runEnvSetup(engine: EngineModel) {
        guard let uv = Paths.bundledUV, let lock = Paths.bundledLock, let stamp = Paths.bundledStamp,
              let script = Paths.setupScript else {
            phase = .failed(kind: "missing_parts"); return
        }
        engine.stopEngine()               // nie eine venv austauschen, aus der gerade ein Prozess läuft
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, uv, lock, stamp, Paths.support.path]
        // Minimale Umgebung: kein geerbtes PYTHON*/VIRTUAL_ENV/UV_* der App, kein Homebrew im PATH.
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        for k in ["TMPDIR", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
                  "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"] {
            if let v = ProcessInfo.processInfo.environment[k] { env[k] = v }
        }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        buffer = Data()
        // Ende erst nach EOF auswerten: alle Zeilen (auch `done`/`fail`) sind dann schon verarbeitet.
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                DispatchQueue.global(qos: .utility).async {
                    p.waitUntilExit()
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(p, engine: engine) } }
                }
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(d) } }
        }
        phase = .env(step: "python")
        do { try p.run(); proc = p } catch { phase = .failed(kind: "failed") }
    }

    private func ended(_ p: Process, engine: EngineModel) {
        guard proc === p else { return }
        proc = nil
        switch phase {
        case .env: phase = .failed(kind: "failed")          // ohne done/fail-Zeile beendet (abgestürzt)
        case .models: startModels(engine: engine)
        default: break
        }
    }

    private func consume(_ d: Data) {
        guard !d.isEmpty else { return }
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            switch EnvLogic.parseSetupLine(line) {
            case .step(let s)?: pkgProgress = nil; phase = .env(step: s)
            case .progress(let p)?: pkgProgress = p
            case .done?: visibleRedo = false; phase = .models   // Modelle starten, sobald der Prozess endet
            case .fail(let k)?: phase = .failed(kind: k)
            case nil: break
            }
        }
    }

    /// Modelle: Engine starten (lädt Fehlendes mit `download_progress`). Fertig, sobald `ready` kommt.
    private func startModels(engine: EngineModel) {
        guard !Paths.pythonIsFallback else { phase = .failed(kind: "failed"); return }
        phase = .models
        engine.lastError = nil              // „Python-Umgebung fehlt“ vom App-Start ist erledigt
        engine.restart()
    }

    /// Engine meldet ready bzw. einen Modellfehler (aus der Ansicht beobachtet).
    func engineChanged(_ engine: EngineModel) {
        guard case .models = phase else { return }
        if engine.engineReady { phase = .done }
        else if engine.modelOffline { phase = .failed(kind: "offline"); engine.stopEngine() }
    }

    func cancel(engine: EngineModel) {
        if let p = proc, p.isRunning {
            p.terminate()                  // setup-env.sh räumt die halbe Umgebung selbst ab
            phase = .failed(kind: "cancelled")
        } else if case .models = phase {
            engine.stopEngine()
            phase = .failed(kind: "cancelled")
        }
    }

    /// App wird beendet: setup-env.sh beenden und kurz warten, damit es die halbe Umgebung entfernt.
    func terminateSetup() {
        guard let p = proc, p.isRunning else { return }
        p.terminate()
        let end = Date().addingTimeInterval(3)
        while p.isRunning && Date() < end { usleep(50_000) }
    }

    /// Abschluss: Bildschirm schließen (die Engine läuft bereits).
    func finish() { visible = false; phase = .idle }

    var running: Bool {
        switch phase { case .env, .models: return true; default: return false }
    }
}

/// Einrichtungs-Bildschirm im Hauptfenster.
struct EnvSetupView: View {
    @EnvironmentObject var m: EngineModel
    @ObservedObject var s: EnvSetupModel

    private var modelsGB: Double { EnvSetupModel.modelsGB(model: m.model, thai: Langs.hasThai) }
    private var envNeeded: Bool { s.envMissing || s.visibleRedo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("envsetup_title")).font(.title.bold())
            Text(L.t(s.isUpdate ? "envsetup_update" : "envsetup_intro"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if Paths.pythonOverride != nil, case .override = Paths.pythonSource {
                Label(L.t("envsetup_dev"), systemImage: "hammer").font(.callout)
            }
            sizeLine
            progressRows
            if case .failed(let kind) = s.phase { failure(kind) }
            buttons
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: m.engineReady) { s.engineChanged(m) }
        .onChange(of: m.modelOffline) { s.engineChanged(m) }
    }

    private var sizeLine: some View {
        let download = (envNeeded ? 0.4 : 0) + modelsGB
        let need = EnvLogic.requiredGB(envMissing: envNeeded, modelsGB: modelsGB)
        var freeB = EnvSetupModel.freeBytes()
        if EnvSetupModel.separateVolumes, modelsGB > 0, let f2 = EnvSetupModel.freeBytes(at: EnvSetupModel.modelsURL) {
            freeB = min(freeB ?? f2, f2)       // der knappere der beiden Volumes zählt
        }
        let free = freeB.map { Double($0) / 1e9 } ?? 0
        return Label(L.f("envsetup_size", download, need, free), systemImage: "internaldrive")
            .font(.callout)
    }

    @ViewBuilder private var progressRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(L.t("envsetup_env"), envState)
            row(L.t("envsetup_models"), modelState)
        }
    }

    private enum RowState { case pending, active(String, Double?), ok }

    private var envState: RowState {
        switch s.phase {
        case .env(let step):
            let key = ["packages": "envsetup_step_packages", "verify": "envsetup_step_verify"][step] ?? "envsetup_step_python"
            return .active(L.t(key) + (step == "packages" ? s.pkgProgress.map { " \($0) %" } ?? "" : ""),
                           EnvLogic.stepFraction(step, progress: s.pkgProgress))
        case .models, .done: return .ok
        default: return envNeeded ? .pending : .ok
        }
    }

    private var modelState: RowState {
        switch s.phase {
        case .done: return .ok
        case .models:
            if let d = m.download {
                return .active(L.f("envsetup_model_progress", d.model, d.done, d.total ?? 0),
                               EnvLogic.downloadFraction(done: d.done, total: d.total))
            }
            return .active(L.t("envsetup_model_waiting"), nil)
        default: return modelsGB == 0 && !envNeeded ? .ok : .pending
        }
    }

    private func row(_ title: String, _ st: RowState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch st {
                case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(LangStyle.success)
                case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
                case .active: ProgressView().controlSize(.small)
                }
            }
            .frame(width: 20)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if case .active(let text, let frac) = st {
                    Text(text).font(.callout).foregroundStyle(.secondary)
                    if let frac { ProgressView(value: frac) } else { ProgressView().progressViewStyle(.linear) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(L.t(stepKey(st)))
    }

    private func stepKey(_ st: RowState) -> String {
        switch st {
        case .ok: return "a11y_step_done"
        case .pending: return "a11y_step_pending"
        case .active: return "a11y_step_active"
        }
    }

    private func failure(_ kind: String) -> some View {
        let key: String = {
            switch kind {
            case "offline": return "envsetup_offline"
            case "disk": return "envsetup_disk"
            case "integrity": return "envsetup_integrity"
            case "no_space": return "envsetup_no_space"
            case "arch": return "envsetup_arch"
            case "cancelled": return "envsetup_cancelled"
            case "missing_parts": return "envsetup_missing_parts"
            default: return "envsetup_failed"
            }
        }()
        return Label(L.t(key), systemImage: kind == "offline" ? "wifi.slash" : "exclamationmark.triangle.fill")
            .foregroundStyle(kind == "cancelled" ? Color.secondary : LangStyle.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack {
            if case .failed = s.phase {
                Button(L.t("envsetup_show_log")) { NSWorkspace.shared.activateFileViewerSelecting([EnvSetupModel.logURL]) }
            }
            Spacer()
            switch s.phase {
            case .idle:
                // bewusst ohne Return-Kürzel: startet einen großen Download (nur per Klick/Leertaste)
                Button(L.t("envsetup_start")) { s.start(engine: m) }.buttonStyle(.borderedProminent)
            case .env, .models:
                Button(L.t("envsetup_cancel")) { s.cancel(engine: m) }.keyboardShortcut(.cancelAction)
            case .failed(let kind):
                if kind != "arch" && kind != "missing_parts" {
                    Button(L.t("envsetup_retry")) { s.start(engine: m) }.buttonStyle(.borderedProminent)
                }
            case .done:
                Label(L.t("envsetup_done"), systemImage: "checkmark.seal.fill").foregroundStyle(LangStyle.success)
                Button(L.t("envsetup_continue")) { s.finish() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Fortschritt eines Modell-Downloads außerhalb der Einrichtung (z. B. nach einem Modellwechsel).
struct DownloadBanner: View {
    let d: EngineModel.Download
    var body: some View {
        let pct = Int((EnvLogic.downloadFraction(done: d.done, total: d.total) ?? 0) * 100)
        NoticeBanner(icon: "arrow.down.circle", tint: .accentColor, text: L.f("download_banner", d.model, pct))
    }
}
