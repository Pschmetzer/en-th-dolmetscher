// L10n+R25.swift – Texte der Runde 25 (Fehler-Schritte, Ausgabe je Richtung, zweispaltiger Verlaufs-Export, Fenster-Selbsttest,
// Live-Zeile der Menüleiste, Handoff). Eigene Tabelle neben L10n.swift; jede Zeile hat de, en und th
// (geprüft in tests/test_r25_mac.py). Zugriff: R25T.t / R25T.f / R25T.any.
import Foundation

enum R25T {
    static func t(_ key: String) -> String {
        guard let row = table[key] else { return key }
        return row[L.lang.rawValue] ?? row["en"] ?? key
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: L.lang == .de ? "de_DE" : "en_US"), arguments: args)
    }

    /// Schlüssel aus L10n, sonst aus dieser Tabelle (für Texte, die ein Logik-Typ nur als Schlüssel kennt).
    static func any(_ key: String) -> String {
        let s = L.t(key)
        return s == key ? t(key) : s
    }

    static let table: [String: [String: String]] = [
        "open_network_settings": ["de": "Netzwerk-Einstellungen", "en": "Network settings", "th": "การตั้งค่าเครือข่าย"],
        "open_storage_settings": ["de": "Speicher verwalten", "en": "Manage storage", "th": "จัดการพื้นที่จัดเก็บ"],
        "open_error_help": ["de": "Fehlerhilfe", "en": "Error help", "th": "วิธีแก้ปัญหา"],
        "advice_disk_full": ["de": "Der Speicher ist voll. Platz schaffen und erneut versuchen.", "en": "The disk is full. Free some space and try again.", "th": "พื้นที่เต็ม ลบไฟล์ให้มีที่ว่างแล้วลองอีกครั้ง"],
        "advice_file": ["de": "Die Datei konnte nicht verarbeitet werden. Das Protokoll nennt die Stelle.", "en": "The file could not be processed. The log shows where.", "th": "ประมวลผลไฟล์ไม่ได้ ดูตำแหน่งในบันทึก"],
        "advice_langs": ["de": "Das Sprachpaar ist ungültig. In den Einstellungen neu wählen.", "en": "The language pair is invalid. Choose it again in Settings.", "th": "คู่ภาษาไม่ถูกต้อง เลือกใหม่ในการตั้งค่า"],
        "route_title": ["de": "Ausgabe je Richtung", "en": "Output per direction", "th": "เสียงออกตามทิศทาง"],
        "route_mine": ["de": "Meine Übersetzungen (ich höre)", "en": "My translations (I listen)", "th": "คำแปลของฉัน (ฉันฟัง)"],
        "route_partner": ["de": "Übersetzungen fürs Gegenüber", "en": "Translations for the other person", "th": "คำแปลสำหรับอีกฝ่าย"],
        "route_default": ["de": "Wie Standard-Ausgabe", "en": "Same as default output", "th": "เหมือนเอาต์พุตมาตรฐาน"],
        "route_same_warn": ["de": "Beide Richtungen nutzen dasselbe Gerät.", "en": "Both directions use the same device.", "th": "ทั้งสองทิศทางใช้อุปกรณ์เดียวกัน"],
        "route_missing": ["de": "Gewähltes Gerät nicht angeschlossen: es gilt die Standard-Ausgabe.", "en": "Chosen device is not connected: the default output is used.", "th": "ไม่ได้เชื่อมต่ออุปกรณ์ที่เลือก ใช้เอาต์พุตมาตรฐานแทน"],
        "route_note": ["de": "Vorbereitet: wirkt, sobald die Engine die Richtung je Satz kennt.", "en": "Prepared: takes effect once the engine knows the direction per sentence.", "th": "เตรียมไว้แล้ว: จะทำงานเมื่อเอนจินรู้ทิศทางของแต่ละประโยค"],
        "hist_md_table": ["de": "Markdown, zweispaltig (Thai | Latein)", "en": "Markdown, two columns (Thai | Latin)", "th": "Markdown สองคอลัมน์ (ไทย | ละติน)"],
        "hist_pdf_table": ["de": "PDF, zweispaltig (Thai | Latein)", "en": "PDF, two columns (Thai | Latin)", "th": "PDF สองคอลัมน์ (ไทย | ละติน)"],
        "col_time": ["de": "Zeit", "en": "Time", "th": "เวลา"],
        "col_thai": ["de": "Thai", "en": "Thai", "th": "ไทย"],
        "col_latin": ["de": "Latein", "en": "Latin", "th": "ละติน"],
        "col_translit": ["de": "Umschrift", "en": "Romanization", "th": "คำอ่าน"],
        "smoke_menu": ["de": "Fenster-Selbsttest", "en": "Window self-test", "th": "ทดสอบหน้าต่าง"],
        "smoke_result": ["de": "%d von %d Fenstern in Ordnung.", "en": "%d of %d windows are fine.", "th": "หน้าต่างปกติ %d จาก %d"],
        "smoke_failed": ["de": "Nicht in Ordnung: %@", "en": "Not fine: %@", "th": "ไม่ปกติ: %@"],
        "menu_live": ["de": "%d Sätze, %d wartend", "en": "%d sentences, %d waiting", "th": "%d ประโยค รอ %d"],
        "menu_live_latency": ["de": "%d Sätze, %d wartend · ⏱ %@", "en": "%d sentences, %d waiting · ⏱ %@", "th": "%d ประโยค รอ %d · ⏱ %@"],
        "handoff_toggle": ["de": "Letzten Satz per Handoff an andere Macs übergeben", "en": "Hand off the last sentence to other Macs", "th": "ส่งประโยคล่าสุดไปยัง Mac เครื่องอื่นด้วย Handoff"],
        "handoff_note": ["de": "Aus: nichts verlässt diesen Mac. Bei sensibler Sitzung wird nie übergeben.", "en": "Off: nothing leaves this Mac. Never handed off during a sensitive session.", "th": "ปิด: ไม่มีข้อมูลออกจาก Mac เครื่องนี้ ไม่ส่งต่อในช่วงเซสชันที่ละเอียดอ่อน"],
        "handoff_activity": ["de": "Dolmetscher: letzter Satz", "en": "Dolmetscher: last sentence", "th": "Dolmetscher: ประโยคล่าสุด"],
    ]
}
