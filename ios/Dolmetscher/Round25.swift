// Round25.swift – Notrufnummern nach Partnersprache und Satzbuch ohne Thai im Paar.
import SwiftUI

/// Notrufnummern des Landes, in dem man die Partnersprache spricht (nur Sprache, nicht Standort: als Richtwert gekennzeichnet).
enum PartnerEmergency {
    enum Kind: String { case general, police, ambulance, fire, fireAmbulance
        var textKey: String { "em_n_" + (self == .fireAmbulance ? "fire_ambulance" : rawValue) }
        var icon: String {
            switch self {
            case .general: return "sos"
            case .police: return "shield.fill"
            case .ambulance: return "cross.case.fill"
            case .fire: return "flame.fill"
            case .fireAmbulance: return "flame.fill"
            }
        }
    }
    struct Number: Equatable { var number: String; var kind: Kind }

    /// Nur Nummern, die mehrere unabhängige Quellen (Botschaften, Behörden, Tourismusamt) bestätigen – Stand der Recherche:
    /// Japan 110/119 (US-Botschaft Japan, Univ. Tohoku), Vietnam 113/114/115 (US-Botschaft, State Dept.), Frankreich 15/17/18/112
    /// (gendarmerie.interieur.gouv.fr, formation-civique.interieur.gouv.fr), Deutschland 110/112, Spanien 112 (EU-weit),
    /// Indonesien 110/113 und 112 (indonesia.travel, Kominfo; die Krankenwagen-Nummer 118/119 ist uneinheitlich und fehlt).
    /// Korea und China: nur Reiseführer als Quelle – keine Nummer, bei Zweifel nur der Hinweis. Thai: eigener Bildschirm.
    static func numbers(for lang: Lang) -> [Number] {
        switch lang.rawValue {
        case "ja": return [.init(number: "110", kind: .police), .init(number: "119", kind: .fireAmbulance)]
        case "vi": return [.init(number: "113", kind: .police), .init(number: "115", kind: .ambulance), .init(number: "114", kind: .fire)]
        case "id": return [.init(number: "112", kind: .general), .init(number: "110", kind: .police), .init(number: "113", kind: .fire)]
        case "de": return [.init(number: "112", kind: .fireAmbulance), .init(number: "110", kind: .police)]
        case "fr": return [.init(number: "112", kind: .general), .init(number: "17", kind: .police), .init(number: "15", kind: .ambulance), .init(number: "18", kind: .fire)]
        case "es": return [.init(number: "112", kind: .general)]
        default: return []
        }
    }
}

/// Notrufnummern in der Notfallkarte, wenn kein Thai im Paar ist.
struct PartnerEmergencySection: View {
    let lang: Lang

    var body: some View {
        let list = PartnerEmergency.numbers(for: lang)
        if list.isEmpty {
            // Keine belegte Nummer: lieber keine als eine falsche.
            Section { Text(T("em_n_unknown")).font(.footnote).foregroundStyle(.secondary) } header: { Text(T("em_n_header")) }
        } else {
            Section {
                ForEach(list, id: \.number) { n in DialRow(number: n.number, en: T(n.kind.textKey), th: "", icon: n.kind.icon) }
            } header: { Text(T("em_n_header")) } footer: { Text(T("em_n_note")) }
        }
    }
}
