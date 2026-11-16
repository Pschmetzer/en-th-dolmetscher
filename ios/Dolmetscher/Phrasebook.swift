// Phrasebook.swift – Satzbuch: feste Reise-Sätze (sofort und offline, Thai fest hinterlegt) und eigene Favoriten.
import SwiftUI

struct Phrase: Identifiable, Codable, Hashable, Sendable {
    var id: String { en }
    var en: String
    /// Thai mit Platzhaltern {p} {q} {i} (siehe Politeness.fill)
    var th: String
    /// ungefähre Aussprache, gleiche Platzhalter
    var roman: String
    var category: String
    /// Nur bei Favoriten aus anderen Sprachpaaren gesetzt; sonst en -> th (eingebautes Satzbuch).
    var src: Lang? = nil
    var dst: Lang? = nil

    var srcLang: Lang { src ?? .en }
    var dstLang: Lang { dst ?? .th }
}

enum Phrasebook {
    static let categories: [(key: String, icon: String)] = [
        ("basics", "hand.wave"), ("food", "fork.knife"), ("transport", "car"),
        ("shopping", "bag"), ("hotel", "bed.double"), ("health", "cross.case"),
    ]

    private static func p(_ c: String, _ en: String, _ th: String, _ roman: String) -> Phrase {
        Phrase(en: en, th: th, roman: roman, category: c)
    }

    static let builtIn: [Phrase] = [
        p("basics", "Hello", "สวัสดี{p}", "sa-wat-dee {p}"),
        p("basics", "Thank you", "ขอบคุณ{p}", "khop khun {p}"),
        p("basics", "Sorry / Excuse me", "ขอโทษ{p}", "kho thot {p}"),
        p("basics", "Yes", "ใช่{p}", "chai {p}"),
        p("basics", "No", "ไม่ใช่{p}", "mai chai {p}"),
        p("basics", "No problem", "ไม่เป็นไร{p}", "mai pen rai {p}"),
        p("basics", "I don't understand", "{i}ไม่เข้าใจ{p}", "{i} mai khao jai {p}"),
        p("basics", "Please speak slowly", "พูดช้าๆ หน่อยได้ไหม{q}", "phut cha cha noi dai mai {q}"),
        p("basics", "Do you speak English?", "พูดภาษาอังกฤษได้ไหม{q}", "phut pha-sa ang-krit dai mai {q}"),
        p("basics", "Where is the toilet?", "ห้องน้ำอยู่ที่ไหน{q}", "hong nam yu thi nai {q}"),
        p("basics", "Wait a moment, please", "รอสักครู่{p}", "ro sak khru {p}"),

        p("food", "The menu, please", "ขอเมนูหน่อย{p}", "kho me-nu noi {p}"),
        p("food", "Not spicy, please", "ไม่เผ็ด{p}", "mai phet {p}"),
        p("food", "A little spicy", "เผ็ดนิดหน่อย{p}", "phet nit noi {p}"),
        p("food", "I am vegetarian", "{i}กินมังสวิรัติ{p}", "{i} kin mang-sa-wi-rat {p}"),
        p("food", "I am allergic to peanuts", "{i}แพ้ถั่วลิสง{p}", "{i} phae thua li-song {p}"),
        p("food", "Water, please", "ขอน้ำเปล่า{p}", "kho nam plao {p}"),
        p("food", "No ice, please", "ไม่ใส่น้ำแข็ง{p}", "mai sai nam khaeng {p}"),
        p("food", "Very delicious!", "อร่อยมาก{p}", "a-roi mak {p}"),
        p("food", "The bill, please", "เช็คบิลด้วย{p}", "chek bin duai {p}"),
        p("food", "To take away", "ใส่ถุงกลับบ้าน{p}", "sai thung klap ban {p}"),

        p("transport", "Please take me to this address", "ช่วยไปส่งที่นี่หน่อย{p}", "chuai pai song thi ni noi {p}"),
        p("transport", "Please use the meter", "ช่วยเปิดมิเตอร์ด้วย{p}", "chuai poet mi-toe duai {p}"),
        p("transport", "How much to go there?", "ไปที่นั่นเท่าไหร่{q}", "pai thi nan thao rai {q}"),
        p("transport", "Stop here, please", "จอดตรงนี้{p}", "jot trong ni {p}"),
        p("transport", "Turn left", "เลี้ยวซ้าย{p}", "liao sai {p}"),
        p("transport", "Turn right", "เลี้ยวขวา{p}", "liao khwa {p}"),
        p("transport", "Go straight", "ตรงไป{p}", "trong pai {p}"),
        p("transport", "Where is the train station?", "สถานีรถไฟอยู่ที่ไหน{q}", "sa-tha-ni rot fai yu thi nai {q}"),
        p("transport", "Where is the airport?", "สนามบินอยู่ที่ไหน{q}", "sa-nam bin yu thi nai {q}"),

        p("shopping", "How much is this?", "อันนี้เท่าไหร่{q}", "an ni thao rai {q}"),
        p("shopping", "Too expensive", "แพงไป{p}", "phaeng pai {p}"),
        p("shopping", "Can you give me a discount?", "ลดราคาได้ไหม{q}", "lot ra-kha dai mai {q}"),
        p("shopping", "I'll take this one", "เอาอันนี้{p}", "ao an ni {p}"),
        p("shopping", "Can I pay by card?", "จ่ายด้วยบัตรได้ไหม{q}", "jai duai bat dai mai {q}"),
        p("shopping", "Just looking", "ดูก่อน{p}", "du kon {p}"),

        p("hotel", "I have a reservation", "{i}จองห้องไว้แล้ว{p}", "{i} jong hong wai laeo {p}"),
        p("hotel", "What is the Wi-Fi password?", "รหัสไวไฟคืออะไร{q}", "ra-hat wai-fai khue a-rai {q}"),
        p("hotel", "The air conditioning does not work", "แอร์เสีย{p}", "ae sia {p}"),
        p("hotel", "What time is check-out?", "เช็คเอาท์กี่โมง{q}", "chek-ao ki mong {q}"),

        p("health", "Help!", "ช่วยด้วย!", "chuai duai!"),
        p("health", "Please call an ambulance", "เรียกรถพยาบาลด้วย{p}", "riak rot pha-ya-ban duai {p}"),
        p("health", "Please call the police", "เรียกตำรวจด้วย{p}", "riak tam-ruat duai {p}"),
        p("health", "I need a doctor", "{i}ต้องการหาหมอ{p}", "{i} tong-kan ha mo {p}"),
        p("health", "Where is the hospital?", "โรงพยาบาลอยู่ที่ไหน{q}", "rong pha-ya-ban yu thi nai {q}"),
        p("health", "Where is a pharmacy?", "ร้านขายยาอยู่ที่ไหน{q}", "ran khai ya yu thi nai {q}"),
        p("health", "I lost my passport", "{i}ทำหนังสือเดินทางหาย{p}", "{i} tham nang-sue doen-thang hai {p}"),
    ]
}

struct PhrasebookView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var category = "favorites"
    @State private var search = ""

    /// Eingebaute Sätze sind Englisch -> Thai: nur mit Thai im Paar.
    private var builtIn: [Phrase] { m.features.thaiExtras ? Phrasebook.builtIn : [] }

    private var shown: [Phrase] {
        let base = category == "favorites" ? m.favorites : builtIn.filter { $0.category == category }
        guard !search.isEmpty else { return base }
        var seen = Set<String>()
        let all = (m.favorites + builtIn).filter { seen.insert($0.en).inserted }
        return all.filter { $0.en.localizedCaseInsensitiveContains(search) || $0.th.contains(search) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("favorites", icon: "star.fill")
                        if m.features.thaiExtras {
                            ForEach(Phrasebook.categories, id: \.key) { chip($0.key, icon: $0.icon) }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                List {
                    if shown.isEmpty {
                        Text(category == "favorites" ? T("fav_empty") : T("nothing_found"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { p in
                        Button {
                            m.say(p)
                            Haptics.tap()
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.en).font(.headline)
                                Text(p.dstLang == .th ? m.politeness.fill(p.th) : p.th).font(.title3)
                                    .foregroundStyle(LangStyle.color(p.dstLang, m.pair))
                                if !p.roman.isEmpty {
                                    Text(p.dstLang == .th ? m.politeness.fillRoman(p.roman) : p.roman)
                                        .font(.caption).foregroundStyle(.secondary).italic()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if m.isFavorite(p) {
                                Button(role: .destructive) { m.toggleFavorite(p) } label: { Label(T("unfavorite"), systemImage: "star.slash") }
                            } else {
                                Button { m.toggleFavorite(p) } label: { Label(T("favorite"), systemImage: "star") }.tint(.yellow)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: T("search"))
            .navigationTitle(T("phrasebook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("done")) { dismiss() } } }
            .onAppear { if m.favorites.isEmpty && m.features.thaiExtras { category = "basics" } }
        }
    }

    private func chip(_ key: String, icon: String) -> some View {
        Button { category = key } label: {
            Label(T("cat_" + key), systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(category == key ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(category == key ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
