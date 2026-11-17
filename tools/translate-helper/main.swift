// translate-helper: Apple Translation (on-device) als stdin/stdout-Dienst, ohne SwiftUI.
//
// Bauen:  swiftc -O -parse-as-library -o /tmp/translate-helper tools/translate-helper/main.swift
// Start:  translate-helper [--check] [--fast] [--timeout S]
//   --check    nur Status der Sprachpaare ausgeben und beenden
//   --fast     Strategie .lowLatency statt Standard (macOS 26.4+)
//   --timeout  Sekunden je Anfrage (Standard 5): danach {"id":…,"error":"timeout"}, Sitzung wird neu gebaut,
//              damit eine hängende Anfrage nicht alle folgenden blockiert (Nr. 218)
//
// Protokoll (eine JSON-Zeile pro Nachricht):
//   Start  -> {"ready":true,"pairs":{"en-th":"installed|supported|unsupported","th-en":"..."}}
//   Eingabe {"id":1,"text":"...","src":"th","dst":"en"}
//   Ausgabe {"id":1,"out":"...","ms":123}  oder  {"id":1,"error":"..."}

import Foundation
import Translation

@main
struct TranslateHelper {
    static func main() async {
        if #available(macOS 26.4, *) {
            await Helper.run()
        } else {
            FileHandle.standardOutput.write("{\"error\":\"macOS 26.4 oder neuer nötig\",\"ready\":false}\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

/// Nimmt genau ein Ergebnis an (Übersetzung oder Zeitüberschreitung, was zuerst kommt).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

struct HelperTimeout: Error {}

@available(macOS 26.4, *)
enum Helper {
    static let pairs: [(String, String)] = [("en", "th"), ("th", "en")]

    static func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
    }

    static func statusName(_ s: LanguageAvailability.Status) -> String {
        switch s {
        case .installed: return "installed"
        case .supported: return "supported"
        case .unsupported: return "unsupported"
        @unknown default: return "unknown"
        }
    }

    static func pairStatus(fast: Bool) async -> [String: String] {
        let avail = fast ? LanguageAvailability(preferredStrategy: .lowLatency) : LanguageAvailability()
        var out: [String: String] = [:]
        for (s, t) in pairs {
            let st = await avail.status(from: Locale.Language(identifier: s),
                                        to: Locale.Language(identifier: t))
            out["\(s)-\(t)"] = statusName(st)
        }
        return out
    }

    /// translate() mit Zeitgrenze. Die Übersetzung läuft als eigene Task: hängt sie, wird sie abgebrochen und die
    /// Antwort kommt trotzdem nach `timeout` Sekunden (eine Task-Gruppe würde auf das Kind warten).
    static func translate(_ s: TranslationSession, _ text: String, timeout: Double) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let once = Once()
            let work = Task {
                do {
                    let r = try await s.translate(text).targetText
                    if once.take() { cont.resume(returning: r) }
                } catch {
                    if once.take() { cont.resume(throwing: error) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.take() { work.cancel(); cont.resume(throwing: HelperTimeout()) }
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if error is HelperTimeout { return "timeout" }
        if TranslationError.notInstalled ~= error {
            return "notInstalled: Sprachpaket fehlt (Systemeinstellungen > Allgemein > Sprache & Region > Übersetzungssprachen)"
        }
        if TranslationError.unsupportedLanguagePairing ~= error { return "unsupportedLanguagePairing" }
        if TranslationError.nothingToTranslate ~= error { return "nothingToTranslate" }
        if TranslationError.unableToIdentifyLanguage ~= error { return "unableToIdentifyLanguage" }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    static func run() async {
        let args = CommandLine.arguments
        let fast = args.contains("--fast")
        var timeout = 5.0
        if let i = args.firstIndex(of: "--timeout"), i + 1 < args.count, let v = Double(args[i + 1]), v > 0 {
            timeout = min(v, 120)
        }
        let status = await pairStatus(fast: fast)

        if args.contains("--check") {
            emit(["ready": true, "pairs": status])
            return
        }
        emit(["ready": true, "pairs": status])

        // Sitzung pro Sprachpaar wiederverwenden.
        var sessions: [String: TranslationSession] = [:]
        func session(_ src: String, _ dst: String) -> TranslationSession {
            let key = "\(src)-\(dst)"
            if let s = sessions[key] { return s }
            let s: TranslationSession
            if fast {
                s = TranslationSession(installedSource: Locale.Language(identifier: src),
                                       target: Locale.Language(identifier: dst),
                                       preferredStrategy: .lowLatency)
            } else {
                s = TranslationSession(installedSource: Locale.Language(identifier: src),
                                       target: Locale.Language(identifier: dst))
            }
            sessions[key] = s
            return s
        }

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                guard let data = trimmed.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    emit(["error": "ungültiges JSON"])
                    continue
                }
                let id = obj["id"] ?? NSNull()
                guard let text = obj["text"] as? String,
                      let src = obj["src"] as? String,
                      let dst = obj["dst"] as? String else {
                    emit(["id": id, "error": "text/src/dst fehlen"])
                    continue
                }
                let t0 = DispatchTime.now().uptimeNanoseconds
                do {
                    let out = try await translate(session(src, dst), text, timeout: timeout)
                    let ms = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                    emit(["id": id, "out": out, "ms": ms])
                } catch {
                    // Kaputte Sitzung verwerfen, nächste Anfrage baut neu.
                    sessions["\(src)-\(dst)"] = nil
                    emit(["id": id, "error": describe(error)])
                }
            }
        } catch {
            emit(["error": "stdin: \(error)"])
        }
    }
}
