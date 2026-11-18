// L10n+R8.swift – Texte der Runde 8 in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round8: [String: [String: String]] = [
        "learn_today": [
            "de": "Heute gelernt: %d", "en": "Learned today: %d", "th": "เรียนวันนี้: %d", "es": "Hoy: %d", "fr": "Aujourd'hui : %d", "ja": "今日: %d", "ko": "오늘: %d", "zh-Hans": "今日已学：%d", "vi": "Hôm nay: %d", "id": "Hari ini: %d"
        ],
        "learn_streak": [
            "de": "%d Tage in Folge", "en": "%d days in a row", "th": "ต่อเนื่อง %d วัน", "es": "%d días seguidos", "fr": "%d jours de suite", "ja": "%d日連続", "ko": "%d일 연속", "zh-Hans": "连续 %d 天", "vi": "%d ngày liên tiếp", "id": "%d hari berturut-turut"
        ],
        "learn_box_a11y": [
            "de": "Fach %d: %d Karten", "en": "Box %d: %d cards", "th": "กล่อง %d: %d ใบ", "es": "Caja %d: %d tarjetas", "fr": "Boîte %d : %d cartes", "ja": "ボックス%d: %d枚", "ko": "상자 %d: 카드 %d장", "zh-Hans": "第 %d 盒：%d 张卡片", "vi": "Ngăn %d: %d thẻ", "id": "Kotak %d: %d kartu"
        ],
        "cat_recent": [
            "de": "Zuletzt", "en": "Recent", "th": "ล่าสุด", "es": "Recientes", "fr": "Récents", "ja": "最近", "ko": "최근", "zh-Hans": "最近", "vi": "Gần đây", "id": "Terbaru"
        ],
        "recent_empty": [
            "de": "Noch nichts gesagt – hier stehen die zuletzt gesprochenen Sätze.", "en": "Nothing said yet – the sentences you spoke last appear here.", "th": "ยังไม่ได้พูดประโยคใด – ประโยคที่พูดล่าสุดจะแสดงที่นี่", "es": "Aún no has dicho nada: aquí aparecen las últimas frases.", "fr": "Rien dit pour l'instant : les dernières phrases apparaissent ici.", "ja": "まだ何も話していません – 最近話した文がここに表示されます。", "ko": "아직 말한 문장이 없습니다 – 최근 말한 문장이 여기에 표시됩니다.", "zh-Hans": "还没有说过任何句子 – 最近说的句子会显示在这里。", "vi": "Chưa nói câu nào – các câu vừa nói sẽ hiện ở đây.", "id": "Belum ada yang diucapkan – kalimat terakhir muncul di sini."
        ],
        "net_back": [
            "de": "Netz wieder da – neuer Übersetzungsversuch (%d)", "en": "Back online – retrying translation (%d)", "th": "กลับมาออนไลน์ – ลองแปลใหม่ (%d)", "es": "De nuevo en línea – reintentando traducir (%d)", "fr": "De nouveau en ligne – nouvelle tentative de traduction (%d)", "ja": "オンライン復帰 – 再翻訳中 (%d)", "ko": "다시 온라인 – 번역 재시도 (%d)", "zh-Hans": "已恢复网络 – 重新翻译 (%d)", "vi": "Đã có mạng – thử dịch lại (%d)", "id": "Online lagi – mencoba menerjemahkan ulang (%d)"
        ],
    ]
}
