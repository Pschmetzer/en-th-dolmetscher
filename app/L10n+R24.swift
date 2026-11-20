// L10n+R24.swift – Texte der Runde 24 (Zahlen & Preise, Zusammenfassung, Lernen, Zeig-Karte, Kürzel-Fenster, Mitteilungen).
// Eigene Tabelle neben L10n.swift. Zugriff: R24T.t bzw. R24T.f mit dem Schlüssel; jede Zeile hat de, en und th.
import Foundation

enum R24T {
    static func t(_ key: String) -> String {
        guard let row = table[key] else { return key }
        return row[L.lang.rawValue] ?? row["en"] ?? key
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: L.lang == .de ? "de_DE" : "en_US"), arguments: args)
    }

    static let table: [String: [String: String]] = [
        "numbers_title": ["de": "Zahlen & Preise", "en": "Numbers & prices", "th": "ตัวเลขและราคา"],
        "summary_title": ["de": "Zusammenfassung", "en": "Summary", "th": "สรุปการสนทนา"],
        "learn_title": ["de": "Lernen", "en": "Learn", "th": "เรียนรู้"],
        "card_title": ["de": "Zeig-Karte", "en": "Show card", "th": "การ์ดแสดง"],
        "shortcuts_title": ["de": "Tastaturkürzel", "en": "Keyboard shortcuts", "th": "ปุ่มลัด"],
        "rate_label": ["de": "Kurs (Baht pro Euro)", "en": "Rate (baht per euro)", "th": "อัตราแลกเปลี่ยน (บาทต่อยูโร)"],
        "rate_invalid": ["de": "Bitte eine Zahl zwischen 0 und 1000 eingeben.", "en": "Enter a number between 0 and 1000.", "th": "กรอกตัวเลขระหว่าง 0 ถึง 1000"],
        "prices_recent": ["de": "Zuletzt genannte Preise", "en": "Recently mentioned prices", "th": "ราคาที่พูดถึงล่าสุด"],
        "prices_none": ["de": "Noch kein Preis im Gespräch.", "en": "No price in the conversation yet.", "th": "ยังไม่มีราคาในการสนทนา"],
        "show_big": ["de": "Groß zeigen", "en": "Show big", "th": "แสดงขนาดใหญ่"],
        "asking": ["de": "Verlangter Preis (฿)", "en": "Asking price (฿)", "th": "ราคาที่ขอ (฿)"],
        "counter_offers": ["de": "Gegenangebote", "en": "Counter-offers", "th": "ราคาที่เสนอกลับ"],
        "my_bid": ["de": "Mein letztes Gebot (฿)", "en": "My last bid (฿)", "th": "ราคาที่ฉันเสนอล่าสุด (฿)"],
        "next_bid": ["de": "Nächstes Gebot: %@", "en": "Next bid: %@", "th": "เสนอครั้งต่อไป: %@"],
        "no_room": ["de": "Kein Spielraum mehr: Preis annehmen oder gehen.", "en": "No room left: accept or walk away.", "th": "ไม่เหลือช่องให้ต่อรอง: ตกลงหรือเดินจากไป"],
        "sum_turns": ["de": "Äußerungen", "en": "Utterances", "th": "จำนวนประโยค"],
        "sum_minutes": ["de": "Minuten", "en": "Minutes", "th": "นาที"],
        "sum_todos": ["de": "Mögliche To-dos", "en": "Possible to-dos", "th": "สิ่งที่อาจต้องทำ"],
        "sum_questions": ["de": "Fragen", "en": "Questions", "th": "คำถาม"],
        "sum_prices": ["de": "Preise", "en": "Prices", "th": "ราคา"],
        "sum_numbers": ["de": "Zahlen", "en": "Numbers", "th": "ตัวเลข"],
        "sum_copy": ["de": "Als Text kopieren", "en": "Copy as text", "th": "คัดลอกเป็นข้อความ"],
        "sum_save": ["de": "Als Markdown sichern …", "en": "Save as Markdown …", "th": "บันทึกเป็น Markdown …"],
        "sum_empty": ["de": "Noch kein Gespräch zum Zusammenfassen.", "en": "No conversation to summarize yet.", "th": "ยังไม่มีการสนทนาให้สรุป"],
        "sum_note": ["de": "Rein lokal erstellt: Stichwörter, keine KI-Zusammenfassung.", "en": "Built locally from keywords, not an AI summary.", "th": "สร้างในเครื่องจากคำสำคัญ ไม่ใช่สรุปโดย AI"],
        "learn_pick": ["de": "Satz wählen", "en": "Choose a sentence", "th": "เลือกประโยค"],
        "learn_words": ["de": "Wort für Wort", "en": "Word by word", "th": "ทีละคำ"],
        "learn_cloze": ["de": "Lückentext", "en": "Fill in the blank", "th": "เติมคำในช่องว่าง"],
        "learn_reveal": ["de": "Auflösen", "en": "Reveal", "th": "เฉลย"],
        "learn_next": ["de": "Anderes Wort", "en": "Another word", "th": "คำอื่น"],
        "learn_anki": ["de": "Anki-Karten sichern …", "en": "Save Anki cards …", "th": "บันทึกการ์ด Anki …"],
        "learn_empty": ["de": "Noch keine übersetzten Sätze zum Lernen.", "en": "No translated sentences to learn from yet.", "th": "ยังไม่มีประโยคที่แปลแล้วให้เรียน"],
        "learn_front": ["de": "Vorderseite in", "en": "Front side in", "th": "ด้านหน้าเป็นภาษา"],
        "learn_cards_n": ["de": "%d Karten", "en": "%d cards", "th": "%d การ์ด"],
        "card_field": ["de": "Satz eintippen (Englisch oder Thai)", "en": "Type a sentence (English or Thai)", "th": "พิมพ์ประโยค (อังกฤษหรือไทย)"],
        "card_last": ["de": "Letzte Übersetzung", "en": "Last translation", "th": "คำแปลล่าสุด"],
        "card_match": ["de": "Satzbuch (offline): %@", "en": "Phrasebook (offline): %@", "th": "สมุดวลี (ออฟไลน์): %@"],
        "card_nomatch": ["de": "Kein passender Satz im Satzbuch.", "en": "No matching phrase in the phrasebook.", "th": "ไม่พบประโยคที่ตรงในสมุดวลี"],
        "card_suggest": ["de": "Meintest du:", "en": "Did you mean:", "th": "คุณหมายถึง:"],
        "card_hint": ["de": "Zum Zeigen an das Gegenüber; die Karte nutzt keinen Übersetzer.", "en": "To show to the other person; the card uses no translator.", "th": "สำหรับแสดงให้อีกฝ่ายดู การ์ดนี้ไม่ใช้ตัวแปล"],
        "grp_conversation": ["de": "Gespräch", "en": "Conversation", "th": "การสนทนา"],
        "grp_view": ["de": "Ansicht", "en": "View", "th": "มุมมอง"],
        "grp_window": ["de": "Fenster", "en": "Windows", "th": "หน้าต่าง"],
        "search_shortcuts": ["de": "Kürzel suchen", "en": "Search shortcuts", "th": "ค้นหาปุ่มลัด"],
        "n_restart": ["de": "Neu starten", "en": "Restart", "th": "เริ่มใหม่"],
        "n_copy": ["de": "Kopieren", "en": "Copy", "th": "คัดลอก"],
        "n_open": ["de": "Öffnen", "en": "Open", "th": "เปิด"],
        "n_use": ["de": "Übernehmen", "en": "Use it", "th": "ใช้เลย"],
        "n_dismiss": ["de": "Nicht jetzt", "en": "Not now", "th": "ไว้ก่อน"],
        "n_summary_title": ["de": "Gespräch beendet", "en": "Conversation ended", "th": "การสนทนาสิ้นสุดแล้ว"],
        "n_summary_body": ["de": "%d Äußerungen. Zusammenfassung ansehen?", "en": "%d utterances. View the summary?", "th": "%d ประโยค ดูสรุปไหม"],
        "scn_suggest": ["de": "Das klingt nach „%@“. Passende Sätze laden?", "en": "This sounds like “%@”. Load matching phrases?", "th": "ฟังดูเหมือน “%@” โหลดประโยคที่เหมาะสมไหม"],
        "scn_use": ["de": "Sätze laden", "en": "Load phrases", "th": "โหลดประโยค"],
        "cap_anchor": ["de": "Position", "en": "Position", "th": "ตำแหน่ง"],
        "cap_anchor_bottom": ["de": "Unten am Bildschirm", "en": "Bottom of screen", "th": "ด้านล่างของหน้าจอ"],
        "cap_anchor_top": ["de": "Oben am Bildschirm", "en": "Top of screen", "th": "ด้านบนของหน้าจอ"],
        "cap_anchor_free": ["de": "Frei verschiebbar", "en": "Free", "th": "ย้ายได้อิสระ"],
        "cap_clickthrough": ["de": "Klicks durchlassen", "en": "Click-through", "th": "ให้คลิกทะลุได้"],
        "cap_bold": ["de": "Fette Schrift", "en": "Bold text", "th": "ตัวหนา"],
        "cap_reset_clickable": ["de": "Untertitel wieder anklickbar machen", "en": "Make captions clickable again", "th": "ทำให้คำบรรยายคลิกได้อีกครั้ง"],
        "card_link": ["de": "Kurzbefehl-Link kopieren", "en": "Copy Shortcuts link", "th": "คัดลอกลิงก์คำสั่งลัด"],
        "copied": ["de": "Kopiert", "en": "Copied", "th": "คัดลอกแล้ว"],
    ]
}
