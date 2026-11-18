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
    /// Mitgelieferter translate-helper (Apple Translation, on-device; Contents/Helpers). Läuft erst ab macOS 26.4 –
    /// auf älteren Systemen gilt er als nicht vorhanden (der Helfer würde nur „macOS 26.4 nötig“ melden).
    static var bundledTranslateHelper: String? {
        let p = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/translate-helper").path
        guard FileManager.default.isExecutableFile(atPath: p),
              ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0))
        else { return nil }
        return p
    }
    static var bundledLock: String? { Bundle.main.path(forResource: "requirements", ofType: "txt") }
    static var bundledStamp: String? { Bundle.main.path(forResource: "env-stamp", ofType: nil) }
    static var setupScript: String? { Bundle.main.path(forResource: "setup-env", ofType: "sh") }

    /// Dev-Override: DOLMETSCHER_PYTHON aus der Umgebung der App oder die Einstellung „DolmetscherPython“
    /// (`defaults write io.github.dolmetscher.en-th DolmetscherPython /pfad/zu/python`). Wird nie verändert.
    /// Nr. 14: Im Release-Build (`-D RELEASE_BUILD`, build.sh --release) zählt nur die Umgebungsvariable: die
    /// Einstellung ließe sich von jedem Prozess des Nutzers setzen und startete ein fremdes Programm mit der
    /// Mikrofon-Freigabe der App.
    static var pythonOverride: String? {
        #if RELEASE_BUILD
        return ProcessInfo.processInfo.environment["DOLMETSCHER_PYTHON"]
        #else
        return ProcessInfo.processInfo.environment["DOLMETSCHER_PYTHON"] ?? UserDefaults.standard.string(forKey: "DolmetscherPython")
        #endif
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
    /// `includeKey`: nur der Engine-Prozess braucht den Claude-Schlüssel (Nr. 13); Hilfsaufrufe (Mikrofonliste,
    /// Profile, Verlauf, Python-Prüfung) bekommen ihn nicht und lösen keinen Schlüsselbund-Zugriff aus.
    static func engineEnvironment(includeKey: Bool = false) -> [String: String] {
        var env: [String: String] = [:]
        for (k, v) in ProcessInfo.processInfo.environment
        where envExact.contains(k) || envPrefixes.contains(where: { k.hasPrefix($0) }) {
            env[k] = v
        }
        if !includeKey { env["ANTHROPIC_API_KEY"] = nil }
        env["PATH"] = (searchDirs + ["/usr/bin", "/bin"]).joined(separator: ":")
        // Die Whitelist lässt PYTHON* bewusst nicht durch – deshalb hier ausdrücklich setzen.
        env["PYTHONPYCACHEPREFIX"] = pycachePrefix
        // Schlüssel aus dem Schlüsselbund (Nr. 23); ein in der App-Umgebung gesetzter Schlüssel hat Vorrang
        if includeKey {
            if env["ANTHROPIC_API_KEY"] == nil, let k = APIKeyStore.read() { env["ANTHROPIC_API_KEY"] = k }
        }
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
/// `anthropic_key` (0600) wird beim Start übernommen. Sie bleibt, solange der Schlüsselbund den Wert nicht
/// nachweislich zurückliefert, und wird auch danach nie gelöscht, sondern in `anthropic_key.migrated` (0600)
/// umbenannt: Rückfall für den Start im Terminal und für Builds, deren Signatur den Schlüsselbund-Zugriff verliert
/// (Ad-hoc-Signatur). Die Engine liest beide Dateien, wenn kein `ANTHROPIC_API_KEY` gesetzt ist.
enum APIKeyStore {
    static let url = Paths.support.appendingPathComponent("anthropic_key")
    static let migratedURL = Paths.support.appendingPathComponent("anthropic_key.migrated")
    static let service = "Dolmetscher"
    static let account = "anthropic"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: migratedURL.path)
    }
    /// Nur Attribute abfragen (kein Geheimnis lesen): löst keine Zugriffsabfrage aus.
    static var exists: Bool {
        var q = baseQuery
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess || fileExists
    }

    /// Einmal je App-Sitzung gelesen (jeder Engine-Start bräuchte sonst einen Schlüsselbund-Zugriff);
    /// Speichern und Entfernen setzen den Zwischenspeicher zurück.
    private nonisolated(unsafe) static var cached: String??

    /// Schlüssel für die Engine: Schlüsselbund, sonst (Rückfall) die alte Datei.
    static func read() -> String? {
        if let c = cached { return c }
        let v = readUncached()
        cached = .some(v)
        return v
    }

    private static func readUncached() -> String? {
        if let k = keychainRead() { return k }
        return readFile(url) ?? readFile(migratedURL)
    }

    private static func readFile(_ u: URL) -> String? {
        guard let s = try? String(contentsOf: u, encoding: .utf8) else { return nil }
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
        cached = nil
        if keychainWrite(k), keychainRead() == k {
            // Rückfall-Datei auf denselben (neuen) Stand bringen, nie ersatzlos löschen
            #if RELEASE_BUILD
            removeFiles()                    // Nr. 15: signierter Build – der Schlüsselbund reicht, keine Klartextkopie
            #else
            if writeFile(k, to: migratedURL) { try? FileManager.default.removeItem(at: url) }
            #endif
            return true
        }
        return writeFile(k, to: url)
    }

    static func keychainWrite(_ k: String) -> Bool {
        let data = Data(k.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var add = baseQuery
        attrs.forEach { add[$0.key] = $0.value }
        add[kSecAttrLabel as String] = "Dolmetscher – Anthropic API"
        let st = SecItemAdd(add as CFDictionary, nil)
        if st == errSecDuplicateItem {
            return SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }
        return st == errSecSuccess
    }

    /// Übernahme der alten Datei in den Schlüsselbund (beim App-Start). Erst wenn der Schlüsselbund denselben
    /// Wert nachweislich zurückliefert, wird die Datei in `anthropic_key.migrated` (0600) umbenannt – nie gelöscht.
    static func migrate() {
        // Nr. 16: vorhandenen Eintrag einmalig auf „nur dieses Gerät“ (kein Backup-/Geräte-Transfer) umstellen
        let flag = "keychainThisDeviceOnly"
        if !UserDefaults.standard.bool(forKey: flag), let kk = keychainRead() {
            if keychainWrite(kk) { UserDefaults.standard.set(true, forKey: flag) }
        }
        #if RELEASE_BUILD
        // Nr. 15: Developer-ID-Build – eine ältere Rückfall-Kopie neben dem Schlüsselbund-Eintrag wird entfernt
        if readFile(migratedURL) != nil, keychainRead() != nil, readFile(url) == nil { removeFiles() }
        #endif
        guard let k = readFile(url) else { return }
        cached = nil
        guard keychainRead() == k || (keychainWrite(k) && keychainRead() == k) else { return }   // Datei bleibt
        #if RELEASE_BUILD
        removeFiles()
        return
        #else
        let fm = FileManager.default
        try? fm.removeItem(at: migratedURL)                // älterer Stand; die aktuelle Datei ersetzt ihn
        do {
            try fm.moveItem(at: url, to: migratedURL)
            chmod(migratedURL.path, 0o600)
        } catch {
            // Umbenennen gescheitert: Datei bleibt unter dem alten Namen (Engine liest sie weiter)
        }
        #endif
    }

    /// Klartextdateien sicher entfernen (erst überschreiben, dann löschen).
    private static func removeFiles() {
        let fm = FileManager.default
        for u in [url, migratedURL] where fm.fileExists(atPath: u.path) {
            if let h = try? FileHandle(forWritingTo: u) {
                let n = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
                try? h.write(contentsOf: Data(repeating: 0x30, count: max(n, 64)))
                try? h.synchronize(); try? h.close()
            }
            try? fm.removeItem(at: u)
        }
    }

    /// Rückfall: Datei so schreiben, dass sie zu keinem Zeitpunkt für andere lesbar ist.
    private static func writeFile(_ k: String, to target: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let fd = open(target.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
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
        cached = nil
        SecItemDelete(baseQuery as CFDictionary)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: migratedURL)   // Nutzer will den Schlüssel ganz entfernen
    }
}
