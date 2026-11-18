// L10n+R17.swift – Texte der Runde 17 (Kurzbefehle) in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft Round17Tests.
import Foundation

extension L10n {
    static let round17: [String: [String: String]] = [
        "sc_swapped": [
            "de": "Sprachpaar getauscht: %@", "en": "Language pair swapped: %@",
            "th": "สลับคู่ภาษาแล้ว: %@", "es": "Pareja de idiomas intercambiada: %@",
            "fr": "Paire de langues inversée : %@", "ja": "言語ペアを入れ替えました: %@",
            "ko": "언어 쌍을 바꿨습니다: %@", "zh-Hans": "已互换语言对：%@",
            "vi": "Đã đổi cặp ngôn ngữ: %@", "id": "Pasangan bahasa ditukar: %@"
        ],
        "sc_said": [
            "de": "Gesagt: %@", "en": "Said: %@",
            "th": "พูดแล้ว: %@", "es": "Dicho: %@",
            "fr": "Dit : %@", "ja": "読み上げました: %@",
            "ko": "말했습니다: %@", "zh-Hans": "已说出：%@",
            "vi": "Đã nói: %@", "id": "Diucapkan: %@"
        ],
        "sc_no_phrase": [
            "de": "Kein passender Satz im Satzbuch gefunden.", "en": "No matching phrase found in the phrasebook.",
            "th": "ไม่พบประโยคที่ตรงกันในสมุดวลี", "es": "No hay ninguna frase que coincida en el libro de frases.",
            "fr": "Aucune phrase correspondante dans le carnet de phrases.", "ja": "フレーズ集に該当する文が見つかりません。",
            "ko": "문장집에서 일치하는 문장을 찾지 못했습니다.", "zh-Hans": "短语手册中没有找到匹配的句子。",
            "vi": "Không tìm thấy câu phù hợp trong sổ câu.", "id": "Tidak ada frasa yang cocok di buku frasa."
        ],
        "sc_no_last": [
            "de": "Noch keine Übersetzung zum Vorlesen.", "en": "No translation to read yet.",
            "th": "ยังไม่มีคำแปลให้อ่าน", "es": "Aún no hay traducción para leer.",
            "fr": "Pas encore de traduction à lire.", "ja": "読み上げる翻訳がまだありません。",
            "ko": "읽을 번역이 아직 없습니다.", "zh-Hans": "还没有可朗读的翻译。",
            "vi": "Chưa có bản dịch để đọc.", "id": "Belum ada terjemahan untuk dibacakan."
        ],
    ]
}
