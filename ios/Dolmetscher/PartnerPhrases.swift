// PartnerPhrases.swift – feste Texte für das Gegenüber, in allen 19 Sprachen des Paars (nicht nur den 10 der
// Oberfläche): „Sie sind dran“, Antwortkarten, Allergie-Karte. Fest hinterlegt, damit sie offline und ohne
// maschinelle Übersetzung funktionieren. Thai und Deutsch/Englisch geprüft, die übrigen ungeprüft.
import Foundation

enum PartnerKey: String, CaseIterable {
    case nowYou, yes, no, dontKnow, number, tapAnswer, listening
}

enum PartnerPhrases {
    /// Reihenfolge wie PartnerKey.allCases
    private static let rows: [String: [String]] = [
        "en": ["Your turn – please speak now", "Yes", "No", "I don't know", "Number", "Or tap an answer", "Listening …"],
        "th": ["ถึงตาคุณแล้ว เชิญพูดได้เลย", "ใช่", "ไม่ใช่", "ไม่ทราบ", "ตัวเลข", "หรือแตะเพื่อตอบ", "กำลังฟัง …"],
        "de": ["Sie sind dran – bitte jetzt sprechen", "Ja", "Nein", "Weiß nicht", "Zahl", "Oder Antwort antippen", "Ich höre zu …"],
        "es": ["Su turno – hable ahora, por favor", "Sí", "No", "No lo sé", "Número", "O toque una respuesta", "Escuchando …"],
        "fr": ["À vous – parlez maintenant, s'il vous plaît", "Oui", "Non", "Je ne sais pas", "Nombre", "Ou touchez une réponse", "J'écoute …"],
        "it": ["Tocca a lei – parli pure", "Sì", "No", "Non lo so", "Numero", "Oppure tocchi una risposta", "In ascolto …"],
        "pt": ["Sua vez – fale agora, por favor", "Sim", "Não", "Não sei", "Número", "Ou toque numa resposta", "Ouvindo …"],
        "nl": ["U bent aan de beurt – spreek nu", "Ja", "Nee", "Weet ik niet", "Getal", "Of tik op een antwoord", "Luisteren …"],
        "ru": ["Ваша очередь – говорите, пожалуйста", "Да", "Нет", "Не знаю", "Число", "Или нажмите на ответ", "Слушаю …"],
        "zh": ["轮到您了，请说话", "是", "不是", "不知道", "数字", "或点击回答", "正在听 …"],
        "ja": ["あなたの番です。どうぞ話してください", "はい", "いいえ", "わかりません", "数字", "または答えをタップ", "聞いています …"],
        "ko": ["말씀하실 차례입니다. 지금 말씀하세요", "네", "아니요", "모르겠어요", "숫자", "또는 답을 누르세요", "듣고 있어요 …"],
        "vi": ["Đến lượt bạn – xin mời nói", "Có", "Không", "Tôi không biết", "Số", "Hoặc chạm vào câu trả lời", "Đang nghe …"],
        "id": ["Giliran Anda – silakan bicara", "Ya", "Tidak", "Saya tidak tahu", "Angka", "Atau ketuk jawaban", "Mendengarkan …"],
        "ar": ["دورك – تفضل بالكلام", "نعم", "لا", "لا أعرف", "رقم", "أو اضغط على إجابة", "أستمع …"],
        "hi": ["आपकी बारी – कृपया अब बोलिए", "हाँ", "नहीं", "मुझे नहीं पता", "संख्या", "या किसी जवाब पर टैप करें", "सुन रहा है …"],
        "tr": ["Sıra sizde – lütfen konuşun", "Evet", "Hayır", "Bilmiyorum", "Sayı", "Ya da bir cevaba dokunun", "Dinliyorum …"],
        "pl": ["Teraz Pan/Pani – proszę mówić", "Tak", "Nie", "Nie wiem", "Liczba", "Albo dotknij odpowiedzi", "Słucham …"],
        "uk": ["Ваша черга – говоріть, будь ласка", "Так", "Ні", "Не знаю", "Число", "Або торкніться відповіді", "Слухаю …"],
        "lo": ["ຮອດຄິວຂອງທ່ານແລ້ວ – ກະລຸນາເວົ້າ", "ແມ່ນ", "ບໍ່ແມ່ນ", "ບໍ່ຮູ້", "ຕົວເລກ", "ຫຼືແຕະເພື່ອຕອບ", "ກຳລັງຟັງ …"],
    ]

    static func text(_ key: PartnerKey, _ lang: Lang) -> String {
        let i = PartnerKey.allCases.firstIndex(of: key)!
        return (rows[lang.rawValue] ?? rows["en"]!)[i]
    }

    static var coveredLangs: Set<String> { Set(rows.keys) }
    static func row(_ lang: Lang) -> [String]? { rows[lang.rawValue] }
}

/// Strukturierte Allergie-Karte: feste Warnsätze statt Freitext-Übersetzung.
enum Allergen: String, CaseIterable, Codable, Sendable {
    case peanut, shellfish, fish, msg, milk, gluten, egg

    /// Sprachen mit fest hinterlegten Sätzen; andere bekommen Englisch plus (falls möglich) maschinelle Übersetzung.
    static let curated: [Lang] = [.en, .th, .de, .es, .fr, .ja, .ko, .zh, .vi, .id]

    /// Reihenfolge wie allCases
    private static let names: [String: [String]] = [
        "en": ["peanuts", "shellfish (shrimp, crab, clams)", "fish and fish sauce", "MSG (glutamate)", "milk and dairy", "wheat (gluten)", "eggs"],
        "th": ["ถั่วลิสง", "อาหารทะเลที่มีเปลือก (กุ้ง ปู หอย)", "ปลาและน้ำปลา", "ผงชูรส", "นมและผลิตภัณฑ์จากนม", "แป้งสาลี (กลูเตน)", "ไข่"],
        "de": ["Erdnüsse", "Schalentiere (Garnelen, Krebse, Muscheln)", "Fisch und Fischsauce", "Glutamat (MSG)", "Milch und Milchprodukte", "Weizen (Gluten)", "Eier"],
        "es": ["cacahuetes", "marisco (gambas, cangrejo, moluscos)", "pescado y salsa de pescado", "glutamato (MSG)", "leche y lácteos", "trigo (gluten)", "huevo"],
        "fr": ["arachides", "crustacés et coquillages (crevettes, crabe, moules)", "poisson et sauce de poisson", "glutamate (MSG)", "lait et produits laitiers", "blé (gluten)", "œufs"],
        "ja": ["ピーナッツ", "甲殻類・貝類（エビ、カニ、貝）", "魚・魚醤", "うま味調味料（MSG）", "牛乳・乳製品", "小麦（グルテン）", "卵"],
        "ko": ["땅콩", "갑각류·조개류(새우, 게, 조개)", "생선·액젓(피시소스)", "MSG(조미료)", "우유·유제품", "밀(글루텐)", "달걀"],
        "zh": ["花生", "甲壳类和贝类（虾、蟹、贝）", "鱼和鱼露", "味精", "牛奶和奶制品", "小麦（麸质）", "鸡蛋"],
        "vi": ["đậu phộng", "hải sản có vỏ (tôm, cua, sò)", "cá và nước mắm", "bột ngọt (mì chính)", "sữa và các sản phẩm từ sữa", "lúa mì (gluten)", "trứng"],
        "id": ["kacang tanah", "kerang dan udang-udangan (udang, kepiting, kerang)", "ikan dan kecap ikan", "MSG (penyedap rasa)", "susu dan produk susu", "gandum (gluten)", "telur"],
    ]

    /// [Einleitung mit %@, Warnung]. Thai mit {i} (ich) und {p} (Höflichkeitswort) – siehe Politeness.fill.
    private static let sentences: [String: [String]] = [
        "en": ["I am allergic to: %@.", "Even a small amount makes me seriously ill. Please do not put it in my food – not in sauce, oil or broth either."],
        "th": ["{i}แพ้: %@", "แม้เพียงเล็กน้อยก็ทำให้{i}ป่วยหนักได้ กรุณาอย่าใส่ในอาหารของ{i} รวมถึงซอส น้ำมัน และน้ำซุปด้วย{p}"],
        "de": ["Ich bin allergisch gegen: %@.", "Schon kleine Mengen machen mich schwer krank. Bitte nicht in mein Essen geben – auch nicht in Soße, Öl oder Brühe."],
        "es": ["Soy alérgico/a a: %@.", "Incluso una cantidad pequeña me enferma gravemente. Por favor, no lo ponga en mi comida, tampoco en salsas, aceite o caldo."],
        "fr": ["Je suis allergique à : %@.", "Même une petite quantité me rend gravement malade. Merci de ne pas en mettre dans mon plat, ni dans la sauce, l'huile ou le bouillon."],
        "ja": ["私は次の食品にアレルギーがあります：%@。", "ごく少量でも重い症状が出ます。ソース・油・スープも含めて、料理に使わないでください。"],
        "ko": ["저는 다음 음식에 알레르기가 있습니다: %@.", "아주 적은 양도 심각하게 아플 수 있습니다. 소스, 기름, 육수를 포함해 제 음식에 넣지 말아 주세요."],
        "zh": ["我对以下食物过敏：%@。", "即使很少量也会让我病得很严重。请不要放进我的食物里，包括酱汁、油和汤底。"],
        "vi": ["Tôi bị dị ứng với: %@.", "Chỉ một lượng nhỏ cũng có thể khiến tôi bị bệnh nặng. Xin đừng cho vào món ăn của tôi, kể cả nước sốt, dầu hoặc nước dùng."],
        "id": ["Saya alergi terhadap: %@.", "Sedikit saja bisa membuat saya sakit parah. Mohon jangan gunakan dalam makanan saya, termasuk saus, minyak, atau kaldu."],
    ]

    func name(_ lang: Lang) -> String? {
        Self.names[lang.rawValue].map { $0[Self.allCases.firstIndex(of: self)!] }
    }

    static func isCurated(_ lang: Lang) -> Bool { names[lang.rawValue] != nil }

    /// Warnkarte in `lang` (nil = nicht fest hinterlegt). Liste mit dem in der Sprache üblichen Trennzeichen.
    static func card(_ list: [Allergen], in lang: Lang, politeness: Politeness = .off) -> (title: String, warning: String)? {
        guard !list.isEmpty, let s = sentences[lang.rawValue] else { return nil }
        let sep = [Lang.ja, .zh].contains(lang) ? "、" : lang == .th ? " " : ", "
        let items = list.compactMap { $0.name(lang) }.joined(separator: sep)
        var title = String(format: s[0], items), warning = s[1]
        if lang == .th {
            let form = politeness == .off ? Politeness.male : politeness
            // „ich“ immer einsetzen; Höflichkeitswort nur, wenn gewünscht
            title = form.fill(title)
            warning = politeness == .off ? warning.replacingOccurrences(of: "{p}", with: "").replacingOccurrences(of: "{i}", with: form.pronoun)
                                         : form.fill(warning)
        }
        return (title, warning)
    }
}
