// WidgetTexts.swift – die wenigen Texte der Widget-Erweiterung in allen 10 Oberflächensprachen.
// Die Erweiterung kennt die App-Einstellung „Sprache der App“ nicht (kein App Group): sie folgt der Systemsprache.
import Foundation

enum WidgetTexts {
    static let languages = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]

    static let table: [String: [String: String]] = [
        "w_phrases": ["de": "Schnellsätze", "en": "Quick phrases", "th": "ประโยคด่วน", "es": "Frases rápidas", "fr": "Phrases rapides",
                      "ja": "クイックフレーズ", "ko": "빠른 문장", "zh-Hans": "快捷短句", "vi": "Câu nhanh", "id": "Frasa cepat"],
        "w_phrases_d": ["de": "Tippen, und Dolmetscher sagt den Satz auf Thai.", "en": "Tap and Dolmetscher says the phrase in Thai.",
                        "th": "แตะแล้ว Dolmetscher จะพูดประโยคเป็นภาษาไทย", "es": "Toca y Dolmetscher dice la frase en tailandés.",
                        "fr": "Touchez et Dolmetscher dit la phrase en thaï.", "ja": "タップするとDolmetscherがタイ語で話します。",
                        "ko": "탭하면 Dolmetscher가 태국어로 말합니다.", "zh-Hans": "轻点后 Dolmetscher 会用泰语说出这句话。",
                        "vi": "Chạm để Dolmetscher nói câu bằng tiếng Thái.", "id": "Ketuk dan Dolmetscher mengucapkan frasa dalam bahasa Thai."],
        "w_start": ["de": "Dolmetscher starten", "en": "Start Dolmetscher", "th": "เริ่ม Dolmetscher", "es": "Iniciar Dolmetscher",
                    "fr": "Lancer Dolmetscher", "ja": "Dolmetscherを開始", "ko": "Dolmetscher 시작", "zh-Hans": "启动 Dolmetscher",
                    "vi": "Bắt đầu Dolmetscher", "id": "Mulai Dolmetscher"],
        "w_start_d": ["de": "Öffnet Dolmetscher und hört sofort zu.", "en": "Opens Dolmetscher and starts listening.",
                      "th": "เปิด Dolmetscher และเริ่มฟังทันที", "es": "Abre Dolmetscher y empieza a escuchar.",
                      "fr": "Ouvre Dolmetscher et commence à écouter.", "ja": "Dolmetscherを開いてすぐに聞き取りを始めます。",
                      "ko": "Dolmetscher를 열고 바로 듣기 시작합니다.", "zh-Hans": "打开 Dolmetscher 并立即开始聆听。",
                      "vi": "Mở Dolmetscher và bắt đầu nghe ngay.", "id": "Membuka Dolmetscher dan langsung mendengarkan."],
        "w_swap": ["de": "Sprachen tauschen", "en": "Swap languages", "th": "สลับภาษา", "es": "Intercambiar idiomas", "fr": "Inverser les langues",
                   "ja": "言語を入れ替え", "ko": "언어 바꾸기", "zh-Hans": "互换语言", "vi": "Đổi chiều ngôn ngữ", "id": "Tukar bahasa"],
        "w_swap_d": ["de": "Tauscht deine Sprache und die Partnersprache.", "en": "Swaps your language and your partner's language.",
                     "th": "สลับภาษาของคุณกับภาษาของคู่สนทนา", "es": "Intercambia tu idioma y el de tu interlocutor.",
                     "fr": "Inverse votre langue et celle de votre interlocuteur.", "ja": "自分の言語と相手の言語を入れ替えます。",
                     "ko": "내 언어와 상대 언어를 바꿉니다.", "zh-Hans": "互换你的语言和对方的语言。",
                     "vi": "Đổi chiều ngôn ngữ của bạn và của người đối thoại.", "id": "Menukar bahasa Anda dan bahasa lawan bicara."],
        "w_speak_last": ["de": "Letzte Übersetzung vorlesen", "en": "Speak last translation", "th": "อ่านคำแปลล่าสุด", "es": "Leer la última traducción",
                         "fr": "Lire la dernière traduction", "ja": "最後の翻訳を読み上げ", "ko": "마지막 번역 읽기", "zh-Hans": "朗读最后一条翻译",
                         "vi": "Đọc bản dịch gần nhất", "id": "Bacakan terjemahan terakhir"],
        "w_speak_last_d": ["de": "Öffnet Dolmetscher und liest die letzte Übersetzung noch einmal vor.", "en": "Opens Dolmetscher and reads the last translation out loud again.",
                           "th": "เปิด Dolmetscher และอ่านคำแปลล่าสุดอีกครั้ง", "es": "Abre Dolmetscher y vuelve a leer la última traducción.",
                           "fr": "Ouvre Dolmetscher et relit la dernière traduction à voix haute.", "ja": "Dolmetscherを開いて最後の翻訳をもう一度読み上げます。",
                           "ko": "Dolmetscher를 열고 마지막 번역을 다시 읽어 줍니다.", "zh-Hans": "打开 Dolmetscher 并再次朗读最后一条翻译。",
                           "vi": "Mở Dolmetscher và đọc lại bản dịch gần nhất.", "id": "Membuka Dolmetscher dan membacakan lagi terjemahan terakhir."],
        "w_stop": ["de": "Stopp", "en": "Stop", "th": "หยุด", "es": "Detener", "fr": "Arrêter", "ja": "停止", "ko": "중지",
                   "zh-Hans": "停止", "vi": "Dừng", "id": "Berhenti"],
        "w_live": ["de": "Zuhören", "en": "Listening", "th": "การฟัง", "es": "Escucha", "fr": "Écoute", "ja": "聞き取り",
                   "ko": "듣기", "zh-Hans": "聆听", "vi": "Đang nghe", "id": "Mendengarkan"],
        "w_live_d": ["de": "Letzter Satz und Mikrofonstatus auf dem Sperrbildschirm.", "en": "Last sentence and microphone status on the Lock Screen.",
                     "th": "ประโยคล่าสุดและสถานะไมโครโฟนบนหน้าจอล็อก", "es": "Última frase y estado del micrófono en la pantalla bloqueada.",
                     "fr": "Dernière phrase et état du micro sur l’écran verrouillé.", "ja": "ロック画面に最後の文とマイクの状態を表示します。",
                     "ko": "잠금 화면에 마지막 문장과 마이크 상태를 표시합니다.", "zh-Hans": "在锁定屏幕上显示最后一句和麦克风状态。",
                     "vi": "Câu cuối và trạng thái micrô trên màn hình khóa.", "id": "Kalimat terakhir dan status mikrofon di Layar Terkunci."],
        "w_hidden": ["de": "Sätze erst nach dem Entsperren", "en": "Sentences only after unlocking", "th": "แสดงประโยคหลังปลดล็อกเท่านั้น",
                     "es": "Frases solo tras desbloquear", "fr": "Phrases visibles après déverrouillage", "ja": "ロック解除後に文を表示",
                     "ko": "잠금 해제 후에만 문장 표시", "zh-Hans": "解锁后才显示句子", "vi": "Chỉ hiện câu sau khi mở khóa",
                     "id": "Kalimat tampil setelah membuka kunci"],
        "w_waiting": ["de": "Noch kein Satz – einfach sprechen", "en": "No sentence yet – just speak", "th": "ยังไม่มีประโยค – พูดได้เลย",
                      "es": "Aún no hay frases – habla sin más", "fr": "Pas encore de phrase – parlez", "ja": "まだ文はありません – 話してください",
                      "ko": "아직 문장이 없습니다 – 말씀하세요", "zh-Hans": "还没有句子 – 直接说话吧", "vi": "Chưa có câu nào – cứ nói",
                      "id": "Belum ada kalimat – bicara saja"],
        "w_stale": ["de": "Stand evtl. veraltet – App öffnen", "en": "May be out of date – open the app", "th": "ข้อมูลอาจไม่เป็นปัจจุบัน – เปิดแอป",
                    "es": "Puede estar desactualizado: abre la app", "fr": "Peut être obsolète – ouvrez l’app", "ja": "情報が古い可能性があります – アプリを開く",
                    "ko": "오래된 정보일 수 있음 – 앱 열기", "zh-Hans": "可能已过期 – 请打开应用", "vi": "Có thể đã cũ – hãy mở ứng dụng",
                    "id": "Mungkin kedaluwarsa – buka aplikasi"],
        "w_pair_a11y": ["de": "Englisch nach Thai", "en": "English to Thai", "th": "อังกฤษเป็นไทย", "es": "Inglés a tailandés", "fr": "Anglais vers thaï",
                           "ja": "英語からタイ語へ", "ko": "영어에서 태국어로", "zh-Hans": "英语到泰语", "vi": "Tiếng Anh sang tiếng Thái", "id": "Inggris ke Thai"],
        "w_empty": ["de": "Satzbuch nicht verfügbar – Dolmetscher öffnen", "en": "Phrasebook unavailable – open Dolmetscher", "th": "ไม่มีวลีให้ใช้ – เปิด Dolmetscher", "es": "Frases no disponibles: abre Dolmetscher", "fr": "Phrases indisponibles – ouvrez Dolmetscher",
                       "ja": "フレーズを読み込めません – Dolmetscherを開く", "ko": "문장을 불러올 수 없음 – Dolmetscher 열기", "zh-Hans": "无法加载短句 – 请打开 Dolmetscher", "vi": "Không có câu nào – hãy mở Dolmetscher", "id": "Frasa tidak tersedia – buka Dolmetscher"],
        "w_say_hint": ["de": "Öffnet Dolmetscher und spricht den Satz", "en": "Opens Dolmetscher and speaks the phrase", "th": "เปิด Dolmetscher และพูดประโยคนี้", "es": "Abre Dolmetscher y dice la frase", "fr": "Ouvre Dolmetscher et dit la phrase",
                          "ja": "Dolmetscherを開いて文を読み上げます", "ko": "Dolmetscher를 열고 문장을 말합니다", "zh-Hans": "打开 Dolmetscher 并说出这句话", "vi": "Mở Dolmetscher và nói câu này", "id": "Membuka Dolmetscher dan mengucapkan frasa"],
        "w_listen": ["de": "Zuhören", "en": "Listening", "th": "ฟัง", "es": "Escuchar", "fr": "Écouter", "ja": "聞き取り", "ko": "듣기",
                     "zh-Hans": "聆听", "vi": "Nghe", "id": "Mendengarkan"],
        "w_listen_d": ["de": "Schaltet das Zuhören von Dolmetscher ein oder aus.", "en": "Turns Dolmetscher listening on or off.",
                       "th": "เปิดหรือปิดการฟังของ Dolmetscher", "es": "Activa o desactiva la escucha de Dolmetscher.",
                       "fr": "Active ou désactive l’écoute de Dolmetscher.", "ja": "Dolmetscherの聞き取りをオン／オフします。",
                       "ko": "Dolmetscher 듣기를 켜거나 끕니다.", "zh-Hans": "开启或关闭 Dolmetscher 聆听。",
                       "vi": "Bật hoặc tắt chế độ nghe của Dolmetscher.", "id": "Menyalakan atau mematikan mode dengar Dolmetscher."],
        "w_emergency": ["de": "Notfall", "en": "Emergency", "th": "ฉุกเฉิน", "es": "Emergencia", "fr": "Urgence", "ja": "緊急", "ko": "긴급",
                        "zh-Hans": "紧急", "vi": "Khẩn cấp", "id": "Darurat"],
        "w_emergency_d": ["de": "Öffnet Notfallkarte und Notrufnummern.", "en": "Opens the emergency card and emergency numbers.",
                          "th": "เปิดบัตรฉุกเฉินและเบอร์ฉุกเฉิน", "es": "Abre la tarjeta y los números de emergencia.",
                          "fr": "Ouvre la carte et les numéros d’urgence.", "ja": "緊急カードと緊急電話番号を開きます。",
                          "ko": "응급 카드와 긴급 전화번호를 엽니다.", "zh-Hans": "打开紧急卡片和紧急电话。",
                          "vi": "Mở thẻ khẩn cấp và số khẩn cấp.", "id": "Membuka kartu darurat dan nomor darurat."],
        "w_taxi": ["de": "Taxi-Karte", "en": "Taxi card", "th": "บัตรแท็กซี่", "es": "Tarjeta de taxi", "fr": "Carte taxi", "ja": "タクシーカード",
                   "ko": "택시 카드", "zh-Hans": "出租车卡片", "vi": "Thẻ taxi", "id": "Kartu taksi"],
        "w_taxi_d": ["de": "Öffnet die Taxi-Sätze in großer Thai-Schrift.", "en": "Opens the taxi phrases in large Thai script.",
                     "th": "เปิดประโยคแท็กซี่ตัวอักษรไทยขนาดใหญ่", "es": "Abre las frases de taxi en tailandés grande.",
                     "fr": "Ouvre les phrases de taxi en grand thaï.", "ja": "タクシー用の文をタイ語で大きく表示します。",
                     "ko": "택시 문장을 큰 태국어로 엽니다.", "zh-Hans": "以大号泰文打开出租车用语。",
                     "vi": "Mở các câu đi taxi bằng chữ Thái cỡ lớn.", "id": "Membuka frasa taksi dengan huruf Thai besar."],
    ]

    /// Erste bevorzugte Systemsprache, die es gibt; sonst Englisch.
    static var lang: String {
        for p in Locale.preferredLanguages {
            if p.hasPrefix("zh-Hans") || p.hasPrefix("zh-CN") { return "zh-Hans" }
            let code = String(p.prefix { $0 != "-" && $0 != "_" })
            if code != "zh", languages.contains(code) { return code }
        }
        return "en"
    }

    static func text(_ key: String, lang: String = WidgetTexts.lang) -> String {
        table[key]?[lang] ?? table[key]?["en"] ?? key
    }
}
