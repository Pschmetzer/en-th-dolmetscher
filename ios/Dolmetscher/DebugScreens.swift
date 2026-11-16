// DebugScreens.swift – nur DEBUG: Bildschirme für Screenshots im Simulator direkt öffnen, mit Beispiel-Gespräch.
// DOLMETSCHER_DEMO=1 füllt den Verlauf (nur im Speicher), DOLMETSCHER_SCREEN=partner|answers|settings|privacy|emergency|allergy.
#if DEBUG
import SwiftUI

@MainActor
enum DebugScreens {
    static func apply(_ m: InterpreterModel, partner: Binding<Bool>) {
        let env = ProcessInfo.processInfo.environment
        if env["DOLMETSCHER_DEMO"] != nil { seed(m) }
        switch env["DOLMETSCHER_SCREEN"] {
        case "partner", "answers": partner.wrappedValue = true
        case "settings": m.sheet = .settings
        case "privacy": m.sheet = .privacy
        case "emergency": m.sheet = .emergency
        case "allergy": m.sheet = .allergy
        case "prep": m.sheet = .prep
        case "places": m.sheet = .places
        case "helpnow": m.sheet = .helpNow
        case "baht": m.sheet = .baht
        case "widgets": m.sheet = .widgetPreview
        default: break
        }
    }

    private static func seed(_ m: InterpreterModel) {
        let t0 = Date()
        m.entries = [
            Entry(date: t0, src: .en, dst: .th, text: "Where is the train station?", translation: "สถานีรถไฟอยู่ที่ไหนครับ",
                  provider: "apple", back: "Where is the train station?"),
            Entry(date: t0, src: .th, dst: .en, text: "เดินตรงไปแล้วเลี้ยวซ้ายครับ", translation: "Go straight and then turn left.",
                  provider: "apple", back: "เดินตรงไปแล้วเลี้ยวซ้าย"),
            Entry(date: t0, src: .en, dst: .th, text: "How much is a ticket to Chiang Mai?", translation: "ตั๋วไปเชียงใหม่ราคาเท่าไหร่ครับ",
                  provider: "apple", back: "What does the paper to the new city cost?"),
            Entry(date: t0, src: .th, dst: .en, text: "ใช่", translation: "Yes", provider: "card"),
        ]
        var e = EmergencyInfo()
        e.name = "Alex Example"
        e.hotel = "Riverside Hotel, 123 Charoen Krung Rd, Bangkok"
        e.allergies = "Peanuts, shellfish"
        e.bloodType = "A+"
        e.allergens = [.peanut, .shellfish]
        m.emergency = e
        m.places = [Place(name: "Riverside Hotel", local: "โรงแรมริเวอร์ไซด์ ถนนเจริญกรุง"),
                    Place(name: "Airport BKK", local: "สนามบินสุวรรณภูมิ")]
    }
}
/// Schnellsätze-Widget und Live-Aktivität in der App zeigen – für Screenshots im Simulator.
struct WidgetPreviewScreen: View {
    private let state = ListeningActivityAttributes.ContentState(
        status: .hearing, statusText: T("hearing"), source: "How much is a ticket to Chiang Mai?",
        translation: "ตั๋วไปเชียงใหม่ราคาเท่าไหร่ครับ", srcFlag: "🇬🇧", dstFlag: "🇹🇭")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QuickPhrasesView(entry: .make(ids: [], female: false), family: .systemSmall)
                    .padding(12).frame(width: 170, height: 170)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22))
                QuickPhrasesView(entry: .make(ids: [], female: false), family: .systemMedium)
                    .padding(12).frame(width: 364, height: 170)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22))
                LiveLockView(pair: "🇬🇧 ⇄ 🇹🇭", state: state)
                    .padding().frame(width: 364)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding()
        }
    }
}
#endif
