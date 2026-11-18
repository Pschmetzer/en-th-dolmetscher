// L10n+R18.swift – Texte der Runde 18 (Verlauf) in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft Round18Tests.
import Foundation

extension L10n {
    static let round18: [String: [String: String]] = [
        "hs_title": [
            "de": "Verlauf", "en": "History",
            "th": "ประวัติ", "es": "Historial",
            "fr": "Historique", "ja": "履歴",
            "ko": "기록", "zh-Hans": "历史记录",
            "vi": "Lịch sử", "id": "Riwayat"
        ],
        "hs_search": [
            "de": "Im Verlauf suchen", "en": "Search history",
            "th": "ค้นหาในประวัติ", "es": "Buscar en el historial",
            "fr": "Rechercher dans l’historique", "ja": "履歴を検索",
            "ko": "기록 검색", "zh-Hans": "搜索历史记录",
            "vi": "Tìm trong lịch sử", "id": "Cari di riwayat"
        ],
        "hs_filter": [
            "de": "Filter", "en": "Filter",
            "th": "ตัวกรอง", "es": "Filtro",
            "fr": "Filtre", "ja": "フィルタ",
            "ko": "필터", "zh-Hans": "筛选",
            "vi": "Bộ lọc", "id": "Filter"
        ],
        "hs_all_pairs": [
            "de": "Alle Sprachpaare", "en": "All language pairs",
            "th": "ทุกคู่ภาษา", "es": "Todos los pares",
            "fr": "Toutes les paires", "ja": "すべての言語ペア",
            "ko": "모든 언어 쌍", "zh-Hans": "所有语言对",
            "vi": "Mọi cặp ngôn ngữ", "id": "Semua pasangan bahasa"
        ],
        "hs_range_all": [
            "de": "Jederzeit", "en": "Any time",
            "th": "ทุกเวลา", "es": "Cualquier fecha",
            "fr": "Toute période", "ja": "すべての期間",
            "ko": "전체 기간", "zh-Hans": "全部时间",
            "vi": "Mọi lúc", "id": "Kapan saja"
        ],
        "hs_range_today": [
            "de": "Heute", "en": "Today",
            "th": "วันนี้", "es": "Hoy",
            "fr": "Aujourd’hui", "ja": "今日",
            "ko": "오늘", "zh-Hans": "今天",
            "vi": "Hôm nay", "id": "Hari ini"
        ],
        "hs_range_week": [
            "de": "Letzte 7 Tage", "en": "Last 7 days",
            "th": "7 วันล่าสุด", "es": "Últimos 7 días",
            "fr": "7 derniers jours", "ja": "過去7日間",
            "ko": "최근 7일", "zh-Hans": "最近 7 天",
            "vi": "7 ngày qua", "id": "7 hari terakhir"
        ],
        "hs_range_month": [
            "de": "Letzte 30 Tage", "en": "Last 30 days",
            "th": "30 วันล่าสุด", "es": "Últimos 30 días",
            "fr": "30 derniers jours", "ja": "過去30日間",
            "ko": "최근 30일", "zh-Hans": "最近 30 天",
            "vi": "30 ngày qua", "id": "30 hari terakhir"
        ],
        "hs_favs": [
            "de": "Nur Favoriten", "en": "Favourites only",
            "th": "เฉพาะรายการโปรด", "es": "Solo favoritos",
            "fr": "Favoris seulement", "ja": "お気に入りのみ",
            "ko": "즐겨찾기만", "zh-Hans": "仅收藏",
            "vi": "Chỉ yêu thích", "id": "Hanya favorit"
        ],
        "hs_select": [
            "de": "Auswählen", "en": "Select",
            "th": "เลือก", "es": "Seleccionar",
            "fr": "Sélectionner", "ja": "選択",
            "ko": "선택", "zh-Hans": "选择",
            "vi": "Chọn", "id": "Pilih"
        ],
        "hs_selected": [
            "de": "%@ ausgewählt", "en": "%@ selected",
            "th": "เลือกแล้ว %@", "es": "%@ seleccionados",
            "fr": "%@ sélectionnés", "ja": "%@件を選択",
            "ko": "%@개 선택됨", "zh-Hans": "已选择 %@ 条",
            "vi": "Đã chọn %@", "id": "%@ dipilih"
        ],
        "hs_select_all": [
            "de": "Alle auswählen", "en": "Select all",
            "th": "เลือกทั้งหมด", "es": "Seleccionar todo",
            "fr": "Tout sélectionner", "ja": "すべて選択",
            "ko": "모두 선택", "zh-Hans": "全选",
            "vi": "Chọn tất cả", "id": "Pilih semua"
        ],
        "hs_delete_sel": [
            "de": "Auswahl löschen", "en": "Delete selected",
            "th": "ลบที่เลือก", "es": "Eliminar selección",
            "fr": "Supprimer la sélection", "ja": "選択を削除",
            "ko": "선택 삭제", "zh-Hans": "删除所选",
            "vi": "Xóa mục đã chọn", "id": "Hapus yang dipilih"
        ],
        "hs_share_sel": [
            "de": "Auswahl teilen", "en": "Share selected",
            "th": "แชร์ที่เลือก", "es": "Compartir selección",
            "fr": "Partager la sélection", "ja": "選択を共有",
            "ko": "선택 공유", "zh-Hans": "分享所选",
            "vi": "Chia sẻ mục đã chọn", "id": "Bagikan yang dipilih"
        ],
        "hs_today": [
            "de": "Heute", "en": "Today",
            "th": "วันนี้", "es": "Hoy",
            "fr": "Aujourd’hui", "ja": "今日",
            "ko": "오늘", "zh-Hans": "今天",
            "vi": "Hôm nay", "id": "Hari ini"
        ],
        "hs_yesterday": [
            "de": "Gestern", "en": "Yesterday",
            "th": "เมื่อวาน", "es": "Ayer",
            "fr": "Hier", "ja": "昨日",
            "ko": "어제", "zh-Hans": "昨天",
            "vi": "Hôm qua", "id": "Kemarin"
        ],
        "hs_empty_title": [
            "de": "Noch kein Gespräch gespeichert", "en": "No conversation saved yet",
            "th": "ยังไม่มีบทสนทนาที่บันทึก", "es": "Aún no hay conversaciones guardadas",
            "fr": "Aucune conversation enregistrée", "ja": "保存された会話はまだありません",
            "ko": "저장된 대화가 아직 없습니다", "zh-Hans": "还没有保存的对话",
            "vi": "Chưa có hội thoại nào được lưu", "id": "Belum ada percakapan tersimpan"
        ],
        "hs_empty_hint": [
            "de": "Starte das Dolmetschen oder tippe einen Satz – er erscheint dann hier.", "en": "Start interpreting or type a sentence – it will show up here.",
            "th": "เริ่มแปลหรือพิมพ์ประโยค แล้วจะแสดงที่นี่", "es": "Empieza a interpretar o escribe una frase y aparecerá aquí.",
            "fr": "Lancez l’interprétation ou saisissez une phrase : elle apparaîtra ici.", "ja": "通訳を始めるか文を入力すると、ここに表示されます。",
            "ko": "통역을 시작하거나 문장을 입력하면 여기에 표시됩니다.", "zh-Hans": "开始口译或输入一句话，它就会出现在这里。",
            "vi": "Hãy bắt đầu phiên dịch hoặc gõ một câu – câu đó sẽ hiện ở đây.", "id": "Mulai menerjemahkan atau ketik kalimat – akan muncul di sini."
        ],
        "hs_empty_go": [
            "de": "Zum Gespräch", "en": "Go to conversation",
            "th": "ไปที่บทสนทนา", "es": "Ir a la conversación",
            "fr": "Aller à la conversation", "ja": "会話へ",
            "ko": "대화로 이동", "zh-Hans": "前往对话",
            "vi": "Đến hội thoại", "id": "Ke percakapan"
        ],
        "hs_none_title": [
            "de": "Nichts gefunden", "en": "Nothing found",
            "th": "ไม่พบรายการ", "es": "No se encontró nada",
            "fr": "Aucun résultat", "ja": "見つかりません",
            "ko": "결과 없음", "zh-Hans": "没有找到",
            "vi": "Không tìm thấy", "id": "Tidak ditemukan"
        ],
        "hs_none_hint": [
            "de": "Suche oder Filter lockern.", "en": "Loosen the search or filters.",
            "th": "ลองผ่อนคำค้นหาหรือตัวกรอง", "es": "Prueba con otra búsqueda o menos filtros.",
            "fr": "Assouplissez la recherche ou les filtres.", "ja": "検索語やフィルタを緩めてください。",
            "ko": "검색어나 필터를 완화해 보세요.", "zh-Hans": "请放宽搜索词或筛选条件。",
            "vi": "Hãy nới lỏng từ khóa hoặc bộ lọc.", "id": "Longgarkan pencarian atau filter."
        ],
        "hs_reset": [
            "de": "Filter zurücksetzen", "en": "Reset filters",
            "th": "ล้างตัวกรอง", "es": "Quitar filtros",
            "fr": "Réinitialiser les filtres", "ja": "フィルタを解除",
            "ko": "필터 초기화", "zh-Hans": "重置筛选",
            "vi": "Đặt lại bộ lọc", "id": "Atur ulang filter"
        ],
        "hs_keep_none": [
            "de": "Gespräche werden nicht gespeichert.", "en": "Conversations are not saved.",
            "th": "ไม่บันทึกบทสนทนา", "es": "Las conversaciones no se guardan.",
            "fr": "Les conversations ne sont pas enregistrées.", "ja": "会話は保存されません。",
            "ko": "대화는 저장되지 않습니다.", "zh-Hans": "不保存对话。",
            "vi": "Hội thoại không được lưu.", "id": "Percakapan tidak disimpan."
        ],
        "hs_keep_1": [
            "de": "Sätze werden nach 1 Tag automatisch gelöscht.", "en": "Sentences are deleted automatically after 1 day.",
            "th": "ประโยคจะถูกลบอัตโนมัติหลัง 1 วัน", "es": "Las frases se eliminan automáticamente tras 1 día.",
            "fr": "Les phrases sont supprimées automatiquement après 1 jour.", "ja": "文は1日後に自動的に削除されます。",
            "ko": "문장은 1일 후 자동으로 삭제됩니다.", "zh-Hans": "句子将在 1 天后自动删除。",
            "vi": "Các câu tự động bị xóa sau 1 ngày.", "id": "Kalimat dihapus otomatis setelah 1 hari."
        ],
        "hs_keep_days": [
            "de": "Sätze werden nach %@ Tagen automatisch gelöscht.", "en": "Sentences are deleted automatically after %@ days.",
            "th": "ประโยคจะถูกลบอัตโนมัติหลัง %@ วัน", "es": "Las frases se eliminan automáticamente tras %@ días.",
            "fr": "Les phrases sont supprimées automatiquement après %@ jours.", "ja": "文は%@日後に自動的に削除されます。",
            "ko": "문장은 %@일 후 자동으로 삭제됩니다.", "zh-Hans": "句子将在 %@ 天后自动删除。",
            "vi": "Các câu tự động bị xóa sau %@ ngày.", "id": "Kalimat dihapus otomatis setelah %@ hari."
        ],
        "hs_keep_forever": [
            "de": "Sätze bleiben, bis du sie löschst.", "en": "Sentences stay until you delete them.",
            "th": "ประโยคจะอยู่จนกว่าคุณจะลบ", "es": "Las frases se quedan hasta que las elimines.",
            "fr": "Les phrases restent jusqu’à ce que vous les supprimiez.", "ja": "文は削除するまで残ります。",
            "ko": "문장은 직접 삭제할 때까지 유지됩니다.", "zh-Hans": "句子会一直保留，直到你删除。",
            "vi": "Các câu được giữ cho đến khi bạn xóa.", "id": "Kalimat tersimpan sampai kamu menghapusnya."
        ],
        "hs_keep_change": [
            "de": "Aufbewahrung ändern", "en": "Change retention",
            "th": "เปลี่ยนระยะเวลาเก็บ", "es": "Cambiar conservación",
            "fr": "Modifier la conservation", "ja": "保存期間を変更",
            "ko": "보관 기간 변경", "zh-Hans": "更改保留时长",
            "vi": "Đổi thời gian lưu", "id": "Ubah masa simpan"
        ],
        "hs_deleted": [
            "de": "%@ gelöscht", "en": "%@ deleted",
            "th": "ลบ %@ รายการแล้ว", "es": "%@ eliminados",
            "fr": "%@ supprimés", "ja": "%@件を削除しました",
            "ko": "%@개 삭제됨", "zh-Hans": "已删除 %@ 条",
            "vi": "Đã xóa %@", "id": "%@ dihapus"
        ],
    ]
}
