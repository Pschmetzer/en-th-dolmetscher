# Troubleshooting

Look at the log first: `~/Library/Logs/Dolmetscher/engine.log` (rotated at about 1 MB). Conversation text is only in it if the engine ran with `--log-text`; remove personal content before sharing a log. The first-time setup log is `~/Library/Application Support/Dolmetscher/setup.log`. German version: [FEHLERHILFE.md](../FEHLERHILFE.md).

## Microphone

**"No microphone access" (Mac)**
1. System Settings, Privacy & Security, Microphone: switch Dolmetscher on. Or reset in Terminal and allow again at the next start: `tccutil reset Microphone io.github.dolmetscher.en-th`.
2. If macOS asks again after every rebuild, that is the ad hoc signature. A stable signature keeps the permission: [CONTRIBUTING.md](../../CONTRIBUTING.md#stable-code-signing).

**"Microphone delivers no audio" or "Microphone gone"**
1. In the settings choose the right microphone and reload the microphone list ("Reload microphone list"). The choice takes effect immediately.
2. If a microphone is unplugged, the app retries by itself, several times at first, then every 10 seconds. Plug it back in.
3. Check that access is allowed (see above).

**Browser:** message "Microphone blocked": allow the microphone in the browser's site settings (Chrome: icon at the left of the address bar). Message "Speech recognition not allowed" in Safari or on the iPhone: switch on dictation (Settings, General, Keyboard, Dictation). Firefox has no speech recognition; use Chrome.

**iPhone:** allow microphone and speech recognition for the app in the iOS settings.

## Loading models takes long

- The first time, the app shows "Downloading model for the first time - this can take a few minutes". That happens once; afterwards recognition works without a network. "Loading speech model ..." at start is loading into memory.
- Sizes: environment about 0.4 GB, about 3.5 GB with the default models (`medium`, `small`, Thai). `best` (large-v3-turbo) needs about 1.6 GB more.
- On the build Mac, `./build.sh --install` downloads the models in advance. Skip that with `DOLMETSCHER_SKIP_MODELS=1`; the app then downloads them at first start. Other selection: `DOLMETSCHER_MODELS="medium small th best"`.
- Too slow in conversation? Use the `small` model (`--model small`). On the Apple GPU a sentence takes roughly 3 to 5 seconds, on the CPU clearly longer ([bench/README.md](../../bench/README.md)).
- Models are stored under `~/.cache/huggingface/hub/`.

## Network

- Recording and speech recognition work offline. Translation and the natural voices need the network.
- The app shows the network state. A failed translation has a "Try again" button and is retried automatically when the network is back.
- Offline, the Mac only translates with "Offline translation (Apple) as fallback": it needs macOS 26.4 or newer and the language packs (System Settings, General, Language & Region, Translation Languages). It is read aloud with the macOS voice then.
- Speech service unreachable: the app falls back to the local macOS voice. `--tts say` forces that.
- iPhone: without installed language packs, text is only translated with "Online translator as fallback" switched on (default: off). Otherwise the app points out the missing pack.
- Browser: translation needs the network; the page and the phrasebook also open without.

## API key (Claude translation)

Claude translation is optional and costs per sentence (billed by Anthropic). Without a key the app translates with Google.

1. Enter the key in the settings ("Anthropic API key"). The app stores it in the Keychain. If it shows "saved, but does not look like an Anthropic key", the key does not start with `sk-ant-`: copy it again.
2. "Saving failed": check Keychain access and save again. "Remove key" deletes it.
3. In the terminal the environment variable `ANTHROPIC_API_KEY` applies, otherwise the file `~/Library/Application Support/Dolmetscher/anthropic_key`.
4. With a key, Claude is on by default; switch it off in the same settings area. Without the `anthropic` package, on errors, implausible answers or a reached monthly limit (`--llm-budget`), Google translates automatically.

## Thai voice

- The natural Thai voice comes online from Microsoft (`edge-tts`). If it is unreachable or `--tts say` is used, the macOS voice speaks.
- Missing Thai system voice: System Settings, Accessibility, Spoken Content, System Voice, Manage Voices, download Thai (Kanya).
- Male or female voice with the politeness form (ครับ/ค่ะ): in the settings or by voice command "Translator, female voice" or "male voice". More: [VOICE-COMMANDS.md](VOICE-COMMANDS.md).
- Thai recognised unreliably? Create a voice profile for the speaker and use `--model best`.

## Echo (the app translates its own voice)

1. Use headphones. That is the safest fix.
2. On laptop speakers the engine discards audio that arrives while the translation plays (plus about 300 ms of reverb). With too many false recognitions lower the sensitivity (`--sensitivity low`) and turn on noise suppression (`--denoise`).
3. `--barge-in` (interrupt by talking) is for headphones only.
4. The output device (speaker or headphones) can be chosen in the settings, also while running.

## Setup fails (Mac, first start)

1. Check the internet: the setup screen says "No internet connection" if there is none.
2. Check free space: the setup shows the need (about 0.4 GB environment, about 3.5 GB with models) and reports "Not enough free space" or "The disk is full".
3. Press "Try again". "Show log" opens the setup log (`setup.log`, see above).
4. "A download is damaged (checksum mismatch)": try again later or update the app.
5. "This Mac is not supported": Dolmetscher needs Apple Silicon (M1 or later); Intel Macs do not work.
6. "This app copy is incomplete": reload the app or rebuild it (`./build.sh --install`).
7. After an app update with changed packages the app sets the environment up again by itself; manually use "Set up Python environment again ..." in the settings.

## Other cases

| Problem | Fix |
|---|---|
| Too many false recognitions (noise, TV, typing) | lower the sensitivity, turn on noise suppression |
| Translation sounds stiff | Claude translation (`--llm`) and tone `--style casual` |
| Own names are translated wrongly | add them to the glossary in the settings (`~/Library/Application Support/Dolmetscher/glossary.txt`) |
| Engine crashes while the window is closed | macOS shows a notification with "Restart" |
| App and engine do not match | bring both to the same version (see the protocol in [PROTOKOLL.md](../PROTOKOLL.md), German) |

Found nothing? An issue with the version number, the operating system and the relevant log excerpt helps.
