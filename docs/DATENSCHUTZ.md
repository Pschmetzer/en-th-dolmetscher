# Datenschutz: was den Mac verlässt und was nicht

Stand: Version 1.2. Gilt für die Mac-App und die Engine (`dolmetscher.py`); die Browser-Version steht ganz unten.

## Bleibt lokal

| Was | Wo |
|---|---|
| **Mikrofon-Audio** | Wird nur im Speicher verarbeitet (Voice Activity Detection, Spracherkennung) und weder gespeichert noch gesendet. |
| **Spracherkennung (Whisper)** | faster-whisper läuft auf dem Mac (Apple GPU oder CPU). Die Modelle werden einmalig von Hugging Face geladen (siehe unten), danach braucht die Erkennung kein Netz. |
| **Stimmprofile (Voiceprints)** | Biometrische Daten. Liegen nur unter `~/Library/Application Support/Dolmetscher/profiles/` (nur für dich lesbar), werden nie gesendet und lassen sich in der App löschen (`--delete-profile`). Die Sprechererkennung läuft lokal (sherpa-onnx). |
| **Wörterbuch/Glossar, Einstellungen, Schnellsätze** | Dateien unter `~/Library/Application Support/Dolmetscher/` bzw. App-Einstellungen. |
| **Log** | `~/Library/Logs/Dolmetscher/engine.log`. Gesprächstexte stehen **nicht** drin, außer mit `--log-text`. |
| **Thai-Umschrift** | `pythainlp` bzw. ICU, lokal. |

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

## Browser-Version (`index.html`, Web Lite)

- **Spracherkennung**: nutzt die Web Speech API von **Chrome**. Chrome sendet das Mikrofon-Audio dafür an Googles Spracherkennungsdienst (nicht von uns kontrollierbar, siehe die Datenschutzhinweise von Chrome/Google). Andere Browser ohne diese API funktionieren nicht.
- **Übersetzung**: derselbe erkannte Text geht direkt aus dem Browser an Google Translate, ersatzweise MyMemory.
- **Sprachausgabe**: lokale Browser-Stimmen (Web Speech Synthesis), je nach Browser/System.
- Die Seite hat keine eigenen Skripte von Dritten und keinen eigenen Server.

## Hinweise für Berichte und Fehlersuche

Wer Logs teilt: `--log-text` schreibt erkannte und übersetzte Sätze in die Logdatei. Vor dem Weitergeben persönliche Inhalte entfernen.
