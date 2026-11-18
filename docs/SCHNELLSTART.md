# Schnellstart

In wenigen Minuten zum ersten übersetzten Satz – je nach Gerät. Ausführliche Beschreibung aller Funktionen:
[README.md](../README.md) (englisch). Bei Problemen: [FEHLERHILFE.md](FEHLERHILFE.md), häufige Fragen: [FAQ.md](FAQ.md).

| Gerät | Weg | Dauer |
|---|---|---|
| Browser (Chrome) | Seite öffnen, fertig | 1 Minute |
| Mac (Apple Silicon, macOS 14+) | aus dem Quellcode bauen, ein Befehl | einmalig ca. 3,5 GB Download |
| iPhone / iPad (iOS 26+) | selbst in Xcode bauen, mit eigener Apple-ID | 10–15 Minuten |

## Browser (Web Lite)

1. Am besten in **Chrome** öffnen: https://pschmetzer.github.io/en-th-dolmetscher/ (Safari geht mit
   eingeschalteter Diktierfunktion; Firefox hat keine Spracherkennung).
2. *Ich spreche* und *Partner spricht* wählen (Standard: Englisch ⇄ Thai).
3. Den Knopf deiner Sprache drücken (oder Taste `E`), sprechen. Für den Partner den anderen Knopf (Taste `T`).
   Beim ersten Mal fragt die Seite einmal um Einwilligung, danach der Browser um das Mikrofon.
4. `Leertaste` stoppt, `P` zeigt die letzte Übersetzung groß für den Partner (`Esc` schließt).

Wichtig: Im Browser erkennt die Seite die Sprache **nicht** selbst – du wählst, wer spricht. Die Spracherkennung
läuft über den Dienst des Browsers (Chrome: Google), Audio verlässt also das Gerät
([DATENSCHUTZ.md](DATENSCHUTZ.md)). Über „Zum Startbildschirm hinzufügen“ lässt sich die Seite als App installieren;
Satzbuch und Seite öffnen dann auch ohne Netz, Übersetzen braucht weiter Internet.

Lokal ausprobieren (z. B. für eigene Änderungen): im Repository-Ordner `make web` (oder `python3 -m http.server 8000`),
dann http://localhost:8000 in Chrome.

## Mac

Voraussetzungen: Mac mit **Apple Silicon** (M1 oder neuer, kein Intel), macOS 14 oder neuer,
Xcode-Command-Line-Tools (`xcode-select --install`) und [uv](https://docs.astral.sh/uv/) (`brew install uv`).
Homebrew-Python und ffmpeg werden **nicht** gebraucht.

```bash
git clone https://github.com/Pschmetzer/en-th-dolmetscher.git
cd en-th-dolmetscher
./build.sh --install
```

`build.sh --install` baut `build/Dolmetscher.app`, kopiert sie nach `~/Applications/Dolmetscher.app`, legt die
Python-Umgebung unter `~/Library/Application Support/Dolmetscher/venv` an und lädt die Sprachmodelle `medium`,
`small` und das Thai-Modell (zusammen ca. 3,5 GB, nur einmal).

Danach:

1. `~/Applications/Dolmetscher.app` öffnen.
2. **Start** drücken (oder `Leertaste`) und den Mikrofonzugriff erlauben.
3. Einfach sprechen. Die App erkennt, welche der beiden Sprachen des Paars gesprochen wird, übersetzt und liest vor.

Nützlich für den Anfang:

- Sprachpaar, Mikrofon, Stimmen und Tempo stehen in den Einstellungen.
- Globale Tastenkürzel: **⌃⌥D** Start/Stopp, **⌃⌥P** Pause.
- Mit Englisch im Paar gibt es Sprachbefehle: „Translator, pause“, „Translator, repeat“, „Translator, help“ …
- Laptop-Lautsprecher funktionieren (die Engine verwirft Audio, das während der eigenen Ausgabe eintrifft);
  Kopfhörer sind trotzdem besser.

Kopierst du die App auf einen **anderen** Mac, zeigt sie beim ersten Start einen Einrichtungs-Bildschirm: Sie lädt ihr
eigenes Python 3.12, die gesperrten Pakete (~0,4 GB) und die Modelle, jeweils mit Fortschrittsbalken.

Weitere Bauoptionen (`./build.sh --help`): andere Modelle mit `DOLMETSCHER_MODELS="medium small th best"`,
Modell-Download überspringen mit `DOLMETSCHER_SKIP_MODELS=1`, feste Signatur mit `DOLMETSCHER_SIGN_IDENTITY`,
Release-Bau mit `--release` – Details in [CONTRIBUTING.md](../CONTRIBUTING.md).

### Nur im Terminal (ohne App)

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --require-hashes -r requirements.txt
.venv/bin/python dolmetscher.py                    # Englisch ⇄ Thai
.venv/bin/python dolmetscher.py --langs de,th      # Deutsch ⇄ Thai
.venv/bin/python dolmetscher.py --list-mics        # Mikrofone auflisten
```

Alle Optionen: `.venv/bin/python dolmetscher.py --help`, Bedeutung im Detail: [PROTOKOLL.md](PROTOKOLL.md).

## iPhone / iPad

Voraussetzungen: ein Mac mit **Xcode 26** oder neuer, ein iPhone oder iPad mit **iOS 26** oder neuer, eine
(kostenlose) Apple-ID. Eine App-Store-Version gibt es noch nicht.

1. `open ios/Dolmetscher.xcodeproj`
2. Xcode → Settings → Accounts: Apple-ID hinzufügen.
3. Ziel **Dolmetscher** → *Signing & Capabilities*: *Team* wählen und die *Bundle Identifier*
   `com.pschmetzer.dolmetscher` in etwas Eigenes ändern (z. B. `com.deinname.dolmetscher`).
4. iPhone anschließen, als Ziel wählen, **Run** (⌘R). Auf dem iPhone beim ersten Mal:
   Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwicklerzertifikat vertrauen, ggf. Entwicklermodus einschalten.
5. Mikrofon und Spracherkennung erlauben, **Start** drücken, sprechen.

Für Übersetzung **ohne Internet** die Sprachpakete laden: in den Einstellungen der App (Download-Knopf für das aktuelle
Paar) oder in den iOS-Einstellungen unter Apps → Übersetzen (englisch: Settings → Apps → Translate → Downloaded Languages). Online-Übersetzung (Google/MyMemory)
ist standardmäßig aus und nur als Rückfall einschaltbar („Online-Übersetzer als Ersatz“).

Mehr (Whisper-Modelle, Debug-Schalter, Tests): [ios/README.md](../ios/README.md).

## Für Mitwirkende

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --require-hashes -r requirements-dev.txt
.venv/bin/python -m pytest          # ohne Modelle, Netz und Mikrofon
make lint                           # ruff wie in der CI, Syntaxprüfung der Shell-Skripte
make test-web                       # nur Web, Pakete, Sprachen (braucht node)
```

Ohne Mac lassen sich Presets, Web-Version und Doku bearbeiten; Regeln, Lock-Dateien und Signatur:
[CONTRIBUTING.md](../CONTRIBUTING.md), Aufbau: [ARCHITEKTUR.md](ARCHITEKTUR.md).
