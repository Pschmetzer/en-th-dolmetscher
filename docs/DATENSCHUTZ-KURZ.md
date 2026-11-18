# Datenschutz in Kürze

Nur Fakten aus [DATENSCHUTZ.md](DATENSCHUTZ.md), dort stehen Einzelheiten und Ausnahmen. Englische Fassung: [en/PRIVACY-SHORT.md](en/PRIVACY-SHORT.md).

**Immer:** keine Konten, keine eigene Telemetrie, kein eigener Server. Wie bei jedem Netzzugriff sehen die genutzten Dienste deine IP-Adresse. Die Wahl des Sprachpaars ändert nicht, wohin Daten gehen.

| | Audio | Übersetzung | Stimme |
|---|---|---|---|
| **Mac** | bleibt auf dem Mac | online: Google (Ersatz MyMemory) oder Claude; bei abweichenden Zahlen zusätzlich der jeweils andere Dienst; ohne Netz auf Wunsch Apple-Übersetzung auf dem Mac | online: Microsoft (Ersatz: lokale macOS-Stimme) |
| **iPhone** | bleibt auf dem Gerät (Apple oder Whisper) | auf dem Gerät; online (Google, Ersatz MyMemory) nur, wenn „Online-Übersetzer als Ersatz“ an ist (Standard: aus) | auf dem Gerät |
| **Browser** | geht an den Spracherkennungsdienst des Browsers (Chrome: Google) | online: Google (Ersatz MyMemory) | lokal im Browser |

## Mac: bleibt lokal

- Mikrofon-Audio wird nur im Speicher verarbeitet, weder gespeichert noch gesendet.
- Die Spracherkennung (Whisper) läuft auf dem Mac; die Modelle werden einmalig von Hugging Face geladen.
- Stimmprofile sind biometrische Daten. Sie liegen nur unter `~/Library/Application Support/Dolmetscher/profiles/`, nur für dich lesbar, werden nie gesendet und lassen sich in der App löschen.
- Der API-Schlüssel für Claude liegt im Schlüsselbund des Macs.
- Das Log (`~/Library/Logs/Dolmetscher/engine.log`) enthält Gesprächstexte nur mit `--log-text`.
- Der Gesprächsverlauf ist standardmäßig aus. Er enthält Texte, kein Audio, liegt unverschlüsselt in `history.sqlite` (Dateirechte 0600) und landet in Backups. Löschen: `--history-purge N` oder `--history-clear`.

## Mac: verlässt den Rechner

- **Erkannter Text** (nicht das Audio) geht zum Übersetzen an Google Translate, ersatzweise MyMemory, per POST im Anfrage-Body. Mit eingeschalteter Claude-Übersetzung geht Text samt den letzten Sätzen (Standard 8) und dem Glossar an Anthropic.
- **Übersetzter Text** geht zum Vorlesen an Microsoft (edge-tts). Mit `--tts say` oder offline spricht die lokale macOS-Stimme, dann wird nichts gesendet.
- **Rückübersetzung** (Standard: aus) schickt den übersetzten Satz zusätzlich an Google Translate.
- Beim Start geht eine kurze Probe-Anfrage („hi“) an Google beziehungsweise Microsoft, ohne Gesprächsinhalt. Der **Privatmodus** (`--private`, Standard: aus) lässt sie weg und weicht nie auf eine URL-Anfrage aus.
- Python, Pakete und Modelle werden beim Einrichten von Astral, PyPI, Hugging Face und GitHub heruntergeladen; es wird kein Gesprächsinhalt gesendet.
- Einen Schalter „nie senden“ gibt es nicht.

## iPhone

- Spracherkennung auf dem Gerät, das Audio wird nicht gesendet und nicht gespeichert.
- MyMemory (nur als Ersatz, nur mit eingeschaltetem „Online-Übersetzer als Ersatz“) wird per GET abgefragt, der Text steht dabei in der URL.
- Verlauf lokal in `history.json`, standardmäßig 30 Tage (einstellbar, 0 schaltet ab), per Face ID sperrbar. „Alle Daten löschen“ steht in den Einstellungen.
- Der Standort wird nur auf dem Bildschirm „Hilfe – jetzt“ benutzt und weder gespeichert noch von der App gesendet.
- Das Whisper-Modell lädt die App nur, wenn du auf „Modell laden“ tippst (von Hugging Face).

## Browser

- Vor dem ersten Mikrofon-Start fragt die Seite einmal um Zustimmung.
- Chrome sendet das Audio an Googles Spracherkennung, Safari an Apple. Pause und Stopp beenden die Erkennung ganz.
- Der erkannte Text geht per GET, also in der URL, an Google Translate, ersatzweise MyMemory.
- Gespeichert wird nur im Browser (`localStorage`): Einstellungen, Zustimmung, Lernkarten und Ähnliches. Die Gesprächsliste verschwindet beim Schließen der Seite.
- Die Seite lädt keine Skripte von Dritten.
