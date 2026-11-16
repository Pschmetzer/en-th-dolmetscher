# Datenschutz: was den Mac verlässt und was nicht

Stand: Version 1.2. Gilt für die Mac-App und die Engine (`dolmetscher.py`); iPhone-App und Browser-Version stehen weiter unten.

## Bleibt lokal

| Was | Wo |
|---|---|
| **Mikrofon-Audio** | Wird nur im Speicher verarbeitet (Voice Activity Detection, Spracherkennung) und weder gespeichert noch gesendet. |
| **Spracherkennung (Whisper)** | faster-whisper läuft auf dem Mac (Apple GPU oder CPU). Die Modelle werden einmalig von Hugging Face geladen (siehe unten), danach braucht die Erkennung kein Netz. |
| **Stimmprofile (Voiceprints)** | Biometrische Daten. Liegen nur unter `~/Library/Application Support/Dolmetscher/profiles/` (nur für dich lesbar), werden nie gesendet und lassen sich in der App löschen (`--delete-profile`). Die Sprechererkennung läuft lokal (sherpa-onnx). |
| **Wörterbuch/Glossar, Einstellungen, Schnellsätze** | Dateien unter `~/Library/Application Support/Dolmetscher/` bzw. App-Einstellungen. |
| **Log** | `~/Library/Logs/Dolmetscher/engine.log`. Gesprächstexte stehen **nicht** drin, außer mit `--log-text`. |
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
| **Erkannter Text** (nicht das Audio) zum Übersetzen | bei jedem Satz, wenn die Übersetzung nicht mit Claude läuft | **Google Translate** (inoffizieller Web-Endpunkt `translate.googleapis.com`). Der Text geht per POST im Anfrage-Body, nicht in der URL (taucht so nicht in URL-Logs von Proxys auf); ein eingestellter HTTPS-Proxy wird benutzt. |
| Derselbe Text | nur wenn Google fehlschlägt (Fallback) | **MyMemory** (`api.mymemory.translated.net`), ebenfalls per POST |
| **Übersetzter Text** zum Vorlesen | bei jeder gesprochenen Ausgabe mit Neural-Stimme (Standard) | **Microsoft** (Edge-Sprachdienst über `edge-tts`). Mit `--tts say` oder offline wird stattdessen die lokale macOS-Stimme benutzt und nichts gesendet. |
| **Erkannter Text** samt den letzten Sätzen als Kontext (Standard 8) und dem Glossar zum Übersetzen | nur wenn Claude-Übersetzung eingeschaltet ist und ein API-Schlüssel vorhanden ist (`--llm`) | **Anthropic** (Claude API), abgerechnet über dein Anthropic-Konto. Der Schlüssel liegt in `ANTHROPIC_API_KEY` oder `~/Library/Application Support/Dolmetscher/anthropic_key` und wird nur an Anthropic gesendet. |
| **Modell-Dateien herunterladen** (Anfrage, kein Gesprächsinhalt) | einmalig beim ersten Start bzw. beim Bauen | **Hugging Face** (Whisper-Modelle, feste Revision je Modell, siehe [LIZENZEN.md](LIZENZEN.md)) und **GitHub** (WeSpeaker-Modell für Stimmprofile, Prüfsumme wird kontrolliert) |

Wie bei jedem Netzwerkzugriff sehen die Dienste außerdem deine IP-Adresse. Es gibt keine eigene Telemetrie, keine Konten und keinen eigenen Server.

Willst du nichts senden: Es gibt dafür keinen reinen Offline-Modus der Übersetzung. Ohne Netz läuft nur die Erkennung, die App zeigt dann den Netzstatus an, und nichts wird übersetzt oder gesprochen.

## iPhone-App (`ios/`)

- **Spracherkennung**: auf dem Gerät (Apple SpeechAnalyzer). Das Audio wird nicht gesendet und nicht gespeichert.
- **Übersetzung**: zuerst mit Apples Übersetzung **auf dem Gerät**, wenn die Offline-Sprachpakete EN/TH installiert sind. Sonst, nur wenn „Online-Übersetzung“ erlaubt ist (Standard: an), geht der erkannte Text an **Google Translate** (`translate.googleapis.com`, per POST im Anfrage-Body) und ersatzweise an **MyMemory** (`api.mymemory.translated.net`, per GET: der Text steht dabei **in der URL**). In der Liste zeigt ein Globus-Symbol, welche Sätze online übersetzt wurden.
- **Sprachausgabe** und **Text aus Fotos**: Systemstimmen und Texterkennung auf dem Gerät.
- **Verlauf**: Die App speichert Gespräche lokal in `history.json` im App-Ordner (Application Support, iOS-Dateischutz), standardmäßig **30 Tage**; einstellbar, 0 schaltet das Speichern ab und löscht die Datei. Notfall-Infos und Favoriten liegen ebenfalls nur lokal.
- Keine Konten, keine eigene Telemetrie (siehe `ios/Dolmetscher/PrivacyInfo.xcprivacy`).

## Browser-Version (`index.html`, Web Lite)

- **Vor dem ersten Mikrofon-Start** fragt die Seite einmal um Zustimmung (im Browser gespeichert, `localStorage`).
- **Spracherkennung**: nutzt die Web Speech API des Browsers. **Chrome** sendet das Mikrofon-Audio an Googles Spracherkennungsdienst, **Safari** an Apple (je nach Gerät auch lokal); beides ist nicht von uns kontrollierbar. Firefox hat keine Spracherkennung. **Pause** und **Stopp** beenden die Erkennung ganz, danach wird kein Audio mehr gesendet.
- **Übersetzung**: der erkannte Text geht direkt aus dem Browser an Google Translate, ersatzweise MyMemory, jeweils per GET, also **in der URL** der Anfrage.
- **Sprachausgabe**: lokale Browser-Stimmen (Web Speech Synthesis), je nach Browser/System.
- **Gespeichert** werden nur Einstellungen (Tastenkürzel an/aus, Zustimmung) im Browser; die Gesprächsliste verschwindet beim Schließen der Seite.
- Die Seite hat keine Skripte von Dritten und keinen eigenen Server (Content-Security-Policy erlaubt nur die beiden Übersetzungsdienste).

## Hinweise für Berichte und Fehlersuche

Wer Logs teilt: `--log-text` schreibt erkannte und übersetzte Sätze in die Logdatei. Vor dem Weitergeben persönliche Inhalte entfernen.
