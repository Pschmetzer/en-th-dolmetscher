// Support.swift – Ansagen für VoiceOver, Export (Markdown/Text/JSON/CSV/SRT) und Diagnosebericht.
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Neue Übersetzungen und Fehler per VoiceOver ansagen (nur wenn VoiceOver läuft; in den Einstellungen abschaltbar).
enum Announcer {
    static func post(_ text: String, force: Bool = false) {
        guard !text.isEmpty,
              UserDefaults.standard.object(forKey: Prefs.announce) as? Bool ?? true,
              NSWorkspace.shared.isVoiceOverEnabled else { return }
        let level: NSAccessibilityPriorityLevel = force ? .high : .medium
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: level.rawValue])
    }
}

// MARK: Export

enum ExportFormat: String, CaseIterable {
    case markdown = "md", text = "txt", json = "json", csv = "csv", srt = "srt"
    static func from(extension ext: String) -> ExportFormat { ExportFormat(rawValue: ext.lowercased()) ?? .markdown }
    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .text: return .plainText
        case .json: return .json
        case .csv: return .commaSeparatedText
        case .srt: return UTType(filenameExtension: "srt") ?? .plainText
        }
    }
}

extension EngineModel {
    /// Gespräch als Text in einem der Exportformate. Kopfzeile in der Oberflächensprache.
    func transcript(_ format: ExportFormat) -> String {
        let done = items.filter { !$0.pending }
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        let day = DateFormatter()
        day.dateStyle = .long; day.timeStyle = .short
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: L.lang.rawValue)
        let title = L.f("export_title", day.string(from: Date()))
        func who(_ u: Utterance) -> String { Langs.flag(u.lang) + " " + u.lang.uppercased() }
        func arrow(_ u: Utterance) -> String {
            u.translated ? Langs.flag(u.to) + " " + u.to.uppercased() : "(" + L.t("not_translated") + ")"
        }
        switch format {
        case .markdown, .text:
            let md = format == .markdown
            var s = md ? "# \(title)\n\n" : "\(title)\n\n"
            for u in done {
                if md {
                    s += "**\(df.string(from: u.date)) · \(who(u))**: \(u.text)  \n"
                    if u.translated { s += "→ \(arrow(u)): \(u.out)\n\n" } else { s += "\n" }
                } else {
                    s += "[\(df.string(from: u.date))] \(who(u)): \(u.text)\n"
                    if u.translated { s += "  → \(arrow(u)): \(u.out)\n" }
                    s += "\n"
                }
            }
            return s
        case .json:
            let iso = ISO8601DateFormatter()
            let rows: [[String: Any]] = done.map { u in
                var r: [String: Any] = ["time": iso.string(from: u.date), "lang": u.lang, "text": u.text,
                                        "translated": u.translated]
                if u.translated { r["to"] = u.to; r["translation"] = u.out }
                if let sp = u.speaker ?? u.role { r["speaker"] = sp }
                return r
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["title": title, "items": rows],
                                                    options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self) + "\n"
        case .csv:
            // Felder, die mit = + - @ beginnen, bekommen ein ' davor (Schutz vor Formeln in Tabellenkalkulationen).
            func cell(_ v: String) -> String {
                var t = v
                if let f = t.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(f) { t = "'" + t }
                return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            let iso = ISO8601DateFormatter()
            var s = "time,lang,text,to,translation,translated,speaker\n"
            for u in done {
                s += [iso.string(from: u.date), u.lang, u.text, u.translated ? u.to : "",
                      u.translated ? u.out : "", u.translated ? "true" : "false", u.speaker ?? u.role ?? ""]
                    .map(cell).joined(separator: ",") + "\n"
            }
            return s
        case .srt:
            guard let t0 = done.first?.date else { return "" }
            func ts(_ v: Double) -> String {
                let ms = Int((max(0, v) * 1000).rounded())
                return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
            }
            var s = ""
            for (i, u) in done.enumerated() {
                let start = u.date.timeIntervalSince(t0)
                var end = start + max(2, min(7, Double(max(u.text.count, u.out.count)) / 14))
                if i + 1 < done.count { end = min(end, done[i + 1].date.timeIntervalSince(t0) - 0.1) }
                end = max(end, start + 0.5)
                s += "\(i + 1)\n\(ts(start)) --> \(ts(end))\n\(u.text)\n" + (u.translated ? "\(u.out)\n" : "") + "\n"
            }
            return s
        }
    }
}

@MainActor
func exportConversation(_ m: EngineModel) {
    let panel = NSSavePanel()
    panel.title = L.t("export")
    panel.message = L.t("export_message")
    panel.allowedContentTypes = ExportFormat.allCases.map(\.contentType)
    panel.allowsOtherFileTypes = true
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH-mm"
    panel.nameFieldStringValue = L.t("export_filename") + " \(df.string(from: Date())).md"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let format = ExportFormat.from(extension: url.pathExtension)
    // CSV mit UTF-8-BOM: Excel liest die Datei sonst als Windows-1252 (Thai und Umlaute als Zeichensalat)
    let text = (format == .csv ? "\u{FEFF}" : "") + m.transcript(format)
    do { try text.write(to: url, atomically: true, encoding: .utf8) }
    catch { NSAlert(error: error).runModal() }
}

// MARK: Diagnose

extension EngineModel {
    /// Bericht für Fehlermeldungen: Versionen, Modelle, System. Enthält weder API-Schlüssel noch Gesprächstexte;
    /// der Home-Pfad ist durch „~“ ersetzt.
    func diagnosticReport(python: Paths.PythonCheck) -> String {
        func redact(_ s: String) -> String { s.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let pyText: String
        switch python {
        case .ok(let v): pyText = "OK – Python / faster-whisper: " + v
        case .noModule: pyText = "faster_whisper fehlt"
        case .failed(let e): pyText = "Fehler: " + redact(e)
        }
        let hub = ProcessInfo.processInfo.environment["HF_HOME"].map { $0 + "/hub" }
            ?? NSHomeDirectory() + "/.cache/huggingface/hub"
        let models = ((try? FileManager.default.contentsOfDirectory(atPath: hub)) ?? [])
            .filter { $0.hasPrefix("models--") }.map { String($0.dropFirst(8)).replacingOccurrences(of: "--", with: "/") }
            .sorted()
        let micAuth: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micAuth = "erlaubt"
        case .denied: micAuth = "verweigert"
        case .restricted: micAuth = "eingeschränkt"
        default: micAuth = "nicht gefragt"
        }
        let micText: String = micName.isEmpty ? (self.mic.isEmpty ? "Standard" : "#" + self.mic) : micName
        let ver = "Dolmetscher " + version + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        let settings = "Einstellungen: model=\(model), claude=\(llm) (\(llmModel)), lang=\(lang), ui=\(L.lang.rawValue), "
            + "mic=\(micText), denoise=\(denoise), zweiPersonen=\(twoPerson), logText=\(logText)"
        let engine = "Engine: state=\(state), ready=\(engineReady), neustarts=\(restartAttempts), "
            + "ungültige Zeilen=\(malformedLines), langsamerStart=\(loadSlow), "
            + "version=\(engineVersion ?? "?"), protokollAbweichung=\(protocolMismatch.map(String.init) ?? "nein"), "
            + "preset=\(preset.isEmpty ? "-" : preset), verlauf=\(history)" + (hwInfo.map { ", hw=\($0)" } ?? "")
        var lines: [String] = [ver]
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)")
        let src: String = { switch Paths.pythonSource {
            case .override: return " (Entwickler-Override)"
            case .venv: return " (eigene venv, Stempel passt)"
            case .none: return " (keine eingerichtete Umgebung)" } }()
        lines.append("Python: \(redact(Paths.python))" + src + " – \(pyText)")
        lines.append("Audio: " + (Paths.ffmpegOverride.map { "ffmpeg " + redact($0) + " (DOLMETSCHER_FFMPEG)" } ?? "PyAV (avhelper.py)"))
        lines.append("Modelle im Cache: " + (models.isEmpty ? "keine" : models.joined(separator: ", ")))
        lines.append(settings)
        lines.append("API-Schlüssel gespeichert: " + (APIKeyStore.exists ? "ja" : "nein"))
        lines.append("Mikrofon-Berechtigung: " + micAuth)
        lines.append(engine)
        if !logText {   // bei eingeschaltetem Text-Log könnten Gesprächsfetzen im stderr stehen
            lines.append("--- stderr.log (Ende) ---")
            lines.append(redact(Self.logTail(15)))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
