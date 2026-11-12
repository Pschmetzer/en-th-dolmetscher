<img src="app/icon_1024.png" width="128" align="right" alt="">

# Dolmetscher EN ⇄ TH

Hands-free speech interpreter for macOS: just talk. English is translated into Thai and Thai into English, and the translation is spoken aloud right away. The engine **detects the language by itself**, so there are no buttons to switch.

- Speech recognition: [faster-whisper](https://github.com/SYSTRAN/faster-whisper), local on the Mac (CPU)
- Translation: Google Translate web endpoint (unofficial, falls back to MyMemory). Needs internet
- Speech output: natural Microsoft neural voices via the unofficial [edge-tts](https://github.com/rany2/edge-tts) library (Thai: Niwat / Premwadee, English: Ava). The translated text is sent to Microsoft for this. Falls back to macOS voices (`say`) when offline or if that service stops working (`--tts say` forces it)
- Latency: roughly 3–4 s after the end of each sentence
- Quiet speech: Silero voice activity detection plus input gain, so soft voices are picked up too
- Only English and Thai: other languages (and noise) are ignored. An Auto / EN / TH picker locks the language if needed
- Log for troubleshooting: `~/Library/Logs/Dolmetscher/engine.log`

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
| Translator, clear | clear the conversation |
| Translator, help | list the commands |
| Translator. *(pause)* … | answers "Yes?" and takes the next sentence as a command |

Commands only control the app. General questions (weather, facts) are not supported, since that would need an LLM.

## Mac app

Requirements: macOS 14+, Xcode Command Line Tools, `brew install ffmpeg`, Python 3.

```bash
./build.sh --install
```

This creates a Python environment with faster-whisper (once), downloads the `small` model and installs `~/Applications/Dolmetscher.app`. Use an existing Python instead: `DOLMETSCHER_PYTHON=/path/to/python ./build.sh --install`.

Open the app, press **Start** (or the space bar) and allow microphone access.

If the Thai voice is missing: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices → Thai (Kanya).

## Terminal only

```bash
pip install faster-whisper
python3 dolmetscher.py            # --model base|small|medium  --polite krub|ka  --mic 0
```

## Browser version

Live: https://pschmetzer.github.io/en-th-dolmetscher/ — `index.html` is a simple variant with the Web Speech API (Chrome, buttons for EN/TH). Serve it with `python3 -m http.server` and open it in Chrome.

## Notes

- Laptop speakers: the microphone is muted while the translation is playing, so the engine doesn't translate its own voice.
- `--polite krub|ka` picks the Thai politeness particle (ครับ/ค่ะ) and the pronoun (ผม/ฉัน).

MIT License
