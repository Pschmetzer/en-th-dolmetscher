# Benchmark: Erkennung und Übersetzung messen

Mit dem Benchmark lässt sich belegen, ob eine Änderung an der Engine die Erkennung (STT) oder die Übersetzung verbessert, vor allem für Thai→Englisch.

Python: `PY="$HOME/Library/Application Support/Dolmetscher/venv/bin/python"`

## 1. Audio erzeugen

```sh
"$PY" bench/make_audio.py                    # sauber      -> bench/audio/clean/
"$PY" bench/make_audio.py --noise            # rosa Rauschen, SNR 15 dB -> bench/audio/noise/
"$PY" bench/make_audio.py --quiet            # −20 dB      -> bench/audio/quiet/
"$PY" bench/make_audio.py --noise --quiet --rate 150 --cases th01,th27
"$PY" bench/make_audio.py --negatives        # Negativfälle -> bench/audio/negatives/
```

**Negativfälle** (`negatives.json`): Stille, rosa Rauschen, Netzbrummen, Musik (Akkorde ohne Gesang), Husten,
Tastaturklicks und drei Fremdsprachen (Deutsch, Japanisch, Spanisch über `say`). Keiner davon darf übersetzt werden.
Mit `run_bench.py --negatives` misst der Lauf zusätzlich `false_accept` (fälschlich übersetzt) und die
`dropped`-Codes; so werden Floskel-, Halluzinations- und Sprachfilter (`MIN_LANG_P`, `MIN_LOGPROB`) messbar.

Die Fälle stehen in `cases.json`; die Tags `num`, `digits`, `time`, `clock` und `phone` markieren Zahlen, Uhrzeiten und Telefonnummern (th43 bis th48, en21 bis en26; Messung mit `--only` und der ID). Die Baseline in `bench/results/` enthält diese Fälle noch nicht und ist bei der nächsten Messung auf `main` zu erneuern. Thai wird mit der Stimme „Kanya“ erzeugt, Englisch mit „Samantha“. Als ffmpeg wird `DOLMETSCHER_FFMPEG` genommen, sonst das ffmpeg im PATH, sonst `/opt/homebrew/bin/ffmpeg` bzw. `/usr/local/bin/ffmpeg` (Intel). `bench/audio/` wird nicht eingecheckt.

## 2. Messen

Mit `--repeat N` wird jeder Fall N-mal verarbeitet; die Zeiten stehen als Median (und `total_p95_s`) im JSON, zusammen mit Gerät und Paketversionen (`meta.device_info`). `--fail-above PROZENT` (nur mit `--compare`) beendet den Lauf mit Exit-Code 2, wenn eine Kennzahl (Fehlerrate, Sprachtreffer, Zeiten, verworfen, Überlapp) um mehr als PROZENT schlechter ist als in der Baseline. Mehrere Sprachbefehle in einem Satz sind (noch) kein Fall: die Befehlsfälle erwarten genau einen Befehl.

```sh
"$PY" bench/run_bench.py --model small --device cpu --only th
"$PY" bench/run_bench.py --model medium --device cpu          # alle Fälle
"$PY" bench/run_bench.py --cases th01,th02 --audio-dir bench/audio/noise
```

Die Engine aus `dolmetscher.py` verarbeitet jede Datei mit `Engine.process(audio, speak=False)`. Gemessen wird pro Fall:

- **Sprache ok**: Wurde die richtige Sprache erkannt?
- **CER bzw. WER**:
  - Thai: CER auf den Zeichen, ohne Leerzeichen und Satzzeichen. `มั้ย` und `ไหม` sowie `เท่าไหร่` und `เท่าไร` zählen als gleich. Zahlwörter werden in Referenz und Erkennung zu Ziffern (`สามร้อย` = `300`).
  - Englisch: WER auf Kleinbuchstaben ohne Satzzeichen. Zahlwörter 0–20 werden als Ziffern gezählt.
  - Ein verworfener Satz zählt als 100 %.
- **Laufzeit**: die Gesamtzeit und die Anteile `stt`/`tr` aus dem `utt`-Ereignis.
- **Übersetzung**: Die Ausgabe steht neben der Soll-Bedeutung (`en_ref`/`th_ref`). „Überlapp“ ist nur ein grober Wort- bzw. Bigramm-F1-Wert und keine Qualitätsnote.

Am Ende erscheint pro Sprache eine Tabelle, dazu die 10 schlechtesten Fälle. Das Ergebnis wird als JSON in `bench/results/<datum>_<model>.json` gespeichert, den Pfad kann man mit `--json-out` ändern.

Weitere Hinweise:

- Die Engine-Ereignisse (`emit`) und das Log (`log`) werden abgefangen, deshalb schreibt der Benchmark nichts ins echte `engine.log`.
- Vor jedem Fall wird der Zustand zurückgesetzt (Pause, Sperre, Wachfenster), sodass „Translator, pause“ die folgenden Fälle nicht beeinflusst.
- Stimmprofile sind aus. Mit `--profiles` bleiben sie an.
- Die Übersetzung braucht Internet (Google, wie in der Engine selbst).

## 3. Vergleichen

```sh
"$PY" bench/run_bench.py --model medium --device cpu --compare bench/results/baseline_main.json
```

Nach einer Änderung an der Metrik lässt sich ein altes Ergebnis ohne Engine neu bewerten: `"$PY" bench/run_bench.py --rescore bench/results/<datei>.json`.

Der Vergleich zeigt für jede Kennzahl alt → neu mit der Differenz, außerdem die Fälle, deren Fehlerrate sich geändert hat. `results/baseline_main.json` ist die gültige Vergleichslinie (Stand `main` vom 12.11.2026, Commit 289de59: medium, CPU, saubere synthetische Stimmen, ein Lauf). `results/feat_medium_cpu.json` ist ein einzelner Zwischenstand eines Feature-Zweigs (Zeiten durch Systemlast verfälscht) und kein Vergleichsmaßstab.

Baseline erneuern: wenn sich ein Modell (Name oder `MODEL_REVISIONS` in `dolmetscher.py`), die Metrik oder `cases.json` ändert, die Baseline auf `main` neu messen (`--repeat 3`, Rechner sonst ruhig) und mit dem Grund im Commit ersetzen. `--model best` und Apple-STT haben noch keine eigene Baseline.

Die Regressionsprüfung (`--fail-above`) wertet Erkennung und Zeit der Erkennung (`stt_mean_s`), nicht
`total_*` (enthält die Netz-Übersetzung). Eine Verschlechterung zählt erst ab einer absoluten Mindestabweichung
(`MIN_ABS`, z. B. 1 Prozentpunkt Fehlerrate, 2 verworfene Sätze); bei Basiswert 0 gilt nur diese Schwelle. Bei weniger
als 20 Fällen steht die Fallzahl in der Meldung. Vor jedem Fall setzt der Lauf auch Claude-Kontext, Übersetzungs-Cache,
letzte Rolle und Preset zurück – die Reihenfolge der Fälle beeinflusst das Ergebnis nicht mehr. Die Kennzahl `real`
zählt eigene Aufnahmen (`bench/audio/real/`).

Regressionsprüfung: Der Benchmark braucht Modelle, `say` und Netz und läuft deshalb nicht im normalen CI-Lauf, nur von Hand: GitHub → Actions → **Benchmark** → *Run workflow* (`.github/workflows/bench.yml`, macOS-26-Runner; Modell, Sprache, `--repeat` und `--fail-above` wählbar; mit `medium` Vergleich gegen `baseline_main.json`; Ergebnis-JSON als Artefakt). Fehlt auf dem Runner die Stimme Kanya, misst der Lauf nur Englisch. Runner-Zeiten sind nicht mit der lokalen Baseline vergleichbar – aussagekräftig sind dort Fehlerraten und verworfene Sätze. Vor einem Release lokal `--compare bench/results/baseline_main.json --fail-above 10` laufen lassen (Release-Checkliste in CONTRIBUTING.md).

## Grenzen und eigene Aufnahmen

Was die Zahlen aussagen und was nicht:

- Alle Fälle sind **synthetisch** (macOS `say`, je eine Stimme: Kanya für Thai, Samantha für Englisch), 28 Thai- und 14 Englisch-Fälle, ohne Raumhall. Fehlerraten und Prozentangaben (auch „~30 % weniger Fehler“ im README) gelten nur für diese Stimmen, nicht allgemein für echte Sprecher.
- Die Zeiten sind Einzelläufe auf einem Rechner (`meta` im JSON) und hängen von Gerät, Last und Cache ab. `total_*_s` misst ab Übergabe der ganzen Datei, nicht die Alltagslatenz am Mikrofon; die misst `bench/e2e.py` (Median/p90 bis Übersetzung und erstem Ton).
- `run_bench.py` bewertet die Übersetzung nicht („Überlapp“ ist kein Qualitätsmaß). Dafür gibt es
  `run_translate.py` (unten).

- **Synthetische Stimmen ersetzen keine echten Sprecher.** Kanya spricht deutlich, in Standard-Thai und ohne Raumhall. Die echten Fehler wie „ฉันม่วงนอน“ statt „ฉันง่วงนอน“ treten bei ihr seltener auf.
- **Eigene Aufnahmen** legt man als `bench/audio/real/<id>.wav` ab, mit derselben ID wie in `cases.json` (auch `.m4a`/`.mp3` gehen). `run_bench.py` nimmt sie bevorzugt, die Referenz kommt aus `cases.json`. Am besten wird der Referenztext wörtlich vorgelesen.
- Der Benchmark gibt die ganze Datei direkt an `process()` weiter, Mikrofon und VAD-Schnitt im Recorder laufen nicht mit. Trotzdem zeigen die langen Fälle (th27, th28, ca. 17–18 s) das Abschneiden. Die Ursache liegt also in der Erkennung selbst und nicht nur im Recorder: Mit `max_new_tokens=160` in `_stt` bricht das Thai-Modell nach etwa 80 Tokens ab (CER ca. 47 %). Ohne die Grenze liegt die CER bei ca. 2 %.
- `process()` hebt leise Aufnahmen an (Spitze < 0,5). `--quiet` allein ändert deshalb wenig, sinnvoll ist es vor allem zusammen mit `--noise`.

## 4. Übersetzung automatisch bewerten

```sh
"$PY" bench/run_translate.py --repeat 3 --json-out bench/results/translate.json
```

Je Satz aus `idioms.json` und Anbieter (Google, Claude-Modelle): Rückübersetzung mit Google und chrF (0–100) gegen
das Original, Zahlen-Erhalt (`numbers_differ` der Engine), Erhalt von Eigennamen und die Zeit (Median über
`--repeat`). Am Ende stehen die Mittelwerte je Anbieter. chrF der Rückübersetzung ist nur ein Näherungswert:
Redewendungen kommen sinngemäß und nie wörtlich zurück. Sinnvoll ist der Vergleich zwischen Anbietern auf denselben
Sätzen, nicht der absolute Wert. `--no-back` spart die Google-Anfragen.
