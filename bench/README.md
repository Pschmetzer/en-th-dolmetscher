# Benchmark: Erkennung und Übersetzung messen

Mit dem Benchmark lässt sich belegen, ob eine Änderung an der Engine die Erkennung (STT) oder die Übersetzung verbessert, vor allem für Thai→Englisch.

Python: `PY="$HOME/Library/Application Support/Dolmetscher/venv/bin/python"`

## 1. Audio erzeugen

```sh
"$PY" bench/make_audio.py                    # sauber      -> bench/audio/clean/
"$PY" bench/make_audio.py --noise            # rosa Rauschen, SNR 15 dB -> bench/audio/noise/
"$PY" bench/make_audio.py --quiet            # −20 dB      -> bench/audio/quiet/
"$PY" bench/make_audio.py --noise --quiet --rate 150 --cases th01,th27
```

Die Fälle stehen in `cases.json`. Thai wird mit der Stimme „Kanya“ erzeugt, Englisch mit „Samantha“. Als ffmpeg wird `DOLMETSCHER_FFMPEG` genommen, sonst das ffmpeg im PATH, sonst `/opt/homebrew/bin/ffmpeg`. `bench/audio/` wird nicht eingecheckt.

## 2. Messen

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

Der Vergleich zeigt für jede Kennzahl alt → neu mit der Differenz, außerdem die Fälle, deren Fehlerrate sich geändert hat. `results/baseline_main.json` ist der Stand von `main` (medium, CPU, saubere Stimmen).

## Grenzen und eigene Aufnahmen

- **Synthetische Stimmen ersetzen keine echten Sprecher.** Kanya spricht deutlich, in Standard-Thai und ohne Raumhall. Die echten Fehler wie „ฉันม่วงนอน“ statt „ฉันง่วงนอน“ treten bei ihr seltener auf.
- **Eigene Aufnahmen** legt man als `bench/audio/real/<id>.wav` ab, mit derselben ID wie in `cases.json` (auch `.m4a`/`.mp3` gehen). `run_bench.py` nimmt sie bevorzugt, die Referenz kommt aus `cases.json`. Am besten wird der Referenztext wörtlich vorgelesen.
- Der Benchmark gibt die ganze Datei direkt an `process()` weiter, Mikrofon und VAD-Schnitt im Recorder laufen nicht mit. Trotzdem zeigen die langen Fälle (th27, th28, ca. 17–18 s) das Abschneiden. Die Ursache liegt also in der Erkennung selbst und nicht nur im Recorder: Mit `max_new_tokens=160` in `_stt` bricht das Thai-Modell nach etwa 80 Tokens ab (CER ca. 47 %). Ohne die Grenze liegt die CER bei ca. 2 %.
- `process()` hebt leise Aufnahmen an (Spitze < 0,5). `--quiet` allein ändert deshalb wenig, sinnvoll ist es vor allem zusammen mit `--noise`.
