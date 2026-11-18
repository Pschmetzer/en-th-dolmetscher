// L10n+R15.swift – Texte der Runde 15 (Gesprächsmodus) in allen 10 Oberflächensprachen.
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round15: [String: [String: String]] = [
        "conv_state_idle": [
            "de": "Bereit", "en": "Ready", "th": "พร้อม", "es": "Listo", "fr": "Prêt", "ja": "待機中", "ko": "대기 중", "zh-Hans": "就绪", "vi": "Sẵn sàng", "id": "Siap",
        ],
        "conv_state_listening": [
            "de": "Hört zu", "en": "Listening", "th": "กำลังฟัง", "es": "Escuchando", "fr": "Écoute", "ja": "聞いています", "ko": "듣는 중", "zh-Hans": "正在聆听", "vi": "Đang nghe", "id": "Mendengarkan",
        ],
        "conv_state_translating": [
            "de": "Übersetzt", "en": "Translating", "th": "กำลังแปล", "es": "Traduciendo", "fr": "Traduction", "ja": "翻訳中", "ko": "번역 중", "zh-Hans": "正在翻译", "vi": "Đang dịch", "id": "Menerjemahkan",
        ],
        "conv_state_speaking": [
            "de": "Spricht", "en": "Speaking", "th": "กำลังพูด", "es": "Hablando", "fr": "Parle", "ja": "読み上げ中", "ko": "말하는 중", "zh-Hans": "正在朗读", "vi": "Đang nói", "id": "Berbicara",
        ],
        "conv_language": [
            "de": "Sprache dieser Hälfte", "en": "Language of this half", "th": "ภาษาของฝั่งนี้", "es": "Idioma de esta mitad", "fr": "Langue de cette moitié", "ja": "この側の言語", "ko": "이 쪽 언어", "zh-Hans": "此侧语言", "vi": "Ngôn ngữ của nửa này", "id": "Bahasa sisi ini",
        ],
        "conv_font_smaller": [
            "de": "Schrift kleiner", "en": "Smaller text", "th": "ตัวอักษรเล็กลง", "es": "Texto más pequeño", "fr": "Texte plus petit", "ja": "文字を小さく", "ko": "글자 작게", "zh-Hans": "缩小文字", "vi": "Chữ nhỏ hơn", "id": "Teks lebih kecil",
        ],
        "conv_font_larger": [
            "de": "Schrift größer", "en": "Larger text", "th": "ตัวอักษรใหญ่ขึ้น", "es": "Texto más grande", "fr": "Texte plus grand", "ja": "文字を大きく", "ko": "글자 크게", "zh-Hans": "放大文字", "vi": "Chữ lớn hơn", "id": "Teks lebih besar",
        ],
        "conv_repeat": [
            "de": "Wiederholen", "en": "Repeat", "th": "พูดซ้ำ", "es": "Repetir", "fr": "Répéter", "ja": "繰り返す", "ko": "반복", "zh-Hans": "重复", "vi": "Lặp lại", "id": "Ulangi",
        ],
        "conv_slow": [
            "de": "Langsam", "en": "Slow", "th": "ช้า", "es": "Despacio", "fr": "Lentement", "ja": "ゆっくり", "ko": "천천히", "zh-Hans": "慢速", "vi": "Chậm", "id": "Pelan",
        ],
    ]
}
