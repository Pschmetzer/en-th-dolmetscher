# Lizenzen von Modellen, Paketen und Diensten

Stand: November 2026. Der Code dieses Repos steht unter MIT (`LICENSE`). Die Mac-App liefert Modelle und Python-Pakete **nicht** mit:
`build.sh` bzw. die App laden sie auf dem eigenen Mac herunter (die iPhone-App linkt dagegen WhisperKit ein, siehe unten). Wer die App oder Modelle weitergibt, muss die Lizenzen
unten selbst prüfen. Angaben aus den Modellkarten (Hugging Face) bzw. den Paket-Metadaten; keine Rechtsberatung.

## Sprachmodelle

Alle Whisper-Modelle werden mit fester Revision geladen (`MODEL_REVISIONS` in `dolmetscher.py`).

| Modell | Verwendung | Quelle | Lizenz |
|---|---|---|---|
| Whisper `small` | Spracherkennung (Sprache erkennen, `--model small`) | [Systran/faster-whisper-small](https://huggingface.co/Systran/faster-whisper-small) (CTranslate2-Umwandlung von OpenAI Whisper) | MIT |
| Whisper `medium` | Spracherkennung (Standard) | [Systran/faster-whisper-medium](https://huggingface.co/Systran/faster-whisper-medium) | MIT |
| Whisper `large-v3-turbo` | `--model best` | [mobiuslabsgmbh/faster-whisper-large-v3-turbo](https://huggingface.co/mobiuslabsgmbh/faster-whisper-large-v3-turbo) (leitet inzwischen auf `dropbox-dash/faster-whisper-large-v3-turbo` weiter, gleiche Revision) | MIT |
| Thai-Whisper | Thai-Erkennung | [Vinxscribe/biodatlab-whisper-th-medium-faster](https://huggingface.co/Vinxscribe/biodatlab-whisper-th-medium-faster) (Drittkonto, CTranslate2-Umwandlung) | Umwandlung als MIT gekennzeichnet; **das Ausgangsmodell [biodatlab/whisper-th-medium-combined](https://huggingface.co/biodatlab/whisper-th-medium-combined) steht unter Apache-2.0** (gilt für die Gewichte weiter; bei Weitergabe Lizenz- und Hinweispflichten beachten) |
| Silero-VAD | Sprach-Aktivitätserkennung | im Paket `faster-whisper` enthalten ([snakers4/silero-vad](https://github.com/snakers4/silero-vad)) | MIT |
| WeSpeaker ResNet34 (VoxCeleb) | Stimmprofile (Sprechererkennung) | [sherpa-onnx-Release](https://github.com/k2-fsa/sherpa-onnx/releases), SHA-256 geprüft (`profiles.py`) | Code von WeSpeaker: Apache-2.0. Die vortrainierten Modelle folgen laut [WeSpeaker-Doku](https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md) der Lizenz des Datensatzes: VoxCeleb = CC BY 4.0 (Namensnennung nötig). |

## iPhone-App (`ios/`)

| Was | Verwendung | Quelle | Lizenz |
|---|---|---|---|
| WhisperKit 1.1.1 | optionale Spracherkennung (Swift-Paket, in die App gelinkt; Revision in `Package.resolved`) | [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) | MIT |
| swift-argument-parser | nur Abhängigkeit von WhisperKit beim Auflösen, nicht in die App gelinkt | [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 |
| Whisper-Modelle für WhisperKit | nur nach Tippen auf „Modell laden“, **ohne** feste Revision | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) (Core-ML-Umwandlung von OpenAI Whisper) | OpenAI Whisper: MIT; Angaben der Modellkarte vor Weitergabe prüfen |

Apples Spracherkennung, Übersetzung und Stimmen sind Teil von iOS.

## Python-Pakete (direkte Abhängigkeiten, `requirements.in`)

| Paket | Lizenz | Hinweis |
|---|---|---|
| faster-whisper | MIT | |
| ctranslate2 | MIT | |
| onnxruntime | MIT | |
| tokenizers, huggingface-hub | Apache-2.0 | |
| numpy | BSD-3-Clause (mit MIT-/Zlib-/0BSD-/CC0-Anteilen) | |
| av (PyAV) | BSD-3-Clause | Ersetzt seit dem eigenständigen App-Bau das externe ffmpeg (Aufnahme, Wiedergabe, Mikrofonliste, `--file`; `avhelper.py`). Das Wheel bringt FFmpeg 8 als LGPL-3.0-Build mit (`library_meta`: „LGPL version 3 or later“, kein `--enable-gpl`), legt aber zusätzlich `libx264`/`libx265` (GPL) als Dylibs bei. Genutzt werden nur Audio-Teile. Das Wheel liegt **nicht** im App-Bundle: Die App lädt es beim Einrichten von PyPI auf den Mac des Nutzers (wie bisher `build.sh`). Wer PyAV selbst weiterverteilt, muss LGPL/GPL der Dylibs beachten. |
| edge-tts | LGPL-3.0 | nur als Abhängigkeit installiert, nicht im Repo/App-Bundle |
| sherpa-onnx | Apache-2.0 | |
| anthropic | Apache-2.0 | optional (`--llm`) |
| pythainlp | Apache-2.0 | optional (Thai-Umschrift) |

Transitive Pakete stehen mit Version und Hash in `requirements.txt`, darunter z. B. `certifi` (MPL-2.0) und `aiohttp`
(Apache-2.0/MIT). Vollständige Liste der installierten Lizenzen: `pip install pip-licenses && pip-licenses` in der venv.

## Externe Werkzeuge und Dienste

| Was | Lizenz/Bedingungen |
|---|---|
| uv (Astral) | MIT oder Apache-2.0. **Im App-Bundle mitgeliefert** (`Contents/Helpers/uv`, mit der App-Identität signiert); richtet beim ersten Start Python und die Pakete ein. Das von uv geladene Python (python-build-standalone) steht unter der PSF-Lizenz und liegt in `~/Library/Application Support/Dolmetscher/python`. |
| ffmpeg | nicht mehr nötig und nicht mitgeliefert. Nur wenn `DOLMETSCHER_FFMPEG` gesetzt ist, nutzt die Engine ein vorhandenes ffmpeg (Homebrew-Builds enthalten GPL-Teile). |
| Google-Translate-Web-Endpunkt | inoffiziell, keine API-Vereinbarung; kann jederzeit wegfallen oder gesperrt werden (Rückfall MyMemory). |
| MyMemory | öffentliche API mit Tageskontingent, eigene Nutzungsbedingungen. |
| Microsoft-Sprachdienst über `edge-tts` | inoffizieller Zugang zum Vorlesedienst von Microsoft Edge, von Microsoft nicht für andere Programme freigegeben (Risiko: Sperre oder Änderung; Rückfall `say`). |
| Claude API (Anthropic) | kostenpflichtig, Nutzungsbedingungen des eigenen Anthropic-Kontos. |

Was dabei den Mac verlässt: [DATENSCHUTZ.md](DATENSCHUTZ.md).
