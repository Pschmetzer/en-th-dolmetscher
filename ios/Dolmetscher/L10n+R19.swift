// L10n+R19.swift – Texte der Runde 19 (Audio-Sitzung) in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft tests/test_runde19_ios_speech.py.
import Foundation

extension L10n {
    static let round19: [String: [String: String]] = [
        "interrupt_resumed": [
            "de": "Weiter am Zuhören", "en": "Listening again",
            "th": "กลับมาฟังต่อแล้ว", "es": "Escuchando de nuevo",
            "fr": "L’écoute a repris", "ja": "聞き取りを再開しました",
            "ko": "다시 듣고 있습니다", "zh-Hans": "已继续聆听",
            "vi": "Đã nghe lại", "id": "Mendengarkan lagi"
        ],
        "route_output_lost": [
            "de": "Kopfhörer getrennt – Vorlesen angehalten, Zuhören läuft weiter", "en": "Headphones disconnected – playback stopped, listening continues",
            "th": "ถอดหูฟังแล้ว – หยุดอ่านออกเสียง การฟังยังทำงานต่อ", "es": "Auriculares desconectados: lectura detenida, la escucha sigue",
            "fr": "Casque débranché – lecture arrêtée, l’écoute continue", "ja": "ヘッドホンが外れました – 読み上げを止め、聞き取りは続けます",
            "ko": "헤드폰 연결이 끊겼습니다 – 읽기를 멈췄고 듣기는 계속됩니다", "zh-Hans": "耳机已断开 – 已停止朗读,聆听继续",
            "vi": "Đã ngắt tai nghe – dừng đọc, vẫn tiếp tục nghe", "id": "Headphone terlepas – pembacaan dihentikan, mendengarkan berlanjut"
        ],
    ]
}
