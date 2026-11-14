// Paths.swift – Pfade zu Python/ffmpeg (Info.plist mit "~" erlaubt, sonst Fallbacks) und API-Schlüsseldatei.
import Foundation

enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dolmetscher")

    private static func info(_ key: String) -> String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String, !s.isEmpty else { return nil }
        return (s as NSString).expandingTildeInPath
    }

    private static func firstExecutable(_ candidates: [String?]) -> String? {
        candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// Python für die Engine: Info-Wert DolmetscherPython → venv in Application Support → /usr/bin/python3.
    static var python: String {
        firstExecutable([info("DolmetscherPython"),
                         support.appendingPathComponent("venv/bin/python").path]) ?? "/usr/bin/python3"
    }

    /// true, wenn die bevorzugte Python-Umgebung (venv/Info-Wert) fehlt und nur /usr/bin/python3 bleibt.
    static var pythonIsFallback: Bool { python == "/usr/bin/python3" }

    /// Suchpfade für Werkzeuge wie ffmpeg: Homebrew (ARM/Intel), MacPorts, asdf, ~/.local.
    static var searchDirs: [String] {
        ["/opt/homebrew/bin", "/opt/local/bin", "/usr/local/bin",
         home + "/.asdf/shims", home + "/.asdf/bin", home + "/.local/bin"]
    }

    /// ffmpeg: Info-Wert DolmetscherFFmpeg → bekannte Installationsorte.
    static var ffmpeg: String? {
        firstExecutable([info("DolmetscherFFmpeg")] + searchDirs.map { $0 + "/ffmpeg" })
    }

    /// Variablen, die die Engine wirklich braucht. Alles andere aus der Umgebung der App
    /// (z. B. geerbte Tokens, PYTHON*-Overrides) bleibt draußen.
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
        if let ff = ffmpeg { env["DOLMETSCHER_FFMPEG"] = ff }
        return env
    }

    enum PythonCheck: Equatable { case ok, noModule, failed(String) }

    /// Prüft im Hintergrund, ob `import faster_whisper` mit dem Engine-Python klappt (Timeout 15 s).
    /// `done` läuft auf dem Main-Thread.
    static func checkPython(done: @escaping (PythonCheck) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = ["-c", "import faster_whisper"]
            p.environment = engineEnvironment()
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            let sem = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in sem.signal() }
            var result = PythonCheck.ok
            do { try p.run() } catch {
                DispatchQueue.main.async { done(.failed(error.localizedDescription)) }
                return
            }
            if sem.wait(timeout: .now() + 15) == .timedOut {
                p.terminate()
                result = .failed("timeout")
            } else if p.terminationStatus != 0 {
                let text = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
                result = text.contains("No module named") ? .noModule : .failed(String(text.suffix(300)))
            }
            DispatchQueue.main.async { done(result) }
        }
    }
}

/// Anthropic-API-Schlüssel als Datei (nur der Schlüssel, Rechte 0600). Inhalt wird nie gelesen oder angezeigt.
enum APIKeyStore {
    static let url = Paths.support.appendingPathComponent("anthropic_key")

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Schreibt den Schlüssel so, dass die Datei zu keinem Zeitpunkt für andere lesbar ist.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        fchmod(fd, 0o600)   // falls die Datei schon mit anderen Rechten existierte
        let bytes = Array(k.utf8)
        return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    static func remove() { try? FileManager.default.removeItem(at: url) }
}
