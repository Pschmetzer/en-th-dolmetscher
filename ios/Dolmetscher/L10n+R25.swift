// L10n+R25.swift – Texte der Runde 25 (Notrufnummern nach Sprache, Satzbuch ohne Thai). de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft.
import Foundation

extension L10n {
    static let round25: [String: [String: String]] = [
        "em_n_general": [
            "de": "Allgemeiner Notruf", "en": "General emergency",
            "th": "เหตุฉุกเฉินทั่วไป", "es": "Emergencias en general",
            "fr": "Urgences (général)", "ja": "緊急通報(共通)",
            "ko": "긴급 통합 신고", "zh-Hans": "综合紧急电话",
            "vi": "Khẩn cấp chung", "id": "Darurat umum"
        ],
        "em_n_police": [
            "de": "Polizei", "en": "Police",
            "th": "ตำรวจ", "es": "Policía",
            "fr": "Police", "ja": "警察",
            "ko": "경찰", "zh-Hans": "警察",
            "vi": "Công an", "id": "Polisi"
        ],
        "em_n_ambulance": [
            "de": "Rettungsdienst", "en": "Ambulance",
            "th": "รถพยาบาล", "es": "Ambulancia",
            "fr": "Ambulance", "ja": "救急",
            "ko": "구급", "zh-Hans": "急救",
            "vi": "Cấp cứu", "id": "Ambulans"
        ],
        "em_n_fire": [
            "de": "Feuerwehr", "en": "Fire brigade",
            "th": "ดับเพลิง", "es": "Bomberos",
            "fr": "Pompiers", "ja": "消防",
            "ko": "소방", "zh-Hans": "消防",
            "vi": "Cứu hỏa", "id": "Pemadam kebakaran"
        ],
        "em_n_fire_ambulance": [
            "de": "Feuerwehr und Rettung", "en": "Fire and ambulance",
            "th": "ดับเพลิงและรถพยาบาล", "es": "Bomberos y ambulancia",
            "fr": "Pompiers et ambulance", "ja": "消防・救急",
            "ko": "소방·구급", "zh-Hans": "消防和急救",
            "vi": "Cứu hỏa và cấp cứu", "id": "Pemadam dan ambulans"
        ],
        "em_n_header": [
            "de": "Notrufnummern der Partnersprache", "en": "Emergency numbers (partner's language)",
            "th": "เบอร์ฉุกเฉิน (ประเทศของภาษาคู่สนทนา)", "es": "Números de emergencia (idioma del interlocutor)",
            "fr": "Numéros d’urgence (langue de l’interlocuteur)", "ja": "緊急番号(相手の言語の国)",
            "ko": "긴급 번호(상대 언어 국가)", "zh-Hans": "紧急号码（对方语言所在国）",
            "vi": "Số khẩn cấp (nước của ngôn ngữ đối phương)", "id": "Nomor darurat (negara bahasa lawan bicara)"
        ],
        "em_n_note": [
            "de": "Richtwert nach Sprache, nicht nach Aufenthaltsort. Vor Ort prüfen; 112 funktioniert in vielen Ländern auch ohne SIM.", "en": "A guide by language, not by your location. Check locally; 112 works without a SIM in many countries.",
            "th": "อิงตามภาษา ไม่ใช่ตำแหน่งของคุณ โปรดตรวจสอบในพื้นที่ เบอร์ 112 ใช้ได้โดยไม่ต้องมีซิมในหลายประเทศ", "es": "Orientativo según el idioma, no tu ubicación. Compruébalo en el lugar; el 112 funciona sin SIM en muchos países.",
            "fr": "Indication selon la langue, pas votre position. Vérifiez sur place ; le 112 fonctionne sans SIM dans de nombreux pays.", "ja": "言語に基づく目安で、現在地ではありません。現地で確認してください。112は多くの国でSIMなしでも使えます。",
            "ko": "언어 기준이며 현재 위치 기준이 아닙니다. 현지에서 확인하세요. 112는 많은 나라에서 SIM 없이도 됩니다.", "zh-Hans": "仅按语言给出，不代表您所在位置。请当地核实；112在许多国家无SIM卡也可拨打。",
            "vi": "Chỉ theo ngôn ngữ, không theo vị trí của bạn. Hãy kiểm tra tại chỗ; 112 hoạt động không cần SIM ở nhiều nước.", "id": "Berdasarkan bahasa, bukan lokasi Anda. Periksa di tempat; 112 berfungsi tanpa SIM di banyak negara."
        ],
        "pb_machine_hint": [
            "de": "Automatisch übersetzt (nicht geprüft). Englische Sätze, übersetzt in die Partnersprache.", "en": "Machine-translated (unchecked). English phrases translated into the partner's language.",
            "th": "แปลอัตโนมัติ (ไม่ได้ตรวจ) วลีภาษาอังกฤษแปลเป็นภาษาของคู่สนทนา", "es": "Traducción automática (sin revisar). Frases en inglés traducidas al idioma del interlocutor.",
            "fr": "Traduction automatique (non vérifiée). Phrases anglaises traduites dans la langue de l’interlocuteur.", "ja": "自動翻訳(未確認)。英語のフレーズを相手の言語に翻訳します。",
            "ko": "자동 번역(미확인). 영어 문장을 상대 언어로 번역합니다.", "zh-Hans": "机器翻译（未核对）。英文短句译成对方语言。",
            "vi": "Dịch tự động (chưa kiểm tra). Câu tiếng Anh được dịch sang ngôn ngữ của đối phương.", "id": "Terjemahan otomatis (belum diperiksa). Frasa Inggris diterjemahkan ke bahasa lawan bicara."
        ],
        "pb_machine_row": [
            "de": "wird automatisch übersetzt", "en": "translated automatically",
            "th": "แปลอัตโนมัติ", "es": "se traduce automáticamente",
            "fr": "traduit automatiquement", "ja": "自動翻訳されます",
            "ko": "자동 번역됩니다", "zh-Hans": "自动翻译",
            "vi": "dịch tự động", "id": "diterjemahkan otomatis"
        ],
        "em_n_unknown": [
            "de": "Für diese Sprache zeige ich keine Nummer an. Vor Ort nach der örtlichen Notrufnummer fragen; 112 funktioniert in vielen Ländern, aber nicht überall.", "en": "No verified number for this language. Ask locally for the emergency number; 112 works in many countries, but not everywhere.",
            "th": "ไม่มีเบอร์ที่ยืนยันสำหรับภาษานี้ โปรดสอบถามเบอร์ฉุกเฉินในพื้นที่ 112 ใช้ได้ในหลายประเทศ แต่ไม่ทุกที่", "es": "No muestro un número verificado para este idioma. Pregunta localmente; el 112 funciona en muchos países, pero no en todos.",
            "fr": "Aucun numéro vérifié pour cette langue. Renseignez-vous sur place ; le 112 fonctionne dans de nombreux pays, mais pas partout.", "ja": "この言語では確認済みの番号を表示しません。現地で緊急番号を確認してください。112は多くの国で使えますが、すべてではありません。",
            "ko": "이 언어에는 확인된 번호가 없습니다. 현지에서 긴급 번호를 확인하세요. 112는 많은 나라에서 되지만 모든 곳은 아닙니다.", "zh-Hans": "此语言没有已核实的号码。请当地询问紧急号码；112在许多国家可用，但并非处处可用。",
            "vi": "Không có số đã xác minh cho ngôn ngữ này. Hãy hỏi số khẩn cấp tại chỗ; 112 dùng được ở nhiều nước nhưng không phải mọi nơi.", "id": "Tidak ada nomor terverifikasi untuk bahasa ini. Tanyakan nomor darurat setempat; 112 berfungsi di banyak negara, tetapi tidak di semua tempat."
        ],
        "cellular_title_packs": [
            "de": "Sprachpakete über Mobilfunk laden?", "en": "Download language packs over mobile data?",
            "th": "ดาวน์โหลดชุดภาษาผ่านข้อมูลมือถือ?", "es": "¿Descargar paquetes de idioma con datos móviles?",
            "fr": "Télécharger les packs de langue en données mobiles ?", "ja": "モバイルデータで言語パックをダウンロードしますか?",
            "ko": "모바일 데이터로 언어 팩을 다운로드할까요?", "zh-Hans": "要用移动数据下载语言包吗？",
            "vi": "Tải gói ngôn ngữ bằng dữ liệu di động?", "id": "Unduh paket bahasa lewat data seluler?"
        ],
        "cellular_msg_packs": [
            "de": "Mobilfunk oder Hotspot ist aktiv. Sprachpakete sind groß (oft mehrere hundert MB) und können Roaming-Kosten verursachen.", "en": "Mobile data or a hotspot is active. Language packs are large (often several hundred MB) and may cause roaming charges.",
            "th": "กำลังใช้ข้อมูลมือถือหรือฮอตสปอต ชุดภาษามีขนาดใหญ่ (มักหลายร้อย MB) และอาจมีค่าโรมมิ่ง", "es": "Hay datos móviles o punto de acceso activos. Los paquetes son grandes (a menudo cientos de MB) y pueden generar costes de roaming.",
            "fr": "Données mobiles ou point d’accès actifs. Les packs sont volumineux (souvent plusieurs centaines de Mo) et peuvent entraîner des frais d’itinérance.", "ja": "モバイルデータまたはテザリング中です。言語パックは大きく(数百MBのことも)、ローミング料金がかかる場合があります。",
            "ko": "모바일 데이터 또는 핫스팟 사용 중입니다. 언어 팩은 용량이 크고(수백 MB) 로밍 요금이 발생할 수 있습니다.", "zh-Hans": "正在使用移动数据或热点。语言包较大（常达数百MB），可能产生漫游费用。",
            "vi": "Đang dùng dữ liệu di động hoặc điểm phát sóng. Gói ngôn ngữ lớn (thường vài trăm MB) và có thể phát sinh phí chuyển vùng.", "id": "Data seluler atau hotspot aktif. Paket bahasa besar (sering ratusan MB) dan bisa dikenai biaya roaming."
        ],
        "pod_title": [
            "de": "Satz des Tages", "en": "Phrase of the day",
            "th": "ประโยคประจำวัน", "es": "Frase del día",
            "fr": "Phrase du jour", "ja": "今日のフレーズ",
            "ko": "오늘의 문장", "zh-Hans": "每日一句",
            "vi": "Câu của ngày", "id": "Frasa hari ini"
        ],
        "pod_toggle": [
            "de": "Satz des Tages (9 Uhr, lokal)", "en": "Phrase of the day (9 am, local)",
            "th": "ประโยคประจำวัน (9 โมง ในเครื่อง)", "es": "Frase del día (9:00, local)",
            "fr": "Phrase du jour (9 h, local)", "ja": "今日のフレーズ(9時・端末内)",
            "ko": "오늘의 문장(오전 9시, 기기 내)", "zh-Hans": "每日一句（9点，本地）",
            "vi": "Câu của ngày (9 giờ, trên máy)", "id": "Frasa hari ini (jam 9, lokal)"
        ],
        "pod_denied": [
            "de": "Benachrichtigungen sind nicht erlaubt (Einstellungen)", "en": "Notifications are not allowed (Settings)",
            "th": "ไม่ได้อนุญาตการแจ้งเตือน (การตั้งค่า)", "es": "Las notificaciones no están permitidas (Ajustes)",
            "fr": "Notifications non autorisées (Réglages)", "ja": "通知が許可されていません(設定)",
            "ko": "알림이 허용되지 않았습니다(설정)", "zh-Hans": "未允许通知（设置）",
            "vi": "Thông báo chưa được cho phép (Cài đặt)", "id": "Notifikasi tidak diizinkan (Pengaturan)"
        ],
        "sc_now": [
            "de": "Jetzt passend", "en": "Right now",
            "th": "เหมาะกับตอนนี้", "es": "Ahora",
            "fr": "Maintenant", "ja": "今おすすめ",
            "ko": "지금 추천", "zh-Hans": "当前推荐",
            "vi": "Phù hợp lúc này", "id": "Cocok sekarang"
        ],
    ]
}
