// OfflineReadiness.swift – Runde 16: Bereitschaft für den Offline-Betrieb (reine Logik, ohne Systemaufrufe).
// Je Sprache des Paars: Erkennung und Stimme; für das Paar: Übersetzungspaket. Daraus Zustand je Baustein,
// Größenhinweis, Reisewarnung und der Nur-offline-Schalter. Die Systemabfragen (LangCheck) liefern nur die Eingaben.
import Foundation

/// Ein Baustein, der für den Betrieb ohne Netz auf dem Gerät liegen muss.
enum PackKind: Hashable, Sendable {
    case recognizer(Lang)
    case translation
    case voice(Lang)
}

enum PackState: Equatable, Sendable {
    /// liegt auf dem Gerät
    case ready
    /// fehlt, lässt sich laden
    case missing
    /// wird gerade geladen
    case loading
    /// gibt es für diese Sprache nicht auf dem Gerät (Erkennung/Übersetzung) bzw. nur über die iOS-Einstellungen (Stimme)
    case unavailable
}

struct PackItem: Equatable, Sendable, Identifiable {
    var kind: PackKind
    var state: PackState
    var id: PackKind { kind }
    /// Kann die App das Laden selbst anstoßen? Stimmen lädt nur iOS (Bedienungshilfen).
    var canLoadHere: Bool {
        if case .voice = kind { return false }
        return state == .missing
    }
}

/// Eingaben der Prüfung, so wie LangCheck sie liefert.
struct OfflineInputs: Equatable, Sendable {
    var mine: Lang
    var partner: Lang
    var recognizerMine: Readiness
    var recognizerPartner: Readiness
    /// beide Richtungen zusammengefasst (`ReadinessReport.combine`)
    var translation: Readiness
    var voiceMine: Bool
    var voicePartner: Bool
    /// Bausteine, deren Download gerade läuft
    var loading: Set<PackKind> = []
    /// Das Paar hat das Satzbuch (Thai-Extras).
    var phrasebook: Bool = false
}

/// Wie weit das Paar ohne Netz geht.
enum OfflineVerdict: Equatable, Sendable {
    /// Erkennung, Übersetzung und Stimme sind da.
    case ready
    /// Es fehlt etwas, das sich laden lässt (braucht einmal Netz).
    case needsDownload
    /// Für mindestens einen Baustein gibt es keine Lösung auf dem Gerät (Sprache ohne Offline-Erkennung/-Übersetzung, Stimme fehlt in iOS).
    case limited
}

struct OfflineReport: Equatable, Sendable {
    var items: [PackItem]
    var phrasebook: Bool

    static func evaluate(_ i: OfflineInputs) -> OfflineReport {
        func item(_ kind: PackKind, _ r: Readiness) -> PackItem {
            let state: PackState
            switch r {
            case .installed: state = .ready
            case .unsupported: state = .unavailable
            case .downloadable: state = i.loading.contains(kind) ? .loading : .missing
            }
            return PackItem(kind: kind, state: state)
        }
        func voice(_ l: Lang, _ has: Bool) -> PackItem {
            PackItem(kind: .voice(l), state: has ? .ready : .unavailable)
        }
        let items = [
            item(.recognizer(i.mine), i.recognizerMine), item(.recognizer(i.partner), i.recognizerPartner),
            item(.translation, i.translation),
            voice(i.mine, i.voiceMine), voice(i.partner, i.voicePartner)
        ]
        return OfflineReport(items: items, phrasebook: i.phrasebook)
    }

    func state(of kind: PackKind) -> PackState? { items.first { $0.kind == kind }?.state }

    private func all(_ match: (PackKind) -> Bool) -> Bool {
        items.filter { match($0.kind) }.allSatisfy { $0.state == .ready }
    }
    var recognitionReady: Bool { all { if case .recognizer = $0 { return true }; return false } }
    var translationReady: Bool { all { $0 == .translation } }
    var speechReady: Bool { all { if case .voice = $0 { return true }; return false } }
    var isReady: Bool { items.allSatisfy { $0.state == .ready } }

    /// Fehlende, ladbare Bausteine (auch die gerade ladenden).
    var loadable: [PackItem] { items.filter { $0.state == .missing || $0.state == .loading } }
    /// Bausteine ohne Lösung auf dem Gerät.
    var unavailable: [PackItem] { items.filter { $0.state == .unavailable } }
    var isLoading: Bool { items.contains { $0.state == .loading } }

    var verdict: OfflineVerdict {
        if !unavailable.isEmpty { return .limited }
        return loadable.isEmpty ? .ready : .needsDownload
    }

    /// Ungefähre Größe dessen, was noch zu laden ist (Stimmen zählen nicht: iOS nennt ihre Größe selbst).
    var missingMB: Int {
        let recognizers = items.filter { if case .recognizer = $0.kind { return $0.state == .missing || $0.state == .loading }; return false }.count
        let translations = items.filter { $0.kind == .translation && ($0.state == .missing || $0.state == .loading) }.count
        // Ein Paar braucht je Richtung ein Paket; das System legt beide mit einem Dialog an.
        return PackSize.missingMB(recognizers: recognizers, translations: translations * 2)
    }

    /// Reisewarnung: was ohne Netz nicht ginge. nil, wenn alles bereit ist.
    var travelWarning: TravelWarning? {
        switch verdict {
        case .ready: return nil
        case .needsDownload: return .missing(loadable.map(\.kind))
        case .limited: return .limited(unavailable.map(\.kind), loadable.map(\.kind))
        }
    }

    /// Das Satzbuch steht immer ohne Netz zur Verfügung (fest hinterlegt), unabhängig von den Paketen.
    var phrasebookAlwaysOffline: Bool { phrasebook }
}

enum TravelWarning: Equatable, Sendable {
    /// Fehlt, lässt sich vor der Reise laden.
    case missing([PackKind])
    /// Geht nur teilweise ohne Netz: (nicht verfügbar, ladbar)
    case limited([PackKind], [PackKind])

    var textKey: String {
        switch self {
        case .missing: return "off_warn_missing"
        case .limited: return "off_warn_limited"
        }
    }
}

/// Modus „Nur offline“: Hat er Vorrang, geht nie etwas an Google/MyMemory/Frankfurter oder Hugging Face.
enum OfflineMode {
    static let key = "offlineOnly"

    nonisolated static func setting(_ d: UserDefaults = .standard) -> Bool { d.object(forKey: key) as? Bool ?? false }

    /// Darf die Übersetzung ins Netz? Nur wenn die Online-Übersetzung erlaubt ist und „Nur offline“ aus ist.
    nonisolated static func allowsOnline(allowOnline: Bool, offlineOnly: Bool) -> Bool { allowOnline && !offlineOnly }

    /// Fehlertext-Schlüssel, wenn die Offline-Übersetzung nicht reicht: bei „Nur offline“ mit Handlungsvorschlag.
    nonisolated static func missingErrorKey(offlineOnly: Bool, allowOnline: Bool) -> String {
        if offlineOnly { return "err_offline_only" }
        return allowOnline ? "err_translate" : "err_offline_missing"
    }
}
