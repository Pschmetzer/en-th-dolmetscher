// L10n+R7.swift – Texte der Runde 7 in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round7: [String: [String: String]] = [
        "err_online_limit": [
            "de": "Online-Übersetzer hat sein Limit erreicht – später nochmal versuchen",
            "en": "The online translator reached its limit – try again later",
            "th": "ตัวแปลออนไลน์ใช้ถึงขีดจำกัดแล้ว – ลองใหม่ภายหลัง",
            "es": "El traductor en línea alcanzó su límite – inténtalo más tarde",
            "fr": "Le traducteur en ligne a atteint sa limite – réessayez plus tard",
            "ja": "オンライン翻訳が上限に達しました – 後でもう一度お試しください",
            "ko": "온라인 번역기가 한도에 도달했습니다 – 나중에 다시 시도하세요",
            "zh-Hans": "在线翻译已达上限 – 请稍后再试",
            "vi": "Trình dịch trực tuyến đã đạt giới hạn – hãy thử lại sau",
            "id": "Penerjemah online mencapai batasnya – coba lagi nanti"],
        "camera_denied": [
            "de": "Kamerazugriff ist ausgeschaltet. In den Einstellungen erlauben.",
            "en": "Camera access is turned off. Allow it in Settings.",
            "th": "การเข้าถึงกล้องปิดอยู่ โปรดอนุญาตในการตั้งค่า",
            "es": "El acceso a la cámara está desactivado. Permítelo en Ajustes.",
            "fr": "L'accès à l'appareil photo est désactivé. Autorisez-le dans Réglages.",
            "ja": "カメラへのアクセスがオフです。設定で許可してください。",
            "ko": "카메라 접근이 꺼져 있습니다. 설정에서 허용하세요.",
            "zh-Hans": "相机访问已关闭。请在设置中允许。",
            "vi": "Quyền truy cập máy ảnh đang tắt. Hãy cho phép trong Cài đặt.",
            "id": "Akses kamera dimatikan. Izinkan di Pengaturan."],
        "help_location_failed": [
            "de": "Position nicht verfügbar (kein GPS-Empfang?).",
            "en": "Position not available (no GPS signal?).",
            "th": "ไม่สามารถระบุตำแหน่งได้ (ไม่มีสัญญาณ GPS?)",
            "es": "Posición no disponible (¿sin señal GPS?).",
            "fr": "Position indisponible (pas de signal GPS ?).",
            "ja": "位置情報を取得できません（GPS信号なし？）。",
            "ko": "위치를 확인할 수 없습니다 (GPS 신호 없음?).",
            "zh-Hans": "无法获取位置（没有 GPS 信号？）。",
            "vi": "Không có vị trí (không có tín hiệu GPS?).",
            "id": "Posisi tidak tersedia (tidak ada sinyal GPS?)."],
        "help_location_approx": [
            "de": "Nur ungefährer Standort – „Genauen Standort“ in den iOS-Einstellungen einschalten.",
            "en": "Approximate location only – turn on “Precise Location” in iOS Settings.",
            "th": "เป็นตำแหน่งโดยประมาณเท่านั้น – เปิด “ตำแหน่งที่แน่นอน” ในการตั้งค่า iOS",
            "es": "Solo ubicación aproximada – activa «Ubicación precisa» en Ajustes de iOS.",
            "fr": "Position approximative seulement – activez « Position précise » dans Réglages iOS.",
            "ja": "おおよその位置のみです。iOSの設定で「正確な位置情報」をオンにしてください。",
            "ko": "대략적인 위치만 표시됩니다 – iOS 설정에서 ‘정확한 위치’를 켜세요.",
            "zh-Hans": "仅为大致位置 – 请在 iOS 设置中开启“精确位置”。",
            "vi": "Chỉ là vị trí gần đúng – hãy bật “Vị trí chính xác” trong Cài đặt iOS.",
            "id": "Hanya lokasi perkiraan – aktifkan “Lokasi Tepat” di Pengaturan iOS."],
        "hearing_now": [
            "de": "Hört: %@",
            "en": "Hearing: %@",
            "th": "กำลังฟัง: %@",
            "es": "Escuchando: %@",
            "fr": "Écoute : %@",
            "ja": "聞き取り中: %@",
            "ko": "듣는 중: %@",
            "zh-Hans": "正在听: %@",
            "vi": "Đang nghe: %@",
            "id": "Mendengar: %@"],
        "dish_incomplete": [
            "de": "Hinweise sind nicht vollständig – bei Allergien im Restaurant nachfragen.",
            "en": "Notes are not complete – with allergies, ask at the restaurant.",
            "th": "ข้อมูลไม่ครบถ้วน – หากแพ้อาหาร โปรดสอบถามที่ร้าน",
            "es": "Las notas no son completas – si tienes alergias, pregunta en el restaurante.",
            "fr": "Les indications sont incomplètes – en cas d'allergie, demandez au restaurant.",
            "ja": "情報は完全ではありません。アレルギーがある場合はお店に確認してください。",
            "ko": "정보가 완전하지 않습니다 – 알레르기가 있으면 식당에 문의하세요.",
            "zh-Hans": "提示并不完整 – 如有过敏，请向餐厅确认。",
            "vi": "Ghi chú chưa đầy đủ – nếu bị dị ứng, hãy hỏi nhà hàng.",
            "id": "Catatan tidak lengkap – jika alergi, tanyakan ke restoran."],
    ]
}
