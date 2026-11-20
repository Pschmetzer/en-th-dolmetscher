# Glossar der Oberflächenbegriffe

Einheitliche Begriffe für Mac-App (`app/L10n.swift`), iPhone-App (`ios/Dolmetscher/L10n*.swift`) und Web (`i18n/*.json`, deutscher Text in `index.html`). Wer neue Texte schreibt, nimmt diese Begriffe; `tests/test_r21_l10n_audit.py` sperrt die unten genannten Varianten.

Stand der Prüfung: de, en und th sind von Hand geschrieben, aber **nicht muttersprachlich geprüft** (siehe [MUTTERSPRACHLER.md](MUTTERSPRACHLER.md)). Die Spalten es bis id sind maschinell übersetzt und **ungeprüft**.

## Begriffe in de, en, th

| Begriff (Konzept) | Deutsch | Englisch (US-Schreibweise) | Thai | Nicht verwenden |
|---|---|---|---|---|
| Gespräch | Gespräch | conversation | บทสนทนา | Unterhaltung, Chat |
| Gesprächsverlauf | Verlauf | History | ประวัติ | Chronik, Protokoll |
| Gegenüber im Gespräch | Partner (in Sätzen auch „Gegenüber“) | partner | คู่สนทนา | Kunde, Gast |
| Sprache des Gegenübers | Partnersprache | Partner language | ภาษาของคู่สนทนา | Partner's language |
| Einstellungen | Einstellungen | Settings | การตั้งค่า (kurz: ตั้งค่า) | Optionen, Präferenzen |
| Merkliste | Favoriten | Favorites | รายการโปรด | favourites, Lieblingssätze |
| Lernkarte | Lernkarte(n) | flashcard(s) | บัตรคำ | Karteikarte, Lernkasten, study card |
| Satzsammlung | Satzbuch | Phrasebook | สมุดวลี | Phrasenbuch, Sprachführer |
| Mikrofon | Mikrofon | Microphone | ไมโครโฟน | Mic, ไมค์ |
| Spracherkennung | Spracherkennung | Speech recognition | การรู้จำเสียง | Diktat, Spracheingabe, การจดจำเสียง |
| Sprachmodell zum Erkennen | Sprachmodell | speech model | โมเดลเสียง | Sprachdatei |
| Ausgabe der Übersetzung | Vorlesen | read aloud | อ่านออกเสียง | TTS |
| Stimme zum Vorlesen | Stimme | voice | เสียง | Sprecher |
| Notfall | Notfall | Emergency | ฉุกเฉิน | Alarm |
| Eigene Wörter und Namen (Mac) | Glossar | Glossary | อภิธานศัพท์ | Wörterbuch |
| Stimmprofil (Mac) | Profil | Profile | โปรไฟล์ | Konto, Account |
| Ohne Netz | Offline | offline | ออฟไลน์ | Nicht verbunden (nur als Zustand „Keine Verbindung“) |
| Erneut versuchen | Erneut versuchen | Try again | ลองอีกครั้ง | Nochmal (bleibt Lernkarten-Antwort „Again“), Retry |
| Vorlesen beenden | Vorlesen stoppen | Stop reading aloud | หยุดอ่านออกเสียง | Stop speaking, หยุดพูด |

Regeln für Zahlen und Einheiten:

- Mengen stehen als Beschriftung mit Doppelpunkt („Treffer: %d“, „Matches: %d“), damit „1 Treffer“ und „1 Treffern“ nie falsch gebeugt werden. Thai und Ostasien kennen keinen Plural; die Beschriftung bleibt trotzdem gleich gebaut.
- Dezimalzeichen, Prozent und Einheiten kommen aus den Foundation-Formatierern mit der Oberflächensprache, nicht aus festen Texten.
- Zeitstempel in Exporten (Markdown, CSV, Text) sind ISO beziehungsweise `HH:mm:ss` mit Gregorianischem Kalender, unabhängig von der Systemsprache.
- Höflichkeit im Thai: neutral mit „โปรด“ (statt „กรุณา“), ohne Endpartikel in Oberflächentexten. Endpartikel ครับ/ค่ะ stehen nur in den Sätzen, die die App spricht, und in der Auswahl der Partikel selbst.
- Englisch: in den Oberflächentexten einheitlich amerikanische Schreibweise (recognized, favorites, color, canceled). Dokumente (README, `docs/en/`) und die Store-Texte sind Fließtext und dürfen weiter britisch schreiben; „Sprachführer“ bleibt als Store-Stichwort erlaubt.

## Weitere Oberflächensprachen (iPhone, maschinell, ungeprüft)

| Begriff | es | fr | ja | ko | zh-Hans | vi | id |
|---|---|---|---|---|---|---|---|
| Verlauf | Historial | Historique | 履歴 | 기록 | 历史记录 | Lịch sử | Riwayat |
| Einstellungen | Ajustes | Réglages | 設定 | 설정 | 设置 | Cài đặt | Pengaturan |
| Favoriten | Favoritos | Favoris | お気に入り | 즐겨찾기 | 收藏 | Yêu thích | Favorit |
| Satzbuch | Guía de frases | Guide de conversation | 会話集 | 회화집 | 常用语手册 | Sổ tay hội thoại | Buku frasa |
| Lernen | Aprender | Apprendre | 学習 | 학습 | 学习 | Học | Belajar |
| Partnersprache | Idioma del interlocutor | Langue de l'interlocuteur | 相手の言語 | 상대방 언어 | 对方语言 | Ngôn ngữ đối phương | Bahasa lawan bicara |
| Mikrofon | Micrófono | Microphone | マイク | 마이크 | 麦克风 | Micrô | Mikrofon |
| Stimmen | Voces | Voix | 声 | 음성 | 声音 | Giọng đọc | Suara |
| Notfall | Emergencia | Urgence | 緊急 | 응급 | 紧急情况 | Khẩn cấp | Darurat |

„Partner“ heißt in diesen Sprachen **nicht** „pareja“, „partenaire“, „đối tác“ oder „mitra“ (Lebensgefährte beziehungsweise Geschäftspartner), sondern das Gegenüber im Gespräch: interlocutor, interlocuteur, đối phương, lawan bicara.

## Bewusst unterschiedlich

Gleiche Schlüssel dürfen zwischen Mac und iPhone abweichen, wenn der Kontext es verlangt (`done`, `listening`, `speaking`, `a11y_ready`, `share`). Feste Texte, die nie übersetzt werden: Markenname „Dolmetscher“, Sprachbefehle („Translator, resume“), Dateiformate („Markdown (.md)“).
