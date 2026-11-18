# Häufige Fragen (FAQ)

Kurze Antworten mit Verweisen. Installation: [SCHNELLSTART.md](SCHNELLSTART.md), Probleme: [FEHLERHILFE.md](FEHLERHILFE.md).

## Allgemein

**Was ist der Dolmetscher?**
Ein Sprach-Dolmetscher zum Freisprechen: Du sprichst, er übersetzt in die Sprache deines Gegenübers und liest vor; die
Antwort kommt in deiner Sprache zurück. Mac und iPhone erkennen selbst, welche der zwei Sprachen gesprochen wird.

**Welche Geräte gibt es?**
Drei Varianten: die Mac-App (Apple Silicon, macOS 14+), die iPhone-/iPad-App (iOS 26+) und die Browser-Version
Web Lite (am besten Chrome). Ein Vergleich steht oben in der [README](../README.md#features-at-a-glance).

**Gibt es eine fertige Download- oder App-Store-Version?**
Nein, noch nicht. Die Mac-App baust du mit `./build.sh --install`, die iPhone-App in Xcode mit eigener Apple-ID.
Die Browser-Version läuft sofort unter https://pschmetzer.github.io/en-th-dolmetscher/.

**Läuft es auf Intel-Macs, Windows oder Android?**
Die Mac-App nur auf Apple Silicon (M1 oder neuer); `build.sh` und die Einrichtung brechen auf Intel ab. Für Windows,
Linux und Android gibt es nur die Browser-Version (in Chrome); auf Android lässt sie sich installieren und nimmt dann auch
geteilten Text zum Übersetzen an.

**Was kostet es?**
Die App selbst nichts (MIT-Lizenz). Nur die optionale Übersetzung mit Claude kostet: Sie braucht einen eigenen
Anthropic-API-Schlüssel und wird pro Satz über dein Anthropic-Konto abgerechnet (Standardmodell `claude-haiku-5-5`,
etwa 8 US-Cent pro Gesprächsstunde). Ein Monatslimit setzt `--llm-budget USD`.

**Brauche ich ein Konto?**
Nein. Es gibt keine Konten, keine Telemetrie und keinen eigenen Server.

## Sprachen

**Welche Sprachen gehen?**
19: Englisch, Thai, Deutsch, Spanisch, Französisch, Italienisch, Portugiesisch, Niederländisch, Russisch, Chinesisch
(Mandarin), Japanisch, Koreanisch, Vietnamesisch, Indonesisch, Arabisch, Hindi, Türkisch, Polnisch, Ukrainisch – jedes
Paar daraus. Standard ist Englisch ⇄ Thai. Die gemeinsame Sprachtabelle ist `languages.json`.

**Kann ich mehr als zwei Sprachen gleichzeitig nutzen?**
Nein. Die Erkennung wählt immer nur zwischen den zwei Sprachen des Paars. Das Paar lässt sich aber jederzeit wechseln
(Mac: Einstellungen oder `--langs MEINE,PARTNER`).

**Wie gut sind die neuen Sprachen?**
Außer Englisch und Thai sind sie noch nicht mit echten Sprechern getestet, und die Erkennungsschwellen sind für sie nicht
kalibriert. Auch die Thai-Sätze und die meisten Oberflächentexte sind maschinell erstellt und nicht von Muttersprachlern
geprüft – Korrekturen sind willkommen ([PRESETS.md](PRESETS.md#muttersprachler-gesucht)).

**Warum gibt es manche Funktionen nur mit Thai oder Englisch im Paar?**
Höflichkeitspartikel (ครับ/ค่ะ), das Thai-Whisper-Modell, Thai-Zahlwörter, Umschrift sowie (iPhone) Baht-Rechner und
Thai-Notrufnummern ergeben nur mit Thai Sinn. Das Weckwort und die Sprachbefehle („Translator, …“) sind absichtlich
englisch und funktionieren daher nur mit Englisch im Paar.

## Datenschutz

**Verlässt meine Stimme das Gerät?**
- **Mac:** Nein. Die Erkennung läuft lokal (Whisper). Ins Netz gehen nur der erkannte *Text* zur Übersetzung (Google,
  Rückfall MyMemory, oder Claude, wenn eingeschaltet) und der übersetzte Text für die Neural-Stimme (Microsoft).
- **iPhone:** Nein. Erkennung und – mit installierten Sprachpaketen – Übersetzung laufen auf dem Gerät; Online-Übersetzung
  ist standardmäßig aus.
- **Browser:** Ja. Die Spracherkennung des Browsers schickt Audio an dessen Dienst (Chrome: Google).

Alles im Detail: [DATENSCHUTZ.md](DATENSCHUTZ.md).

**Wird das Gespräch gespeichert?**
Mac: Der Verlauf ist standardmäßig **aus** (`--history`), lokal in `~/Library/Application Support/Dolmetscher/history.sqlite`,
mit `--history-days N` beim Start um ältere Einträge bereinigt und mit `--history-clear` löschbar. iPhone: standardmäßig 30 Tage, einstellbar,
optional mit Face-ID-Sperre. Browser: kein Verlauf, nur Kopieren oder Speichern von Hand. Im Engine-Log steht kein
Gesprächstext, außer mit `--log-text`.

**Was ist mit Stimmprofilen?**
Stimmabdrücke sind biometrische Daten. Sie liegen nur auf dem Mac (`~/Library/Application Support/Dolmetscher/profiles/`,
nur für dich lesbar) und lassen sich einzeln oder alle auf einmal löschen („Alle Stimmdaten löschen“ bzw.
`--delete-all-profiles`). Ein Profil trainiert das Modell nicht nach.

**Wo liegt mein Claude-Schlüssel?**
In der Mac-App im macOS-Schlüsselbund. Eine ältere Datei `~/Library/Application Support/Dolmetscher/anthropic_key` wird
beim Start übernommen und als `anthropic_key.migrated` behalten. Im Terminal: Umgebungsvariable `ANTHROPIC_API_KEY`.

**Was macht der private Modus?**
`--private` (Mac): keine Aufwärm-Anfragen an die Dienste, Text steht nie in einer URL.

## Mac-App

**Geht es ohne Internet?**
Die Erkennung ja. Übersetzung ohne Netz gibt es ab macOS 26.4 über Apple („Offline-Übersetzung (Apple) als Rückfall“,
Standard an, Sprachpakete in den Systemeinstellungen); vorgelesen wird dann mit der macOS-Stimme. Ältere macOS-Versionen
übersetzen offline nicht. Für die erste Einrichtung und die Modelle braucht es Internet.

**Wie viel Speicher braucht es?**
Einmal ca. 3,5 GB für die Standardmodelle (`medium`, `small`, Thai-Modell) plus ~0,4 GB für die Python-Umgebung.
`--model best` (large-v3-turbo) braucht ~1,6 GB zusätzlich.

**Welches Modell soll ich nehmen?**
`medium` ist Standard. `small` ist schneller, `best` besser bei Akzenten, `auto` wählt nach Chip und Arbeitsspeicher.
Für Thai nutzt die Engine ein auf Thai feinabgestimmtes Modell, wenn Thai im Paar ist.

**Wie schnell ist es?**
Einige Sekunden nach Satzende: auf der Apple-GPU etwa 3–5 s, auf der CPU deutlich langsamer (Benchmark `medium` auf CPU,
synthetische Stimmen: Median 6,8 s, p90 8,5 s, [bench/README.md](../bench/README.md)). Der nächste Satz wird schon erkannt,
während der vorige noch gesprochen wird.

**Brauche ich Kopfhörer?**
Nein. Audio, das während der eigenen Ausgabe (plus ~300 ms Nachhall) eintrifft, wird verworfen, damit die App sich nicht
selbst übersetzt. Mit Kopfhörern kannst du mit `--barge-in` die Ausgabe durch Sprechen unterbrechen.

**Wie stimmen Preise und Uhrzeiten?**
Weichen die Zahlen der Übersetzung vom Original ab, fragt die Engine den anderen Anbieter und nimmt die Version mit passenden
Zahlen; sonst zeigt die Blase eine Warnung.

**Was ist besser: Google oder Claude?**
Claude (`--llm`) übersetzt natürlicher und hält Kontext und Höflichkeit besser, kostet aber. Claude bekommt den erkannten Satz,
die letzten Sätze als Kontext (Standard 8) und dein Glossar. Sieht die Antwort falsch aus (falsche Schrift, Ablehnung,
Kommentar), übersetzt Google diesen Satz; ohne Schlüssel oder bei Fehlern fällt die Engine automatisch auf Google zurück.

**Kann ich das Ganze ohne App im Terminal nutzen?**
Ja: `python3 dolmetscher.py` (mit der venv aus `requirements.txt`), alle Optionen mit `--help`. Die App ist nur eine
Oberfläche, die dieselbe Engine mit `--json` startet ([ARCHITEKTUR.md](ARCHITEKTUR.md)).

**Wie entferne ich alles wieder?**
App, `~/Library/Application Support/Dolmetscher`, `~/Library/Logs/Dolmetscher` und die Modelle unter
`~/.cache/huggingface/hub/` löschen – die genauen Befehle stehen in der [README](../README.md#uninstall).

## iPhone-App

**Warum muss ich sie selbst bauen?**
Sie ist noch nicht im App Store. Mit einer kostenlosen Apple-ID läuft sie auf deinem eigenen Gerät, muss aber alle 7 Tage
neu aus Xcode installiert werden ([ios/README.md](../ios/README.md)).

**Nutzt sie die Python-Engine des Macs?**
Nein. Sie ist eine eigene SwiftUI-App mit Apples Spracherkennung (optional Whisper über WhisperKit) und Apples
Übersetzung auf dem Gerät.

**Brauche ich Whisper?**
Nein, es ist optional („Whisper verwenden (experimentell)“). Modelle werden nur geladen, wenn du auf Download tippst. Whisper zeigt
keinen Live-Text und braucht mehr Akku und Speicher; kleine Modelle (tiny/base) taugen für Englisch, kaum für Thai.

## Browser-Version

**Warum muss ich im Browser selbst wählen, wer spricht?**
Die Web-Speech-Erkennung des Browsers erkennt nur eine vorher festgelegte Sprache. Daher drückst du `E` (deine Sprache)
bzw. `T` (Partner) oder die Knöpfe. Die Mac-App ist hier besser.

**Geht die Browser-Version offline?**
Als installierte App (PWA) öffnen Seite und Satzbuch auch ohne Netz; Erkennung (Chrome) und Übersetzung brauchen Internet.

**Kann ich sie auf meiner eigenen Domain anbieten?**
Ja, sie besteht nur aus statischen Dateien; HTTPS ist Pflicht. Dateiliste, Header und QR-Links wie
`#preset=hotel&l=de`: [WEB-HOSTING.md](WEB-HOSTING.md).

## Mitmachen

**Wie kann ich helfen ohne Mac?**
Satzbuch-Pakete (`presets/*.json`, [PRESETS.md](PRESETS.md)), Web-Version und Doku brauchen keinen Mac. Tests dafür:
`make test-web`, Prüfung: `make lint`. Regeln für Pull Requests: [CONTRIBUTING.md](../CONTRIBUTING.md).

**Wo melde ich einen falschen Satz?**
Im Browser in der Großansicht über ⚑ (öffnet ein vorbefülltes GitHub-Issue) oder direkt als Issue bzw. Pull Request.
