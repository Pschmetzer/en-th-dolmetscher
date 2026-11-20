// L10n+R23.swift – Texte der Runde 23 (Hauptfenster, Blasen, Mini-Ansicht). Eigene Tabelle neben L10n.swift,
// damit sich parallele Änderungen nicht überschneiden. Zugriff: L.r23 bzw. L.r23f mit dem Schlüssel.
// Jeder Schlüssel braucht de, en und th (geprüft von tests/test_runde23_l10n.py). Gleiche Schlüssel nie doppelt.
import Foundation

extension L {
    /// Text der Runde-23-Tabelle in der Oberflächensprache (Rückfall: Englisch, dann der Schlüssel selbst).
    static func r23(_ key: String) -> String {
        guard let row = r23Table[key] else { return key }
        return row[lang.rawValue] ?? row["en"] ?? key
    }

    /// Wie `r23`, mit Platzhaltern (%@, %d).
    static func r23f(_ key: String, _ args: CVarArg...) -> String {
        String(format: r23(key), locale: Locale(identifier: lang == .de ? "de_DE" : "en_US"), arguments: args)
    }

    static let r23Table: [String: [String: String]] = [
        "hit_prev": ["de": "Vorheriger Treffer (⇧⌘G)", "en": "Previous match (⇧⌘G)", "th": "ผลลัพธ์ก่อนหน้า (⇧⌘G)"],
        "hit_next": ["de": "Nächster Treffer (⌘G)", "en": "Next match (⌘G)", "th": "ผลลัพธ์ถัดไป (⌘G)"],
        "hit_position": ["de": "Treffer %@", "en": "Match %@", "th": "ผลลัพธ์ %@"],
        "select_mode": ["de": "Blasen auswählen", "en": "Select bubbles", "th": "เลือกข้อความ"],
        "select_done": ["de": "Auswahl beenden", "en": "Done selecting", "th": "เลือกเสร็จแล้ว"],
        "select_all": ["de": "Alle auswählen", "en": "Select all", "th": "เลือกทั้งหมด"],
        "select_none": ["de": "Auswahl aufheben", "en": "Clear selection", "th": "ยกเลิกการเลือก"],
        "selected_n": ["de": "%d ausgewählt", "en": "%d selected", "th": "เลือกแล้ว %d"],
        "select_copy": ["de": "Auswahl kopieren", "en": "Copy selection", "th": "คัดลอกที่เลือก"],
        "select_export": ["de": "Auswahl exportieren", "en": "Export selection", "th": "ส่งออกที่เลือก"],
        "select_delete": ["de": "Auswahl löschen", "en": "Delete selection", "th": "ลบที่เลือก"],
        "select_toggle": ["de": "Auswählen", "en": "Select", "th": "เลือก"],
        "copy_menu": ["de": "Kopieren als …", "en": "Copy as …", "th": "คัดลอกเป็น …"],
        "export_only_lang": ["de": "Nur %@ exportieren", "en": "Export only %@", "th": "ส่งออกเฉพาะ %@"],
        "export_no_times": ["de": "Ohne Uhrzeiten exportieren", "en": "Export without times", "th": "ส่งออกโดยไม่มีเวลา"],
        "back_show": ["de": "Rückübersetzung zeigen", "en": "Show back-translation", "th": "แสดงการแปลกลับ"],
        "back_hide": ["de": "Rückübersetzung ausblenden", "en": "Hide back-translation", "th": "ซ่อนการแปลกลับ"],
        "back_enable": ["de": "Rückübersetzung für neue Sätze einschalten", "en": "Turn on back-translation for new sentences",
                        "th": "เปิดการแปลกลับสำหรับประโยคใหม่"],
        "num_warn_missing": ["de": "fehlt in der Übersetzung: %@", "en": "missing in the translation: %@", "th": "ขาดในคำแปล: %@"],
        "num_warn_extra": ["de": "zusätzlich in der Übersetzung: %@", "en": "extra in the translation: %@", "th": "เพิ่มเข้ามาในคำแปล: %@"],
        "alt_next": ["de": "Nächste Lesart (%@)", "en": "Next reading (%@)", "th": "คำอ่านถัดไป (%@)"],
        "tip_label": ["de": "Tipp", "en": "Tip", "th": "เคล็ดลับ"],
        "tip_space": ["de": "Die Leertaste startet und stoppt das Zuhören, solange kein Textfeld den Fokus hat.",
                      "en": "The space bar starts and stops listening while no text field has focus.",
                      "th": "กดเว้นวรรคเพื่อเริ่มหรือหยุดฟัง เมื่อไม่ได้พิมพ์ในช่องข้อความ"],
        "tip_phrase": ["de": "Häufige Sätze als Schnellsatz speichern: Rechtsklick auf eine Blase, dann „Als Schnellsatz speichern“.",
                       "en": "Save frequent sentences as quick phrases: right-click a bubble, then “Save as quick phrase”.",
                       "th": "บันทึกประโยคที่ใช้บ่อยเป็นวลีด่วน: คลิกขวาที่ข้อความแล้วเลือกบันทึกเป็นวลีด่วน"],
        "tip_partner": ["de": "Die Partner-Ansicht (⇧⌘P) zeigt nur die letzte Übersetzung, sehr groß.",
                        "en": "The partner view (⇧⌘P) shows only the latest translation, very large.",
                        "th": "มุมมองคู่สนทนา (⇧⌘P) แสดงเฉพาะคำแปลล่าสุดด้วยตัวอักษรขนาดใหญ่"],
        "tip_search": ["de": "⌘F sucht im Verlauf, ⌘G springt zum nächsten Treffer.",
                       "en": "⌘F searches the conversation, ⌘G jumps to the next match.",
                       "th": "⌘F ค้นหาในบทสนทนา และ ⌘G ข้ามไปยังผลลัพธ์ถัดไป"],
        "tip_mini": ["de": "Der Mini-Modus (⌥⌘M) bleibt als kleines Fenster immer sichtbar.",
                     "en": "Mini mode (⌥⌘M) stays visible as a small window.",
                     "th": "โหมดย่อ (⌥⌘M) แสดงเป็นหน้าต่างเล็กไว้ด้านบนเสมอ"],
        "tip_correct": ["de": "Falsch erkannt? Mit E oder dem Stift an der Blase den Text korrigieren und neu übersetzen.",
                        "en": "Misheard? Press E or use the pencil on a bubble to fix the text and translate again.",
                        "th": "ฟังผิด? กด E หรือใช้ปุ่มดินสอที่ข้อความเพื่อแก้ไขแล้วแปลใหม่"],
        "latency_trend_up": ["de": "Latenz steigt", "en": "Latency rising", "th": "ความหน่วงเพิ่มขึ้น"],
        "latency_trend_down": ["de": "Latenz sinkt", "en": "Latency falling", "th": "ความหน่วงลดลง"],
        "latency_recent": ["de": "Letzte Latenzen", "en": "Recent latencies", "th": "ความหน่วงล่าสุด"],
        "clip_short": ["de": "Zu laut", "en": "Too loud", "th": "เสียงดังเกินไป"],
        "clip_warn": ["de": "Mikrofon übersteuert – Abstand vergrößern oder Eingangspegel senken",
                      "en": "Microphone is clipping – move back or lower the input level",
                      "th": "ไมโครโฟนเสียงแตก – ขยับห่างออกหรือลดระดับสัญญาณเข้า"],
        "script_mismatch": ["de": "Richtung steht auf %@, die letzten Sätze waren aber in einer anderen Sprache.",
                            "en": "Direction is set to %@, but the last sentences were in another language.",
                            "th": "ตั้งทิศทางเป็น %@ แต่ประโยคล่าสุดเป็นอีกภาษาหนึ่ง"],
        "set_auto": ["de": "Auf Automatisch stellen", "en": "Switch to Auto", "th": "เปลี่ยนเป็นอัตโนมัติ"],
        "interrupted": ["de": "unterbrochen – Engine neu gestartet", "en": "interrupted – engine restarted",
                        "th": "ถูกขัดจังหวะ – เริ่มเอนจินใหม่"],
        "mini_copy": ["de": "Übersetzung kopieren", "en": "Copy translation", "th": "คัดลอกคำแปล"],
        "bubble_position": ["de": "Nachricht %@", "en": "Message %@", "th": "ข้อความ %@"],
        "current_hit": ["de": "aktueller Treffer", "en": "current match", "th": "ผลลัพธ์ปัจจุบัน"],
        "selected_state": ["de": "ausgewählt", "en": "selected", "th": "เลือกแล้ว"],
    ]
}
