// Support.swift – Ansagen für VoiceOver, Export (Markdown/Text/JSON/CSV/SRT/WebVTT) und Diagnosebericht.
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Neue Übersetzungen und Fehler per VoiceOver ansagen (nur wenn VoiceOver läuft; in den Einstellungen abschaltbar).
enum Announcer {
    /// `lang` (BCP 47, z. B. "th-TH"): VoiceOver liest den Text mit der Stimme dieser Sprache (Nr. 366).
    static func post(_ text: String, force: Bool = false, lang: String? = nil) {
        guard !text.isEmpty,
              UserDefaults.standard.object(forKey: Prefs.announce) as? Bool ?? true,
              NSWorkspace.shared.isVoiceOverEnabled else { return }
        let level: NSAccessibilityPriorityLevel = force ? .high : .medium
        let value: Any = lang.map { NSAttributedString(string: text, attributes: [.accessibilityLanguage: $0]) } ?? text
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: value, .priority: level.rawValue])
    }
}

// MARK: Export

func mdEscape(_ s: String) -> String { ExportFormats.mdEscape(s) }

/// Locale-Kennung der Oberflächensprache für Zahlen (Thai-UI bekam vorher en_US).
var uiNumberLocale: String {
    switch L.lang { case .de: return "de_DE"; case .th: return "th_TH"; case .en: return "en_US" }
}

/// Zahl mit Dezimalzeichen der Oberflächensprache (Nr. 39).
func fmtNumber(_ v: Double, digits: Int = 2, plus: Bool = false) -> String {
    let loc = Locale(identifier: uiNumberLocale)
    return String(format: plus ? "%+.\(digits)f" : "%.\(digits)f", locale: loc, v)
}

enum ExportFormat: String, CaseIterable {
    case markdown = "md", text = "txt", json = "json", csv = "csv", srt = "srt", vtt = "vtt"
    static func from(extension ext: String) -> ExportFormat { ExportFormat(rawValue: ext.lowercased()) ?? .markdown }
    var title: String {
        switch self {
        case .markdown: return L.t("export_fmt_md")
        case .text: return L.t("export_fmt_txt")
        case .json: return L.t("export_fmt_json")
        case .csv: return L.t("export_fmt_csv")
        case .srt: return L.t("export_fmt_srt")
        case .vtt: return L.t("export_fmt_vtt")
        }
    }
    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .text: return .plainText
        case .json: return .json
        case .csv: return .commaSeparatedText
        case .srt: return UTType(filenameExtension: "srt") ?? .plainText
        case .vtt: return UTType(filenameExtension: "vtt") ?? .plainText
        }
    }
}

extension EngineModel {
    /// Gespräch als Text in einem der Exportformate. Kopfzeile in der Oberflächensprache.
    /// `from`: nur diese Einträge (z. B. die Treffer der Suche); sonst der ganze Verlauf.
    func transcript(_ format: ExportFormat, from subset: [Utterance]? = nil) -> String {
        let done = (subset ?? items).filter { !$0.pending }
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
                    s += "**\(df.string(from: u.date)) · \(who(u))**: \(mdEscape(u.text))  \n"
                    if u.translated { s += "→ \(arrow(u)): \(mdEscape(u.out))\n\n" } else { s += "\n" }
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
            let cell = ExportFormats.csvCell
            let iso = ISO8601DateFormatter()
            var s = "time,lang,text,to,translation,translated,speaker\n"
            for u in done {
                s += [iso.string(from: u.date), u.lang, u.text, u.translated ? u.to : "",
                      u.translated ? u.out : "", u.translated ? "true" : "false", u.speaker ?? u.role ?? ""]
                    .map(cell).joined(separator: ",") + "\n"
            }
            return s
        case .srt, .vtt:
            let rows = done.map { u in
                ExportItem(at: u.date, lang: u.lang, to: u.to, text: u.text, out: u.out, translated: u.translated,
                           speaker: u.speaker ?? u.role, dur: u.dur, readyS: u.readyS)
            }
            return format == .srt ? ExportFormats.srt(rows) : ExportFormats.webvtt(rows)
        }
    }
}

/// Zubehör des Exportdialogs: Format, Zeitraum und Datenschutz-Hinweis (der Export enthält Gesprächstext).
@MainActor
private final class ExportAccessory: NSObject {
    let panel: NSSavePanel
    let formatPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let rangePop = NSPopUpButton(frame: .zero, pullsDown: false)
    let view = NSStackView()
    let base = L.t("export_filename")

    init(panel: NSSavePanel, withRange: Bool) {
        self.panel = panel
        super.init()
        for f in ExportFormat.allCases { formatPop.addItem(withTitle: f.title) }
        formatPop.target = self; formatPop.action = #selector(formatChanged)
        for k in ["export_range_all", "export_range_hour", "export_range_today"] { rangePop.addItem(withTitle: L.t(k)) }
        let note = NSTextField(wrappingLabelWithString: L.t("export_privacy"))
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 360
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        view.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: L.t("export_format")), formatPop]))
        if withRange {
            view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: L.t("export_range")), rangePop]))
        }
        view.addArrangedSubview(note)
        panel.accessoryView = view
        formatChanged()
    }

    var format: ExportFormat { ExportFormat.allCases[max(0, formatPop.indexOfSelectedItem)] }

    @objc func formatChanged() {
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = ExportFormats.fileName(base: base, date: Date(), ext: format.rawValue)
    }

    /// Untergrenze des gewählten Zeitraums (nil = alles).
    var since: Date? {
        switch rangePop.indexOfSelectedItem {
        case 1: return Date().addingTimeInterval(-3600)
        case 2: return Calendar.current.startOfDay(for: Date())
        default: return nil
        }
    }
}

@MainActor
func exportConversation(_ m: EngineModel, only subset: [Utterance]? = nil) {
    let panel = NSSavePanel()
    panel.title = L.t("export")
    panel.message = L.t("export_message")
        + (m.trimmedCount > 0 ? "\n" + L.f("export_trimmed", EngineModel.maxItems, m.trimmedCount) : "")
    let acc = ExportAccessory(panel: panel, withRange: subset == nil)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let format = acc.format
    var rows = subset
    if subset == nil, let since = acc.since { rows = m.items.filter { $0.date >= since } }
    let text = m.transcript(format, from: rows)
    do { try ExportFormats.fileData(text, csv: format == .csv).write(to: url, options: .atomic) }
    catch { NSAlert(error: error).runModal() }
}

// MARK: Diagnose

extension EngineModel {
    /// Bericht für Fehlermeldungen: Versionen, Modelle, System. Enthält weder API-Schlüssel noch Gesprächstexte;
    /// Home-Pfad, Nutzername und Schlüsselmuster sind geschwärzt (DiagnosticsLogic).
    func diagnosticReport(python: Paths.PythonCheck, selfTest: [DiagnosticsLogic.Row] = []) -> String {
        func redact(_ s: String) -> String { DiagnosticsLogic.redact(s, home: NSHomeDirectory(), user: NSUserName()) }
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
        let models = ModelCache.cached().sorted()
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
            + "mic=\(micText), denoise=\(denoise), zweiPersonen=\(twoPerson), logText=\(logText), "
            + "silence=\(silence), sensitivity=\(sensitivity), ttsRace=\(ttsRace), fastEndpoint=\(fastEndpoint), "
            + "partialText=\(partialText), rate=\(rate), volume=\(volume), "
            + "ausgabe=\(outputDevice.isEmpty ? "Standard" : (outputDeviceName.isEmpty ? "UID" : outputDeviceName)), "
            + "kürzelFehler=\(HotKeys.shared.failures.isEmpty ? "-" : HotKeys.shared.failures.joined(separator: "/"))"
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
        return DiagnosticsLogic.report(lines: lines, rows: selfTest, lastError: lastError.map { $0.msg },
                                       home: NSHomeDirectory(), user: NSUserName())
    }
}
