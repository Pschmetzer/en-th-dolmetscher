# Engine ⇄ App: Protokoll (Stand Branch feat/latenz-thai-ui)

Die Mac-App startet `dolmetscher.py --json …`. Die Engine schreibt **eine JSON-Zeile pro Ereignis** auf stdout.
Die App schickt Einstellungen als **JSON-Zeilen auf stdin**. Unbekannte Felder werden auf beiden Seiten ignoriert.

## Neu: Sprachausgabe läuft asynchron

Erkennung und Übersetzung des nächsten Satzes laufen, während der vorige noch vorgelesen wird.
Deshalb kann `thinking` für Satz 2 kommen, während Satz 1 noch `speaking` ist.
Jede Äußerung hat eine `id` (String, z. B. `"u7"`). Die App darf den Status „spricht“ nur über
`speaking`/`speak_done` setzen bzw. zurücksetzen, **nicht** über `listening`.

## Startargumente

| Argument | Bedeutung |
|---|---|
| `--model small\|medium\|best` | wie bisher |
| `--polite krub\|ka`, `--lang auto\|en\|th`, `--mute`, `--no-en`, `--no-th`, `--barge-in` | wie bisher |
| `--mic INDEX` | Mikrofon (Index aus `--list-mics`) |
| `--list-mics` | gibt `{"event":"mics","mics":[{"index":"0","name":"MacBook Pro Microphone"}]}` aus und beendet sich |
| `--rate N` | Sprechtempo in %, −50 … 50 (Standard 0) |
| `--volume F` | Lautstärke 0.2 … 2.0 (Standard 1.0) |
| `--silence S` | Sekunden Stille bis Satzende, 0.4 … 2.0 (Standard 0.8) |
| `--sensitivity low\|normal\|high` | Empfindlichkeit der Spracherkennung (VAD) |
| `--denoise` | Rauschunterdrückung im Mikrofon-Filter |
| `--voice-en NAME`, `--voice-th NAME` | Neural-Stimme (z. B. `en-US-AvaMultilingualNeural`, `th-TH-PremwadeeNeural`); ohne Angabe: Thai nach `--polite` |
| `--llm` | Übersetzung mit Claude (braucht API-Schlüssel, sonst automatisch Google) |
| `--llm-model ID` | Standard `claude-opus-5-5` |
| `--earcons` | Signalton statt gesprochener Bestätigung bei Sprachbefehlen |
| `--meter` | Pegel-Ereignisse `level` senden |
| `--log-text` / `--no-log-text` | Gesprächstexte ins Log schreiben. **Standard jetzt: aus** |

API-Schlüssel: Umgebungsvariable `ANTHROPIC_API_KEY` oder Datei
`~/Library/Application Support/Dolmetscher/anthropic_key` (nur der Schlüssel, Rechte 0600).

## Ereignisse (stdout)

| event | Felder | Hinweis |
|---|---|---|
| `loading` | `msg` | |
| `ready` | `msg`, `device`, `llm` (bool: Claude aktiv) | |
| `listening` | | Mikrofon bereit; ändert den Sprech-Status nicht |
| `hearing` | | jemand spricht gerade |
| `thinking` | `id` | Äußerung `id` wird erkannt/übersetzt → Platzhalter-Blase |
| `dropped` | `reason`, `id` (optional) | Platzhalter `id` entfernen |
| `utt` | `id`, `lang`, `to`, `text`, `out`, `stt`, `tr` (s), `lp` (Erkennungs-Konfidenz, log-prob, ≈ −0.1 sicher … −1.3 unsicher), `translated`, `provider` (`claude`\|`google`\|`mymemory`\|`none`), `speaker`, `replaces` (optional: id der korrigierten Blase), `source` (`mic`\|`phrase`\|`edit`) | |
| `speaking` | `id`, `first_s` (s bis zum ersten Ton) | nur wenn wirklich Ton kommt (nicht bei stumm, Überspringen, Abbruch vor dem ersten Ton); `id` = `"cmd"` bei Befehlsantworten und „repeat“ |
| `speak_done` | `id`, `skipped` (bool), `interrupted` (bool) | kommt für jede eingereihte Ausgabe **genau einmal**, auch ohne vorheriges `speaking`; `skipped`: wegen Rückstand/Stopp nicht vorgelesen |
| `queue` | `stt` (wartende Äußerungen), `tts` (wartende Ausgaben) | bei jeder Änderung |
| `level` | `rms` (0…1, dBFS skaliert), `voice` (bool) | ~7×/s, nur mit `--meter` |
| `net` | `ok` (bool), `what` (`translate`\|`tts`) | nur bei Zustandswechsel |
| `command` | wie bisher + `rate`, `volume`, `voice_en`, `voice_th` | App speichert `rate`/`volume` dauerhaft |
| `error` | `msg` | |
| `barge_in` | | |

## Steuerung (stdin)

Bisher: `tr_en`, `tr_th`, `lang`, `polite`, `speak`, `paused`.

Neu:

| Feld | Typ | Wirkung |
|---|---|---|
| `rate` | int | Sprechtempo |
| `volume` | float | Lautstärke |
| `silence` | float | Satzende-Pause |
| `sensitivity` | `low\|normal\|high` | VAD-Schwellen |
| `voice_en`, `voice_th` | string | Stimme (leer = Standard) |
| `llm` | bool | Claude-Übersetzung an/aus |
| `earcons` | bool | Signaltöne statt Sprache bei Befehlen |
| `stop_speaking` | true | laufende und wartende Ausgaben abbrechen |
| `say` | `{"text": "...", "lang": "en"\|"th"}` | Schnellsatz: übersetzen und vorlesen wie eine Äußerung (`source: "phrase"`) |
| `retranslate` | `{"id": "u7", "text": "korrigierter Text", "lang": "en"\|"th"}` | neu übersetzen und vorlesen; `utt` kommt mit `replaces: "u7"`, `source: "edit"` |

## Tempo-Ausbau (Branch feat/tempo)

### Engine bleibt geladen (kein Modell-Laden bei jedem Start)

- Neues Startargument `--idle`: Modelle laden, Mikrofon **aus**. Die App startet die Engine damit
  gleich beim App-Start im Hintergrund.
- Steuerung `{"listen": true}` öffnet das Mikrofon (Start-Knopf), `{"listen": false}` schließt es
  wieder (Stopp-Knopf; Mikrofon-Anzeige von macOS geht aus). Die Modelle bleiben geladen.
- Ereignis `mic` mit `on` (bool) bestätigt den Zustand. `ready` kommt einmal nach dem Laden.
- Laufende/wartende Ausgaben werden bei `listen: false` abgebrochen.

### Teiltext und Vorab-Erkennung

- Jede Äußerung bekommt ihre `id` schon beim Sprechbeginn (`hearing` hat jetzt `id`).
- Neues Ereignis `partial` mit `id`, `text`, `lang`: vorläufiger Text, während noch gesprochen wird
  (etwa alle 2 s, nur wenn die Engine nicht ausgelastet ist). Die App zeigt ihn in der Platzhalter-Blase.
- Danach kommen wie bisher `thinking` → `utt`/`dropped` mit derselben `id`.

### Latenz

- `speaking` hat zusätzlich `latency_s`: Sekunden vom Ende der Äußerung (letzter Sprach-Frame)
  bis zum ersten Ton. `utt` hat zusätzlich `ready_s`: Sekunden vom Ende der Äußerung bis die
  Übersetzung fertig ist.

### Neue Einstellungen

| Startargument | Steuerung | Bedeutung |
|---|---|---|
| `--tts-race S` (Standard 0.9, 0 = aus) | `tts_race` (float) | kommt die Neural-Stimme nicht in S Sekunden, spricht sofort die vorbereitete macOS-Stimme |
| `--no-fast-endpoint` | `fast_endpoint` (bool) | schnelles Satzende: nach 0,35 s Pause vorab erkennen; sieht der Satz fertig aus, nicht bis zur vollen Pause warten |
| `--no-partial` | `partial` (bool) | Teiltext während des Sprechens |
