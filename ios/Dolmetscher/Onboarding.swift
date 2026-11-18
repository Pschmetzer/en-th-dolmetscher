// Onboarding.swift – Erststart und Berechtigungen: reine Logik (ohne UI), getestet in Round14Tests.
import Foundation

/// Schritte des Willkommensflusses, in dieser Reihenfolge.
enum OnboardingStep: Int, CaseIterable, Equatable {
    case pair, microphone, speech, packs, test

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isLast: Bool { next == nil }
    /// „Schritt 2 von 5“ (zählt ab 1).
    var position: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    /// Schlüssel von Überschrift und Text in den Oberflächentexten (Runde 14).
    var titleKey: String {
        switch self {
        case .pair: "ob_pair_t"
        case .microphone: "ob_mic_t"
        case .speech: "ob_speech_t"
        case .packs: "ob_packs_t"
        case .test: "ob_test_t"
        }
    }

    var bodyKey: String { titleKey.dropLast(1) + "b" }
}

/// Stand einer Systemfreigabe, unabhängig von Framework (Mikrofon: undetermined/granted/denied;
/// Spracherkennung zusätzlich restricted, z. B. durch Bildschirmzeit oder Geräteverwaltung).
enum PermissionState: Equatable, Sendable {
    case notDetermined, granted, denied, restricted
}

/// Was die Oberfläche bei einer Freigabe tun soll.
enum PermissionAdvice: Equatable, Sendable {
    /// Erst erklären, dann den Systemdialog zeigen.
    case explainThenAsk
    /// Alles in Ordnung.
    case proceed
    /// Abgelehnt: der Systemdialog erscheint nicht mehr, nur die Einstellungen helfen.
    case openSettings
    /// Eingeschränkt: die Nutzerin kann es oft selbst nicht ändern (Bildschirmzeit, Verwaltung); Hinweis plus Einstellungen.
    case restricted

    static func of(_ state: PermissionState) -> PermissionAdvice {
        switch state {
        case .notDetermined: .explainThenAsk
        case .granted: .proceed
        case .denied: .openSettings
        case .restricted: .restricted
        }
    }

    /// Zeigt der Hinweis einen Knopf in die Einstellungen?
    var offersSettings: Bool { self == .openSettings || self == .restricted }
}

/// Ob die Oberfläche etwas anzeigen muss, wenn es nicht läuft: Mikrofon ist Pflicht, Spracherkennung
/// verschlechtert nur (die Erkennung läuft auf dem Gerät), deshalb nur ein Hinweis.
struct PermissionSummary: Equatable, Sendable {
    var microphone: PermissionState
    var speech: PermissionState

    /// Blockiert das Dolmetschen: Mikrofon abgelehnt oder eingeschränkt.
    var blocksListening: Bool { microphone == .denied || microphone == .restricted }
    /// Hinweisband im Gespräch nötig? (Nie, solange nichts abgelehnt wurde; „noch nicht gefragt“ ist kein Fehler.)
    var needsBanner: Bool { blocksListening || speech == .denied || speech == .restricted }
    var allGranted: Bool { microphone == .granted && speech == .granted }

    /// Textschlüssel des Hinweisbands; das Mikrofon geht vor, weil ohne es nichts läuft.
    var bannerTextKey: String? {
        switch microphone {
        case .denied: return "ob_mic_denied"
        case .restricted: return "ob_mic_restricted"
        default: break
        }
        switch speech {
        case .denied: return "ob_speech_denied"
        case .restricted: return "ob_speech_restricted"
        default: return nil
        }
    }
}

/// Wann der Willkommensfluss erscheint.
enum OnboardingPolicy {
    /// - Parameters:
    ///   - completed: Fluss bis zum Ende durchlaufen
    ///   - deferred: „Später“ gewählt (nicht noch einmal beim Start, nur aus der Hilfe)
    ///   - existingUser: war schon vor dieser Version da (Reise-Vorbereitung gesehen)
    static func shouldShowAtLaunch(completed: Bool, deferred: Bool, existingUser: Bool) -> Bool {
        !completed && !deferred && !existingUser
    }
}

/// Ungefähre Größe der Offline-Pakete (die genauen Werte nennt nur das System beim Laden).
enum PackSize {
    /// Sprachmodell der Erkennung je Sprache, Übersetzungspaket je Sprache, in Megabyte (gerundete Schätzung).
    static let recognizerMB = 150
    static let translationMB = 200

    /// Summe für die noch fehlenden Bausteine; 0, wenn nichts fehlt.
    static func missingMB(recognizers: Int, translations: Int) -> Int {
        max(0, recognizers) * recognizerMB + max(0, translations) * translationMB
    }

    /// Text wie „ca. 350 MB“ bzw. „ca. 1,2 GB“; nil, wenn nichts zu laden ist. Der Zusatz „ca.“ kommt von der Oberfläche.
    static func format(mb: Int, locale: Locale = .current) -> String? {
        guard mb > 0 else { return nil }
        let f = NumberFormatter()
        f.locale = locale
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        if mb >= 1000 { return (f.string(from: NSNumber(value: Double(mb) / 1000)) ?? "\(mb / 1000)") + " GB" }
        // auf 10 MB runden, damit keine Scheingenauigkeit entsteht
        let rounded = Int((Double(mb) / 10).rounded()) * 10
        return (f.string(from: NSNumber(value: rounded)) ?? "\(rounded)") + " MB"
    }
}

/// Verlauf durch den Fluss: gültiges Paar, Vor und Zurück, „Später“.
struct OnboardingFlow: Equatable {
    private(set) var step: OnboardingStep = .pair
    private(set) var finished = false
    private(set) var deferredLater = false

    mutating func advance() {
        if let n = step.next { step = n } else { finished = true }
    }

    mutating func goBack() {
        if let p = step.previous { step = p }
    }

    mutating func later() { deferredLater = true }

    /// Sprachpaar auswählen: die Partnersprache darf nicht gleich meiner sein; sonst bleibt die andere Seite
    /// die Standardsprache (Thai bzw. Englisch).
    static func pair(mine: Lang, partner: Lang) -> LangPair {
        guard mine == partner else { return LangPair(mine: mine, partner: partner) }
        return LangPair(mine: mine, partner: mine == .th ? .en : .th)
    }
}
