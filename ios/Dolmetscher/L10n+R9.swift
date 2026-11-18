// L10n+R9.swift – Texte der Runde 9 in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round9: [String: [String: String]] = [
        "interrupt_paused": [
            "de": "Pausiert (Anruf, Siri oder anderes) – hört danach von selbst weiter zu", "en": "Paused (call, Siri or similar) – listening resumes by itself", "th": "หยุดชั่วคราว (สายเรียกเข้า, Siri หรืออื่น ๆ) – จะกลับมาฟังเองภายหลัง", "es": "En pausa (llamada, Siri u otro): seguirá escuchando solo", "fr": "En pause (appel, Siri ou autre) – l’écoute reprend toute seule", "ja": "一時停止中(通話やSiriなど) – 終わると自動で再開します", "ko": "일시 중지됨(통화, Siri 등) – 끝나면 자동으로 다시 듣습니다", "zh-Hans": "已暂停(来电、Siri 等)– 结束后自动继续聆听", "vi": "Đã tạm dừng (cuộc gọi, Siri…) – sẽ tự nghe lại sau đó", "id": "Dijeda (panggilan, Siri, dll.) – mendengarkan lagi otomatis",
        ],
        "route_lost": [
            "de": "Kopfhörer getrennt – Ton läuft wieder über den iPhone-Lautsprecher, Mikrofon neu gestartet", "en": "Headphones disconnected – sound now plays on the iPhone speaker, microphone restarted", "th": "ถอดหูฟังแล้ว – เสียงออกทางลำโพงของ iPhone และเริ่มไมโครโฟนใหม่", "es": "Auriculares desconectados: el sonido sale por el altavoz del iPhone, micrófono reiniciado", "fr": "Casque débranché – le son passe par le haut-parleur de l’iPhone, micro relancé", "ja": "ヘッドホンが外れました – 音声はiPhoneのスピーカーから出ます。マイクを再起動しました", "ko": "헤드폰 연결이 끊겼습니다 – 소리는 iPhone 스피커로 나오고 마이크를 다시 시작했습니다", "zh-Hans": "耳机已断开 – 声音改由 iPhone 扬声器播放,麦克风已重新启动", "vi": "Đã ngắt tai nghe – âm thanh phát qua loa iPhone, micrô đã khởi động lại", "id": "Headphone terlepas – suara kini lewat speaker iPhone, mikrofon dimulai ulang",
        ],
    ]
}
