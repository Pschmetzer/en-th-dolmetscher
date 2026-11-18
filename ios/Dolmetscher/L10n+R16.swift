// L10n+R16.swift – Texte der Runde 16 (Offline-Betrieb) in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft tests/test_runde16_ios.py.
import Foundation

extension L10n {
    static let round16: [String: [String: String]] = [
        "off_title": [
            "de": "Offline-Sprachpakete", "en": "Offline language packs",
            "th": "แพ็กภาษาออฟไลน์", "es": "Paquetes de idioma sin conexión",
            "fr": "Packs de langue hors ligne", "ja": "オフライン言語パック",
            "ko": "오프라인 언어 팩", "zh-Hans": "离线语言包",
            "vi": "Gói ngôn ngữ ngoại tuyến", "id": "Paket bahasa luring"
        ],
        "off_intro": [
            "de": "Damit alles ohne Netz läuft, müssen Erkennung, Übersetzung und Stimme auf dem iPhone liegen.", "en": "For everything to work without a network, recognition, translation and voice must be on the iPhone.",
            "th": "เพื่อให้ทุกอย่างทำงานโดยไม่มีเน็ต การรู้จำเสียง การแปล และเสียงพูดต้องอยู่ในเครื่อง", "es": "Para que todo funcione sin red, el reconocimiento, la traducción y la voz deben estar en el iPhone.",
            "fr": "Pour que tout fonctionne sans réseau, la reconnaissance, la traduction et la voix doivent être sur l'iPhone.", "ja": "ネットワークなしで使うには、音声認識・翻訳・音声が iPhone 内にある必要があります。",
            "ko": "네트워크 없이 쓰려면 음성 인식, 번역, 음성이 iPhone에 있어야 합니다.", "zh-Hans": "要在无网络时使用，语音识别、翻译和语音必须已在 iPhone 上。",
            "vi": "Để mọi thứ chạy không cần mạng, nhận dạng, dịch và giọng nói phải có sẵn trên iPhone.", "id": "Agar semuanya berjalan tanpa jaringan, pengenalan, terjemahan, dan suara harus ada di iPhone."
        ],
        "off_recognizer": [
            "de": "Erkennung %@", "en": "Recognition %@",
            "th": "การรู้จำเสียง %@", "es": "Reconocimiento %@",
            "fr": "Reconnaissance %@", "ja": "音声認識 %@",
            "ko": "음성 인식 %@", "zh-Hans": "语音识别 %@",
            "vi": "Nhận dạng %@", "id": "Pengenalan %@"
        ],
        "off_translation": [
            "de": "Übersetzung %@", "en": "Translation %@",
            "th": "การแปล %@", "es": "Traducción %@",
            "fr": "Traduction %@", "ja": "翻訳 %@",
            "ko": "번역 %@", "zh-Hans": "翻译 %@",
            "vi": "Dịch %@", "id": "Terjemahan %@"
        ],
        "off_voice": [
            "de": "Stimme %@", "en": "Voice %@",
            "th": "เสียงพูด %@", "es": "Voz %@",
            "fr": "Voix %@", "ja": "音声 %@",
            "ko": "음성 %@", "zh-Hans": "语音 %@",
            "vi": "Giọng nói %@", "id": "Suara %@"
        ],
        "off_ready": [
            "de": "Bereit", "en": "Ready",
            "th": "พร้อม", "es": "Listo",
            "fr": "Prêt", "ja": "準備完了",
            "ko": "준비됨", "zh-Hans": "就绪",
            "vi": "Sẵn sàng", "id": "Siap"
        ],
        "off_missing": [
            "de": "Fehlt", "en": "Missing",
            "th": "ยังไม่มี", "es": "Falta",
            "fr": "Manquant", "ja": "未取得",
            "ko": "없음", "zh-Hans": "缺少",
            "vi": "Thiếu", "id": "Belum ada"
        ],
        "off_loading": [
            "de": "Lädt …", "en": "Loading …",
            "th": "กำลังโหลด …", "es": "Descargando …",
            "fr": "Téléchargement …", "ja": "読み込み中 …",
            "ko": "내려받는 중 …", "zh-Hans": "正在下载 …",
            "vi": "Đang tải …", "id": "Mengunduh …"
        ],
        "off_unavailable": [
            "de": "Nicht verfügbar", "en": "Not available",
            "th": "ไม่พร้อมใช้งาน", "es": "No disponible",
            "fr": "Indisponible", "ja": "利用不可",
            "ko": "사용할 수 없음", "zh-Hans": "不可用",
            "vi": "Không khả dụng", "id": "Tidak tersedia"
        ],
        "off_load": [
            "de": "Laden", "en": "Download",
            "th": "โหลด", "es": "Descargar",
            "fr": "Télécharger", "ja": "ダウンロード",
            "ko": "내려받기", "zh-Hans": "下载",
            "vi": "Tải", "id": "Unduh"
        ],
        "off_load_all": [
            "de": "Fehlende Pakete laden", "en": "Download missing packs",
            "th": "โหลดแพ็กที่ขาด", "es": "Descargar paquetes que faltan",
            "fr": "Télécharger les packs manquants", "ja": "不足しているパックをダウンロード",
            "ko": "없는 팩 내려받기", "zh-Hans": "下载缺少的包",
            "vi": "Tải các gói còn thiếu", "id": "Unduh paket yang kurang"
        ],
        "off_size": [
            "de": "Ca. %@ zu laden, am besten über WLAN.", "en": "About %@ to download, best over Wi-Fi.",
            "th": "ต้องโหลดประมาณ %@ ควรใช้ Wi-Fi", "es": "Unos %@ por descargar, mejor con Wi-Fi.",
            "fr": "Environ %@ à télécharger, de préférence en Wi-Fi.", "ja": "約 %@ をダウンロードします。Wi-Fi 推奨。",
            "ko": "약 %@를 내려받아야 합니다. Wi-Fi를 권장합니다.", "zh-Hans": "需下载约 %@，建议使用 Wi-Fi。",
            "vi": "Cần tải khoảng %@, nên dùng Wi-Fi.", "id": "Sekitar %@ untuk diunduh, sebaiknya lewat Wi-Fi."
        ],
        "off_voice_hint": [
            "de": "Stimmen lädst du in iOS: Einstellungen > Bedienungshilfen > Gesprochene Inhalte > Stimmen.", "en": "Voices are loaded in iOS: Settings > Accessibility > Spoken Content > Voices.",
            "th": "เสียงพูดโหลดใน iOS: การตั้งค่า > การเข้าถึง > เนื้อหาที่พูด > เสียง", "es": "Las voces se descargan en iOS: Ajustes > Accesibilidad > Contenido hablado > Voces.",
            "fr": "Les voix se téléchargent dans iOS : Réglages > Accessibilité > Contenu énoncé > Voix.", "ja": "音声は iOS で追加します：設定 > アクセシビリティ > 読み上げコンテンツ > 声。",
            "ko": "음성은 iOS에서 받습니다: 설정 > 손쉬운 사용 > 음성 콘텐츠 > 음성.", "zh-Hans": "语音需在 iOS 中下载：设置 > 辅助功能 > 朗读内容 > 声音。",
            "vi": "Giọng nói tải trong iOS: Cài đặt > Trợ năng > Nội dung đọc > Giọng nói.", "id": "Suara diunduh di iOS: Pengaturan > Aksesibilitas > Konten Terucap > Suara."
        ],
        "off_unavail_hint": [
            "de": "Für diese Sprache gibt es auf dem iPhone keine Offline-Lösung.", "en": "There is no offline option on the iPhone for this language.",
            "th": "ภาษานี้ไม่มีตัวเลือกออฟไลน์บน iPhone", "es": "Este idioma no tiene opción sin conexión en el iPhone.",
            "fr": "Cette langue n'a pas d'option hors ligne sur l'iPhone.", "ja": "この言語は iPhone ではオフラインに対応していません。",
            "ko": "이 언어는 iPhone에서 오프라인을 지원하지 않습니다.", "zh-Hans": "iPhone 上此语言没有离线方案。",
            "vi": "Ngôn ngữ này không có tùy chọn ngoại tuyến trên iPhone.", "id": "Bahasa ini tidak punya opsi luring di iPhone."
        ],
        "off_warn_missing": [
            "de": "Ohne Netz würde etwas fehlen: %@. Lade es vor der Reise über WLAN.", "en": "Without a network something would be missing: %@. Download it before the trip over Wi-Fi.",
            "th": "ถ้าไม่มีเน็ตจะขาด: %@ โหลดก่อนเดินทางผ่าน Wi-Fi", "es": "Sin red faltaría: %@. Descárgalo antes del viaje con Wi-Fi.",
            "fr": "Sans réseau il manquerait : %@. Téléchargez-le avant le voyage en Wi-Fi.", "ja": "ネットワークがないと不足します：%@。旅行前に Wi-Fi でダウンロードしてください。",
            "ko": "네트워크가 없으면 부족합니다: %@. 여행 전에 Wi-Fi로 내려받으세요.", "zh-Hans": "没有网络时会缺少：%@。请在出发前用 Wi-Fi 下载。",
            "vi": "Không có mạng sẽ thiếu: %@. Hãy tải trước chuyến đi qua Wi-Fi.", "id": "Tanpa jaringan akan kurang: %@. Unduh sebelum bepergian lewat Wi-Fi."
        ],
        "off_warn_limited": [
            "de": "Ohne Netz geht dieses Paar nur teilweise: %@ gibt es auf diesem iPhone nicht offline.", "en": "Without a network this pair works only in part: %@ is not available offline on this iPhone.",
            "th": "ถ้าไม่มีเน็ต คู่ภาษานี้ใช้ได้บางส่วน: %@ ไม่มีแบบออฟไลน์บน iPhone เครื่องนี้", "es": "Sin red este par solo funciona en parte: %@ no está disponible sin conexión en este iPhone.",
            "fr": "Sans réseau cette paire ne fonctionne qu'en partie : %@ n'est pas disponible hors ligne sur cet iPhone.", "ja": "ネットワークがないと、この組み合わせは一部しか使えません：%@ はこの iPhone ではオフラインで使えません。",
            "ko": "네트워크가 없으면 이 언어쌍은 일부만 작동합니다: %@는 이 iPhone에서 오프라인으로 쓸 수 없습니다.", "zh-Hans": "没有网络时，这对语言只能部分使用：%@ 在此 iPhone 上无法离线使用。",
            "vi": "Không có mạng, cặp này chỉ chạy một phần: %@ không có ngoại tuyến trên iPhone này.", "id": "Tanpa jaringan, pasangan ini hanya berfungsi sebagian: %@ tidak tersedia luring di iPhone ini."
        ],
        "off_all_ok": [
            "de": "Dieses Paar funktioniert komplett ohne Netz: Erkennung, Übersetzung und Stimme.", "en": "This pair works fully without a network: recognition, translation and voice.",
            "th": "คู่ภาษานี้ใช้ได้เต็มที่โดยไม่ต้องมีเน็ต: การรู้จำเสียง การแปล และเสียงพูด", "es": "Este par funciona totalmente sin red: reconocimiento, traducción y voz.",
            "fr": "Cette paire fonctionne entièrement sans réseau : reconnaissance, traduction et voix.", "ja": "この組み合わせはネットワークなしで完全に使えます：音声認識、翻訳、音声。",
            "ko": "이 언어쌍은 네트워크 없이 완전히 작동합니다: 음성 인식, 번역, 음성.", "zh-Hans": "这对语言可完全离线使用：语音识别、翻译和语音。",
            "vi": "Cặp này chạy hoàn toàn không cần mạng: nhận dạng, dịch và giọng nói.", "id": "Pasangan ini berfungsi penuh tanpa jaringan: pengenalan, terjemahan, dan suara."
        ],
        "off_phrasebook": [
            "de": "Das Satzbuch funktioniert immer ohne Netz, auch ohne diese Pakete.", "en": "The phrasebook always works without a network, even without these packs.",
            "th": "สมุดวลีใช้ได้เสมอโดยไม่ต้องมีเน็ต แม้ไม่มีแพ็กเหล่านี้", "es": "El libro de frases siempre funciona sin red, incluso sin estos paquetes.",
            "fr": "Le carnet de phrases fonctionne toujours sans réseau, même sans ces packs.", "ja": "フレーズ集は、これらのパックがなくても常にネットワークなしで使えます。",
            "ko": "문장집은 이 팩이 없어도 항상 네트워크 없이 작동합니다.", "zh-Hans": "常用语手册始终无需网络，即使没有这些包。",
            "vi": "Sổ câu luôn chạy không cần mạng, kể cả khi không có các gói này.", "id": "Buku frasa selalu berfungsi tanpa jaringan, bahkan tanpa paket ini."
        ],
        "off_only": [
            "de": "Nur offline", "en": "Offline only",
            "th": "ออฟไลน์เท่านั้น", "es": "Solo sin conexión",
            "fr": "Hors ligne uniquement", "ja": "オフラインのみ",
            "ko": "오프라인 전용", "zh-Hans": "仅离线",
            "vi": "Chỉ ngoại tuyến", "id": "Hanya luring"
        ],
        "off_only_note": [
            "de": "Nichts geht ins Netz: weder Übersetzung noch Wechselkurs noch Sprachmodell-Download. Das Laden der Sprachpakete durch iOS bleibt möglich.", "en": "Nothing goes online: no translation, exchange rate or speech-model download. iOS can still download the language packs.",
            "th": "ไม่มีอะไรส่งออกเน็ต: ไม่แปลออนไลน์ ไม่ดึงอัตราแลกเปลี่ยน ไม่โหลดโมเดลเสียง แต่ iOS ยังโหลดแพ็กภาษาได้", "es": "Nada sale a la red: ni traducción, ni tipo de cambio, ni descarga de modelos de voz. iOS aún puede descargar los paquetes de idioma.",
            "fr": "Rien ne part en ligne : ni traduction, ni taux de change, ni téléchargement de modèle vocal. iOS peut toujours télécharger les packs de langue.", "ja": "何もネットに送りません：翻訳、為替レート、音声モデルのダウンロードもなし。言語パックの iOS によるダウンロードは可能です。",
            "ko": "아무것도 온라인으로 보내지 않습니다: 번역, 환율, 음성 모델 내려받기 모두 없음. iOS의 언어 팩 내려받기는 가능합니다.", "zh-Hans": "不会联网发送任何内容：不在线翻译、不查汇率、不下载语音模型。iOS 仍可下载语言包。",
            "vi": "Không gì được gửi lên mạng: không dịch, không tỷ giá, không tải mô hình giọng nói. iOS vẫn có thể tải gói ngôn ngữ.", "id": "Tidak ada yang dikirim ke jaringan: tanpa terjemahan, kurs, atau unduhan model suara. iOS tetap bisa mengunduh paket bahasa."
        ],
        "off_only_banner": [
            "de": "Nur offline: nichts wird gesendet", "en": "Offline only: nothing is sent",
            "th": "ออฟไลน์เท่านั้น: ไม่ส่งอะไรออกไป", "es": "Solo sin conexión: no se envía nada",
            "fr": "Hors ligne uniquement : rien n'est envoyé", "ja": "オフラインのみ：何も送信しません",
            "ko": "오프라인 전용: 아무것도 전송하지 않음", "zh-Hans": "仅离线：不发送任何内容",
            "vi": "Chỉ ngoại tuyến: không gửi gì", "id": "Hanya luring: tidak ada yang dikirim"
        ],
        "err_offline_only": [
            "de": "Nur-offline-Modus: Das Übersetzungspaket fehlt. Lade es unter Einstellungen > Offline-Sprachpakete.", "en": "Offline-only mode: the translation pack is missing. Download it under Settings > Offline language packs.",
            "th": "โหมดออฟไลน์เท่านั้น: ไม่มีแพ็กแปลภาษา โหลดได้ที่ การตั้งค่า > แพ็กภาษาออฟไลน์", "es": "Modo solo sin conexión: falta el paquete de traducción. Descárgalo en Ajustes > Paquetes de idioma sin conexión.",
            "fr": "Mode hors ligne uniquement : le pack de traduction manque. Téléchargez-le dans Réglages > Packs de langue hors ligne.", "ja": "オフラインのみモード：翻訳パックがありません。設定 > オフライン言語パックでダウンロードしてください。",
            "ko": "오프라인 전용 모드: 번역 팩이 없습니다. 설정 > 오프라인 언어 팩에서 내려받으세요.", "zh-Hans": "仅离线模式：缺少翻译包。请在 设置 > 离线语言包 中下载。",
            "vi": "Chế độ chỉ ngoại tuyến: thiếu gói dịch. Tải tại Cài đặt > Gói ngôn ngữ ngoại tuyến.", "id": "Mode hanya luring: paket terjemahan belum ada. Unduh di Pengaturan > Paket bahasa luring."
        ],
        "off_blocked": [
            "de": "Im Nur-offline-Modus gesperrt. Schalte ihn unter Einstellungen > Offline-Sprachpakete aus, wenn du laden willst.", "en": "Blocked in offline-only mode. Turn it off under Settings > Offline language packs to download.",
            "th": "ถูกบล็อกในโหมดออฟไลน์เท่านั้น ปิดโหมดที่ การตั้งค่า > แพ็กภาษาออฟไลน์ หากต้องการโหลด", "es": "Bloqueado en modo solo sin conexión. Desactívalo en Ajustes > Paquetes de idioma sin conexión para descargar.",
            "fr": "Bloqué en mode hors ligne uniquement. Désactivez-le dans Réglages > Packs de langue hors ligne pour télécharger.", "ja": "オフラインのみモードでは使えません。ダウンロードするには 設定 > オフライン言語パック でオフにしてください。",
            "ko": "오프라인 전용 모드에서는 차단됩니다. 내려받으려면 설정 > 오프라인 언어 팩에서 끄세요.", "zh-Hans": "仅离线模式下已被阻止。要下载，请在 设置 > 离线语言包 中关闭该模式。",
            "vi": "Bị chặn trong chế độ chỉ ngoại tuyến. Tắt tại Cài đặt > Gói ngôn ngữ ngoại tuyến để tải.", "id": "Diblokir di mode hanya luring. Matikan di Pengaturan > Paket bahasa luring untuk mengunduh."
        ]
    ]
}
