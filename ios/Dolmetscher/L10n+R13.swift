// L10n+R13.swift – Texte der Runde 13 (VoiceOver-Ansagen bei Statuswechseln) in allen 10 Oberflächensprachen.
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft L10nTests.
import Foundation

extension L10n {
    static let round13: [String: [String: String]] = [
        "a11y_started": [
            "de": "Zuhören gestartet", "en": "Listening started", "th": "เริ่มฟังแล้ว", "es": "Escucha iniciada", "fr": "Écoute démarrée", "ja": "聞き取りを開始しました", "ko": "듣기를 시작했습니다", "zh-Hans": "已开始聆听", "vi": "Đã bắt đầu nghe", "id": "Mulai mendengarkan",
        ],
        "a11y_stopped": [
            "de": "Zuhören beendet", "en": "Listening stopped", "th": "หยุดฟังแล้ว", "es": "Escucha detenida", "fr": "Écoute arrêtée", "ja": "聞き取りを停止しました", "ko": "듣기를 중지했습니다", "zh-Hans": "已停止聆听", "vi": "Đã dừng nghe", "id": "Berhenti mendengarkan",
        ],
        "a11y_failed": [
            "de": "Fehler", "en": "Error", "th": "เกิดข้อผิดพลาด", "es": "Error", "fr": "Erreur", "ja": "エラー", "ko": "오류", "zh-Hans": "出错", "vi": "Lỗi", "id": "Kesalahan",
        ],
        "a11y_translation_failed": [
            "de": "Übersetzung fehlgeschlagen", "en": "Translation failed", "th": "แปลไม่สำเร็จ", "es": "Falló la traducción", "fr": "Échec de la traduction", "ja": "翻訳に失敗しました", "ko": "번역에 실패했습니다", "zh-Hans": "翻译失败", "vi": "Dịch không thành công", "id": "Terjemahan gagal",
        ],
    ]
}
