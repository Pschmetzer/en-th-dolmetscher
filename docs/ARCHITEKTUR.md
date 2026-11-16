# Architektur

Überblick für Mitwirkende. Das genaue Ereignis- und Einstellungsformat steht in [PROTOKOLL.md](PROTOKOLL.md), welche Daten wohin gehen in [DATENSCHUTZ.md](DATENSCHUTZ.md).

## Prozessmodell

```
┌──────────────────────────┐   stdin: JSON-Zeilen (Einstellungen)   ┌───────────────────────────┐
│ Dolmetscher.app (Swift)  │ ─────────────────────────────────────▶ │ dolmetscher.py --json     │
│  SwiftUI, Menüleiste,    │                                        │  (Python-Prozess, venv)   │
│  Tastenkürzel, L10n      │ ◀───────────────────────────────────── │  Mikrofon → VAD → Whisper │
│  EngineModel (@MainActor)│   stdout: JSON-Zeilen (Ereignisse)     │  → Übersetzung → Stimme   │
└──────────────────────────┘                                        └───────────────────────────┘
```

- Die App ist nur Oberfläche. Sie startet die Engine als Kindprozess und liest stdout zeilenweise. Mikrofon, Erkennung, Übersetzung und Ton gehören der Engine.
- Welches Python (`Paths.swift`, Logik in `EnvLogic.swift`): Dev-Override (`DOLMETSCHER_PYTHON` bzw. Einstellung `DolmetscherPython`) → eigene venv `~/Library/Application Support/Dolmetscher/venv`, aber nur, wenn ihr Stempel `.dolmetscher-stamp` gleich `Contents/Resources/env-stamp` ist (Lock-Hash, Python 3.12, arm64) → sonst Einrichtungs-Bildschirm (`EnvSetup.swift`). Nie `/usr/bin/python3`. Die Info.plist enthält keine Pfade der Bau-Maschine.
- Einrichtung: `setup-env.sh` (aus `build-support/`) mit dem mitgelieferten, signierten `Contents/Helpers/uv`: uv-verwaltetes Python 3.12 nach `…/Dolmetscher/python`, `uv pip sync --require-hashes --no-build` mit dem mitgelieferten `requirements.txt`, Stempel zuletzt. Danach startet die App die Engine, die fehlende Modelle lädt und `download_progress` meldet. Nur Apple Silicon.
- Bundle-Signatur bleibt heil: die App setzt `PYTHONPYCACHEPREFIX` auf `…/Dolmetscher/pycache`, Hilfsprozesse laufen mit `python -B`.
- Ein Fehler in der Engine stürzt die App nicht ab; die App kann den Prozess beenden und neu starten (`EngineModel.restart()`), etwa wenn sich Startargumente ändern (Mikrofon, Modell, Stimme). Reine Laufzeit-Einstellungen (Tempo, Lautstärke, Sperre auf eine Sprache, Pause) gehen als JSON auf stdin, ohne Neustart.
- Unbekannte JSON-Felder werden auf beiden Seiten ignoriert, so bleiben ältere und neuere Teile kompatibel.
- Dieselbe Engine läuft im Terminal (`python3 dolmetscher.py`), dann ohne `--json` mit Textausgabe.

## Engine: Threads und Pipeline

| Thread / Komponente | Aufgabe |
|---|---|
| Hauptthread (`control_loop`) | liest stdin (Einstellungen, Befehle der App), verarbeitet Aufträge aus der `jobs`-Queue (Erkennen und Übersetzen) |
| `mic-read`, `mic` (`Mic`, `StreamVAD`) | Mikrofon über `avhelper.py` (PyAV/avfoundation, Kindprozess; mit `DOLMETSCHER_FFMPEG` über ffmpeg) lesen, Stille/Sprache erkennen (Silero-VAD), bei Satzende einen Auftrag in die `jobs`-Queue legen |
| `load-*` | Whisper-Modelle parallel laden (`Engine.__init__`) |
| `speaker` (`Speaker`) | Sprachausgabe in eigener Warteschlange; Aufholmodus (schneller sprechen) und Überspringen alter Ausgaben bei Rückstand |
| `tts` (Event-Loop für `edge-tts`), `tts-warmup`, `say-prerender` | Verbindung zur Neural-Stimme schon während des Sprechens öffnen, Fallback `say` vorbereiten |
| kurzlebige Threads | Aufwärmen von Übersetzung und Thai-Umschrift beim Start |

Ablauf eines Satzes: Mikrofon → VAD (Satzende nach `--silence`) → Sprache bestimmen (Whisper-Wahrscheinlichkeiten, ggf. Stimmprofil, Sperre `--lang`) → Erkennung (englisches oder Thai-Modell) → Befehlserkennung („Translator, …“, wird nie übersetzt) → Übersetzung (Claude, sonst Google, sonst MyMemory) → Ausgabe an den `speaker`. Erkennung und Übersetzung des nächsten Satzes laufen, während der vorige noch gesprochen wird. Die Echo-Sperre verwirft Audio, das während der eigenen Ausgabe plus Nachhall eintrifft.

## Zustände

Es gibt zwei getrennte Zustände, die man nicht vermischen darf:

- **Prozess** (`EngineState` in `app/Engine.swift`): `stopped` → `starting` (Prozess läuft, Modelle laden, bis `ready`) → `running`. Drückt der Nutzer Start, bevor `ready` kam, merkt sich die App den Wunsch und sendet ihn bei `ready`.
- **Äußerung** (je `id`): Platzhalter-Blase bei `thinking` → `utt` mit Text und Übersetzung → `speaking` (nur wenn wirklich Ton kommt) → `speak_done` (genau einmal, auch bei Überspringen oder Abbruch). `dropped` entfernt den Platzhalter. Der Status „spricht“ wird nur über `speaking`/`speak_done` gesetzt, nicht über `listening`.
- Dazu kommen Schalter der Engine: pausiert (die Engine hört weiter auf Befehle), Sprachsperre `auto|en|th`, Richtungen EN→TH / TH→EN einzeln abschaltbar, stumm.

## Dateien

| Datei | Inhalt |
|---|---|
| `dolmetscher.py` | Engine: Mikrofon, VAD, Whisper, Übersetzung, Stimmen, Befehle, JSON-Protokoll |
| `profiles.py` | Stimmprofile (Sprechererkennung per sherpa-onnx), Vokabular-Hinweise |
| `app/*.swift` | SwiftUI-App: `Engine.swift` (Prozess, Ereignisse), `Views`/`BubbleViews`/`SettingsView`, `L10n.swift` (de/en/th), `HotKeys.swift`, `PartnerView.swift` |
| `avhelper.py` | Audio über PyAV als Kindprozess (wie früher ffmpeg): `capture` (s16le auf stdout), `play` (mp3 von stdin → AudioToolbox, vorgewärmt), `list` (Mikrofone) |
| `build.sh` | baut `build/Dolmetscher.app` (swiftc, Info.plist, uv + Lock + Stempel + `setup-env.sh` ins Bundle, Signatur von innen nach außen), optional `--install`/`--release` |
| `build-support/` | Entitlements, `setup-env.sh` (Einrichtung), `make-stamp.sh` (Stempel) |
| `bench/` | Benchmark für Erkennung und Übersetzung |

## Demo-Modus (`DOLMETSCHER_DEMO`)

Setzt man die Umgebungsvariable `DOLMETSCHER_DEMO` (irgendein Wert, z. B. `1`) beim Start der App, füllt `EngineModel` den Verlauf mit festen Beispiel-Blasen (Englisch, Thai, unsicher erkannt, übersprungen, Platzhalter). Außerdem startet `boot()` die Engine nicht (`app/Engine.swift` kehrt früh zurück): kein Python-Prozess, kein Mikrofon, kein Netz. Der Modus ist nur für Screenshots und Oberflächentests gedacht. Beispiel:

```bash
DOLMETSCHER_DEMO=1 open -n ~/Applications/Dolmetscher.app   # oder die Binärdatei direkt starten
```

## Tests

`tests/` importiert `dolmetscher.py` direkt, ohne Modelle, Netz oder Mikrofon. `tests/conftest.py` sorgt dafür, dass kein Test ins echte `engine.log` schreibt. Die Swift-Seite wird in CI nur typgeprüft und kompiliert.
