<img src="app/icon_1024.png" width="128" align="right" alt="">

# Dolmetscher EN ⇄ TH

Hands-free speech interpreter for macOS: just talk. English is translated into Thai and Thai into English, and the translation is spoken aloud right away. The engine **detects the language by itself**, so there are no buttons to switch.

- Speech recognition: [faster-whisper](https://github.com/SYSTRAN/faster-whisper), local on the Mac, on the Apple GPU (Metal) when available, otherwise CPU. Models: `small` (fast), `medium` (default), `best` (+ large-v3-turbo for English, better with accents; ~1.6 GB extra). Thai is transcribed with a Whisper model fine-tuned on Thai ([biodatlab/whisper-th-medium-combined](https://huggingface.co/biodatlab/whisper-th-medium-combined), CTranslate2 version, MIT), about 30 % fewer errors on quiet or distant Thai speech in our tests (synthetic Thai TTS clips, clean and degraded; real voices may differ – the profile score shows it)
- Translation: Google Translate web endpoint (unofficial, falls back to MyMemory). Needs internet. Optional: translation with Claude (see below)
- Speech output: natural Microsoft neural voices via the unofficial [edge-tts](https://github.com/rany2/edge-tts) library (Thai: Niwat / Premwadee, English: Ava; other voices selectable). The translated text is sent to Microsoft for this. Falls back to macOS voices (`say`) when offline or if that service stops working (`--tts say` forces it)
- Asynchronous output: the next sentence is recognised and translated while the previous one is still being spoken. If too much piles up, the engine catches up by skipping older translations (they stay visible, just not read aloud)
- Latency: roughly 3–5 s after the end of each sentence (recognition ~1.5–3 s on the GPU, translation ~1.5 s, voice ~1.5 s)
- Quiet speech: Silero voice activity detection plus input gain, so soft voices are picked up too
- Only English and Thai: other languages (and noise) are ignored. An Auto / EN / TH picker locks the language if needed
- Log for troubleshooting: `~/Library/Logs/Dolmetscher/engine.log`. Privacy: conversation text is **not** written to the log by default (`--log-text` turns it on)

## Translation with Claude (optional)

`--llm` (or the switch in the app's settings) translates with Claude instead of Google: more natural, keeps context and politeness better. It needs an Anthropic API key and **costs a little per sentence** (billed to your Anthropic account). Key: environment variable `ANTHROPIC_API_KEY`, or a file `~/Library/Application Support/Dolmetscher/anthropic_key` containing only the key (`chmod 600`). Default model `claude-opus-5-5`, change it with `--llm-model ID`. Without a key, without the `anthropic` package or on errors the engine falls back to Google automatically.

## Mac app settings

- **Microphone** (`--mic`, list with `--list-mics`), **speaking rate** (`--rate`, −50 … 50 %), **volume** (`--volume`, 0.2 … 2.0), **voices** for English and Thai (`--voice-en`, `--voice-th`)
- **Pause at end of sentence** (`--silence`, 0.4 … 2.0 s), **sensitivity** (`--sensitivity low|normal|high`), **noise suppression** (`--denoise`)
- **Earcons**: a short tone instead of a spoken confirmation for voice commands (`--earcons`)
- **Push-to-talk**, **menu bar** icon, global shortcuts **⌃⌥D** start/stop (⌃⌥Space is the macOS input-source switch) and **⌃⌥P** pause
- **Quick phrases**: tap a saved sentence, it is translated and spoken like a spoken one
- **Correct & retranslate**: fix a misrecognised bubble, it is translated and spoken again
- **Thai transliteration** (Latin script) for Thai text, and a **confidence marker** on bubbles the recogniser was unsure about

## Voice commands

Talk to it like Siri: start with **"Translator, …"** (or "Hey translator, …"). Commands are never translated.

| Say | Effect |
|---|---|
| Translator, pause / resume | stop translating / start again (it keeps listening for commands) |
| Translator, repeat | say the last translation again |
| Translator, slower / faster | speaking rate |
| Translator, louder / quieter | volume |
| Translator, Thai only / English only / auto | lock the language or detect automatically |
| Translator, female voice / male voice | Thai voice and politeness particle (ค่ะ / ครับ) |
| Translator, English off / Thai off | that language is only shown, not translated or spoken (e.g. you speak English, only your partner's Thai is translated) |
| Translator, English on / Thai on / translate both | turn a direction back on |
| Translator, clear | clear the conversation |
| Translator, help | list the commands |
| Translator. *(pause)* … | answers "Yes?" and takes the next sentence as a command |

Commands only control the app. General questions (weather, facts) are not supported, since that would need an LLM.

## Voice profiles

Each person reads 8 short sentences once (about a minute) in **Voice profiles**. The guide runs fully in Thai for Thai profiles, so a Thai speaker can do it alone. The app language can be switched between ไทย / English / Deutsch.

A profile gives:
- **who is speaking**: their name appears on the bubble
- **the right language**: the person's language decides when detection is unsure, so short Thai sentences are no longer dropped
- **own words**: names, companies, places, passed to Whisper as hints
- **a quality score**: how well the engine understood the sentences

It does *not* retrain the model on the voice. Voiceprints are biometric data. They are stored only on this Mac (`~/Library/Application Support/Dolmetscher/profiles/`, readable only by you) and can be deleted in the app. Speaker recognition uses [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) with the WeSpeaker ResNet34 model (~25 MB, downloaded on first use, checksum-verified).

Terminal: `python3 dolmetscher.py --enroll Nok --enroll-lang th`, `--profiles`, `--vocab Nok "Sukhumvit, Siam"`, `--delete-profile Nok`.

## Mac app

Requirements: macOS 14+, Xcode Command Line Tools, `brew install ffmpeg`, Python 3.

```bash
./build.sh --install
```

This creates a Python environment under `~/Library/Application Support/Dolmetscher/venv` with the pinned versions from `requirements.txt` (via `uv` if installed, else `pip`; re-running the script brings an existing environment back to those versions), downloads the `medium`, `small` and Thai models (once, ~3.5 GB) and installs `~/Applications/Dolmetscher.app`. Use an existing Python instead: `DOLMETSCHER_PYTHON=/path/to/python ./build.sh --install` (nothing is installed into it; it needs the packages from `requirements.txt`).

Each rebuild is signed ad hoc, so macOS may ask for microphone access again. To avoid that, sign with a stable identity: `DOLMETSCHER_SIGN_IDENTITY="Dolmetscher Dev" ./build.sh --install` (see [CONTRIBUTING.md](CONTRIBUTING.md#stable-code-signing)).

The app bundle stores the Python and ffmpeg paths with `~` instead of your home folder, so it contains no user name; if ffmpeg is not found there, the app also looks in `/opt/homebrew/bin` and `/usr/local/bin`.

Open the app, press **Start** (or the space bar) and allow microphone access.

If the Thai voice is missing: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices → Thai (Kanya).

## Terminal only

```bash
pip install -r requirements.txt
python3 dolmetscher.py            # --model small|medium|best  --polite krub|ka  --mic 0  --barge-in  --llm  --log-text
```

All options: `python3 dolmetscher.py --help`. The app ⇄ engine protocol is described in [docs/PROTOKOLL.md](docs/PROTOKOLL.md).

## Browser version

Live: https://pschmetzer.github.io/en-th-dolmetscher/ — `index.html` is the **Web Lite** version: a single file, no build step, no external scripts. It uses Chrome's Web Speech API, so you pick the language yourself (buttons / keys `E`, `T`). The Mac app is better: automatic language detection, voice commands in both languages, better recognition.

Web Lite features:
- Per-direction switches "Translate EN→TH" / "Translate TH→EN". When a direction is off, only the recognized text is shown (no translation, no speech).
- Voice commands in EN mode, at the start of a sentence, never translated: "Translator pause / resume / repeat / slower / faster".
- Partner view (`P`): full screen, only the latest translation in huge type (`Esc` closes).
- Dark/light theme follows the system; works at phone width.
- Keys: `E` English, `T` Thai, `Space` stop, `P` partner view, `Esc` close it.
- Translation: Google endpoint, MyMemory as fallback. Error or quota messages are never shown or spoken as a translation.

Serve it locally with `python3 -m http.server` and open it in Chrome.

## Notes

- Laptop speakers: only audio that arrives while the translation is playing (plus ~300 ms of reverb) is discarded, so the engine doesn't translate its own voice. Speech during recognition and translation is queued and handled in order, so a quick answer is not lost.
- `--barge-in` (headphones only): talking while the translation plays stops it immediately. On speakers the engine would interrupt itself.
- Log: `~/Library/Logs/Dolmetscher/engine.log`, rotated at about 1 MB (2 files kept). Recognised and translated text is left out by default; `--log-text` writes it (useful for bug reports, remove personal content before sharing).
- `--polite krub|ka` picks the Thai politeness particle (ครับ/ค่ะ) and the pronoun (ผม/ฉัน).

## Uninstall

```bash
rm -rf ~/Applications/Dolmetscher.app
rm -rf ~/Library/Application\ Support/Dolmetscher   # Python environment and settings
rm -rf ~/Library/Logs/Dolmetscher
rm -rf ~/.cache/huggingface/hub/models--Systran--faster-whisper-*   # Whisper models (shared with other apps using faster-whisper)
```

Microphone permission: System Settings → Privacy & Security → Microphone, or `tccutil reset Microphone io.github.dolmetscher.en-th`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests: `pip install -r requirements-dev.txt && pytest` (no models, network or microphone needed). Lint: `ruff check dolmetscher.py profiles.py bench/`. Latency and quality benchmark: see [bench/README.md](bench/README.md).

## License

MIT License. Dependencies keep their own licenses; notably [edge-tts](https://github.com/rany2/edge-tts) is LGPL-3.0. It is only installed as a dependency, not included in this repository or the app bundle.
