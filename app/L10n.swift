// Oberflächensprache: Deutsch, English, ไทย – umschaltbar in der App.
import Foundation

enum UILang: String, CaseIterable, Identifiable {
    case th, en, de
    var id: String { rawValue }
    var label: String { ["th": "🇹🇭 ไทย", "en": "🇬🇧 English", "de": "🇩🇪 Deutsch"][rawValue]! }
}

enum L {
    static var lang: UILang {
        UILang(rawValue: UserDefaults.standard.string(forKey: "uiLang") ?? "") ?? .de
    }

    /// Text in der gewählten Oberflächensprache (oder einer erzwungenen, z. B. Thai im Profil-Assistenten).
    static func t(_ key: String, _ forced: UILang? = nil) -> String {
        let l = forced ?? lang
        guard let row = table[key] else { return key }
        return row[l.rawValue] ?? row["en"] ?? key
    }

    static let table: [String: [String: String]] = [
        // Hauptfenster
        "start": ["de": "Start", "en": "Start", "th": "เริ่ม"],
        "stop": ["de": "Stopp", "en": "Stop", "th": "หยุด"],
        "stopped": ["de": "Gestoppt", "en": "Stopped", "th": "หยุดแล้ว"],
        "starting": ["de": "Starte …", "en": "Starting …", "th": "กำลังเริ่ม …"],
        "loading": ["de": "Lade Sprachmodell …", "en": "Loading speech model …", "th": "กำลังโหลดโมเดลเสียง …"],
        "ready": ["de": "Modell geladen", "en": "Model loaded", "th": "โหลดโมเดลแล้ว"],
        "listening": ["de": "🎙 Hört zu – einfach Englisch oder Thai sprechen",
                      "en": "🎙 Listening – just speak English or Thai",
                      "th": "🎙 กำลังฟัง – พูดภาษาไทยหรืออังกฤษได้เลย"],
        "paused": ["de": "⏸ Pausiert – sag „Translator, resume“", "en": "⏸ Paused – say \"Translator, resume\"",
                   "th": "⏸ หยุดชั่วคราว – พูดว่า \"Translator, resume\""],
        "hearing": ["de": "👂 Höre …", "en": "👂 Hearing …", "th": "👂 กำลังฟัง …"],
        "thinking": ["de": "⏳ Übersetze …", "en": "⏳ Translating …", "th": "⏳ กำลังแปล …"],
        "speaking": ["de": "🔊 Spricht …", "en": "🔊 Speaking …", "th": "🔊 กำลังพูด …"],
        "dropped": ["de": "🤷 Nicht verstanden – bitte lauter oder länger sprechen",
                    "en": "🤷 Didn't catch that – please speak louder or longer",
                    "th": "🤷 ไม่ได้ยินชัด – กรุณาพูดดังขึ้นหรือยาวขึ้น"],
        "ended": ["de": "Engine beendet", "en": "Engine stopped", "th": "เครื่องแปลหยุดทำงาน"],
        "nomic": ["de": "Kein Mikrofon-Zugriff – Systemeinstellungen → Datenschutz → Mikrofon",
                  "en": "No microphone access – System Settings → Privacy → Microphone",
                  "th": "ไม่มีสิทธิ์ใช้ไมโครโฟน – การตั้งค่าระบบ → ความเป็นส่วนตัว → ไมโครโฟน"],
        "read_aloud": ["de": "Vorlesen", "en": "Read aloud", "th": "อ่านออกเสียง"],
        "not_translated": ["de": "nicht übersetzt", "en": "not translated", "th": "ไม่ได้แปล"],
        "fast": ["de": "Schnell", "en": "Fast", "th": "เร็ว"],
        "normal": ["de": "Normal", "en": "Normal", "th": "ปกติ"],
        "best": ["de": "Beste Qualität", "en": "Best quality", "th": "คุณภาพดีที่สุด"],
        "only_en": ["de": "🇬🇧 nur EN", "en": "🇬🇧 EN only", "th": "🇬🇧 อังกฤษเท่านั้น"],
        "only_th": ["de": "🇹🇭 nur TH", "en": "🇹🇭 TH only", "th": "🇹🇭 ไทยเท่านั้น"],
        "clear": ["de": "Verlauf leeren", "en": "Clear conversation", "th": "ล้างบทสนทนา"],
        "empty": ["de": "Start drücken und einfach sprechen.\nEnglisch wird auf Thai übersetzt, Thai auf Englisch.",
                  "en": "Press Start and just talk.\nEnglish is translated into Thai, Thai into English.",
                  "th": "กด \"เริ่ม\" แล้วพูดได้เลย\nภาษาไทยจะถูกแปลเป็นภาษาอังกฤษ และภาษาอังกฤษเป็นภาษาไทย"],
        "commands_hint": ["de": "Sprachbefehle: „Translator, pause / resume / repeat / slower / louder / English off / help“",
                          "en": "Voice commands: \"Translator, pause / resume / repeat / slower / louder / English off / help\"",
                          "th": "คำสั่งเสียง (ภาษาอังกฤษ): \"Translator, pause / resume / repeat\""],
        "profiles": ["de": "Stimmprofile", "en": "Voice profiles", "th": "โปรไฟล์เสียง"],
        "ui_language": ["de": "Sprache der App", "en": "App language", "th": "ภาษาของแอป"],

        // Profile
        "profiles_intro": ["de": "Mit einem Stimmprofil erkennt die App, wer spricht, wählt die richtige Sprache und versteht eigene Wörter (Namen, Orte) besser. Die Daten bleiben auf diesem Mac.",
                           "en": "With a voice profile the app knows who is speaking, picks the right language and understands your own words (names, places) better. The data stays on this Mac.",
                           "th": "เมื่อมีโปรไฟล์เสียง แอปจะรู้ว่าใครกำลังพูด เลือกภาษาได้ถูกต้อง และเข้าใจคำเฉพาะของคุณ (ชื่อ สถานที่) ได้ดีขึ้น ข้อมูลจะเก็บไว้ในเครื่อง Mac นี้เท่านั้น"],
        "no_profiles": ["de": "Noch keine Profile.", "en": "No profiles yet.", "th": "ยังไม่มีโปรไฟล์"],
        "new_profile": ["de": "Neues Profil", "en": "New profile", "th": "สร้างโปรไฟล์ใหม่"],
        "name": ["de": "Name", "en": "Name", "th": "ชื่อ"],
        "speaks": ["de": "Spricht", "en": "Speaks", "th": "พูดภาษา"],
        "thai": ["de": "Thai", "en": "Thai", "th": "ไทย"],
        "english": ["de": "Englisch", "en": "English", "th": "อังกฤษ"],
        "record": ["de": "Aufnahme starten", "en": "Start recording", "th": "เริ่มบันทึกเสียง"],
        "cancel": ["de": "Abbrechen", "en": "Cancel", "th": "ยกเลิก"],
        "close": ["de": "Schließen", "en": "Close", "th": "ปิด"],
        "delete": ["de": "Löschen", "en": "Delete", "th": "ลบ"],
        "delete_confirm": ["de": "Profil wirklich löschen?", "en": "Really delete this profile?", "th": "ต้องการลบโปรไฟล์นี้ใช่ไหม"],
        "redo": ["de": "Neu aufnehmen", "en": "Record again", "th": "บันทึกใหม่"],
        "vocab": ["de": "Eigene Wörter (kommagetrennt): Namen, Firmen, Orte …",
                  "en": "Own words (comma-separated): names, companies, places …",
                  "th": "คำเฉพาะ (คั่นด้วยจุลภาค): ชื่อคน บริษัท สถานที่ …"],
        "save": ["de": "Speichern", "en": "Save", "th": "บันทึก"],
        "understood": ["de": "verstanden", "en": "understood", "th": "เข้าใจ"],
        "read_this": ["de": "Bitte diesen Satz laut und normal vorlesen:", "en": "Please read this sentence aloud, normally:",
                      "th": "กรุณาอ่านประโยคนี้ออกเสียงตามปกติ:"],
        "sentence": ["de": "Satz", "en": "Sentence", "th": "ประโยค"],
        "of": ["de": "von", "en": "of", "th": "จาก"],
        "heard": ["de": "Gehört:", "en": "Heard:", "th": "ได้ยินว่า:"],
        "again": ["de": "🔁 Bitte den Satz noch einmal vorlesen.", "en": "🔁 Please read the sentence once more.", "th": "🔁 กรุณาอ่านประโยคนี้อีกครั้ง"],
        "prep": ["de": "Wird vorbereitet … (beim ersten Mal bis zu 1 Minute)", "en": "Preparing … (up to 1 minute the first time)",
                 "th": "กำลังเตรียม … (ครั้งแรกอาจใช้เวลาถึง 1 นาที)"],
        "done": ["de": "Fertig! Profil gespeichert.", "en": "Done! Profile saved.", "th": "เสร็จแล้ว! บันทึกโปรไฟล์เรียบร้อย"],
        "failed": ["de": "Hat nicht geklappt:", "en": "That didn't work:", "th": "ไม่สำเร็จ:"],
        "tip_quiet": ["de": "Tipp: nah am Mac sprechen, ruhige Umgebung.", "en": "Tip: speak close to the Mac, in a quiet place.",
                      "th": "คำแนะนำ: พูดใกล้ๆ เครื่อง Mac ในที่เงียบ"],
        "speaker_unknown": ["de": "Unbekannt", "en": "Unknown", "th": "ไม่ทราบ"],
    ]
}
