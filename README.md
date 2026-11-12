# Dolmetscher EN ⇄ TH

Hands-free speech interpreter for macOS: just talk. English is translated into Thai and Thai into English, and the translation is spoken aloud right away. The engine **detects the language by itself**, so there are no buttons to switch.

- Speech recognition: [faster-whisper](https://github.com/SYSTRAN/faster-whisper), local on the Mac (CPU)
- Translation: Google Translate web endpoint (unofficial, falls back to MyMemory). Needs internet
- Speech output: macOS `say` (Thai: Kanya, English: Samantha)
- Latency: roughly 3–4 s after the end of each sentence

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

`index.html` is a simple variant with the Web Speech API (Chrome, buttons for EN/TH). Serve it with `python3 -m http.server` and open it in Chrome.

## Notes

- Laptop speakers: the microphone is muted while the translation is playing, so the engine doesn't translate its own voice.
- `--polite krub|ka` picks the Thai politeness particle (ครับ/ค่ะ) and the pronoun (ผม/ฉัน).

MIT License
