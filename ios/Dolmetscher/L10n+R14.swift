// L10n+R14.swift – Texte der Runde 14 (Erststart und Berechtigungen) in allen 10 Oberflächensprachen (Schlüssel -> Sprache -> Text).
// de/en/th von Hand, die übrigen MASCHINELL ÜBERSETZT und nicht muttersprachlich geprüft. Vollständigkeit prüft Round14Tests.
import Foundation

extension L10n {
    static let round14: [String: [String: String]] = [
        "ob_title": [
            "de": "Willkommen", "en": "Welcome",
            "th": "ยินดีต้อนรับ", "es": "Bienvenido",
            "fr": "Bienvenue", "ja": "ようこそ",
            "ko": "환영합니다", "zh-Hans": "欢迎",
            "vi": "Chào mừng", "id": "Selamat datang"
        ],
        "ob_step": [
            "de": "Schritt %d von %d", "en": "Step %d of %d",
            "th": "ขั้นที่ %d จาก %d", "es": "Paso %d de %d",
            "fr": "Étape %d sur %d", "ja": "ステップ %d / %d",
            "ko": "%d/%d 단계", "zh-Hans": "第 %d 步，共 %d 步",
            "vi": "Bước %d/%d", "id": "Langkah %d dari %d"
        ],
        "ob_pair_t": [
            "de": "Welche Sprachen sprecht ihr?", "en": "Which languages do you speak?",
            "th": "คุณพูดภาษาอะไรกัน", "es": "¿Qué idiomas habláis?",
            "fr": "Quelles langues parlez-vous ?", "ja": "どの言語で話しますか？",
            "ko": "어떤 언어로 대화하나요?", "zh-Hans": "你们说哪两种语言？",
            "vi": "Bạn nói những ngôn ngữ nào?", "id": "Bahasa apa yang Anda gunakan?"
        ],
        "ob_pair_b": [
            "de": "Wähle deine Sprache und die deines Gegenübers. Das lässt sich später in den Einstellungen ändern.", "en": "Choose your language and the one of the person opposite. You can change this later in Settings.",
            "th": "เลือกภาษาของคุณและภาษาของคู่สนทนา เปลี่ยนภายหลังได้ในการตั้งค่า", "es": "Elige tu idioma y el de la otra persona. Puedes cambiarlo más tarde en Ajustes.",
            "fr": "Choisissez votre langue et celle de votre interlocuteur. Vous pourrez la modifier plus tard dans Réglages.", "ja": "自分の言語と相手の言語を選んでください。あとで設定から変更できます。",
            "ko": "내 언어와 상대방의 언어를 선택하세요. 나중에 설정에서 바꿀 수 있습니다.", "zh-Hans": "选择你的语言和对方的语言。之后可以在设置中更改。",
            "vi": "Chọn ngôn ngữ của bạn và của người đối diện. Bạn có thể đổi sau trong Cài đặt.", "id": "Pilih bahasa Anda dan bahasa lawan bicara. Bisa diubah nanti di Pengaturan."
        ],
        "ob_mic_t": [
            "de": "Warum das Mikrofon?", "en": "Why the microphone?",
            "th": "ทำไมต้องใช้ไมโครโฟน", "es": "¿Por qué el micrófono?",
            "fr": "Pourquoi le microphone ?", "ja": "なぜマイクが必要？",
            "ko": "마이크가 필요한 이유", "zh-Hans": "为什么需要麦克风？",
            "vi": "Vì sao cần micrô?", "id": "Mengapa perlu mikrofon?"
        ],
        "ob_mic_b": [
            "de": "Das Mikrofon hört das Gespräch, damit die App es übersetzen kann. Die Erkennung läuft auf dem iPhone; Aufnahmen werden nicht gespeichert. Gleich fragt iOS dich um Erlaubnis.", "en": "The microphone listens to the conversation so the app can translate it. Recognition runs on the iPhone; recordings are not saved. iOS will ask for your permission next.",
            "th": "ไมโครโฟนฟังบทสนทนาเพื่อให้แอปแปลได้ การรู้จำเสียงทำงานบน iPhone และไม่บันทึกเสียง ต่อไป iOS จะขออนุญาตจากคุณ", "es": "El micrófono escucha la conversación para que la app pueda traducirla. El reconocimiento se hace en el iPhone y no se guardan grabaciones. A continuación iOS te pedirá permiso.",
            "fr": "Le microphone écoute la conversation pour que l'app puisse la traduire. La reconnaissance se fait sur l'iPhone ; aucun enregistrement n'est conservé. iOS va maintenant vous demander l'autorisation.", "ja": "マイクは会話を聞き取り、アプリが翻訳できるようにします。認識は iPhone 上で行われ、録音は保存されません。このあと iOS が許可を求めます。",
            "ko": "마이크는 앱이 번역할 수 있도록 대화를 듣습니다. 인식은 iPhone에서 처리되며 녹음은 저장되지 않습니다. 다음으로 iOS가 권한을 요청합니다.", "zh-Hans": "麦克风用来听取对话，以便应用翻译。识别在 iPhone 上完成，不会保存录音。接下来 iOS 会请求你的许可。",
            "vi": "Micrô nghe cuộc trò chuyện để ứng dụng có thể dịch. Nhận dạng chạy trên iPhone và không lưu bản ghi âm. Tiếp theo iOS sẽ xin phép bạn.", "id": "Mikrofon mendengarkan percakapan agar aplikasi bisa menerjemahkan. Pengenalan berjalan di iPhone dan rekaman tidak disimpan. Selanjutnya iOS akan meminta izin Anda."
        ],
        "ob_speech_t": [
            "de": "Warum die Spracherkennung?", "en": "Why speech recognition?",
            "th": "ทำไมต้องรู้จำเสียงพูด", "es": "¿Por qué el reconocimiento de voz?",
            "fr": "Pourquoi la reconnaissance vocale ?", "ja": "なぜ音声認識が必要？",
            "ko": "음성 인식이 필요한 이유", "zh-Hans": "为什么需要语音识别？",
            "vi": "Vì sao cần nhận dạng giọng nói?", "id": "Mengapa perlu pengenalan ucapan?"
        ],
        "ob_speech_b": [
            "de": "Die Spracherkennung macht aus dem Gesprochenen Text. Das passiert auf dem Gerät mit den Sprachpaketen von Apple. Ohne diese Freigabe kann die Erkennung eingeschränkt sein.", "en": "Speech recognition turns what is said into text. It happens on the device with Apple's language packs. Without this permission, recognition may be limited.",
            "th": "การรู้จำเสียงพูดเปลี่ยนคำพูดเป็นข้อความ ทำงานบนอุปกรณ์ด้วยชุดภาษาของ Apple หากไม่อนุญาต การรู้จำอาจถูกจำกัด", "es": "El reconocimiento de voz convierte lo hablado en texto. Se hace en el dispositivo con los paquetes de idioma de Apple. Sin este permiso, el reconocimiento puede quedar limitado.",
            "fr": "La reconnaissance vocale transforme la parole en texte. Elle s'effectue sur l'appareil avec les modules de langue d'Apple. Sans cette autorisation, la reconnaissance peut être limitée.", "ja": "音声認識は話した内容をテキストに変換します。処理は Apple の言語パックを使って端末上で行われます。この許可がないと、認識が制限されることがあります。",
            "ko": "음성 인식은 말한 내용을 텍스트로 바꿉니다. Apple 언어 팩을 사용해 기기에서 처리됩니다. 권한이 없으면 인식이 제한될 수 있습니다.", "zh-Hans": "语音识别把说的话转成文字。它使用 Apple 的语言包在设备上完成。没有此权限，识别可能受限。",
            "vi": "Nhận dạng giọng nói chuyển lời nói thành văn bản. Việc này diễn ra trên thiết bị bằng gói ngôn ngữ của Apple. Không có quyền này, nhận dạng có thể bị hạn chế.", "id": "Pengenalan ucapan mengubah ucapan menjadi teks. Prosesnya berjalan di perangkat dengan paket bahasa Apple. Tanpa izin ini, pengenalan bisa terbatas."
        ],
        "ob_packs_t": [
            "de": "Offline-Sprachpakete", "en": "Offline language packs",
            "th": "ชุดภาษาออฟไลน์", "es": "Paquetes de idioma sin conexión",
            "fr": "Modules de langue hors ligne", "ja": "オフライン言語パック",
            "ko": "오프라인 언어 팩", "zh-Hans": "离线语言包",
            "vi": "Gói ngôn ngữ ngoại tuyến", "id": "Paket bahasa offline"
        ],
        "ob_packs_b": [
            "de": "Damit alles ohne Netz funktioniert, lädt iOS einmalig Sprachmodelle und Übersetzungspakete: ca. %@. Am besten im WLAN.", "en": "So everything works without a network, iOS downloads speech models and translation packs once: about %@. Best on Wi-Fi.",
            "th": "เพื่อให้ใช้งานได้โดยไม่ต้องมีเครือข่าย iOS จะดาวน์โหลดโมเดลเสียงและชุดแปลหนึ่งครั้ง ประมาณ %@ ควรใช้ Wi-Fi", "es": "Para que todo funcione sin red, iOS descarga una vez modelos de voz y paquetes de traducción: unos %@. Mejor con Wi-Fi.",
            "fr": "Pour tout utiliser sans réseau, iOS télécharge une fois les modèles vocaux et les modules de traduction : environ %@. De préférence en Wi-Fi.", "ja": "ネットワークなしで使えるよう、iOS が音声モデルと翻訳パックを一度ダウンロードします（約 %@）。Wi-Fi 推奨。",
            "ko": "네트워크 없이 사용하도록 iOS가 음성 모델과 번역 팩을 한 번 내려받습니다(약 %@). Wi-Fi 권장.", "zh-Hans": "为了无网络也能使用，iOS 会一次性下载语音模型和翻译包，约 %@。建议使用 Wi-Fi。",
            "vi": "Để mọi thứ chạy không cần mạng, iOS tải một lần mô hình giọng nói và gói dịch: khoảng %@. Nên dùng Wi-Fi.", "id": "Agar semuanya berjalan tanpa jaringan, iOS mengunduh model ucapan dan paket terjemahan sekali: sekitar %@. Sebaiknya lewat Wi-Fi."
        ],
        "ob_packs_none": [
            "de": "Alles Nötige ist schon auf dem iPhone. Nichts zu laden.", "en": "Everything needed is already on this iPhone. Nothing to download.",
            "th": "ทุกอย่างที่จำเป็นอยู่ใน iPhone แล้ว ไม่ต้องดาวน์โหลด", "es": "Todo lo necesario ya está en este iPhone. Nada que descargar.",
            "fr": "Tout le nécessaire est déjà sur cet iPhone. Rien à télécharger.", "ja": "必要なものはすべてこの iPhone に入っています。ダウンロードは不要です。",
            "ko": "필요한 것이 모두 이 iPhone에 있습니다. 내려받을 것이 없습니다.", "zh-Hans": "所需内容已在这台 iPhone 上，无需下载。",
            "vi": "Mọi thứ cần thiết đã có trên iPhone này. Không cần tải gì.", "id": "Semua yang diperlukan sudah ada di iPhone ini. Tidak ada yang perlu diunduh."
        ],
        "ob_packs_load": [
            "de": "Jetzt laden", "en": "Download now",
            "th": "ดาวน์โหลดตอนนี้", "es": "Descargar ahora",
            "fr": "Télécharger maintenant", "ja": "今すぐダウンロード",
            "ko": "지금 내려받기", "zh-Hans": "立即下载",
            "vi": "Tải ngay", "id": "Unduh sekarang"
        ],
        "ob_test_t": [
            "de": "Test-Satz", "en": "Test sentence",
            "th": "ประโยคทดสอบ", "es": "Frase de prueba",
            "fr": "Phrase d'essai", "ja": "テスト文",
            "ko": "테스트 문장", "zh-Hans": "测试句",
            "vi": "Câu thử", "id": "Kalimat uji"
        ],
        "ob_test_b": [
            "de": "Probiere die Übersetzung mit einem Beispielsatz aus: Du siehst die Übersetzung und hörst die Stimme.", "en": "Try the translation with an example sentence: you see the translation and hear the voice.",
            "th": "ลองแปลด้วยประโยคตัวอย่าง คุณจะเห็นคำแปลและได้ยินเสียงพูด", "es": "Prueba la traducción con una frase de ejemplo: verás la traducción y oirás la voz.",
            "fr": "Essayez la traduction avec une phrase d'exemple : vous verrez la traduction et entendrez la voix.", "ja": "例文で翻訳を試しましょう。翻訳が表示され、音声が再生されます。",
            "ko": "예문으로 번역을 시험해 보세요. 번역이 표시되고 음성이 재생됩니다.", "zh-Hans": "用示例句试一下翻译：你会看到译文并听到语音。",
            "vi": "Thử bản dịch bằng một câu mẫu: bạn sẽ thấy bản dịch và nghe giọng đọc.", "id": "Coba terjemahan dengan kalimat contoh: Anda melihat terjemahan dan mendengar suaranya."
        ],
        "ob_test_go": [
            "de": "Test-Satz übersetzen", "en": "Translate the test sentence",
            "th": "แปลประโยคทดสอบ", "es": "Traducir la frase de prueba",
            "fr": "Traduire la phrase d'essai", "ja": "テスト文を翻訳",
            "ko": "테스트 문장 번역", "zh-Hans": "翻译测试句",
            "vi": "Dịch câu thử", "id": "Terjemahkan kalimat uji"
        ],
        "ob_next": [
            "de": "Weiter", "en": "Next",
            "th": "ถัดไป", "es": "Siguiente",
            "fr": "Suivant", "ja": "次へ",
            "ko": "다음", "zh-Hans": "下一步",
            "vi": "Tiếp", "id": "Lanjut"
        ],
        "ob_back": [
            "de": "Zurück", "en": "Back",
            "th": "ย้อนกลับ", "es": "Atrás",
            "fr": "Retour", "ja": "戻る",
            "ko": "뒤로", "zh-Hans": "返回",
            "vi": "Quay lại", "id": "Kembali"
        ],
        "ob_later": [
            "de": "Später", "en": "Later",
            "th": "ภายหลัง", "es": "Más tarde",
            "fr": "Plus tard", "ja": "あとで",
            "ko": "나중에", "zh-Hans": "稍后",
            "vi": "Để sau", "id": "Nanti"
        ],
        "ob_allow": [
            "de": "Erlauben …", "en": "Allow …",
            "th": "อนุญาต …", "es": "Permitir …",
            "fr": "Autoriser …", "ja": "許可する …",
            "ko": "허용 …", "zh-Hans": "允许 …",
            "vi": "Cho phép …", "id": "Izinkan …"
        ],
        "ob_start": [
            "de": "Los geht's", "en": "Let's go",
            "th": "เริ่มเลย", "es": "¡Vamos!",
            "fr": "C'est parti", "ja": "始めましょう",
            "ko": "시작하기", "zh-Hans": "开始",
            "vi": "Bắt đầu", "id": "Mulai"
        ],
        "ob_granted": [
            "de": "Erlaubt", "en": "Allowed",
            "th": "อนุญาตแล้ว", "es": "Permitido",
            "fr": "Autorisé", "ja": "許可済み",
            "ko": "허용됨", "zh-Hans": "已允许",
            "vi": "Đã cho phép", "id": "Diizinkan"
        ],
        "ob_mic_denied": [
            "de": "Mikrofon ist ausgeschaltet. Ohne Mikrofon kann die App nicht zuhören. Erlaube es in den Einstellungen unter „Mikrofon“.", "en": "The microphone is turned off. Without it the app cannot listen. Allow it in Settings under “Microphone”.",
            "th": "ไมโครโฟนปิดอยู่ หากไม่มีไมโครโฟน แอปจะฟังไม่ได้ โปรดอนุญาตในการตั้งค่าที่ “ไมโครโฟน”", "es": "El micrófono está desactivado. Sin él la app no puede escuchar. Permítelo en Ajustes, en «Micrófono».",
            "fr": "Le microphone est désactivé. Sans lui, l'app ne peut pas écouter. Autorisez-le dans Réglages, sous « Microphone ».", "ja": "マイクがオフです。マイクがないとアプリは聞き取れません。設定の「マイク」で許可してください。",
            "ko": "마이크가 꺼져 있습니다. 마이크가 없으면 앱이 들을 수 없습니다. 설정의 '마이크'에서 허용하세요.", "zh-Hans": "麦克风已关闭，没有麦克风应用无法聆听。请在设置的“麦克风”中允许。",
            "vi": "Micrô đang tắt. Không có micrô, ứng dụng không thể nghe. Hãy cho phép trong Cài đặt, mục “Micrô”.", "id": "Mikrofon dimatikan. Tanpa mikrofon, aplikasi tidak bisa mendengar. Izinkan di Pengaturan pada “Mikrofon”."
        ],
        "ob_mic_restricted": [
            "de": "Das Mikrofon ist eingeschränkt, z. B. durch Bildschirmzeit oder eine Geräteverwaltung. Prüfe die Einstellungen oder frage die Person, die das Gerät verwaltet.", "en": "The microphone is restricted, e.g. by Screen Time or device management. Check Settings or ask whoever manages this device.",
            "th": "ไมโครโฟนถูกจำกัด เช่น โดยเวลาหน้าจอหรือการจัดการอุปกรณ์ ตรวจสอบการตั้งค่าหรือสอบถามผู้ดูแลอุปกรณ์", "es": "El micrófono está restringido, p. ej. por Tiempo de uso o la gestión del dispositivo. Revisa Ajustes o pregunta a quien administra el dispositivo.",
            "fr": "Le microphone est restreint, par ex. par Temps d'écran ou la gestion de l'appareil. Vérifiez Réglages ou demandez à la personne qui gère l'appareil.", "ja": "マイクはスクリーンタイムやデバイス管理などで制限されています。設定を確認するか、デバイスの管理者に問い合わせてください。",
            "ko": "마이크가 스크린 타임이나 기기 관리 등으로 제한되어 있습니다. 설정을 확인하거나 기기 관리자에게 문의하세요.", "zh-Hans": "麦克风受到限制，例如被“屏幕使用时间”或设备管理限制。请检查设置，或询问设备管理者。",
            "vi": "Micrô bị hạn chế, ví dụ bởi Thời gian sử dụng hoặc quản lý thiết bị. Hãy kiểm tra Cài đặt hoặc hỏi người quản lý thiết bị.", "id": "Mikrofon dibatasi, mis. oleh Waktu Layar atau manajemen perangkat. Periksa Pengaturan atau tanyakan kepada pengelola perangkat."
        ],
        "ob_speech_denied": [
            "de": "Spracherkennung ist ausgeschaltet. Die Erkennung kann eingeschränkt sein. Erlaube sie in den Einstellungen unter „Spracherkennung“.", "en": "Speech recognition is turned off. Recognition may be limited. Allow it in Settings under “Speech Recognition”.",
            "th": "การรู้จำเสียงพูดปิดอยู่ การรู้จำอาจถูกจำกัด โปรดอนุญาตในการตั้งค่าที่ “การรู้จำเสียงพูด”", "es": "El reconocimiento de voz está desactivado. El reconocimiento puede quedar limitado. Permítelo en Ajustes, en «Reconocimiento de voz».",
            "fr": "La reconnaissance vocale est désactivée. La reconnaissance peut être limitée. Autorisez-la dans Réglages, sous « Reconnaissance vocale ».", "ja": "音声認識がオフです。認識が制限されることがあります。設定の「音声認識」で許可してください。",
            "ko": "음성 인식이 꺼져 있습니다. 인식이 제한될 수 있습니다. 설정의 '음성 인식'에서 허용하세요.", "zh-Hans": "语音识别已关闭，识别可能受限。请在设置的“语音识别”中允许。",
            "vi": "Nhận dạng giọng nói đang tắt. Nhận dạng có thể bị hạn chế. Hãy cho phép trong Cài đặt, mục “Nhận dạng giọng nói”.", "id": "Pengenalan ucapan dimatikan. Pengenalan bisa terbatas. Izinkan di Pengaturan pada “Pengenalan Ucapan”."
        ],
        "ob_speech_restricted": [
            "de": "Spracherkennung ist eingeschränkt, z. B. durch Bildschirmzeit. Die App funktioniert dann nur begrenzt. Prüfe die Einstellungen.", "en": "Speech recognition is restricted, e.g. by Screen Time. The app then works only in a limited way. Check Settings.",
            "th": "การรู้จำเสียงพูดถูกจำกัด เช่น โดยเวลาหน้าจอ แอปจะใช้งานได้อย่างจำกัด ตรวจสอบการตั้งค่า", "es": "El reconocimiento de voz está restringido, p. ej. por Tiempo de uso. La app solo funciona de forma limitada. Revisa Ajustes.",
            "fr": "La reconnaissance vocale est restreinte, par ex. par Temps d'écran. L'app ne fonctionne alors que partiellement. Vérifiez Réglages.", "ja": "音声認識はスクリーンタイムなどで制限されています。アプリの機能が限られます。設定を確認してください。",
            "ko": "음성 인식이 스크린 타임 등으로 제한되어 있습니다. 앱이 제한적으로만 작동합니다. 설정을 확인하세요.", "zh-Hans": "语音识别受到限制，例如被“屏幕使用时间”限制。应用只能部分使用。请检查设置。",
            "vi": "Nhận dạng giọng nói bị hạn chế, ví dụ bởi Thời gian sử dụng. Ứng dụng chỉ hoạt động hạn chế. Hãy kiểm tra Cài đặt.", "id": "Pengenalan ucapan dibatasi, mis. oleh Waktu Layar. Aplikasi hanya berfungsi terbatas. Periksa Pengaturan."
        ],
        "ob_replay": [
            "de": "Willkommen und Berechtigungen erneut ansehen", "en": "Show welcome and permissions again",
            "th": "ดูการต้อนรับและสิทธิ์อีกครั้ง", "es": "Ver de nuevo la bienvenida y los permisos",
            "fr": "Revoir l'accueil et les autorisations", "ja": "ようこそ画面と許可をもう一度見る",
            "ko": "환영 화면과 권한 다시 보기", "zh-Hans": "再次查看欢迎和权限说明",
            "vi": "Xem lại phần chào mừng và quyền", "id": "Lihat lagi sambutan dan izin"
        ],
    ]
}
