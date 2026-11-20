// L10n+R26.swift – Texte der Runde 26 (Gruppenmodus, Aufnahmequelle, verschlüsselter Verlauf, experimentelle Schalter,
// Latenz-Verteilung, Hinweise der Engine). Eigene Tabelle neben L10n.swift; jede Zeile hat de, en und th
// (geprüft in tests/test_r26_mac.py). Zugriff: R26T.t / R26T.f.
import Foundation

enum R26T {
    static func t(_ key: String) -> String {
        guard let row = table[key] else { return key }
        return row[L.lang.rawValue] ?? row["en"] ?? key
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: L.lang == .de ? "de_DE" : "en_US"), arguments: args)
    }

    static let table: [String: [String: String]] = [
        // Gruppenmodus
        "grp_speaker": ["de": "Sprecher %d", "en": "Speaker %d", "th": "ผู้พูด %d"],
        "grp_toggle": ["de": "Gruppenmodus (Sprecher nummerieren)", "en": "Group mode (number the speakers)", "th": "โหมดกลุ่ม (ใส่หมายเลขผู้พูด)"],
        "grp_note": ["de": "Sprecher ohne Stimmprofil bekommen Nummern und Farben. Nummern gelten bis „Gespräch löschen“ oder Neustart der Engine.", "en": "Speakers without a voice profile get numbers and colors. Numbers last until “Clear conversation” or an engine restart.", "th": "ผู้พูดที่ไม่มีโปรไฟล์เสียงจะได้หมายเลขและสี หมายเลขใช้ได้จนกว่าจะล้างการสนทนาหรือรีสตาร์ตเอนจิน"],
        "grp_menu": ["de": "Sprecher", "en": "Speakers", "th": "ผู้พูด"],
        "grp_rename": ["de": "Sprecher umbenennen", "en": "Rename speaker", "th": "เปลี่ยนชื่อผู้พูด"],
        "grp_rename_title": ["de": "Name für %@", "en": "Name for %@", "th": "ชื่อสำหรับ %@"],
        "grp_rename_hint": ["de": "Leer lassen für die Nummer. Höchstens 24 Zeichen.", "en": "Leave empty to use the number. 24 characters at most.", "th": "เว้นว่างเพื่อใช้หมายเลข ไม่เกิน 24 ตัวอักษร"],
        "grp_rename_field": ["de": "Name", "en": "Name", "th": "ชื่อ"],
        "grp_rename_note": ["de": "Der Name gilt nur in der App; der Verlauf speichert „Sprecher N“.", "en": "The name applies in the app only; the history stores “Sprecher N”.", "th": "ชื่อนี้ใช้ในแอปเท่านั้น ประวัติเก็บเป็น “Sprecher N”"],
        "grp_unsupported": ["de": "Diese Engine kennt den Gruppenmodus nicht (bitte aktualisieren).", "en": "This engine does not know group mode (please update).", "th": "เอนจินนี้ไม่รู้จักโหมดกลุ่ม (โปรดอัปเดต)"],
        // Aufnahmequelle
        "src_title": ["de": "Aufnahmequelle", "en": "Recording source", "th": "แหล่งเสียงที่บันทึก"],
        "src_mic": ["de": "Mikrofon", "en": "Microphone", "th": "ไมโครโฟน"],
        "src_system": ["de": "Systemton (Loopback-Gerät)", "en": "System audio (loopback device)", "th": "เสียงระบบ (อุปกรณ์ลูปแบ็ก)"],
        "src_note": ["de": "Systemton braucht ein virtuelles Loopback-Gerät (z. B. BlackHole). Die Ausgabe der App darf nicht auf dieses Gerät gehen, sonst hört sie sich selbst.", "en": "System audio needs a virtual loopback device (for example BlackHole). Do not send the app's output to that device, or it hears itself.", "th": "เสียงระบบต้องมีอุปกรณ์ลูปแบ็กเสมือน (เช่น BlackHole) อย่าส่งเสียงออกของแอปไปที่อุปกรณ์นั้น ไม่เช่นนั้นจะได้ยินตัวเอง"],
        "src_unsupported": ["de": "Diese Engine kennt keine zweite Quelle (bitte aktualisieren).", "en": "This engine has no second source (please update).", "th": "เอนจินนี้ไม่มีแหล่งเสียงที่สอง (โปรดอัปเดต)"],
        "hint_system_audio": ["de": "Systemton aktiv: Die Ausgabe der App nicht auf das Loopback-Gerät legen.", "en": "System audio is on: do not route the app's output to the loopback device.", "th": "เปิดเสียงระบบอยู่: อย่าส่งเสียงออกของแอปไปที่อุปกรณ์ลูปแบ็ก"],
        "hint_mic_gap": ["de": "Mikrofon-Puffer übergelaufen – der folgende Satz kann unvollständig sein (%d×).", "en": "Microphone buffer overflowed – the next sentence may be incomplete (%d×).", "th": "บัฟเฟอร์ไมโครโฟนล้น – ประโยคถัดไปอาจไม่ครบ (%d ครั้ง)"],
        // Verlauf verschlüsseln
        "hpw_title": ["de": "Verlauf verschlüsseln", "en": "Encrypt history", "th": "เข้ารหัสประวัติ"],
        "hpw_toggle": ["de": "Verschlüsselten Verlauf verwenden", "en": "Use encrypted history", "th": "ใช้ประวัติที่เข้ารหัส"],
        "hpw_field": ["de": "Passwort für den Verlauf", "en": "History password", "th": "รหัสผ่านของประวัติ"],
        "hpw_saved": ["de": "Passwort im Schlüsselbund gespeichert", "en": "Password saved in the keychain", "th": "บันทึกรหัสผ่านใน Keychain แล้ว"],
        "hpw_missing": ["de": "Noch kein Passwort gespeichert – ohne Passwort bleibt der Verlauf unverschlüsselt.", "en": "No password saved yet – without one the history stays unencrypted.", "th": "ยังไม่ได้บันทึกรหัสผ่าน – หากไม่มี ประวัติจะไม่ถูกเข้ารหัส"],
        "hpw_invalid": ["de": "Passwort ungültig (leer, zu lang oder mit Zeilenumbruch).", "en": "Invalid password (empty, too long or with a line break).", "th": "รหัสผ่านไม่ถูกต้อง (ว่าง ยาวเกินไป หรือมีการขึ้นบรรทัดใหม่)"],
        "hpw_failed": ["de": "Passwort konnte nicht im Schlüsselbund gespeichert werden.", "en": "The password could not be saved in the keychain.", "th": "บันทึกรหัสผ่านใน Keychain ไม่ได้"],
        "hpw_remove": ["de": "Passwort entfernen", "en": "Remove password", "th": "ลบรหัสผ่าน"],
        "hpw_note_plain": ["de": "Die bisherige Klartext-Datei history.sqlite bleibt bestehen und wird nicht umgewandelt. Neue Sätze landen nur in der verschlüsselten Datei.", "en": "The existing plain-text file history.sqlite stays and is not converted. New sentences go only to the encrypted file.", "th": "ไฟล์ข้อความธรรมดา history.sqlite เดิมยังอยู่และไม่ถูกแปลง ประโยคใหม่จะเข้าไฟล์ที่เข้ารหัสเท่านั้น"],
        "hpw_note_lost": ["de": "Ein vergessenes Passwort lässt sich nicht zurücksetzen; der verschlüsselte Verlauf ist dann nicht mehr lesbar. Wirkt nach einem Neustart der Engine.", "en": "A forgotten password cannot be reset; the encrypted history is then unreadable. Takes effect after an engine restart.", "th": "รหัสผ่านที่ลืมกู้คืนไม่ได้ และประวัติที่เข้ารหัสจะอ่านไม่ได้อีก มีผลหลังรีสตาร์ตเอนจิน"],
        "hpw_clear_note": ["de": "„Verlauf löschen“ betrifft beide Dateien, solange das Passwort gespeichert und die Verschlüsselung an ist. Ohne Passwort wird nur die Klartext-Datei gelöscht.", "en": "“Clear history” affects both files while the password is saved and encryption is on. Without the password only the plain-text file is cleared.", "th": "“ล้างประวัติ” มีผลกับทั้งสองไฟล์เมื่อบันทึกรหัสผ่านและเปิดการเข้ารหัสอยู่ ถ้าไม่มีรหัสผ่านจะล้างเฉพาะไฟล์ข้อความธรรมดา"],
        "hpw_unsupported": ["de": "Diese Engine kennt keinen verschlüsselten Verlauf (bitte aktualisieren).", "en": "This engine has no encrypted history (please update).", "th": "เอนจินนี้ไม่รองรับประวัติที่เข้ารหัส (โปรดอัปเดต)"],
        // Experimentelle Schalter
        "exp_title": ["de": "Experimentell", "en": "Experimental", "th": "ทดลอง"],
        "exp_warn": ["de": "Achtung: Diese Schalter sind nicht gemessen. Sie können Text, Ton oder Reihenfolge der Sätze ändern und sind standardmäßig aus.", "en": "Careful: these switches are unmeasured. They can change the text, the sound or the order of sentences and are off by default.", "th": "คำเตือน: สวิตช์เหล่านี้ยังไม่ได้วัดผล อาจเปลี่ยนข้อความ เสียง หรือลำดับประโยค และปิดไว้เป็นค่าเริ่มต้น"],
        "exp_old_engine": ["de": "Die laufende Engine meldet keine Fähigkeiten – Schalter nicht verfügbar. Engine starten oder aktualisieren.", "en": "The running engine reports no capabilities – switches unavailable. Start or update the engine.", "th": "เอนจินที่ทำงานอยู่ไม่รายงานความสามารถ – ใช้สวิตช์ไม่ได้ เริ่มหรืออัปเดตเอนจิน"],
        "exp_not_supported": ["de": "Nicht in dieser Engine", "en": "Not in this engine", "th": "ไม่มีในเอนจินนี้"],
        "exp_llm_stream": ["de": "Claude streamen", "en": "Stream Claude replies", "th": "สตรีมคำตอบของ Claude"],
        "exp_llm_stream_note": ["de": "Misst die Zeit bis zum ersten Wort und vertont die erste Teilphrase vorab.", "en": "Measures time to the first token and pre-voices the first phrase.", "th": "วัดเวลาถึงคำแรกและสังเคราะห์เสียงวลีแรกล่วงหน้า"],
        "exp_llm_router": ["de": "Modell-Router", "en": "Model router", "th": "ตัวเลือกโมเดล"],
        "exp_llm_router_note": ["de": "Kurze Sätze bleiben bei Haiku, lange oder zahlenreiche gehen an Sonnet.", "en": "Short sentences stay on Haiku; long or number-heavy ones go to Sonnet.", "th": "ประโยคสั้นใช้ Haiku ประโยคยาวหรือมีตัวเลขมากใช้ Sonnet"],
        "exp_defer": ["de": "Zurückstellen", "en": "Defer", "th": "เลื่อนการแปล"],
        "exp_defer_note": ["de": "Stellt Sätze zurück, wenn gerade gesprochen wird; die Reihenfolge kann sich ändern.", "en": "Holds sentences back while speech is playing; the order can change.", "th": "พักประโยคไว้ขณะกำลังพูด ลำดับอาจเปลี่ยน"],
        "exp_parallel_alt": ["de": "Gegenprobe parallel", "en": "Parallel cross-check", "th": "ตรวจสอบภาษาแบบขนาน"],
        "exp_parallel_alt_note": ["de": "Startet die Erkennung in der anderen Sprache gleichzeitig (mehr Rechenlast).", "en": "Starts recognition in the other language at the same time (more CPU).", "th": "เริ่มจดจำเสียงในอีกภาษาพร้อมกัน (ใช้ CPU มากขึ้น)"],
        "exp_stt_prompt": ["de": "Namen als Erkennungs-Hinweis", "en": "Names as recognition hint", "th": "ใช้ชื่อเป็นคำใบ้การจดจำ"],
        "exp_stt_prompt_note": ["de": "Gemerkte Namen des Gesprächs helfen der Erkennung (kann Fehler verstärken).", "en": "Remembered names of the conversation guide recognition (can reinforce mistakes).", "th": "ชื่อที่จำไว้ในบทสนทนาช่วยการจดจำ (อาจทำให้ผิดซ้ำ)"],
        "exp_speak_numbers": ["de": "Thai-Zahlen als Wörter", "en": "Thai numbers as words", "th": "อ่านตัวเลขไทยเป็นคำ"],
        "exp_speak_numbers_note": ["de": "350 wird „สามร้อยห้าสิบ“; Telefon- und Kontonummern bleiben Ziffern.", "en": "350 is read as words; phone and account numbers stay digits.", "th": "350 อ่านเป็นคำ ส่วนเบอร์โทรและเลขบัญชียังอ่านเป็นตัวเลข"],
        // Latenz-Verteilung
        "lat_title": ["de": "Latenz über Sitzungen", "en": "Latency across sessions", "th": "ความหน่วงข้ามเซสชัน"],
        "lat_stt": ["de": "Erkennung", "en": "Recognition", "th": "การจดจำเสียง"],
        "lat_tr": ["de": "Übersetzung", "en": "Translation", "th": "การแปล"],
        "lat_sound": ["de": "Bis zum Ton", "en": "To first sound", "th": "ถึงเสียงแรก"],
        "lat_row": ["de": "%d Sätze · Median %@ · 95 %% %@", "en": "%d sentences · median %@ · 95%% %@", "th": "%d ประโยค · มัธยฐาน %@ · 95%% %@"],
        "lat_empty": ["de": "Noch keine Messwerte.", "en": "No measurements yet.", "th": "ยังไม่มีค่าวัด"],
        "lat_refresh": ["de": "Aktualisieren", "en": "Refresh", "th": "รีเฟรช"],
        "lat_need_engine": ["de": "Die Engine muss laufen.", "en": "The engine must be running.", "th": "ต้องให้เอนจินทำงานอยู่"],
    ]
}
