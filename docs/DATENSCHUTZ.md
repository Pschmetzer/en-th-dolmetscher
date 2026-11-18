# Datenschutz: was den Mac verlässt und was nicht

Stand: Version 1.2 mit den Änderungen bis Pull Request #47, November 2026 (siehe [CHANGELOG.md](../CHANGELOG.md)). Gilt für die Mac-App und die Engine (`dolmetscher.py`); iPhone-App und Browser-Version stehen weiter unten.

Kurz je Plattform:

| | Audio | Übersetzung | Stimme |
|---|---|---|---|
| **Mac** | bleibt auf dem Mac | online: Google (Ersatz MyMemory) oder Claude; bei abweichenden Zahlen zusätzlich der jeweils andere Dienst; ohne Netz auf Wunsch Apple-Übersetzung auf dem Mac | online: Microsoft (Ersatz: lokale macOS-Stimme) |
| **iPhone** | bleibt auf dem Gerät (Apple oder Whisper) | auf dem Gerät; online (Google, Ersatz MyMemory) **nur**, wenn „Online-Übersetzer als Ersatz“ an ist (Standard: aus) | auf dem Gerät |
| **Browser** | geht an den Spracherkennungsdienst des Browsers (Chrome: Google) | online: Google (Ersatz MyMemory) | lokal im Browser |

Nirgends gibt es Konten, eigene Telemetrie oder einen eigenen Server.

Das gilt für alle 19 Sprachen gleich: Die Wahl des Sprachpaars ändert nur, welche Sprachen erkannt und übersetzt werden, nicht, wohin Daten gehen. Bei den Sprachcodes für die Dienste wird Chinesisch als `zh-CN` (Google/MyMemory) bzw. `zh-Hans` (Apple) angefragt.

## Bleibt lokal

| Was | Wo |
|---|---|
| **Mikrofon-Audio** | Wird nur im Speicher verarbeitet (Voice Activity Detection, Spracherkennung) und weder gespeichert noch gesendet. |
| **Spracherkennung (Whisper)** | faster-whisper läuft auf dem Mac (Apple GPU oder CPU). Die Modelle werden einmalig von Hugging Face geladen (siehe unten), danach braucht die Erkennung kein Netz. |
| **Stimmprofile (Voiceprints)** | Biometrische Daten. Liegen nur unter `~/Library/Application Support/Dolmetscher/profiles/` (nur für dich lesbar), werden nie gesendet und lassen sich in der App löschen (`--delete-profile`). Die Sprechererkennung läuft lokal (sherpa-onnx). |
| **Wörterbuch/Glossar, Einstellungen, Schnellsätze** | Dateien unter `~/Library/Application Support/Dolmetscher/` bzw. App-Einstellungen. Lernt das Glossar aus Korrekturen (Standard: an, abschaltbar), landen neue Eigennamen ebenfalls nur in dieser Datei. |
| **API-Schlüssel für Claude** | Im **Schlüsselbund** des Macs. Die App gibt ihn beim Start als `ANTHROPIC_API_KEY` an die Engine weiter. Eine alte Datei `anthropic_key` wird beim Umzug nicht gelöscht, sondern erst dann in `anthropic_key.migrated` (Rechte 0600) umbenannt, wenn der Schlüsselbund den Wert nachweislich zurückgibt. Die Engine liest diese Datei nur, wenn kein `ANTHROPIC_API_KEY` gesetzt ist (Start im Terminal). Klappt der Schlüsselbund nicht, speichert die App den Schlüssel wie früher in `anthropic_key`. Wer die Datei nicht mehr braucht, kann `anthropic_key.migrated` selbst löschen. |
| **Ausgabegerät** | Die Wahl des Lautsprechers oder Kopfhörers (CoreAudio-Kennung) steht nur in den App-Einstellungen und geht an die lokale Wiedergabe (`avhelper.py play`). |
| **Offline-Übersetzung (Apple)** | Nur wenn kein Netz da ist und die Sprachpakete installiert sind, übersetzt `translate-helper` mit Apples Übersetzung **auf dem Mac** (Ergebnis wird nicht zwischengespeichert). Einstellung „Offline-Übersetzung (Apple) als Rückfall“, Standard an, wenn der Helfer in der App liegt und macOS 26.4 oder neuer läuft. Die Sprachpakete lädt macOS selbst über Apple. |
| **Log** | `~/Library/Logs/Dolmetscher/engine.log`, wird ab etwa 1 MB rotiert (3 alte Dateien, einstellbar über `DOLMETSCHER_LOG_MB` und `DOLMETSCHER_LOG_BACKUPS`). Gesprächstexte stehen **nicht** drin, außer mit `--log-text`. |
| **Thai-Umschrift** | `pythainlp` bzw. ICU, lokal. |
| **Gesprächsverlauf** (nur mit `--history`, Standard: aus) | Siehe nächster Abschnitt. |

## Gesprächsverlauf (`--history`)

- **Standard: aus.** Aufgezeichnet wird nur, wenn du `--history` startest bzw. die App ihn einschaltet (`{"history": true}`).
- **Was:** erkannter Text, Übersetzung, Umschrift, Sprache, Konfidenz, Übersetzungsdienst und Zeitpunkt jeder Äußerung. **Kein Audio.**
- **Wo:** `~/Library/Application Support/Dolmetscher/history.sqlite` (oder `$DOLMETSCHER_HOME`), Ordner 0700, Datei 0600. Die Texte liegen **im Klartext** in der Datei (nicht verschlüsselt) und landen damit auch in Backups (z. B. Time Machine), solange du den Ordner nicht ausschließt.
- **Aufbewahrung:** `--history-days N` löscht beim Start Einträge, die älter als N Tage sind. Ohne Angabe bleibt alles, bis du es löschst. 0 oder negative Werte werden ignoriert (sie löschen nicht alles).
- **Löschen:** `--history-purge N` (älter als N Tage, N > 0) oder `--history-clear` (alles). Gelöschte Zeilen werden in der Datei überschrieben (`PRAGMA secure_delete`), Suchindex und Datei danach neu geschrieben (`VACUUM`), damit sie nicht in freien Bereichen lesbar bleiben. Kopien in Backups löscht das nicht.
- **Export:** `--history-export md|json|csv|srt|vtt|anki` schreibt auf stdout oder mit `--out PFAD` in eine neue Datei mit Rechten 0600. Was du exportierst und weitergibst, liegt dann außerhalb der App.
- Gesendet wird aus dem Verlauf nichts.

## Verlässt den Mac

| Was wird gesendet | Wann | An wen |
|---|---|---|
| **Erkannter Text** (nicht das Audio) zum Übersetzen | bei jedem Satz, wenn die Übersetzung nicht mit Claude läuft. Bei eingeschaltetem Claude zusätzlich: (a) Claude antwortet nicht binnen weniger Sekunden (Hedging, je nach Modell 2–4,5 s): Google übersetzt parallel, die schnellere brauchbare Fassung gilt; (b) Claudes Antwort wirkt unplausibel (falsche Schrift, Ablehnung, Anmerkung, unpassende Länge); (c) die Zahlen in Claudes Übersetzung weichen vom Original ab (Gegenprobe); (d) Claude ist nach Fehlern vorübergehend pausiert oder das Monatslimit ist erreicht | **Google Translate** (inoffizieller Web-Endpunkt `translate.googleapis.com`). Der Text geht per POST im Anfrage-Body, nicht in der URL (taucht so nicht in URL-Logs von Proxys auf); ein eingestellter HTTPS-Proxy wird benutzt. |
| Derselbe Text | nur wenn Google fehlschlägt (Fallback, auch bei der Gegenprobe) | **MyMemory** (`api.mymemory.translated.net`), ebenfalls per POST. Ist `DOLMETSCHER_MYMEMORY_EMAIL` gesetzt (nur lokal), geht diese Mail-Adresse als Parameter `de` mit, damit MyMemory ein höheres Tageslimit gewährt. |
| **Übersetzter Text** zur Rückübersetzung | nur wenn „Rückübersetzung“ eingeschaltet ist (`--back-translate`, Standard: aus): nach jeder Übersetzung einmal | **Google Translate**, wie oben per POST |
| Kurze Probe-Anfrage („hi“) und Verbindungsaufbau zur Neural-Stimme | beim Start, damit der erste Satz schneller geht; **nicht** im Privatmodus | Google bzw. Microsoft. Gesprächsinhalt ist nicht dabei. |
| **Übersetzter Text** zum Vorlesen | bei jeder gesprochenen Ausgabe mit Neural-Stimme (Standard) | **Microsoft** (Edge-Sprachdienst über `edge-tts`). Mit `--tts say` oder offline wird stattdessen die lokale macOS-Stimme benutzt und nichts gesendet. |
| **Erkannter Text** samt den letzten Sätzen als Kontext (Standard 8) und dem Glossar zum Übersetzen | nur wenn Claude-Übersetzung eingeschaltet ist und ein API-Schlüssel vorhanden ist (`--llm`), das Monatslimit (`--llm-budget`) nicht erreicht ist: bei jedem Satz – oder, wenn zuerst Google übersetzt hat (z. B. nach einem Claude-Fehler), als Gegenprobe, sobald die Zahlen in Googles Übersetzung abweichen (Google kann trotz eingeschaltetem Claude zuerst übersetzt haben, z. B. durch Hedging) | **Anthropic** (Claude API), abgerechnet über dein Anthropic-Konto. Der Schlüssel liegt im Schlüsselbund (siehe oben), in `ANTHROPIC_API_KEY` oder in einer Schlüsseldatei und wird nur an Anthropic gesendet. |
| **Python und Pakete herunterladen** (Anfrage, kein Gesprächsinhalt) | nur im Einrichtungs-Bildschirm beim ersten Start auf einem Mac ohne passende Umgebung, nach App-Updates mit geändertem Lock und bei „neu einrichten“ | Das mitgelieferte `uv` lädt Python 3.12 (python-build-standalone von **Astral**, über die Standard-Downloadquelle von uv) und die Pakete aus `requirements.txt` von **PyPI** (`files.pythonhosted.org`), jeweils mit Hash-Prüfung. Ablage nur unter `~/Library/Application Support/Dolmetscher/`. |
| **Modell-Dateien herunterladen** (Anfrage, kein Gesprächsinhalt) | einmalig beim ersten Start bzw. beim Bauen; ein Modell wird nur geladen, wenn es wirklich fehlt | **Hugging Face** (Whisper-Modelle, feste Revision je Modell, siehe [LIZENZEN.md](LIZENZEN.md)) und **GitHub** (WeSpeaker-Modell für Stimmprofile, Prüfsumme wird kontrolliert) |

Wie bei jedem Netzwerkzugriff sehen die Dienste außerdem deine IP-Adresse. Es gibt keine eigene Telemetrie, keine Konten und keinen eigenen Server.

Der Selbsttest der Neural-Stimme beim Start (`edge-tts`) prüft nur die Bibliothek lokal und sendet nichts.

**Privatmodus** (Mac-Einstellung „Privatmodus“, Engine `--private`, Standard: aus): keine Probe-Anfragen beim Start. Lehnt Google oder MyMemory die POST-Anfrage ab, weicht die Engine nicht auf GET aus, der Text landet also nie in einer URL (dann schlägt die Übersetzung fehl). Was übersetzt wird, geht weiterhin an die Dienste oben.

Willst du nichts senden: Ohne Netz läuft die Erkennung weiter. Übersetzt wird dann nur, wenn die Offline-Übersetzung (Apple) eingeschaltet ist und die Sprachpakete installiert sind, vorgelesen wird mit der lokalen macOS-Stimme. Sonst zeigt die App den Netzstatus an, und nichts wird übersetzt. Einen Schalter „nie senden“ gibt es nicht.

## iPhone-App (`ios/`)

- **Spracherkennung**: auf dem Gerät, entweder mit Apples Erkennung (SpeechAnalyzer, Standard) oder, wenn eingeschaltet, mit Whisper (WhisperKit). Das Audio wird nicht gesendet und nicht gespeichert.
- **Whisper-Modelle (optional)**: Nur wenn du in den Einstellungen Whisper einschaltest und auf „Modell laden“ tippst, lädt die App das gewählte Modell und den Tokenizer von **Hugging Face** (`argmaxinc/whisperkit-coreml`, keine feste Revision). Gesendet wird dabei nur die Download-Anfrage (wie immer mit IP-Adresse), kein Gesprächsinhalt. Die Dateien liegen im App-Ordner (Application Support/`whisper`), sind vom iCloud-Backup ausgenommen und lassen sich in den Einstellungen löschen. Danach läuft Whisper ohne Netz.
- **Sprachpakete**: Apples Erkennungsmodelle, Übersetzungs-Sprachpakete und Stimmen lädt iOS selbst über Apple. Beim Laden der Erkennungsmodelle über Mobilfunk fragt die App vorher nach.
- **Übersetzung**: zuerst mit Apples Übersetzung **auf dem Gerät**, wenn die Offline-Sprachpakete für das gewählte Sprachpaar installiert sind. Sonst geht der erkannte Text **nur**, wenn „Online-Übersetzer als Ersatz“ eingeschaltet ist (**Standard: aus**), an **Google Translate** (`translate.googleapis.com`, per POST im Anfrage-Body) und ersatzweise an **MyMemory** (`api.mymemory.translated.net`, per GET: der Text steht dabei **in der URL**). Ist der Schalter aus und fehlt ein Paket, wird nicht übersetzt, und die App weist darauf hin. Paare, die Apple nicht auf dem Gerät übersetzen kann, sind in der Sprachauswahl mit 🌐 markiert. In der Liste zeigt ein Globus-Symbol, welche Sätze online übersetzt wurden. Eine Gegenprobe mit einem zweiten Dienst wie auf dem Mac gibt es auf dem iPhone nicht.
- **Rückübersetzung** (abschaltbar): läuft nur mit Apples Übersetzung auf dem Gerät und nur, wenn die Sprachpakete installiert sind. Dafür geht nie Text ins Netz.
- **Satzbuch zuerst**: Passt ein Satz auf einen Satz im Satzbuch, kommt die gespeicherte Fassung, ohne Übersetzungsdienst.
- **Sprachausgabe**, **Text aus Fotos** und **Textscan für Ziele** (Visitenkarte oder Schild fotografieren): Systemstimmen und Texterkennung (Vision) auf dem Gerät. Das Foto wird nur ausgewertet, nicht gespeichert; übernommen werden Name und Adresse in die Ziele.
- **Standort**: nur auf dem Bildschirm „Hilfe – jetzt“ (Notfall). Beim Öffnen fragt die App einmal nach der Erlaubnis „Beim Verwenden der App“ und zeigt die Koordinaten an. Sie werden weder gespeichert noch von der App gesendet. Den Standort ermittelt iOS selbst (GPS, je nach Lage mit Apples Ortungsdiensten).
- **Apple Karten**: Der Link bei einem Ziel öffnet Apple Karten mit Name bzw. Adresse. Das geht erst beim Tippen an Apple.
- **Verlauf**: Die App speichert Gespräche lokal in `history.json` im App-Ordner (Application Support, iOS-Dateischutz), standardmäßig **30 Tage**; einstellbar, 0 schaltet das Speichern ab und löscht die Datei. Notfallkarte, Favoriten und Ziele liegen ebenfalls nur lokal (`emergency.json`, `favorites.json`, `places.json`). Der Verlauf lässt sich per Face ID sperren; gesperrt bleiben ältere Sätze verborgen.
- **Lernkarten**: Favoriten und übersetzte Sätze, die du ins Lernen übernimmst, liegen mit dem Lernstand nur auf dem Gerät in `learn.json` (gleicher Dateischutz). Sätze aus dem gesperrten Verlauf kommen nicht in die Karten.
- **Widgets und Steuerelement**: Das Schnellsätze-Widget zeigt nur Sätze aus dem eingebauten Satzbuch (`phrases.json` im Widget selbst). Es liest weder Verlauf noch Einstellungen der App (kein gemeinsamer App-Group-Speicher).
- **Live-Aktivität** (Standard: an, abschaltbar in den Einstellungen): Beim Zuhören zeigen Sperrbildschirm und Dynamic Island den letzten Satz samt Übersetzung. Sie sind dort **ohne Entsperren lesbar**. Wer das nicht will, schaltet die Live-Aktivität aus.
- **Alle Daten löschen** (Einstellungen, mit Rückfrage, bei gesperrtem Verlauf erst Face ID): entfernt Verlauf, Favoriten, Notfallkarte, Ziele, Lernstand und alle Einstellungen, auch Sicherungskopien beschädigter Dateien. Geladene Whisper-Modelle bleiben; die löscht „Löschen“ im Whisper-Abschnitt. Kopien in Backups des iPhones löscht das nicht.
- Keine Konten, keine eigene Telemetrie (siehe `ios/Dolmetscher/PrivacyInfo.xcprivacy`).

## Browser-Version (`index.html`, Web Lite)

- **Vor dem ersten Mikrofon-Start** fragt die Seite einmal um Zustimmung (im Browser gespeichert, `localStorage`). Die Zustimmung trägt eine Textversion (`CONSENT_VER` in `index.html`, aktuell **1**): ändern sich Dialogtext oder Datenfluss, wird die Version erhöht und neu gefragt.
- **Spracherkennung**: nutzt die Web Speech API des Browsers. **Chrome** sendet das Mikrofon-Audio an Googles Spracherkennungsdienst, **Safari** an Apple (je nach Gerät auch lokal); beides ist nicht von uns kontrollierbar. Firefox hat keine Spracherkennung. **Pause** und **Stopp** beenden die Erkennung ganz, danach wird kein Audio mehr gesendet.
- **Übersetzung**: der erkannte Text geht direkt aus dem Browser an Google Translate, ersatzweise MyMemory, jeweils per GET, also **in der URL** der Anfrage. Das gilt für alle 19 Sprachen. Satzbuch-Sätze, die es im Paket nicht in der Partnersprache gibt (alles außer Englisch und Thai), werden beim ersten Tippen einmal übersetzt (also an Google Translate gesendet; die Karte ist als „automatisch übersetzt“ markiert) und im Browser gemerkt (`pbTrans`).
- **Sprachausgabe**: lokale Browser-Stimmen (Web Speech Synthesis), je nach Browser/System.
- **Gespeichert** wird nur im Browser (`localStorage`): Einstellungen (`webSettings`, `keysOn`), Zustimmung (`micConsent`), übersetzte Satzbuch-Sätze (`pbTrans`) und die Lernkarten. Die Gesprächsliste verschwindet beim Schließen der Seite, außer du kopierst sie oder speicherst sie als Textdatei.
- **Weitere Browser-Daten (nur lokal, nie gesendet)**: eigene Karten wie Hotel oder Adresse (`myCardsV1`, höchstens 30), die Allergie- und Notfallkarte (`allergyV1`), Lernstatistik der letzten 30 Tage (`learnStatsV1`), wie oft ein Satzbuch-Thema benutzt wurde (`pbUse`, für die Reihenfolge) und ob der Installationshinweis weggeklickt wurde (`installHint`). Gemerkte Satzbuch-Übersetzungen (`pbTrans`) verfallen nach 90 Tagen, höchstens 1500; „Gemerkte Übersetzungen löschen“ leert sie. „Sichern (.json)“ schreibt Lernkarten in eine Datei, die du selbst aufbewahrst.
- **Lernkarten** (`learnV1`): Mit ☆ gemerkte Sätze werden samt Übersetzung und Lernstand gespeichert, höchstens 200 Karten. „Zuletzt übersetzte Sätze automatisch aufnehmen“ ist **standardmäßig aus**. „Alle Lernkarten löschen“ leert den Speicher, ebenso das Löschen der Website-Daten im Browser. Gesendet wird davon nichts.
- **Speicher dieser Adresse**: `localStorage` gilt pro Ursprung (bei GitHub Pages `pschmetzer.github.io`), nicht pro Pfad; andere Seiten unter demselben Ursprung könnten die Schlüssel lesen. Auf Safari löscht der Browser Website-Daten nach 7 Tagen ohne Besuch, wenn die Seite nicht zum Home-Bildschirm hinzugefügt ist; die Seite bittet beim Anlegen einer Lernkarte um dauerhaften Speicher (`navigator.storage.persist`), der Browser entscheidet.
- **Offline (PWA)**: Der Service Worker speichert nur die eigenen Dateien der Seite (HTML, Icons, Satzbuch-Pakete), keine Übersetzungen. Anfragen an Google und MyMemory laufen nie über ihn.
- **Geteilter Text an die App** (Web-Share-Target, nur installierte Android-App): Text aus einer anderen App wird übersetzt (Google Translate) und groß gezeigt, nicht gespeichert.
- **Lokale Erkennung** (Chrome 139+, Schalter „Nur auf dem Gerät erkennen“, aus): bleibt das Audio auf dem Gerät. Für Thai nicht geprüft.
- **Teilen per Link**: Der Text steht hinter `#` in der Adresse. Diesen Teil schickt der Browser nicht an den Server; die Empfängerin sieht den Satz nur angezeigt (höchstens 500 Zeichen) und mit dem Hinweis „von der App nicht geprüft“; beim Öffnen wird der `#`-Teil aus Adresszeile und Verlauf entfernt. **Aber:** Verschickst du den Link über WhatsApp, LINE, iMessage o. Ä., sieht der Messenger den ganzen Link samt Satz. Bei sensiblen Sätzen (Arzt) besser den Bildschirm zeigen.
- Die Seite hat keine Skripte von Dritten und keinen eigenen Server (Content-Security-Policy erlaubt nur die beiden Übersetzungsdienste).

## Hinweise für Berichte und Fehlersuche

Wer Logs teilt: `--log-text` schreibt erkannte und übersetzte Sätze in die Logdatei. Vor dem Weitergeben persönliche Inhalte entfernen.

## Ergänzungen Runde 7 (Engine)

- **Sprechermodell** (Stimmprofile): Fehlt die Modelldatei, lädt die Engine sie einmalig von GitHub (Prüfsumme SHA-256, danach
  lokal). Das passiert nur, wenn Stimmprofile genutzt werden. Mit `--private` lädt sie **nichts** nach: die Stimmerkennung
  bleibt dann aus (`error` `profiles_failed`), bis die Datei vorhanden ist (`DOLMETSCHER_SPEAKER_MODEL` für eine lokale Kopie).
  Eine vorhandene Datei wird gegen die Prüfsumme geprüft und bei Abweichung neu geladen.
- **Rückübersetzung** (`back_translate`, Standard aus): Ist sie an, geht der **übersetzte Satz** zusätzlich an Google Translate, um
  ihn zurück in die Ausgangssprache zu übersetzen. Höchstens zwei Anfragen gleichzeitig; mit pausiertem Google entfällt sie.
- **Verlauf**: Die Datenbank ist nicht verschlüsselt (nur Dateirechte 0600) und enthält, wenn Stimmprofile genutzt werden,
  **Profilnamen im Klartext** (`speaker`). Mit dem Steuerfeld `history_speakers: false` werden keine Namen gespeichert. Ausgeschaltet
  räumt die Engine die WAL-Datei mit auf; Exporte (`--out`) bekommen Rechte 0600.
- **Übersetzungs-Cache auf der Platte** (`cache_persist`, Standard aus): Ist er an, liegen übersetzte Sätze in
  `translation_cache.json` (0600, höchstens 300 Einträge). Ausschalten und „clear“ löschen die Datei.
- **Log-Pseudonyme** von Profilnamen sind mit einem zufälligen Installations-Salz (`log_salt`, 0600) gebildet und lassen sich nicht
  per Namensliste zurückrechnen.

## Ergänzungen Runde 7 (Mac, iPhone, Web)

- **Mac, URL-Schema `dolmetscher://`:** andere Programme können Start, Stopp, Pause und „Satz sprechen“ auslösen. Beim ersten Aufruf fragt die App nach; Text höchstens 1000 Zeichen.
- **Mac, Bildschirmaufnahme:** Der Schalter „Fenster vor Bildschirmaufnahme verbergen“ schließt die App-Fenster aus Aufnahmen und Screenshots aus (`sharingType = .none`). Standard: aus.
- **Mac, Audiodateien:** Beim Übersetzen einer Datei läuft ein eigener Engine-Prozess; Ergebnisse stehen nur im Verlauf der App.
- **Mac, API-Schlüssel:** Der Schlüssel geht nur an den Engine-Prozess, nicht an Hilfsprozesse. Der Schlüsselbund-Eintrag gilt nur für dieses Gerät. Klartext-Schlüsseldateien werden in Release-Builds gelöscht.
- **iPhone, Wechselkurs (optional, Standard aus):** Die Kursabfrage sendet nur den Währungscode an `api.frankfurter.dev`; keine Sätze, keine Gerätekennung.
- **iPhone, Spotlight (optional, Standard aus):** Favoriten werden in der Systemsuche des Geräts sichtbar gemacht; sie bleiben auf dem Gerät.
- **iPhone, Datenschutz-Manifest:** nennt jetzt „Freier Speicherplatz“ (DiskSpace, Grund E174.1) für die Prüfung vor dem Modell-Download.
- **iPhone, Lernkarten:** folgen der Verlaufseinstellung und der Face-ID-Sperre, haben ein Verfallsdatum und lassen sich löschen.
- **Web:** Texteingabe, „Meine Karten“ (Adresse, Hotel) und die Lernkarten bleiben nur in diesem Browser. „Falsch? Melden“ öffnet ein vorbefülltes GitHub-Formular; gesendet wird nur, was du dort selbst abschickst.

