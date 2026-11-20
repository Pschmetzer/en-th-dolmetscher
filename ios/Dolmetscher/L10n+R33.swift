// L10n+R33.swift – Texte der Runde 33 (Bluetooth-Hinweis, Umweg über Englisch, Bereitschafts-Ampel, Spotlight)
// in allen 10 Oberflächensprachen. de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft.
import Foundation

extension L10n {
    static let round33: [String: [String: String]] = [
        "r33_hfp_warn": [
            "de": "Bluetooth-Headset: schmale Tonqualität, die Erkennung kann schlechter sein. Eingebautes Mikrofon wählen?",
            "en": "Bluetooth headset: narrow audio quality, recognition may suffer. Try the built-in microphone?",
            "th": "หูฟังบลูทูธ: คุณภาพเสียงแคบ การรู้จำเสียงอาจแย่ลง ลองใช้ไมโครโฟนในเครื่องไหม",
            "es": "Auricular Bluetooth: calidad de audio reducida, el reconocimiento puede empeorar. ¿Probar el micrófono integrado?",
            "fr": "Casque Bluetooth : qualité audio réduite, la reconnaissance peut en pâtir. Essayer le micro intégré ?",
            "ja": "Bluetoothヘッドセット：音質が狭帯域のため、認識精度が下がることがあります。内蔵マイクを試しますか？",
            "ko": "블루투스 헤드셋: 음질이 좁은 대역이라 인식이 떨어질 수 있습니다. 내장 마이크를 사용해 볼까요?",
            "zh-Hans": "蓝牙耳机：音质带宽较窄，识别效果可能变差。要试试内置麦克风吗？",
            "vi": "Tai nghe Bluetooth: chất lượng âm thanh hẹp, nhận dạng có thể kém hơn. Thử micro tích hợp?",
            "id": "Headset Bluetooth: kualitas audio sempit, pengenalan bisa menurun. Coba mikrofon bawaan?"
        ],
        "r33_pivot_via": [
            "de": "über Englisch", "en": "via English", "th": "ผ่านภาษาอังกฤษ", "es": "vía inglés", "fr": "via l'anglais",
            "ja": "英語経由", "ko": "영어 경유", "zh-Hans": "经由英语", "vi": "qua tiếng Anh", "id": "lewat bahasa Inggris"
        ],
        "r33_light_green": [
            "de": "Offline bereit, auch mit guter Stimme", "en": "Offline ready, with a good voice", "th": "พร้อมใช้งานออฟไลน์ พร้อมเสียงคุณภาพดี",
            "es": "Listo sin conexión, con buena voz", "fr": "Prêt hors ligne, avec une bonne voix", "ja": "オフライン対応済み（高品質の音声）",
            "ko": "오프라인 준비 완료, 좋은 음성 포함", "zh-Hans": "离线已就绪，语音质量良好", "vi": "Sẵn sàng ngoại tuyến, giọng đọc tốt", "id": "Siap offline, dengan suara yang baik"
        ],
        "r33_light_yellow": [
            "de": "Offline möglich, aber nur mit einfacher Stimme oder noch etwas zu laden", "en": "Works offline, but only with a basic voice or something still to download",
            "th": "ใช้ออฟไลน์ได้ แต่มีเพียงเสียงพื้นฐานหรือยังมีบางอย่างต้องดาวน์โหลด", "es": "Funciona sin conexión, pero solo con voz básica o falta algo por descargar",
            "fr": "Fonctionne hors ligne, mais avec une voix basique ou un élément à télécharger", "ja": "オフラインで使えますが、基本の音声のみ、またはまだダウンロードが必要です",
            "ko": "오프라인 사용 가능하지만 기본 음성이거나 받을 항목이 남아 있습니다", "zh-Hans": "可离线使用，但只有基础语音，或还有内容待下载",
            "vi": "Dùng được ngoại tuyến, nhưng chỉ có giọng cơ bản hoặc còn mục cần tải", "id": "Bisa offline, tetapi hanya dengan suara dasar atau masih ada yang perlu diunduh"
        ],
        "r33_light_red": [
            "de": "Offline nicht nutzbar: es fehlt etwas Wichtiges", "en": "Not usable offline: something essential is missing", "th": "ใช้ออฟไลน์ไม่ได้ ขาดสิ่งสำคัญบางอย่าง",
            "es": "No se puede usar sin conexión: falta algo esencial", "fr": "Inutilisable hors ligne : un élément essentiel manque",
            "ja": "オフラインでは使えません：必要なものが足りません", "ko": "오프라인에서 사용할 수 없음: 꼭 필요한 항목이 없습니다",
            "zh-Hans": "无法离线使用：缺少必要内容", "vi": "Không dùng được ngoại tuyến: thiếu thành phần thiết yếu", "id": "Tidak bisa dipakai offline: ada yang penting belum tersedia"
        ],
        "r33_spotlight": [
            "de": "Verlauf in der Spotlight-Suche", "en": "History in Spotlight search", "th": "ประวัติในการค้นหา Spotlight", "es": "Historial en la búsqueda de Spotlight",
            "fr": "Historique dans la recherche Spotlight", "ja": "履歴をSpotlight検索に表示", "ko": "기록을 Spotlight 검색에 표시",
            "zh-Hans": "在聚焦搜索中显示历史记录", "vi": "Lịch sử trong tìm kiếm Spotlight", "id": "Riwayat di pencarian Spotlight"
        ],
        "r33_spotlight_d": [
            "de": "Aus. Nur auf diesem iPhone, die letzten 200 Sätze; bei Face-ID-Sperre oder Löschen wird der Index geleert.",
            "en": "Off by default. Only on this iPhone, the last 200 sentences; the index is cleared with the Face ID lock or when history is deleted.",
            "th": "ปิดไว้ตามค่าเริ่มต้น อยู่ใน iPhone เครื่องนี้เท่านั้น 200 ประโยคล่าสุด ดัชนีจะถูกล้างเมื่อเปิดล็อก Face ID หรือลบประวัติ",
            "es": "Desactivado por defecto. Solo en este iPhone, las últimas 200 frases; el índice se borra con el bloqueo de Face ID o al borrar el historial.",
            "fr": "Désactivé par défaut. Uniquement sur cet iPhone, les 200 dernières phrases ; l'index est vidé avec le verrouillage Face ID ou à la suppression de l'historique.",
            "ja": "初期設定はオフ。このiPhoneのみ、直近200文。Face IDロック時や履歴削除時にインデックスを消去します。",
            "ko": "기본값은 꺼짐. 이 iPhone에만, 최근 200문장; Face ID 잠금 또는 기록 삭제 시 색인이 지워집니다.",
            "zh-Hans": "默认关闭。仅限此 iPhone，最近 200 句；启用 Face ID 锁定或删除历史记录时会清除索引。",
            "vi": "Mặc định tắt. Chỉ trên iPhone này, 200 câu gần nhất; chỉ mục bị xóa khi bật khóa Face ID hoặc khi xóa lịch sử.",
            "id": "Mati secara bawaan. Hanya di iPhone ini, 200 kalimat terakhir; indeks dihapus saat kunci Face ID aktif atau riwayat dihapus."
        ],
    ]
}
