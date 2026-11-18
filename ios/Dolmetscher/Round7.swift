// Round7.swift – kleine, testbare Bausteine der Runde 7 (Barrierefreiheit).
import SwiftUI
import UniformTypeIdentifiers
import AVFAudio
import UIKit

/// „Bewegung reduzieren“: Animationen entfallen, Inhalte springen direkt.
enum Motion {
    static func animation(_ a: Animation? = .default, reduce: Bool) -> Animation? { reduce ? nil : a }
}

/// VoiceOver-Beschreibung einer Blase. Quelle und Übersetzung tragen ihre eigene Sprache
/// (Sprachattribut der Bedienungshilfen), sonst läse VoiceOver Thai oder Japanisch mit der Stimme der Oberflächensprache.
enum A11yLabel {
    static func build(src: Lang, text: String, target: Lang, translation: String?, extras: [String], uiLang: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func plain(_ s: String) { out.append(NSAttributedString(string: s)) }
        func spoken(_ s: String, _ lang: Lang) {
            out.append(NSAttributedString(string: s, attributes: [.accessibilitySpeechLanguage: lang.voiceLocale]))
        }
        plain("\(src.name(in: uiLang)): "); spoken(text, src)
        if let translation {
            plain(". \(target.name(in: uiLang)): "); spoken(translation, target)
        }
        for e in extras where !e.isEmpty { plain(". " + e) }
        return out
    }

    /// Für `.accessibilityLabel`; fällt bei einem Umwandlungsfehler auf reinen Text zurück.
    static func text(_ ns: NSAttributedString) -> Text {
        if let a = try? AttributedString(ns, including: \.accessibility) { return Text(a) }
        return Text(ns.string)
    }
}

/// Aufbewahrung: wie viele Sätze die App hält, abhängig von der Einstellung „Verlauf aufbewahren“.
enum Retention {
    /// „1 Tag“ und „gar nicht“ brauchen nur wenige Sätze; „30 Tage“ und „für immer“ sollen nicht nach 300 Sätzen enden.
    static func cap(days: Int) -> Int { (days > 1 || days < 0) ? 2000 : 300 }
}

/// „Jetzt Sie/Jetzt ich“: braucht es einen vorübergehenden Erkenner-Wechsel (ohne den gespeicherten Modus zu ändern)?
enum ListenOverride {
    static func needed(for lang: Lang, mode: Direction, pair: LangPair) -> Direction? {
        guard pair.contains(lang), !mode.langs(pair).contains(lang) else { return nil }
        return lang == pair.mine ? .mine : .partner
    }
}

private final class AbandonBox<T: Sendable>: @unchecked Sendable {
    let lock = NSLock()
    var cont: CheckedContinuation<T, Error>?
    var task: Task<Void, Never>?
    var done = false
    var cancelled = false
    func finish(_ r: Result<T, Error>) {
        lock.lock()
        guard !done, let c = cont else { lock.unlock(); return }
        done = true; cont = nil; lock.unlock()
        c.resume(with: r)
    }
}

/// Wartet auf `op`, kehrt aber bei Abbruch des umgebenden Tasks sofort zurück (mit `CancellationError`), auch wenn `op`
/// selbst nicht abbrechbar ist (Modell-Download). `op` läuft dann im Hintergrund zu Ende.
func abandonable<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
    let box = AbandonBox<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            box.lock.lock()
            if box.cancelled { box.lock.unlock(); c.resume(throwing: CancellationError()); return }
            box.cont = c
            box.lock.unlock()
            box.task = Task {
                do { box.finish(.success(try await op())) } catch { box.finish(.failure(error)) }
            }
        }
    } onCancel: {
        box.lock.lock(); box.cancelled = true; box.lock.unlock()
        box.finish(.failure(CancellationError()))
    }
}

/// Nach einer Unterbrechung (Anruf, Siri, Wecker) nur dann von selbst weiterhören, wenn iOS es erlaubt.
enum InterruptionPolicy {
    static func shouldRestart(optionsRaw: UInt) -> Bool {
        AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
    }
}

/// Speicherbedarf eines Whisper-Downloads: Modell plus das von Core ML vorbereitete Abbild (grob doppelt).
enum WhisperSize {
    static func requiredBytes(sizeMB: Int?) -> Int64? { sizeMB.map { Int64($0) * 2_000_000 } }
}

/// Sprechen-Geste: Halten (Standard) oder Tippen zum Starten/Beenden (Motorik, Switch Control).
struct PushGesture: ViewModifier {
    let tapMode: Bool
    let held: Bool
    let press: () -> Void
    let release: () -> Void

    func body(content: Content) -> some View {
        if tapMode {
            content.onTapGesture { held ? release() : press() }
        } else {
            content.onLongPressGesture(minimumDuration: 0, maximumDistance: 80, perform: {}, onPressingChanged: { pressing in
                if pressing { press() } else { release() }
            })
        }
    }
}

/// Zuletzt benutzte Sprachpaare für den Schnellwechsel in der Kopfzeile.
enum RecentPairs {
    static let key = "recentPairs"
    static let limit = 5

    static func load(from d: UserDefaults) -> [LangPair] {
        (d.stringArray(forKey: key) ?? []).compactMap { s in
            let p = s.split(separator: ">").map(String.init)
            guard p.count == 2, let a = Lang(rawValue: p[0]), let b = Lang(rawValue: p[1]), a != b else { return nil }
            return LangPair(mine: a, partner: b)
        }
    }

    /// Das gerade verlassene Paar und das neue vorn merken, ohne Doppelte.
    static func remember(_ left: LangPair, current: LangPair, in d: UserDefaults) {
        var list = load(from: d)
        for p in [left, current].reversed() {
            list.removeAll { $0 == p }
            list.insert(p, at: 0)
        }
        d.set(list.prefix(limit).map { "\($0.mine.rawValue)>\($0.partner.rawValue)" }, forKey: key)
    }
}

/// Verlauf als CSV-Datei (UTF-8 mit BOM, damit Thai in Excel stimmt).
struct TranscriptCSV: Transferable {
    let entries: [Entry]

    static func csv(_ entries: [Entry]) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let f = ISO8601DateFormatter()
        let rows = entries.filter { $0.photo != true }.map {
            [f.string(from: $0.date), $0.src.rawValue, $0.target.rawValue, $0.text, $0.translation ?? ""].map(q).joined(separator: ",")
        }
        return "\u{FEFF}" + (["date,from,to,text,translation"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { c in
            let url = URL.temporaryDirectory.appending(path: "Dolmetscher.csv")
            try Data(TranscriptCSV.csv(c.entries).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Wechselkurs holen (Frankfurter/EZB, ohne Konto) – nur auf ausdrücklichen Wunsch des Nutzers.
enum FXFetch {
    static func url(code: String) -> URL? {
        URL(string: "https://api.frankfurter.dev/v1/latest?base=THB&symbols=\(code.uppercased())")
    }

    static func parse(_ data: Data, code: String) -> (rate: Double, date: String)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rates = root["rates"] as? [String: Any],
              let rate = (rates[code.uppercased()] as? Double) ?? (rates[code.uppercased()] as? Int).map(Double.init), rate > 0
        else { return nil }
        return (rate, root["date"] as? String ?? "")
    }
}
