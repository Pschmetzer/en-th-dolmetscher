// Paths.swift – Python der Engine (Dev-Override → eigene venv mit Stempel → Einrichtung), Umgebung und API-Schlüsseldatei.
// Die Info.plist enthält keine Pfade der Bau-Maschine; ffmpeg wird nicht mehr gesucht (Audio über PyAV).
import Foundation
import Security

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dolmetscher")

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// Eigene venv (setup-env.sh legt sie an) und ihr Stempel.
    static var venv: URL { support.appendingPathComponent("venv") }
    static var venvPython: String { venv.appendingPathComponent("bin/python").path }
    static var venvStamp: URL { venv.appendingPathComponent(EnvLogic.stampName) }

    /// Mitgelieferte Einrichtung: uv (Contents/Helpers), Lock, erwarteter Stempel, Skript (Contents/Resources).
    static var bundledUV: String? {
        let p = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/uv").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }
    static var bundledLock: String? { Bundle.main.path(forResource: "requirements", ofType: "txt") }
    static var bundledStamp: String? { Bundle.main.path(forResource: "env-stamp", ofType: nil) }
    static var setupScript: String? { Bundle.main.path(forResource: "setup-env", ofType: "sh") }

    /// Dev-Override: DOLMETSCHER_PYTHON aus der Umgebung der App oder die Einstellung „DolmetscherPython“
    /// (`defaults write io.github.dolmetscher.en-th DolmetscherPython /pfad/zu/python`). Wird nie verändert.
    static var pythonOverride: String? {
        ProcessInfo.processInfo.environment["DOLMETSCHER_PYTHON"] ?? UserDefaults.standard.string(forKey: "DolmetscherPython")
    }

    /// Stempel der venv passt zum Bundle (sonst: Einrichtung bzw. Aktualisierung nach App-Update).
    static var venvStampOK: Bool {
        let expected = bundledStamp.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        let actual = try? String(contentsOf: venvStamp, encoding: .utf8)
        return EnvLogic.stampMatches(expected: expected, actual: actual)
    }

    static var pythonSource: EnvLogic.PythonSource {
        EnvLogic.resolvePython(override: pythonOverride, venvPython: venvPython, stampOK: venvStampOK,
                               isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// Python für die Engine. Ohne eingerichtete Umgebung ein harmloser Platzhalter: `pythonIsFallback`
    /// verhindert jeden Start (nie /usr/bin/python3 – ohne Command-Line-Tools öffnet das einen Xcode-Dialog).
    static var python: String {
        switch pythonSource {
        case .override(let p), .venv(let p): return p
        case .none: return "/usr/bin/false"
        }
    }

    /// true, wenn keine passende Python-Umgebung da ist (Einrichtungs-Bildschirm zeigen).
    static var pythonIsFallback: Bool { pythonSource == .none }

    /// Suchpfade für Hilfsprogramme der Engine (afplay/say liegen in /usr/bin).
    static var searchDirs: [String] {
        ["/opt/homebrew/bin", "/opt/local/bin", "/usr/local/bin",
         home + "/.asdf/shims", home + "/.asdf/bin", home + "/.local/bin"]
    }

    /// Externes ffmpeg nur, wenn ausdrücklich gesetzt (DOLMETSCHER_FFMPEG); sonst PyAV.
    static var ffmpegOverride: String? {
        ProcessInfo.processInfo.environment["DOLMETSCHER_FFMPEG"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// .pyc-Dateien nie ins (signierte) App-Bundle schreiben: eigener Ordner unter Application Support.
    static var pycachePrefix: String { support.appendingPathComponent("pycache").path }

    /// Variablen, die die Engine wirklich braucht. Alles andere aus der Umgebung der App
    /// (z. B. geerbte Tokens, PYTHON*-Overrides) bleibt draußen. DOLMETSCHER_FFMPEG kommt nur durch,
    /// wenn er in der Umgebung der App gesetzt ist (Präfix DOLMETSCHER_).
    private static let envExact: Set<String> = [
        "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SHELL", "ANTHROPIC_API_KEY",
        "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "OMP_NUM_THREADS", "TOKENIZERS_PARALLELISM",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy", "__CF_USER_TEXT_ENCODING",
    ]
    private static let envPrefixes = ["DOLMETSCHER_", "LC_", "HF_", "HUGGINGFACE_", "CT2_", "KMP_"]

    /// Umgebung für jeden Start von dolmetscher.py (Whitelist, siehe oben).
    static func engineEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for (k, v) in ProcessInfo.processInfo.environment
        where envExact.contains(k) || envPrefixes.contains(where: { k.hasPrefix($0) }) {
            env[k] = v
        }
        env["PATH"] = (searchDirs + ["/usr/bin", "/bin"]).joined(separator: ":")
        // Die Whitelist lässt PYTHON* bewusst nicht durch – deshalb hier ausdrücklich setzen.
        env["PYTHONPYCACHEPREFIX"] = pycachePrefix
        // Schlüssel aus dem Schlüsselbund (Nr. 23); ein in der App-Umgebung gesetzter Schlüssel hat Vorrang
        if env["ANTHROPIC_API_KEY"] == nil, let k = APIKeyStore.read() { env["ANTHROPIC_API_KEY"] = k }
        return env
    }

    /// `ok` trägt die Versionen („3.12.4 1.0.3“ = Python, faster-whisper).
    enum PythonCheck: Equatable { case ok(String), noModule, failed(String) }

    /// Prüft im Hintergrund, ob `import faster_whisper` mit dem Engine-Python klappt (Timeout 15 s).
    /// `done` läuft auf dem Main-Thread.
    static func checkPython(done: @escaping (PythonCheck) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = ["-c", "import sys, faster_whisper; print(sys.version.split()[0], getattr(faster_whisper, '__version__', '?'))"]
            p.environment = engineEnvironment()
            let err = Pipe()
            p.standardError = err
            let outPipe = Pipe()
            p.standardOutput = outPipe
            p.standardInput = FileHandle.nullDevice
            let sem = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in sem.signal() }
            var result = PythonCheck.ok("?")
            do { try p.run() } catch {
                DispatchQueue.main.async { done(.failed(error.localizedDescription)) }
                return
            }
            if sem.wait(timeout: .now() + 15) == .timedOut {
                p.terminate()
                result = .failed("timeout")
            } else if p.terminationStatus == 0 {
                let v = String(decoding: outPipe.fileHandleForReading.availableData, as: UTF8.self)
                result = .ok(v.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                let text = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
                result = text.contains("No module named") ? .noModule : .failed(String(text.suffix(300)))
            }
            DispatchQueue.main.async { done(result) }
        }
    }
}

/// Anthropic-API-Schlüssel im macOS-Schlüsselbund (Nr. 23); Inhalt wird nie angezeigt oder geloggt.
/// Die Engine liest ihn nicht selbst (keine ACL-Abfrage durch `security`): die App reicht ihn beim Start jedes
/// Engine-Prozesses als `ANTHROPIC_API_KEY` durch (`Paths.engineEnvironment`). Die frühere Datei
/// `anthropic_key` (0600) wird beim ersten Start übernommen und erst gelöscht, wenn der Schlüsselbund denselben
/// Wert zurückliefert. Fehlt der Schlüsselbund (Fehler beim Schreiben), bleibt die Datei als Rückfall.
enum APIKeyStore {
    static let url = Paths.support.appendingPathComponent("anthropic_key")
    static let service = "Dolmetscher"
    static let account = "anthropic"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }
    static var exists: Bool { keychainRead() != nil || fileExists }

    /// Schlüssel für die Engine: Schlüsselbund, sonst (Rückfall) die alte Datei.
    static func read() -> String? {
        if let k = keychainRead() { return k }
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty ? nil : k
    }

    static func keychainRead() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let k = String(data: d, encoding: .utf8), !k.isEmpty else { return nil }
        return k
    }

    /// In den Schlüsselbund schreiben (vorhandenen Eintrag ersetzen); erst nach erfolgreichem Zurücklesen die
    /// alte Datei löschen. Klappt der Schlüsselbund nicht, wird wie früher die Datei (0600) geschrieben.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return false }
        if keychainWrite(k), keychainRead() == k {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        return writeFile(k)
    }

    static func keychainWrite(_ k: String) -> Bool {
        let data = Data(k.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var add = baseQuery
        attrs.forEach { add[$0.key] = $0.value }
        add[kSecAttrLabel as String] = "Dolmetscher – Anthropic API"
        let st = SecItemAdd(add as CFDictionary, nil)
        if st == errSecDuplicateItem {
            return SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }
        return st == errSecSuccess
    }

    /// Einmalige Übernahme der alten Datei in den Schlüsselbund (beim App-Start).
    static func migrate() {
        guard fileExists, let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if keychainRead() == k || (keychainWrite(k) && keychainRead() == k) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Rückfall: Datei so schreiben, dass sie zu keinem Zeitpunkt für andere lesbar ist.
    private static func writeFile(_ k: String) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        fchmod(fd, 0o600)   // falls die Datei schon mit anderen Rechten existierte
        let bytes = Array(k.utf8)
        return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    /// Format-Hinweis (Nr. 390): Anthropic-Schlüssel beginnen mit `sk-ant-` (falsche Zwischenablage?).
    static func looksValid(_ key: String) -> Bool {
        key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-")
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
        try? FileManager.default.removeItem(at: url)
    }
}
