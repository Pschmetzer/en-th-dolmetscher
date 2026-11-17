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
