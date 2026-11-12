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

    /// Python für die Engine: Info-Wert DolmetscherPython → venv in Application Support → /usr/bin/python3.
    static var python: String {
        firstExecutable([info("DolmetscherPython"),
                         support.appendingPathComponent("venv/bin/python").path]) ?? "/usr/bin/python3"
    }

    /// ffmpeg: Info-Wert DolmetscherFFmpeg → Homebrew (Apple Silicon) → Homebrew (Intel).
    static var ffmpeg: String? {
        firstExecutable([info("DolmetscherFFmpeg"), "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"])
    }

    /// Umgebung für jeden Start von dolmetscher.py.
    static func engineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let ff = ffmpeg { env["DOLMETSCHER_FFMPEG"] = ff }
        return env
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
