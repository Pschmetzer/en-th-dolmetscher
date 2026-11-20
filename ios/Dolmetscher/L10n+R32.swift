// L10n+R32.swift – Texte der Runde 32 (Taxi-Karte, Preishilfe, Notfall-Ablauf, Bildschirmschutz, Wort-Lexikon)
// in allen 10 Oberflächensprachen. de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft.
import Foundation

extension L10n {
    static let round32: [String: [String: String]] = [
        "r32_taxi": [
            "de": "Taxi-Karte", "en": "Taxi card", "th": "บัตรแท็กซี่", "es": "Tarjeta de taxi", "fr": "Carte taxi",
            "ja": "タクシーカード", "ko": "택시 카드", "zh-Hans": "出租车卡片", "vi": "Thẻ taxi", "id": "Kartu taksi"
        ],
        "r32_taxi_hint": [
            "de": "Tippen zeigt den Satz groß auf Thai, Lautsprecher spricht ihn.", "en": "Tap to show the phrase in large Thai script; the speaker says it out loud.",
            "th": "แตะเพื่อแสดงประโยคตัวใหญ่เป็นภาษาไทย ปุ่มลำโพงจะพูดให้ฟัง", "es": "Toca para mostrar la frase en tailandés grande; el altavoz la dice en voz alta.",
            "fr": "Touchez pour afficher la phrase en grand thaï ; le haut-parleur la dit à voix haute.", "ja": "タップするとタイ語を大きく表示し、スピーカーで読み上げます。",
            "ko": "탭하면 태국어를 크게 보여 주고 스피커로 읽어 줍니다.", "zh-Hans": "轻点以大号泰文显示该句，扬声器会朗读。",
            "vi": "Chạm để hiện câu bằng chữ Thái cỡ lớn; loa sẽ đọc to.", "id": "Ketuk untuk menampilkan kalimat dengan huruf Thai besar; pengeras suara membacakannya."
        ],
        "r32_price_help": [
            "de": "Preishilfe", "en": "Price helper", "th": "ตัวช่วยต่อราคา", "es": "Ayuda de precios", "fr": "Aide au marchandage",
            "ja": "値段交渉ヘルパー", "ko": "가격 흥정 도우미", "zh-Hans": "砍价助手", "vi": "Trợ giúp trả giá", "id": "Bantuan tawar-menawar"
        ],
        "r32_price_asked": [
            "de": "Verlangter Preis (Baht)", "en": "Asking price (baht)", "th": "ราคาที่เสนอ (บาท)", "es": "Precio pedido (baht)", "fr": "Prix demandé (bahts)",
            "ja": "提示価格（バーツ）", "ko": "부른 가격(바트)", "zh-Hans": "对方报价（泰铢）", "vi": "Giá người bán đưa (baht)", "id": "Harga yang diminta (baht)"
        ],
        "r32_price_counter": [
            "de": "Gegenangebot", "en": "Counter-offer", "th": "ราคาที่ต่อ", "es": "Contraoferta", "fr": "Contre-offre",
            "ja": "対案", "ko": "역제안", "zh-Hans": "还价", "vi": "Giá trả lại", "id": "Penawaran balik"
        ],
        "r32_emflow": [
            "de": "Notfall Schritt für Schritt", "en": "Emergency, step by step", "th": "ฉุกเฉิน ทีละขั้น", "es": "Emergencia paso a paso", "fr": "Urgence pas à pas",
            "ja": "緊急時の手順", "ko": "긴급 상황 단계별", "zh-Hans": "紧急情况分步指引", "vi": "Khẩn cấp từng bước", "id": "Darurat langkah demi langkah"
        ],
        "r32_emflow_1": [
            "de": "Ruhig atmen, an einen sicheren Ort gehen.", "en": "Breathe, move to a safe place.", "th": "หายใจลึก ๆ ไปยังที่ปลอดภัย",
            "es": "Respira y ve a un lugar seguro.", "fr": "Respirez, allez dans un endroit sûr.", "ja": "落ち着いて、安全な場所へ移動します。",
            "ko": "침착하게 숨 쉬고 안전한 곳으로 이동하세요.", "zh-Hans": "保持冷静，转移到安全的地方。", "vi": "Hít thở, di chuyển đến nơi an toàn.", "id": "Tarik napas, pindah ke tempat aman."
        ],
        "r32_emflow_2": [
            "de": "Passende Nummer wählen.", "en": "Call the right number.", "th": "โทรเบอร์ที่เหมาะสม",
            "es": "Llama al número adecuado.", "fr": "Appelez le bon numéro.", "ja": "適切な番号に電話します。",
            "ko": "알맞은 번호로 전화하세요.", "zh-Hans": "拨打合适的号码。", "vi": "Gọi đúng số khẩn cấp.", "id": "Hubungi nomor yang tepat."
        ],
        "r32_emflow_3": [
            "de": "Hilfe-Satz auf Thai zeigen oder abspielen.", "en": "Show or play the Thai help sentence.", "th": "แสดงหรือเล่นประโยคขอความช่วยเหลือภาษาไทย",
            "es": "Muestra o reproduce la frase de ayuda en tailandés.", "fr": "Montrez ou jouez la phrase d'aide en thaï.", "ja": "タイ語の助けを求める文を見せるか再生します。",
            "ko": "태국어 도움 문장을 보여 주거나 재생하세요.", "zh-Hans": "展示或播放泰语求助语句。", "vi": "Cho xem hoặc phát câu cầu cứu bằng tiếng Thái.", "id": "Tunjukkan atau putar kalimat minta tolong dalam bahasa Thai."
        ],
        "r32_emflow_4": [
            "de": "Standort teilen, Notfallkarte zeigen.", "en": "Share your location, show the emergency card.", "th": "แชร์ตำแหน่ง แสดงบัตรฉุกเฉิน",
            "es": "Comparte tu ubicación y muestra la tarjeta de emergencia.", "fr": "Partagez votre position, montrez la carte d'urgence.", "ja": "位置情報を共有し、緊急カードを見せます。",
            "ko": "위치를 공유하고 응급 카드를 보여 주세요.", "zh-Hans": "分享位置，出示紧急卡片。", "vi": "Chia sẻ vị trí, cho xem thẻ khẩn cấp.", "id": "Bagikan lokasi, tunjukkan kartu darurat."
        ],
        "r32_shield": [
            "de": "Bildschirmaufnahme erkannt. Inhalt verborgen.", "en": "Screen recording detected. Content hidden.", "th": "ตรวจพบการบันทึกหน้าจอ ซ่อนเนื้อหาแล้ว",
            "es": "Grabación de pantalla detectada. Contenido oculto.", "fr": "Enregistrement d'écran détecté. Contenu masqué.", "ja": "画面収録を検出しました。内容を非表示にしています。",
            "ko": "화면 녹화가 감지되어 내용을 숨겼습니다.", "zh-Hans": "检测到屏幕录制，内容已隐藏。", "vi": "Phát hiện ghi màn hình. Nội dung đã bị ẩn.", "id": "Perekaman layar terdeteksi. Konten disembunyikan."
        ],
        "r32_shield_set": [
            "de": "Inhalt bei Bildschirmaufnahme verbergen", "en": "Hide content during screen recording", "th": "ซ่อนเนื้อหาขณะบันทึกหน้าจอ",
            "es": "Ocultar contenido al grabar la pantalla", "fr": "Masquer le contenu pendant l'enregistrement d'écran", "ja": "画面収録中は内容を非表示",
            "ko": "화면 녹화 중 내용 숨기기", "zh-Hans": "屏幕录制时隐藏内容", "vi": "Ẩn nội dung khi ghi màn hình", "id": "Sembunyikan konten saat perekaman layar"
        ],
        "r32_words_hint": [
            "de": "Wort antippen für Umschrift und Bedeutung.", "en": "Tap a word for its romanization and meaning.", "th": "แตะคำเพื่อดูคำอ่านและความหมาย",
            "es": "Toca una palabra para ver su romanización y significado.", "fr": "Touchez un mot pour sa romanisation et son sens.", "ja": "単語をタップすると読みと意味が表示されます。",
            "ko": "단어를 탭하면 발음과 뜻을 볼 수 있습니다.", "zh-Hans": "轻点单词查看拼音和含义。", "vi": "Chạm vào từ để xem phiên âm và nghĩa.", "id": "Ketuk kata untuk romanisasi dan artinya."
        ],
        "r32_numbers_for": [
            "de": "Notrufnummern für %@", "en": "Emergency numbers for %@", "th": "เบอร์ฉุกเฉินสำหรับ %@", "es": "Números de emergencia para %@",
            "fr": "Numéros d'urgence pour %@", "ja": "%@の緊急電話番号", "ko": "%@ 긴급 전화번호", "zh-Hans": "%@的紧急电话", "vi": "Số khẩn cấp của %@", "id": "Nomor darurat untuk %@"
        ],
    ]
}
