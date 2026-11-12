# apple-stt: Apples On-Device-Erkennung als Ersatz für faster-whisper?

Kommandozeilen-Werkzeug (Swift, macOS 26), das WAV-Dateien mit `DictationTranscriber` + `SpeechAnalyzer` transkribiert und JSON ausgibt.

```sh
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 tools/apple-stt/main.swift -o tools/apple-stt/apple-stt
./apple-stt --status                                   # Berechtigung + Assets, lädt nichts
./apple-stt --locale en-US --realtime --out r.json bench/audio/clean/en*.wav
python bench/run_apple_stt.py r.json                   # CER/WER mit run_bench.error_rate, Vergleich mit Whisper
```

`--realtime` spielt das Audio in 100-ms-Stücken im Echtzeittakt ein (wie ein Mikrofon). `ms_after_audio_end` = Zeit vom letzten Stück bis zum letzten endgültigen Ergebnis. `--skip-asset-check` ist nötig, weil `AssetInventory.status` auf diesem Mac auch für das tatsächlich installierte en-US „supported“ meldet. Es wird nie etwas heruntergeladen.

## Ergebnis (bench/audio/clean, synthetische Stimmen)

| Sprache | Fälle | Apple CER/WER Ø | Whisper medium CER/WER Ø | Apple: Median nach Audio-Ende | Whisper (GPU, laut Messung in der Engine) |
|---|---|---|---|---|---|
| Englisch (en-US) | 14 | **0,0 % WER** | 1,4 % | **30 ms** (max 77 ms), erstes Teilergebnis nach ~0,7 s | ~1,2–1,9 s |
| Thai (th-TH) | 28 | **nicht messbar: Assets fehlen** | 3,6 % CER | – | ~1,2–1,9 s |

- Ohne Echtzeittakt (ganze Datei sofort): 70–570 ms pro Datei, Analyzer-Vorbereitung ~80 ms (nach dem ersten Mal).
- Berechtigung: Ein nacktes CLI funktioniert ohne Dialog und ohne .app-Bundle, obwohl `SFSpeechRecognizer.authorizationStatus()` = `notDetermined`.
- Zeiten unsicher: Während der Messung lief die Dolmetscher-App (PID 57706, ~10 % CPU) und die Systemlast lag bei ~11 (anderer Prozess). Die Apple-Zeiten sind trotzdem so klein, dass das Ergebnis eindeutig ist.
- Whisper-Vergleich: `hyp` aus `bench/results/feat_medium_cpu.json`, neu bewertet mit derselben Funktion. Die dortigen Zeiten (CPU) sind nicht vergleichbar, daher die GPU-Angabe.
- Fairness: Apple bekam die richtige Sprache vorgegeben, Whisper musste sie selbst erkennen. Die Testaudios stammen aus Apples eigener Sprachausgabe (`say`), was Apple begünstigen kann.

### Thai: Assets fehlen

`DictationTranscriber.installedLocales` = `de-DE, en-US`; th-TH ist „supported“, aber nicht installiert. `bestAvailableAudioFormat` liefert für th-TH nichts. Installieren (durch den Nutzer): Systemeinstellungen > Tastatur > Diktat > Sprachen > „Thai (Thailand)“ hinzufügen (lädt das Modell), oder im Code `AssetInventory.assetInstallationRequest(supporting:)` + `downloadAndInstall()`. Danach: `./apple-stt --locale th-TH --realtime --out th.json bench/audio/clean/th*.wav`.

### Falsche Sprache

Thai-Audio mit en-US ergibt Unsinn („Chan non-crap“ für ฉันง่วงนอนครับ). Apple braucht also eine feste, richtige Sprache.

## Empfehlung

- **Englisch: ja**, Apple kann Whisper ersetzen (gleiche Qualität, Latenz ~30 ms statt 1–2 s).
- **Thai: offen**, bis die Assets installiert und die 28 Fälle gemessen sind. Erst bei CER ≤ ~4 % (Whisper-Niveau) umstellen.
- Einbau: als dauerhaft laufender Unterprozess (`apple-stt --stream --locale …`), der 16-kHz-PCM über stdin bekommt und Teil-/Endergebnisse als JSON-Zeilen ausgibt. Analyzer pro Sprache einmal vorbereiten und halten. Whisper bleibt als Rückfall.
- Sprachwechsel: Die Engine erkennt die Sprache heute über Whisper (`p_en`/`p_th`). Möglichkeiten: (a) zwei Analyzer (en-US, th-TH) parallel mit demselben Audio füttern und das Ergebnis mit höherer Konfidenz (`transcriptionConfidence`) bzw. Thai-Zeichenanteil nehmen; (b) Spracherkennung billig mit Whisper-tiny/`detect_language` auf den ersten ~1 s, dann den passenden Apple-Analyzer finalisieren; (c) Standard = zuletzt erkannte Sprache, Umschalten bei Unsinn/geringer Konfidenz.
