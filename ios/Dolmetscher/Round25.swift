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

    /// Gut belegte, stabile Landesnummern (Japan 110/119, Korea 112/119, China 110/120/119, Vietnam 113/114/115,
    /// Indonesien 110/113/118 + 112, Deutschland 110/112, Frankreich 17/15/18 + 112, Spanien 112). Thai: eigener Bildschirm.
    static func numbers(for lang: Lang) -> [Number] {
        switch lang.rawValue {
        case "ja": return [.init(number: "110", kind: .police), .init(number: "119", kind: .fireAmbulance)]
        case "ko": return [.init(number: "112", kind: .police), .init(number: "119", kind: .fireAmbulance)]
        case "zh": return [.init(number: "110", kind: .police), .init(number: "120", kind: .ambulance), .init(number: "119", kind: .fire)]
        case "vi": return [.init(number: "113", kind: .police), .init(number: "115", kind: .ambulance), .init(number: "114", kind: .fire)]
        case "id": return [.init(number: "112", kind: .general), .init(number: "110", kind: .police), .init(number: "118", kind: .ambulance), .init(number: "113", kind: .fire)]
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
        if !list.isEmpty {
            Section {
                ForEach(list, id: \.number) { n in DialRow(number: n.number, en: T(n.kind.textKey), th: "", icon: n.kind.icon) }
            } header: { Text(T("em_n_header")) } footer: { Text(T("em_n_note")) }
        }
    }
}
