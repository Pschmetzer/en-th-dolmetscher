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
        "help_title": [
            "de": "Kurzanleitung", "en": "Quick guide", "th": "คู่มือย่อ", "es": "Guía rápida", "fr": "Guide rapide", "ja": "クイックガイド", "ko": "빠른 안내", "zh-Hans": "快速指南", "vi": "Hướng dẫn nhanh", "id": "Panduan singkat",
        ],
        "help_s1_t": [
            "de": "Start drücken und sprechen", "en": "Press Start and talk", "th": "กด เริ่ม แล้วพูด", "es": "Pulsa Inicio y habla", "fr": "Appuyez sur Démarrer et parlez", "ja": "開始を押して話す", "ko": "시작을 누르고 말하기", "zh-Hans": "按开始并说话", "vi": "Nhấn Bắt đầu và nói", "id": "Tekan Mulai lalu bicara",
        ],
        "help_s1_b": [
            "de": "Die App erkennt die Sprache selbst und übersetzt in die andere.", "en": "The app detects the language itself and translates into the other one.", "th": "แอปตรวจจับภาษาเอง แล้วแปลเป็นอีกภาษา", "es": "La app detecta el idioma y traduce al otro.", "fr": "L’app détecte la langue et traduit vers l’autre.", "ja": "言語を自動で判別し、もう一方へ翻訳します。", "ko": "언어를 자동으로 감지해 다른 언어로 번역합니다.", "zh-Hans": "应用会自动识别语言并翻译成另一种语言。", "vi": "Ứng dụng tự nhận ngôn ngữ và dịch sang ngôn ngữ kia.", "id": "Aplikasi mendeteksi bahasa sendiri dan menerjemahkan ke bahasa lain.",
        ],
        "help_s2_t": [
            "de": "Gespräch mit Gegenüber", "en": "Talking face to face", "th": "คุยกับคนตรงข้าม", "es": "Conversación cara a cara", "fr": "Conversation en face à face", "ja": "向かい合って会話", "ko": "마주 보고 대화", "zh-Hans": "面对面交谈", "vi": "Trò chuyện đối mặt", "id": "Bercakap berhadapan",
        ],
        "help_s2_b": [
            "de": "Gesprächsmodus teilt den Bildschirm; die obere Hälfte ist für das Gegenüber gedreht.", "en": "Conversation mode splits the screen; the top half is turned for the other person.", "th": "โหมดสนทนาแบ่งหน้าจอ ครึ่งบนหันให้อีกฝ่าย", "es": "El modo conversación divide la pantalla; la mitad superior se gira hacia la otra persona.", "fr": "Le mode conversation partage l’écran ; la moitié haute est tournée vers l’autre personne.", "ja": "会話モードは画面を分割し、上半分が相手向きになります。", "ko": "대화 모드는 화면을 나누고 위쪽 절반이 상대방 쪽으로 돌아갑니다.", "zh-Hans": "对话模式会分屏,上半部分朝向对方。", "vi": "Chế độ hội thoại chia đôi màn hình; nửa trên xoay về phía người đối diện.", "id": "Mode percakapan membagi layar; bagian atas diputar menghadap lawan bicara.",
        ],
        "help_s3_t": [
            "de": "Nicht verstanden? Langsam wiederholen", "en": "Not understood? Repeat slowly", "th": "ไม่เข้าใจ? พูดซ้ำช้า ๆ", "es": "¿No se entendió? Repite despacio", "fr": "Pas compris ? Répétez lentement", "ja": "通じない?ゆっくり繰り返す", "ko": "못 알아들었나요? 천천히 다시", "zh-Hans": "没听懂?放慢重复", "vi": "Chưa hiểu? Nhắc lại chậm", "id": "Tidak paham? Ulangi pelan",
        ],
        "help_s3_b": [
            "de": "Das Schildkröten-Symbol unter einem Satz spricht ihn langsamer und deutlicher.", "en": "The tortoise icon under a sentence says it slower and clearer.", "th": "ไอคอนเต่าใต้ประโยคจะพูดช้าลงและชัดขึ้น", "es": "El icono de la tortuga bajo una frase la dice más lento y claro.", "fr": "L’icône tortue sous une phrase la dit plus lentement et clairement.", "ja": "文の下の亀のアイコンで、ゆっくりはっきり読み上げます。", "ko": "문장 아래 거북이 아이콘은 더 느리고 또렷하게 말합니다.", "zh-Hans": "句子下方的乌龟图标会更慢更清晰地朗读。", "vi": "Biểu tượng con rùa dưới câu sẽ đọc chậm và rõ hơn.", "id": "Ikon kura-kura di bawah kalimat membacakannya lebih pelan dan jelas.",
        ],
        "help_s4_t": [
            "de": "Daten bleiben auf dem Gerät", "en": "Your data stays on the device", "th": "ข้อมูลอยู่ในเครื่อง", "es": "Tus datos se quedan en el dispositivo", "fr": "Vos données restent sur l’appareil", "ja": "データは端末内に残ります", "ko": "데이터는 기기에 남습니다", "zh-Hans": "数据保留在设备上", "vi": "Dữ liệu ở lại trên thiết bị", "id": "Data tetap di perangkat",
        ],
        "help_s4_b": [
            "de": "Online-Übersetzung ist aus, solange du sie nicht einschaltest. Details unter Datenschutz in den Einstellungen.", "en": "Online translation stays off until you switch it on. Details under Privacy in Settings.", "th": "การแปลออนไลน์ปิดอยู่จนกว่าคุณจะเปิด ดูรายละเอียดที่ความเป็นส่วนตัวในการตั้งค่า", "es": "La traducción en línea está desactivada hasta que la actives. Detalles en Privacidad, en Ajustes.", "fr": "La traduction en ligne reste désactivée tant que vous ne l’activez pas. Détails dans Confidentialité, dans les Réglages.", "ja": "オンライン翻訳は有効にするまでオフです。詳細は設定のプライバシーをご覧ください。", "ko": "온라인 번역은 켜기 전까지 꺼져 있습니다. 자세한 내용은 설정의 개인정보 보호에서 확인하세요.", "zh-Hans": "在线翻译默认关闭,开启前不会使用。详情见设置中的隐私。", "vi": "Dịch trực tuyến luôn tắt cho đến khi bạn bật. Chi tiết trong Quyền riêng tư ở Cài đặt.", "id": "Terjemahan online mati sampai Anda menyalakannya. Detail di Privasi dalam Pengaturan.",
        ],
        "help_s5_t": [
            "de": "Tastatur und VoiceOver", "en": "Keyboard and VoiceOver", "th": "แป้นพิมพ์และ VoiceOver", "es": "Teclado y VoiceOver", "fr": "Clavier et VoiceOver", "ja": "キーボードとVoiceOver", "ko": "키보드와 VoiceOver", "zh-Hans": "键盘和旁白", "vi": "Bàn phím và VoiceOver", "id": "Keyboard dan VoiceOver",
        ],
        "help_s5_b": [
            "de": "⌘↩ startet und stoppt, ⌘B öffnet das Satzbuch, ⌘/ diese Hilfe. VoiceOver: Doppeltippen mit zwei Fingern startet und stoppt.", "en": "⌘↩ starts and stops, ⌘B opens the phrasebook, ⌘/ this help. VoiceOver: a two-finger double tap starts and stops.", "th": "⌘↩ เริ่มและหยุด, ⌘B เปิดสมุดวลี, ⌘/ เปิดวิธีใช้นี้ VoiceOver: แตะสองครั้งด้วยสองนิ้วเพื่อเริ่มและหยุด", "es": "⌘↩ inicia y detiene, ⌘B abre el libro de frases, ⌘/ esta ayuda. VoiceOver: doble toque con dos dedos inicia y detiene.", "fr": "⌘↩ démarre et arrête, ⌘B ouvre le recueil, ⌘/ cette aide. VoiceOver : double toucher à deux doigts pour démarrer et arrêter.", "ja": "⌘↩で開始/停止、⌘Bでフレーズ集、⌘/でこのヘルプ。VoiceOver:2本指でダブルタップすると開始/停止します。", "ko": "⌘↩로 시작/중지, ⌘B로 문장집, ⌘/로 이 도움말. VoiceOver: 두 손가락으로 두 번 탭하면 시작/중지합니다.", "zh-Hans": "⌘↩ 开始/停止,⌘B 打开短语本,⌘/ 打开本帮助。旁白:双指双击可开始/停止。", "vi": "⌘↩ bắt đầu/dừng, ⌘B mở sổ câu, ⌘/ mở trợ giúp này. VoiceOver: chạm đúp hai ngón để bắt đầu/dừng.", "id": "⌘↩ memulai/menghentikan, ⌘B membuka buku frasa, ⌘/ bantuan ini. VoiceOver: ketuk dua kali dengan dua jari untuk memulai/menghentikan.",
        ],
    ]
}
