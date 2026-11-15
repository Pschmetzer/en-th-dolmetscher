// L10n.swift – Texte der Oberfläche in Deutsch, Englisch und Thai (wie die Mac-App).
import Foundation

enum L10n {
    nonisolated(unsafe) static var lang = systemLang()

    static func systemLang() -> String {
        let p = Locale.preferredLanguages.first ?? "en"
        return p.hasPrefix("de") ? "de" : p.hasPrefix("th") ? "th" : "en"
    }

    static let table: [String: [String: String]] = [
        "start": ["de": "Start", "en": "Start", "th": "เริ่ม"],
        "stop": ["de": "Stopp", "en": "Stop", "th": "หยุด"],
        "idle": ["de": "Bereit – tippe auf Start", "en": "Ready – tap Start", "th": "พร้อม – แตะเริ่ม"],
        "loading": ["de": "Lade Sprachmodell …", "en": "Loading speech model …", "th": "กำลังโหลดโมเดลเสียง …"],
        "downloading": ["de": "Lade Sprachmodell (einmalig)", "en": "Downloading speech model (once)", "th": "กำลังดาวน์โหลดโมเดลเสียง (ครั้งเดียว)"],
        "listening": ["de": "Ich höre zu – einfach sprechen", "en": "Listening – just talk", "th": "กำลังฟัง – พูดได้เลย"],
        "hearing": ["de": "Ich höre dich …", "en": "Hearing you …", "th": "กำลังได้ยิน …"],
        "speaking": ["de": "Ich lese vor …", "en": "Speaking …", "th": "กำลังพูด …"],
        "paused": ["de": "Pausiert – sag „Translator, resume“", "en": "Paused – say \"Translator, resume\"",
                   "th": "หยุดชั่วคราว – พูดว่า \"Translator, resume\""],
        "resumed": ["de": "Weiter geht's", "en": "Resumed", "th": "แปลต่อ"],
        "say_command": ["de": "Befehl?", "en": "Command?", "th": "คำสั่ง?"],
        "pause": ["de": "Pause", "en": "Pause", "th": "หยุดชั่วคราว"],
        "resume": ["de": "Fortsetzen", "en": "Resume", "th": "ทำต่อ"],
        "mode_auto": ["de": "Automatisch", "en": "Auto", "th": "อัตโนมัติ"],
        "empty_example": ["de": "Sag z. B.: „Where is the toilet?“", "en": "Try saying: \"Where is the toilet?\"",
                          "th": "ลองพูดว่า: \"Where is the toilet?\""],
        "empty_hint": ["de": "Englisch wird ins Thailändische übersetzt, Thai ins Englische – und sofort vorgelesen.",
                       "en": "English is translated into Thai and Thai into English – and spoken right away.",
                       "th": "แปลอังกฤษเป็นไทย และไทยเป็นอังกฤษ แล้วพูดออกมาทันที"],
        "commands": ["de": "Sprachbefehle", "en": "Voice commands", "th": "คำสั่งเสียง"],
        "commands_say": ["de": "Sag „Translator“ und dann den Befehl (auf Englisch):",
                         "en": "Say \"Translator\" and then the command:",
                         "th": "พูดว่า \"Translator\" แล้วตามด้วยคำสั่ง (ภาษาอังกฤษ):"],
        "cmd_pause": ["de": "Übersetzen anhalten", "en": "stop translating", "th": "หยุดแปลชั่วคราว"],
        "cmd_resume": ["de": "weiter übersetzen", "en": "continue translating", "th": "แปลต่อ"],
        "cmd_repeat": ["de": "letzten Satz noch einmal", "en": "say the last sentence again", "th": "พูดประโยคล่าสุดอีกครั้ง"],
        "cmd_slower": ["de": "langsamer / schneller sprechen", "en": "speak slower / faster", "th": "พูดช้าลง / เร็วขึ้น"],
        "cmd_louder": ["de": "lauter / leiser", "en": "louder / quieter", "th": "ดังขึ้น / เบาลง"],
        "cmd_clear": ["de": "Verlauf leeren", "en": "clear the conversation", "th": "ล้างบทสนทนา"],
        "cmd_slower_done": ["de": "Langsamer", "en": "Slower", "th": "ช้าลง"],
        "cmd_faster_done": ["de": "Schneller", "en": "Faster", "th": "เร็วขึ้น"],
        "cmd_louder_done": ["de": "Lauter", "en": "Louder", "th": "ดังขึ้น"],
        "cmd_quieter_done": ["de": "Leiser", "en": "Quieter", "th": "เบาลง"],
        "type_hint": ["de": "Oder tippen …", "en": "Or type …", "th": "หรือพิมพ์ …"],
        "translating": ["de": "Übersetze …", "en": "Translating …", "th": "กำลังแปล …"],
        "retry": ["de": "Nochmal", "en": "Retry", "th": "ลองอีกครั้ง"],
        "copy": ["de": "Kopieren", "en": "Copy", "th": "คัดลอก"],
        "replay": ["de": "Vorlesen", "en": "Play", "th": "เล่น"],
        "swap": ["de": "Andere Sprache war gemeint", "en": "Other language was meant", "th": "หมายถึงอีกภาษาหนึ่ง"],
        "partner": ["de": "Partner-Ansicht", "en": "Partner view", "th": "มุมมองคู่สนทนา"],
        "partner_empty": ["de": "Hier erscheint die Übersetzung in groß.", "en": "The translation appears here in large type.",
                          "th": "คำแปลจะแสดงที่นี่เป็นตัวใหญ่"],
        "flip": ["de": "Umdrehen", "en": "Flip", "th": "กลับด้าน"],
        "done": ["de": "Fertig", "en": "Done", "th": "เสร็จ"],
        "settings": ["de": "Einstellungen", "en": "Settings", "th": "ตั้งค่า"],
        "share": ["de": "Gespräch teilen", "en": "Share conversation", "th": "แชร์บทสนทนา"],
        "clear": ["de": "Verlauf leeren", "en": "Clear conversation", "th": "ล้างบทสนทนา"],
        "sec_speech": ["de": "Sprache", "en": "Speech", "th": "เสียงพูด"],
        "silence": ["de": "Satzende nach Pause", "en": "Sentence ends after pause", "th": "จบประโยคเมื่อเงียบ"],
        "auto_speak": ["de": "Übersetzung vorlesen", "en": "Speak translations", "th": "อ่านคำแปลออกเสียง"],
        "rate": ["de": "Sprechtempo", "en": "Speaking rate", "th": "ความเร็วในการพูด"],
        "volume": ["de": "Lautstärke", "en": "Volume", "th": "ระดับเสียง"],
        "sec_translation": ["de": "Übersetzung", "en": "Translation", "th": "การแปล"],
        "offline_ready": ["de": "Offline-Sprachpakete installiert", "en": "Offline language packs installed",
                          "th": "ติดตั้งชุดภาษาออฟไลน์แล้ว"],
        "offline_get": ["de": "Offline-Sprachpakete laden", "en": "Download offline language packs",
                        "th": "ดาวน์โหลดชุดภาษาออฟไลน์"],
        "online": ["de": "Online-Übersetzer als Ersatz", "en": "Online translator as fallback", "th": "ใช้ตัวแปลออนไลน์สำรอง"],
        "online_note": ["de": "Ohne Offline-Pakete geht der Text an Google Translate (Ersatz: MyMemory). Die Spracherkennung läuft immer auf dem Gerät.",
                        "en": "Without offline packs the text is sent to Google Translate (fallback: MyMemory). Speech recognition always runs on the device.",
                        "th": "หากไม่มีชุดภาษาออฟไลน์ ข้อความจะถูกส่งไปยัง Google Translate (สำรอง: MyMemory) การรู้จำเสียงทำงานบนเครื่องเสมอ"],
        "ui_lang": ["de": "Sprache der App", "en": "App language", "th": "ภาษาของแอป"],
        "err_unsupported": ["de": "Diese Sprache wird von der Spracherkennung nicht unterstützt",
                            "en": "Speech recognition does not support this language", "th": "ไม่รองรับภาษานี้"],
        "err_no_model": ["de": "Sprachmodell fehlt und ließ sich nicht laden", "en": "Speech model is missing and could not be loaded",
                         "th": "ไม่มีโมเดลเสียงและโหลดไม่ได้"],
        "err_no_mic": ["de": "Kein Mikrofon gefunden", "en": "No microphone found", "th": "ไม่พบไมโครโฟน"],
        "err_denied": ["de": "Mikrofon oder Spracherkennung nicht erlaubt – bitte in den Einstellungen freigeben",
                       "en": "Microphone or speech recognition not allowed – please enable it in Settings",
                       "th": "ไม่ได้รับอนุญาตให้ใช้ไมโครโฟนหรือการรู้จำเสียง – โปรดเปิดในการตั้งค่า"],
        "err_offline_missing": ["de": "Offline-Sprachpakete fehlen (Einstellungen)", "en": "Offline language packs missing (Settings)",
                                "th": "ไม่มีชุดภาษาออฟไลน์ (ตั้งค่า)"],
        "err_translate": ["de": "Übersetzung fehlgeschlagen – Internet?", "en": "Translation failed – internet?",
                          "th": "แปลไม่สำเร็จ – อินเทอร์เน็ต?"],
    ]
}

func T(_ key: String) -> String {
    L10n.table[key]?[L10n.lang] ?? L10n.table[key]?["en"] ?? key
}
