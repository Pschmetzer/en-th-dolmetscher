// Availability.swift – Welche Sprachen kann dieses iPhone wirklich: On-Device-Erkennung (DictationTranscriber),
// Apple-Übersetzung (LanguageAvailability, je Richtung) und eine Stimme (AVSpeechSynthesisVoice)?
import AVFoundation
import Speech
import Translation
import os

private let log = Logger(subsystem: "dolmetscher", category: "langs")

/// Stand eines Bausteins: gibt es nicht / lädt das System bei Bedarf / ist schon auf dem Gerät.
enum Readiness: Sendable { case unsupported, downloadable, installed }

enum LangLevel: Equatable, Sendable {
    /// alles auf dem Gerät
    case ready
    /// geht, aber Sprachmodell, Übersetzungspaket oder Stimme muss erst geladen werden (Netz)
    case needsDownload
    /// Apple übersetzt dieses Paar nicht auf dem Gerät: nur mit Online-Übersetzung (Netz)
    case onlineOnly
    /// keine On-Device-Erkennung: nicht anbieten
    case unavailable

    static func of(recognizer: Readiness, translation: Readiness, voice: Bool) -> LangLevel {
        if recognizer == .unsupported { return .unavailable }
        if translation == .unsupported { return .onlineOnly }
        if recognizer == .installed && translation == .installed && voice { return .ready }
        return .needsDownload
    }
}

enum LangCheck {
    static func recognizer(_ l: Lang) async -> Readiness {
        guard let loc = await LangRecognizer.locale(for: l) else { return .unsupported }
        let installed = await DictationTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == loc.identifier(.bcp47) } ? .installed : .downloadable
    }

    static func translation(_ a: Lang, _ b: Lang) async -> Readiness {
        guard a != b else { return .installed }
        switch await LanguageAvailability().status(from: Translator.language(a), to: Translator.language(b)) {
        case .installed: return .installed
        case .supported: return .downloadable
        default: return .unsupported
        }
    }

    /// Stufe der Sprache `l` im Paar mit `other` (Übersetzung in beide Richtungen nötig).
    static func level(_ l: Lang, with other: Lang) async -> LangLevel {
        let r = await recognizer(l)
        let t1 = await translation(l, other), t2 = await translation(other, l)
        let t: Readiness = (t1 == .unsupported || t2 == .unsupported) ? .unsupported
            : (t1 == .installed && t2 == .installed) ? .installed : .downloadable
        let v = await MainActor.run { Speaker.hasVoice(l) }
        let level = LangLevel.of(recognizer: r, translation: t, voice: v)
        log.info("lang \(l.rawValue, privacy: .public) with \(other.rawValue, privacy: .public): recognizer \(String(describing: r), privacy: .public) translation \(String(describing: t), privacy: .public) voice \(v, privacy: .public) -> \(String(describing: level), privacy: .public)")
        return level
    }

    /// Alle Sprachen gegen `other` prüfen (für die Auswahlliste).
    static func levels(with other: Lang) async -> [Lang: LangLevel] {
        // Parallel: 19 Sprachen nacheinander zu prüfen ließ das Öffnen der Einstellungen träge wirken.
        await withTaskGroup(of: (Lang, LangLevel).self) { group in
            for l in Lang.all where l != other { group.addTask { (l, await level(l, with: other)) } }
            var out: [Lang: LangLevel] = [:]
            for await (l, v) in group { out[l] = v }
            return out
        }
    }
}
