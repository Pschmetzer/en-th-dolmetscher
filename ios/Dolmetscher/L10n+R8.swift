// L10n+R8.swift – Texte der Runde 8 in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round8: [String: [String: String]] = [
        "learn_today": [
            "de": "Heute gelernt: %d", "en": "Learned today: %d", "th": "เรียนวันนี้: %d", "es": "Hoy: %d", "fr": "Aujourd'hui : %d", "ja": "今日: %d", "ko": "오늘: %d", "zh-Hans": "今日已学：%d", "vi": "Hôm nay: %d", "id": "Hari ini: %d"
        ],
        "learn_streak": [
            "de": "Tage in Folge: %d", "en": "Days in a row: %d", "th": "ต่อเนื่อง %d วัน", "es": "Días seguidos: %d", "fr": "Jours de suite : %d", "ja": "%d日連続", "ko": "%d일 연속", "zh-Hans": "连续 %d 天", "vi": "%d ngày liên tiếp", "id": "%d hari berturut-turut"
        ],
        "learn_box_a11y": [
            "de": "Fach %d, Karten: %d", "en": "Box %d, cards: %d", "th": "กล่อง %d: %d ใบ", "es": "Caja %d, tarjetas: %d", "fr": "Boîte %d, cartes : %d", "ja": "ボックス%d: %d枚", "ko": "상자 %d: 카드 %d장", "zh-Hans": "第 %d 盒：%d 张卡片", "vi": "Ngăn %d: %d thẻ", "id": "Kotak %d: %d kartu"
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
        "hide_on_capture": [
            "de": "Bei Bildschirmaufnahme und Spiegelung verbergen", "en": "Hide during screen recording and mirroring", "th": "ซ่อนระหว่างบันทึกหน้าจอและมิเรอร์", "es": "Ocultar al grabar o duplicar la pantalla", "fr": "Masquer pendant l'enregistrement et la recopie d'écran", "ja": "画面収録やミラーリング中は隠す", "ko": "화면 녹화·미러링 중 숨기기", "zh-Hans": "屏幕录制和镜像时隐藏", "vi": "Ẩn khi quay màn hình hoặc phản chiếu", "id": "Sembunyikan saat merekam atau mencerminkan layar"
        ],
        "clipboard_expires": [
            "de": "Kopierte Texte nach 2 Minuten löschen", "en": "Clear copied text after 2 minutes", "th": "ล้างข้อความที่คัดลอกหลัง 2 นาที", "es": "Borrar el texto copiado tras 2 minutos", "fr": "Effacer le texte copié après 2 minutes", "ja": "コピーしたテキストを2分後に消去", "ko": "복사한 텍스트를 2분 후 삭제", "zh-Hans": "2 分钟后清除已复制的文本", "vi": "Xóa văn bản đã sao chép sau 2 phút", "id": "Hapus teks yang disalin setelah 2 menit"
        ],
        "copy_all": [
            "de": "Gespräch kopieren", "en": "Copy conversation", "th": "คัดลอกการสนทนา", "es": "Copiar conversación", "fr": "Copier la conversation", "ja": "会話をコピー", "ko": "대화 복사", "zh-Hans": "复制对话", "vi": "Sao chép cuộc trò chuyện", "id": "Salin percakapan"
        ],
        "share_favorites": [
            "de": "Favoriten teilen", "en": "Share favorites", "th": "แชร์รายการโปรด", "es": "Compartir favoritos", "fr": "Partager les favoris", "ja": "お気に入りを共有", "ko": "즐겨찾기 공유", "zh-Hans": "分享收藏", "vi": "Chia sẻ mục yêu thích", "id": "Bagikan favorit"
        ],
        "learn_practice": [
            "de": "Alle Karten üben", "en": "Practice all cards", "th": "ฝึกทุกใบ", "es": "Practicar todas las tarjetas", "fr": "Réviser toutes les cartes", "ja": "すべてのカードを練習", "ko": "모든 카드 연습", "zh-Hans": "练习所有卡片", "vi": "Luyện tất cả thẻ", "id": "Latih semua kartu"
        ],
        "learn_reset": [
            "de": "Fortschritt zurücksetzen", "en": "Reset progress", "th": "รีเซ็ตความคืบหน้า", "es": "Restablecer progreso", "fr": "Réinitialiser la progression", "ja": "進捗をリセット", "ko": "진행 상황 초기화", "zh-Hans": "重置进度", "vi": "Đặt lại tiến độ", "id": "Setel ulang kemajuan"
        ],
        "learn_reset_ask": [
            "de": "Alle Karten wieder in Fach 1?", "en": "Move all cards back to box 1?", "th": "ย้ายทุกใบกลับไปกล่อง 1 ไหม", "es": "¿Devolver todas las tarjetas a la caja 1?", "fr": "Remettre toutes les cartes dans la boîte 1 ?", "ja": "すべてのカードをボックス1に戻しますか?", "ko": "모든 카드를 상자 1로 되돌릴까요?", "zh-Hans": "将所有卡片放回第 1 盒?", "vi": "Đưa tất cả thẻ về ngăn 1?", "id": "Kembalikan semua kartu ke kotak 1?"
        ],
        "net_offline_hint": [
            "de": "Offline – übersetzt nur mit Sprachpaketen auf dem Gerät", "en": "Offline – translating with on-device language packs only", "th": "ออฟไลน์ – แปลได้เฉพาะชุดภาษาในเครื่อง", "es": "Sin conexión: solo se traduce con paquetes del dispositivo", "fr": "Hors ligne – traduction avec les packs de l'appareil uniquement", "ja": "オフライン – 端末の言語パックのみで翻訳", "ko": "오프라인 – 기기 언어 팩으로만 번역", "zh-Hans": "离线 – 仅使用设备上的语言包翻译", "vi": "Ngoại tuyến – chỉ dịch bằng gói ngôn ngữ trên máy", "id": "Offline – hanya menerjemahkan dengan paket bahasa di perangkat"
        ],
    ]
}
