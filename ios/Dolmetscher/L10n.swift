// L10n.swift – Texte der Oberfläche in Deutsch, Englisch und Thai (wie die Mac-App); weitere Sprachen
// (maschinell übersetzt) in L10n+Extra.swift.
import Foundation
import Observation

enum L10n {
    /// Sprache der Oberfläche. Beobachtbar (555): Ansichten, die `T()` lesen, zeichnen sich bei einem Wechsel
    /// neu, ohne dass der ganze Baum neu entsteht (Sheets bleiben offen). Mit Sperre (650: Lesen aus Hintergrund-Threads).
    static var lang: String {
        get { UILanguage.shared.code }
        set { UILanguage.shared.code = newValue }
    }

    /// Sprachen der Oberfläche (Codes wie die .lproj-Ordner).
    static let languages = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]

    static func systemLang() -> String { match(Locale.preferredLanguages) }

    /// Erste bevorzugte Sprache, die die App kann ("zh-Hans-CN" -> "zh-Hans", "de-AT" -> "de"); sonst Englisch.
    static func match(_ preferred: [String]) -> String {
        for p in preferred {
            if p.hasPrefix("zh") {
                // Traditionelles Chinesisch gibt es nicht – lieber Englisch als die falsche Schrift.
                if p.hasPrefix("zh-Hans") || p == "zh" || p.hasPrefix("zh-CN") || p.hasPrefix("zh-SG") { return "zh-Hans" }
                continue
            }
            let code = String(p.prefix { $0 != "-" && $0 != "_" })
            if languages.contains(code) { return code }
        }
        return "en"
    }

    /// Die Oberflächensprache als Sprache der Sprachtabelle ("zh-Hans" -> zh), falls es eine ist.
    static var asLang: Lang? { Lang(rawValue: lang == "zh-Hans" ? "zh" : lang) }

    /// Code der Oberflächen-Tabelle für eine Sprache des Paars (zh -> "zh-Hans").
    static func uiCode(_ l: Lang) -> String { l == .zh ? "zh-Hans" : l.rawValue }

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

        "more": ["de": "Mehr", "en": "More", "th": "เพิ่มเติม"],
        "direction": ["de": "Richtung", "en": "Direction", "th": "ทิศทาง"],
        "stop_speaking": ["de": "Vorlesen stoppen", "en": "Stop speaking", "th": "หยุดพูด"],
        "replay_slow": ["de": "Langsam vorlesen", "en": "Play slowly", "th": "เล่นช้าๆ"],
        "favorite": ["de": "Favorit", "en": "Favorite", "th": "รายการโปรด"],
        "unfavorite": ["de": "Kein Favorit mehr", "en": "Remove favorite", "th": "เอาออกจากรายการโปรด"],
        "share_one": ["de": "Teilen", "en": "Share", "th": "แชร์"],
        "show_big": ["de": "Groß anzeigen", "en": "Show large", "th": "แสดงตัวใหญ่"],
        "edit_text": ["de": "Text korrigieren", "en": "Correct text", "th": "แก้ไขข้อความ"],
        "delete": ["de": "Löschen", "en": "Delete", "th": "ลบ"],
        "cancel": ["de": "Abbrechen", "en": "Cancel", "th": "ยกเลิก"],
        "translate": ["de": "Übersetzen", "en": "Translate", "th": "แปล"],
        "prov_offline": ["de": "Offline übersetzt", "en": "Translated offline", "th": "แปลแบบออฟไลน์"],
        "prov_online": ["de": "Online übersetzt", "en": "Translated online", "th": "แปลแบบออนไลน์"],
        "split_view": ["de": "Geteilte Ansicht", "en": "Split view", "th": "มุมมองแบ่งครึ่ง"],
        "phrasebook": ["de": "Satzbuch", "en": "Phrasebook", "th": "สมุดวลี"],
        "search": ["de": "Suchen", "en": "Search", "th": "ค้นหา"],
        "fav_empty": ["de": "Noch keine Favoriten – tippe in einer Sprechblase auf ☆.", "en": "No favorites yet – tap ☆ in a bubble.",
                      "th": "ยังไม่มีรายการโปรด – แตะ ☆ ในข้อความ"],
        "nothing_found": ["de": "Nichts gefunden", "en": "Nothing found", "th": "ไม่พบ"],
        "cat_favorites": ["de": "Favoriten", "en": "Favorites", "th": "รายการโปรด"],
        "cat_basics": ["de": "Grundlagen", "en": "Basics", "th": "พื้นฐาน"],
        "cat_food": ["de": "Essen", "en": "Food", "th": "อาหาร"],
        "cat_transport": ["de": "Unterwegs", "en": "Getting around", "th": "การเดินทาง"],
        "cat_shopping": ["de": "Einkaufen", "en": "Shopping", "th": "ช้อปปิ้ง"],
        "cat_hotel": ["de": "Hotel", "en": "Hotel", "th": "โรงแรม"],
        "cat_health": ["de": "Notfall", "en": "Emergency", "th": "ฉุกเฉิน"],
        "photo_text": ["de": "Text aus Foto", "en": "Text from photo", "th": "ข้อความจากรูปภาพ"],
        "take_photo": ["de": "Foto aufnehmen", "en": "Take photo", "th": "ถ่ายรูป"],
        "choose_photo": ["de": "Foto wählen", "en": "Choose photo", "th": "เลือกรูป"],
        "reading_text": ["de": "Lese Text …", "en": "Reading text …", "th": "กำลังอ่านข้อความ …"],
        "pick_lines": ["de": "Zeilen wählen (keine = alle)", "en": "Pick lines (none = all)", "th": "เลือกบรรทัด (ไม่เลือก = ทั้งหมด)"],
        "no_text": ["de": "Kein Text gefunden", "en": "No text found", "th": "ไม่พบข้อความ"],
        "auto_stopped": ["de": "Nach langer Stille gestoppt", "en": "Stopped after a long silence", "th": "หยุดหลังจากเงียบนาน"],
        "sec_thai": ["de": "Thai", "en": "Thai", "th": "ภาษาไทย"],
        "politeness": ["de": "Höflichkeitsform", "en": "Polite form", "th": "คำลงท้าย"],
        "pol_male": ["de": "ครับ (Mann)", "en": "ครับ (male)", "th": "ครับ (ชาย)"],
        "pol_female": ["de": "ค่ะ (Frau)", "en": "ค่ะ (female)", "th": "ค่ะ (หญิง)"],
        "pol_off": ["de": "Wie übersetzt", "en": "As translated", "th": "ตามคำแปล"],
        "politeness_note": ["de": "Thai-Sätze enden je nach Geschlecht des Sprechers mit ครับ oder ค่ะ. Übersetzer mischen das oft – die App korrigiert es.",
                            "en": "Thai sentences end with ครับ or ค่ะ depending on the speaker's gender. Translators often mix them up – the app fixes it.",
                            "th": "ประโยคภาษาไทยลงท้ายด้วย ครับ หรือ ค่ะ ตามเพศของผู้พูด แอปจะแก้ให้ถูกต้อง"],
        "haptics": ["de": "Vibration", "en": "Haptics", "th": "การสั่น"],
        "voices": ["de": "Stimmen", "en": "Voices", "th": "เสียง"],
        "voice_basic": ["de": "einfach", "en": "basic", "th": "พื้นฐาน"],
        "voice_enhanced": ["de": "verbessert", "en": "enhanced", "th": "ปรับปรุงแล้ว"],
        "voices_note": ["de": "Bessere Stimmen: Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen › Thai bzw. Englisch – eine „verbesserte“ Stimme laden.",
                        "en": "Better voices: Settings › Accessibility › Spoken Content › Voices › Thai or English – download an “enhanced” voice.",
                        "th": "เสียงที่ดีกว่า: การตั้งค่า › การช่วยการเข้าถึง › เนื้อหาที่พูด › เสียง › ภาษาไทย"],
        "sec_recognition": ["de": "Spracherkennung", "en": "Speech recognition", "th": "การรู้จำเสียง"],
        "whisper_use": ["de": "Whisper verwenden (experimentell)", "en": "Use Whisper (experimental)", "th": "ใช้ Whisper (ทดลอง)"],
        "whisper_model": ["de": "Modell", "en": "Model", "th": "โมเดล"],
        "whisper_get": ["de": "Modell laden", "en": "Download model", "th": "ดาวน์โหลดโมเดล"],
        "whisper_wifi": ["de": "Am besten im WLAN laden.", "en": "Best downloaded over Wi-Fi.", "th": "ควรดาวน์โหลดผ่าน Wi-Fi"],
        "whisper_cancel": ["de": "Abbrechen", "en": "Cancel", "th": "ยกเลิก"],
        "whisper_installed": ["de": "Installiert", "en": "Installed", "th": "ติดตั้งแล้ว"],
        "whisper_delete": ["de": "Whisper-Modell löschen", "en": "Delete Whisper model", "th": "ลบโมเดล Whisper"],
        "whisper_note": ["de": "Standard ist Apples Erkennung. Whisper erkennt ganze Sätze erst nach der Pause (keine Live-Anzeige) und braucht mehr Akku und Speicher. Fehlt das Modell oder lässt es sich nicht laden, nutzt die App Apples Erkennung.",
                         "en": "Apple's recognition is the default. Whisper recognizes whole sentences only after the pause (no live text) and uses more battery and memory. If the model is missing or fails to load, the app uses Apple's recognition.",
                         "th": "ค่าเริ่มต้นคือการรู้จำเสียงของ Apple  Whisper จะแปลงเสียงทั้งประโยคหลังหยุดพูด (ไม่มีข้อความสด) และใช้แบตเตอรี่และหน่วยความจำมากกว่า หากไม่มีโมเดลหรือโหลดไม่สำเร็จ แอปจะใช้การรู้จำของ Apple"],
        "whisper_bg_warn": ["de": "Achtung: Whisper im Hintergrund braucht viel Akku und kann vom System beendet werden.",
                            "en": "Note: Whisper in the background drains the battery and may be stopped by the system.",
                            "th": "หมายเหตุ: Whisper ในเบื้องหลังใช้แบตเตอรี่มากและระบบอาจหยุดการทำงาน"],
        "whisper_preparing": ["de": "Whisper-Modell wird vorbereitet …", "en": "Preparing Whisper model …", "th": "กำลังเตรียมโมเดล Whisper …"],
        "whisper_no_model": ["de": "Kein Whisper-Modell geladen", "en": "No Whisper model downloaded", "th": "ยังไม่ได้ดาวน์โหลดโมเดล Whisper"],
        "whisper_load_failed": ["de": "Whisper-Modell ließ sich nicht laden", "en": "Whisper model failed to load", "th": "โหลดโมเดล Whisper ไม่สำเร็จ"],
        "whisper_fallback": ["de": "nutze Apple-Erkennung", "en": "using Apple recognition", "th": "ใช้การรู้จำของ Apple"],
        "sec_listening": ["de": "Zuhören", "en": "Listening", "th": "การฟัง"],
        "auto_stop": ["de": "Automatisch stoppen nach Stille", "en": "Auto-stop after silence", "th": "หยุดอัตโนมัติเมื่อเงียบ"],
        "never": ["de": "Nie", "en": "Never", "th": "ไม่เลย"],
        "background": ["de": "Im Hintergrund weiter zuhören", "en": "Keep listening in background", "th": "ฟังต่อในเบื้องหลัง"],
        "headset": ["de": "Bluetooth-Headset als Mikrofon", "en": "Bluetooth headset as microphone", "th": "ใช้หูฟังบลูทูธเป็นไมโครโฟน"],
        "listening_note": ["de": "Hintergrund: Die App hört auch bei ausgeschaltetem Bildschirm zu (mehr Akku). Headset: Ton ist schmaler, die Erkennung kann schlechter werden.",
                           "en": "Background: keeps listening with the screen off (more battery). Headset: narrower audio, recognition may get worse.",
                           "th": "เบื้องหลัง: ฟังต่อแม้ปิดหน้าจอ (ใช้แบตมากขึ้น) หูฟัง: เสียงแคบลง การรู้จำอาจแย่ลง"],
        "shortcuts_note": ["de": "Tipp: In der Kurzbefehle-App gibt es „Dolmetscher starten“ und „Übersetzen“ – auch für Siri und die Aktionstaste.",
                           "en": "Tip: the Shortcuts app offers “Start interpreting” and “Translate” – also for Siri and the Action button.",
                           "th": "เคล็ดลับ: แอปคำสั่งลัดมี “เริ่มแปล” และ “แปล” ใช้กับ Siri และปุ่มแอ็คชั่นได้"],

        "interrupted": ["de": "Unterbrochen (Anruf) – geht gleich weiter", "en": "Interrupted (call) – resumes shortly", "th": "ถูกขัดจังหวะ (สายเรียกเข้า) – จะทำต่อเร็วๆ นี้"],
        "online_hint": ["de": "Ohne Offline-Sprachpakete wird online übersetzt. Tippen, um sie zu laden.", "en": "Without offline language packs, translation happens online. Tap to download them.", "th": "หากไม่มีชุดภาษาออฟไลน์ จะแปลแบบออนไลน์ แตะเพื่อดาวน์โหลด"],
        "edit": ["de": "Bearbeiten", "en": "Edit", "th": "แก้ไข"],
        "emergency": ["de": "Notfall", "en": "Emergency", "th": "ฉุกเฉิน"],
        "emergency_numbers": ["de": "Notrufnummern Thailand (antippen = anrufen)", "en": "Emergency numbers in Thailand (tap to call)", "th": "หมายเลขฉุกเฉิน (แตะเพื่อโทร)"],
        "em_card": ["de": "Meine Notfallkarte", "en": "My emergency card", "th": "บัตรฉุกเฉินของฉัน"],
        "em_empty": ["de": "Noch leer – „Bearbeiten“ tippen und Hotel, Allergien, Kontakt eintragen.", "en": "Empty – tap “Edit” and add hotel, allergies, contact.", "th": "ยังว่าง – แตะ “แก้ไข” เพื่อเพิ่มข้อมูล"],
        "em_note": ["de": "Bleibt nur auf diesem iPhone. Ideal: Hoteladresse auf Thai eintragen (vom Hotel kopieren), um sie Taxifahrern zu zeigen.", "en": "Stays on this iPhone only. Tip: paste your hotel address in Thai to show taxi drivers.", "th": "เก็บไว้ในเครื่องนี้เท่านั้น"],
        "em_name": ["de": "Name", "en": "Name", "th": "ชื่อ"],
        "em_hotel": ["de": "Hotel / Adresse (am besten auf Thai)", "en": "Hotel / address (ideally in Thai)", "th": "โรงแรม / ที่อยู่"],
        "em_allergies": ["de": "Allergien", "en": "Allergies", "th": "แพ้"],
        "em_medical": ["de": "Medizinisches (Medikamente, Blutgruppe)", "en": "Medical (medication, blood type)", "th": "ข้อมูลทางการแพทย์"],
        "em_contact": ["de": "Notfallkontakt (Telefon)", "en": "Emergency contact (phone)", "th": "ผู้ติดต่อฉุกเฉิน"],
        "baht_calc": ["de": "Baht-Rechner", "en": "Baht calculator", "th": "เครื่องคิดเงินบาท"],
        "baht_amount": ["de": "Betrag in Baht", "en": "Amount in baht", "th": "จำนวนเงินบาท"],
        "baht_rate": ["de": "Kurs", "en": "Rate", "th": "อัตรา"],
        "baht_note": ["de": "Kurs selbst eintragen (z. B. vom Wechselschalter) – funktioniert ohne Internet.", "en": "Enter the rate yourself (e.g. from the exchange booth) – works offline.", "th": "กรอกอัตราเอง ใช้ได้แบบออฟไลน์"],
        "thai_speaker": ["de": "Partnersprache immer über den Lautsprecher", "en": "Partner language always through the speaker", "th": "ภาษาของคู่สนทนาออกลำโพงเสมอ"],
        "sec_privacy": ["de": "Datenschutz", "en": "Privacy", "th": "ความเป็นส่วนตัว"],
        "history_keep": ["de": "Verlauf aufbewahren", "en": "Keep conversation", "th": "เก็บบทสนทนา"],
        "history_none": ["de": "Nicht speichern", "en": "Don't save", "th": "ไม่บันทึก"],
        "history_1d": ["de": "1 Tag", "en": "1 day", "th": "1 วัน"],
        "history_7d": ["de": "7 Tage", "en": "7 days", "th": "7 วัน"],
        "history_30d": ["de": "30 Tage", "en": "30 days", "th": "30 วัน"],
        "history_forever": ["de": "Immer", "en": "Forever", "th": "ตลอดไป"],
        "history_note": ["de": "Der Verlauf liegt verschlüsselt nur auf diesem iPhone.", "en": "The conversation is stored encrypted on this iPhone only.", "th": "บทสนทนาถูกเก็บแบบเข้ารหัสในเครื่องนี้เท่านั้น"],
        "just_talk": ["de": "Sprich einfach", "en": "Just talk", "th": "พูดได้เลย"],
        "example_sentence": ["de": "Wo ist die Toilette?", "en": "Where is the toilet?", "th": "ห้องน้ำอยู่ที่ไหน"],
        "empty_example_fmt": ["de": "Sag z. B.: „%@“", "en": "Try saying: \"%@\"", "th": "ลองพูดว่า: \"%@\""],
        "empty_hint_pair": ["de": "%1$@ wird übersetzt in %2$@ und umgekehrt – und sofort vorgelesen.",
                            "en": "%1$@ is translated into %2$@ and back – and spoken right away.",
                            "th": "แปล%1$@เป็น%2$@ และกลับกัน แล้วพูดออกมาทันที"],
        "same_script_hint": ["de": "Beide Sprachen nutzen dieselbe Schrift – die App kann sie nicht sicher unterscheiden. Richtung oben per Tippen wählen.",
                             "en": "Both languages use the same script, so the app cannot tell them apart reliably. Tap above to choose the direction.",
                             "th": "ทั้งสองภาษาใช้ตัวอักษรแบบเดียวกัน แอปแยกไม่ได้แน่นอน แตะด้านบนเพื่อเลือกทิศทาง"],
        "paused_plain": ["de": "Pausiert", "en": "Paused", "th": "หยุดชั่วคราว"],
        "undo": ["de": "Rückgängig", "en": "Undo", "th": "เลิกทำ"],
        "clear_confirm": ["de": "Ganzen Verlauf leeren?", "en": "Clear the whole conversation?", "th": "ล้างบทสนทนาทั้งหมดหรือไม่?"],
        "cleared": ["de": "Verlauf geleert", "en": "Conversation cleared", "th": "ล้างบทสนทนาแล้ว"],
        "restored": ["de": "Verlauf wiederhergestellt", "en": "Conversation restored", "th": "กู้คืนบทสนทนาแล้ว"],
        "cellular_title": ["de": "Sprachmodell über Mobilfunk laden?", "en": "Download speech model over cellular?",
                           "th": "ดาวน์โหลดโมเดลเสียงผ่านเครือข่ายมือถือหรือไม่?"],
        "cellular_msg": ["de": "Für diese Sprache fehlt noch das Sprachmodell. Der einmalige Download kann groß sein und im Roaming Geld kosten. Besser im WLAN laden.",
                         "en": "The speech model for this language is not on the iPhone yet. The one-time download can be large and may cost money when roaming. Wi-Fi is better.",
                         "th": "ยังไม่มีโมเดลเสียงสำหรับภาษานี้ การดาวน์โหลดครั้งเดียวอาจมีขนาดใหญ่และเสียค่าโรมมิ่ง แนะนำให้ใช้ Wi-Fi"],
        "cellular_go": ["de": "Trotzdem laden", "en": "Download anyway", "th": "ดาวน์โหลดเลย"],
        "cellular_wait": ["de": "Später im WLAN", "en": "Later on Wi-Fi", "th": "ภายหลังผ่าน Wi-Fi"],
        "err_model_offline": ["de": "Das Sprachmodell muss einmalig geladen werden – dafür Internet (am besten WLAN) einschalten.",
                              "en": "The speech model has to be downloaded once – please connect to the internet (Wi-Fi is best).",
                              "th": "ต้องดาวน์โหลดโมเดลเสียงหนึ่งครั้ง – โปรดเชื่อมต่ออินเทอร์เน็ต (แนะนำ Wi-Fi)"],
        "err_recognizer": ["de": "Spracherkennung ausgefallen – bitte neu starten", "en": "Speech recognition stopped – please start again",
                           "th": "การรู้จำเสียงหยุดทำงาน – โปรดเริ่มใหม่"],
        "recognizer_restarted": ["de": "Spracherkennung neu gestartet", "en": "Speech recognition restarted", "th": "เริ่มการรู้จำเสียงใหม่แล้ว"],
        "err_no_network": ["de": "Kein Internet – nur Offline-Sprachpakete übersetzen ohne Netz", "en": "No internet – only offline language packs work without a connection",
                           "th": "ไม่มีอินเทอร์เน็ต – ใช้ได้เฉพาะชุดภาษาออฟไลน์"],
        "err_online_cooldown": ["de": "Online-Übersetzer gerade nicht erreichbar – gleich nochmal versuchen", "en": "Online translator unreachable right now – try again shortly",
                                "th": "ตัวแปลออนไลน์ไม่ตอบสนอง – ลองอีกครั้งในไม่ช้า"],
        "offline_hint": ["de": "Offline-Sprachpakete fehlen. Tippen, um sie zu laden (oder Online-Übersetzung erlauben).",
                         "en": "Offline language packs are missing. Tap to download them (or allow online translation).",
                         "th": "ไม่มีชุดภาษาออฟไลน์ แตะเพื่อดาวน์โหลด (หรืออนุญาตการแปลออนไลน์)"],
        "sec_langs": ["de": "Sprachen", "en": "Languages", "th": "ภาษา"],
        "lang_mine": ["de": "Meine Sprache", "en": "My language", "th": "ภาษาของฉัน"],
        "lang_partner": ["de": "Partnersprache", "en": "Partner language", "th": "ภาษาของคู่สนทนา"],
        "lang_download": ["de": "braucht Download", "en": "needs download", "th": "ต้องดาวน์โหลด"],
        "lang_note": ["de": "Angeboten wird nur, was dieses iPhone erkennen, übersetzen und vorlesen kann. ⬇︎ = Sprachmodell, Übersetzungspaket oder Stimme fehlt noch und wird einmalig geladen (Internet nötig). 🌐 = Apple übersetzt dieses Paar nicht auf dem Gerät – nur mit Online-Übersetzung. Thai-Extras (Höflichkeit, Baht, Notrufnummern, Satzbuch) gibt es nur mit Thai, Sprachbefehle nur mit Englisch im Paar.",
                      "en": "Only languages this iPhone can recognise, translate and speak are offered. ⬇︎ = speech model, translation pack or voice is still missing and will be downloaded once (internet needed). 🌐 = Apple cannot translate this pair on the device – online translation only. Thai extras (politeness, baht, emergency numbers, phrasebook) need Thai, voice commands need English in the pair.",
                      "th": "แสดงเฉพาะภาษาที่ iPhone นี้รู้จำ แปล และอ่านออกเสียงได้ ⬇︎ = ยังไม่มีโมเดลเสียง ชุดแปล หรือเสียงพูด ต้องดาวน์โหลดครั้งเดียว (ต้องใช้อินเทอร์เน็ต) 🌐 = แปลบนเครื่องไม่ได้ ต้องใช้การแปลออนไลน์ ฟังก์ชันภาษาไทยมีเฉพาะเมื่อมีภาษาไทย คำสั่งเสียงเฉพาะเมื่อมีภาษาอังกฤษ"],
        "lang_online_only": ["de": "nur online übersetzbar", "en": "online translation only", "th": "แปลได้เฉพาะออนไลน์"],
        "lang_unavailable": ["de": "Auf diesem iPhone nicht verfügbar", "en": "Not available on this iPhone", "th": "ไม่มีในเครื่องนี้"],
        "online_off_note": ["de": "Aus (Standard): Alles bleibt auf dem iPhone. An: Fehlt ein Offline-Paket, geht der Text an Google Translate (Ersatz: MyMemory). Die Spracherkennung läuft immer auf dem Gerät.",
                            "en": "Off (default): everything stays on the iPhone. On: if an offline pack is missing, the text is sent to Google Translate (fallback: MyMemory). Speech recognition always runs on the device.",
                            "th": "ปิด (ค่าเริ่มต้น): ทุกอย่างอยู่ในเครื่อง เปิด: หากไม่มีชุดภาษาออฟไลน์ ข้อความจะถูกส่งไปยัง Google Translate (สำรอง: MyMemory) การรู้จำเสียงทำงานบนเครื่องเสมอ"],
        "sos_title": ["de": "Notruf-Satz", "en": "Emergency phrase", "th": "ประโยคฉุกเฉิน"],
        "a11y_ready": ["de": "Übersetzung bereit", "en": "Translation ready", "th": "แปลเสร็จแล้ว"],
        "open_settings": ["de": "Einstellungen öffnen", "en": "Open Settings", "th": "เปิดการตั้งค่า"],
        "now_me": ["de": "Jetzt ich", "en": "My turn", "th": "ตาฉันพูด"],
        "answer_cards": ["de": "Antwortkarte", "en": "Answer card", "th": "การ์ดคำตอบ"],
        "back_label": ["de": "Rückübersetzung", "en": "Back-translation", "th": "แปลย้อนกลับ"],
        "back_deviates": ["de": "Achtung: Rückübersetzung weicht ab – Übersetzung prüfen", "en": "Careful: back-translation differs – check the translation", "th": "ระวัง: คำแปลย้อนกลับไม่ตรง – โปรดตรวจสอบคำแปล"],
        "back_check": ["de": "Rückübersetzung anzeigen", "en": "Show back-translation", "th": "แสดงคำแปลย้อนกลับ"],
        "back_check_note": ["de": "Rückübersetzung: Die Übersetzung wird auf dem iPhone zurückübersetzt und klein darunter gezeigt; ⚠️ markiert deutliche Abweichungen. Nur mit Offline-Paketen, dafür geht nichts ins Netz. Umschrift: Lesehilfe in Lateinschrift für Thai, Japanisch, Koreanisch und Chinesisch (automatisch, ungefähr).", "en": "Back-translation: the translation is translated back on the iPhone and shown small underneath; ⚠️ marks clear differences. Only with offline packs – nothing is sent online for it. Romanization: reading aid in Latin letters for Thai, Japanese, Korean and Chinese (automatic, approximate).", "th": "คำแปลย้อนกลับ: คำแปลจะถูกแปลกลับบน iPhone และแสดงตัวเล็กด้านล่าง ⚠️ แสดงเมื่อแตกต่างชัดเจน ใช้ได้เฉพาะเมื่อมีชุดภาษาออฟไลน์ ไม่มีการส่งข้อมูลออนไลน์ การถอดอักษร: ช่วยอ่านเป็นอักษรละตินสำหรับภาษาไทย ญี่ปุ่น เกาหลี และจีน (อัตโนมัติ โดยประมาณ)"],
        "show_roman": ["de": "Umschrift anzeigen", "en": "Show romanization", "th": "แสดงคำอ่านอักษรละติน"],
        "allergy_card": ["de": "Allergie-Karte", "en": "Allergy card", "th": "บัตรแจ้งแพ้อาหาร"],
        "allergy_show": ["de": "Allergie-Karte zeigen (%@)", "en": "Show allergy card (%@)", "th": "แสดงบัตรแจ้งแพ้อาหาร (%@)"],
        "allergy_note": ["de": "Feste, vorformulierte Warnsätze in der Partnersprache – sicherer als eine Freitext-Übersetzung. Für Sprachen ohne festen Satz: Englisch plus maschinelle Übersetzung. Ersetzt keine ärztliche Beratung.", "en": "Fixed, pre-written warning sentences in your partner's language – safer than translating free text. For languages without a fixed sentence: English plus machine translation. Not a substitute for medical advice.", "th": "ประโยคเตือนที่เขียนไว้แล้วในภาษาของคู่สนทนา ปลอดภัยกว่าการแปลข้อความอิสระ สำหรับภาษาที่ไม่มีประโยคสำเร็จรูป: ภาษาอังกฤษและการแปลด้วยเครื่อง ไม่สามารถใช้แทนคำแนะนำทางการแพทย์"],
        "em_blood": ["de": "Blutgruppe", "en": "Blood type", "th": "กรุ๊ปเลือด"],
        "em_insurance": ["de": "Versicherung / Notfallnummer", "en": "Insurance / emergency number", "th": "ประกัน / เบอร์ฉุกเฉิน"],
        "em_embassy": ["de": "Botschaft / Konsulat", "en": "Embassy / consulate", "th": "สถานทูต / สถานกงสุล"],
        "em_translate": ["de": "Allergien und Medizinisches übersetzen (%@)", "en": "Translate allergies and medical info (%@)", "th": "แปลข้อมูลการแพ้และข้อมูลทางการแพทย์ (%@)"],
        "machine_translated": ["de": "maschinell übersetzt – ungeprüft", "en": "machine-translated – not checked", "th": "แปลด้วยเครื่อง – ยังไม่ได้ตรวจสอบ"],
        "lock_history": ["de": "Verlauf mit Face ID sperren", "en": "Lock history with Face ID", "th": "ล็อกประวัติด้วย Face ID"],
        "lock_reason": ["de": "Gesprächsverlauf anzeigen", "en": "Show conversation history", "th": "แสดงประวัติการสนทนา"],
        "lock_hidden": ["de": "%d ältere Sätze gesperrt – zum Entsperren tippen", "en": "%d earlier sentences locked – tap to unlock", "th": "ล็อกประโยคก่อนหน้า %d ประโยค – แตะเพื่อปลดล็อก"],
        "privacy_overview": ["de": "Datenschutz-Übersicht", "en": "Privacy overview", "th": "ภาพรวมความเป็นส่วนตัว"],
        "pv_now": ["de": "Mit deinen Einstellungen", "en": "With your current settings", "th": "ตามการตั้งค่าปัจจุบันของคุณ"],
        "pv_local": ["de": "lokal", "en": "on device", "th": "ในเครื่อง"],
        "pv_net": ["de": "Internet", "en": "internet", "th": "อินเทอร์เน็ต"],
        "pv_speech": ["de": "Spracherkennung", "en": "Speech recognition", "th": "การรู้จำเสียง"],
        "pv_speech_d": ["de": "Läuft immer auf dem iPhone (Apple oder Whisper). Ton wird nie gespeichert oder gesendet.", "en": "Always runs on the iPhone (Apple or Whisper). Audio is never stored or sent.", "th": "ทำงานบน iPhone เสมอ (Apple หรือ Whisper) ไม่มีการบันทึกหรือส่งเสียง"],
        "pv_translate": ["de": "Übersetzung", "en": "Translation", "th": "การแปล"],
        "pv_translate_off": ["de": "Nur auf dem iPhone (Apple-Übersetzung mit Offline-Paketen). Fehlt ein Paket, erscheint ein Hinweis – nichts geht ins Netz.", "en": "Only on the iPhone (Apple Translation with offline packs). If a pack is missing you see a note – nothing is sent online.", "th": "บน iPhone เท่านั้น (Apple Translation พร้อมชุดภาษาออฟไลน์) หากไม่มีชุดภาษาจะแสดงคำแนะนำ ไม่มีการส่งข้อมูลออนไลน์"],
        "pv_translate_on": ["de": "Mit Offline-Paket auf dem iPhone. Fehlt es, geht der erkannte Text an Google Translate (Ersatz: MyMemory) – ohne Konto, aber außerhalb deines Geräts.", "en": "On the iPhone if the offline pack is installed. Otherwise the recognized text goes to Google Translate (fallback: MyMemory) – no account, but it leaves your device.", "th": "แปลบน iPhone หากมีชุดภาษาออฟไลน์ หากไม่มี ข้อความจะถูกส่งไปยัง Google Translate (สำรอง: MyMemory) ไม่ต้องมีบัญชี แต่ข้อมูลจะออกจากเครื่อง"],
        "pv_back_d": ["de": "Nur mit Offline-Paketen auf dem iPhone – geht nie ins Netz.", "en": "Only with offline packs on the iPhone – never sent online.", "th": "ใช้เฉพาะชุดภาษาออฟไลน์บน iPhone – ไม่ส่งออนไลน์"],
        "pv_history": ["de": "Verlauf und Favoriten", "en": "History and favorites", "th": "ประวัติและรายการโปรด"],
        "pv_history_d": ["de": "Nur auf diesem iPhone, durch die Geräteverschlüsselung geschützt. Aufbewahrung: %@.", "en": "Only on this iPhone, protected by device encryption. Kept: %@.", "th": "อยู่ใน iPhone เครื่องนี้เท่านั้น ป้องกันด้วยการเข้ารหัสของเครื่อง เก็บไว้: %@"],
        "pv_lock_on": ["de": "Ältere Sätze nur nach Face ID.", "en": "Earlier sentences only after Face ID.", "th": "ประโยคก่อนหน้าดูได้หลังใช้ Face ID เท่านั้น"],
        "pv_lock_off": ["de": "Face-ID-Sperre aus.", "en": "Face ID lock off.", "th": "ปิดการล็อกด้วย Face ID"],
        "pv_card_d": ["de": "Nur auf dem iPhone. „Übersetzen“ nutzt dieselbe Übersetzung wie oben (bei erlaubter Online-Übersetzung ggf. Google).", "en": "Only on the iPhone. \"Translate\" uses the same translation as above (with online translation allowed, possibly Google).", "th": "อยู่ใน iPhone เท่านั้น \"แปล\" ใช้การแปลแบบเดียวกับด้านบน (หากอนุญาตการแปลออนไลน์ อาจใช้ Google)"],
        "pv_models": ["de": "Sprachmodelle und Sprachpakete", "en": "Speech models and language packs", "th": "โมเดลเสียงและชุดภาษา"],
        "pv_models_d": ["de": "Einmaliger Download von Apple. Dabei wird nur das Modell geladen, kein Gesprächsinhalt gesendet.", "en": "One-time download from Apple. Only the model is downloaded; no conversation content is sent.", "th": "ดาวน์โหลดครั้งเดียวจาก Apple ดาวน์โหลดเฉพาะโมเดล ไม่มีการส่งเนื้อหาการสนทนา"],
        "pv_models_whisper": ["de": "Einmaliger Download: Apple-Modelle von Apple, Whisper-Modelle von Hugging Face (argmaxinc). Dabei wird kein Gesprächsinhalt gesendet.", "en": "One-time download: Apple models from Apple, Whisper models from Hugging Face (argmaxinc). No conversation content is sent.", "th": "ดาวน์โหลดครั้งเดียว: โมเดลของ Apple จาก Apple และโมเดล Whisper จาก Hugging Face (argmaxinc) ไม่มีการส่งเนื้อหาการสนทนา"],
        "pv_none": ["de": "Kein Konto, kein Tracking", "en": "No account, no tracking", "th": "ไม่มีบัญชี ไม่มีการติดตาม"],
        "pv_none_d": ["de": "Keine Anmeldung, keine Werbung, keine Analyse-Dienste. Geteilt oder kopiert wird nur, was du selbst auslöst.", "en": "No sign-in, no ads, no analytics. Only what you share or copy yourself leaves the app.", "th": "ไม่ต้องลงชื่อเข้าใช้ ไม่มีโฆษณา ไม่มีการวิเคราะห์ข้อมูล ข้อมูลจะออกจากแอปเฉพาะเมื่อคุณแชร์หรือคัดลอกเอง"],
        "pv_footer": ["de": "Dolmetscher ist eine Verständigungshilfe und ersetzt keine geprüfte Dolmetscherin – bei Arzt, Polizei oder Verträgen wichtige Punkte bitte bestätigen lassen.", "en": "Dolmetscher helps you communicate but is no substitute for a certified interpreter – with doctors, police or contracts, please have important points confirmed.", "th": "Dolmetscher ช่วยในการสื่อสาร แต่ไม่สามารถใช้แทนล่ามที่ได้รับการรับรอง – กับแพทย์ ตำรวจ หรือสัญญา โปรดยืนยันประเด็นสำคัญอีกครั้ง"],
    ]
}

func T(_ key: String) -> String {
    L10n.text(key, lang: L10n.lang) ?? L10n.text(key, lang: "en") ?? key
}

extension L10n {
    /// Text in einer bestimmten Sprache, nil wenn es ihn dort nicht gibt (kein Rückfall).
    static func text(_ key: String, lang: String) -> String? {
        table[key]?[lang] ?? extra[lang]?[key] ?? round4[key]?[lang] ?? round5[key]?[lang] ?? round6[key]?[lang] ?? round7[key]?[lang] ?? round8[key]?[lang] ?? round9[key]?[lang]
    }

    /// Alle Schlüssel (Grundtabelle, Runde 4 und 5).
    static var allKeys: Set<String> { Set(table.keys).union(round4.keys).union(round5.keys).union(round6.keys).union(round7.keys).union(round8.keys).union(round9.keys) }
}

/// Beobachtbarer Speicher für `L10n.lang`.
@Observable
final class UILanguage: @unchecked Sendable {
    static let shared = UILanguage()
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var stored = L10n.systemLang()

    var code: String {
        get {
            access(keyPath: \.code)
            return lock.withLock { stored }
        }
        set {
            withMutation(keyPath: \.code) { lock.withLock { stored = newValue } }
        }
    }
}
