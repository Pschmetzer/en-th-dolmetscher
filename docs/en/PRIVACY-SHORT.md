# Privacy in brief

Thai version (machine-translated, not checked by native speakers): [ภาษาไทย](../th/PRIVACY-SHORT.md).

Facts only, taken from [DATENSCHUTZ.md](../DATENSCHUTZ.md) (German), which has the details and exceptions. German version: [DATENSCHUTZ-KURZ.md](../DATENSCHUTZ-KURZ.md).

**Always:** no accounts, no own telemetry, no own server. As with any network access, the services used see your IP address. The choice of language pair does not change where data goes.

| | Audio | Translation | Voice |
|---|---|---|---|
| **Mac** | stays on the Mac | online: Google (fallback MyMemory) or Claude; if numbers differ, additionally the other service; offline, Apple translation on the Mac if you want | online: Microsoft (fallback: local macOS voice) |
| **iPhone** | stays on the device (Apple or Whisper) | on the device; online (Google, fallback MyMemory) only if "Online translator as fallback" is on (default: off) | on the device |
| **Browser** | goes to the browser's speech recognition service (Chrome: Google) | online: Google (fallback MyMemory) | local in the browser |

## Mac: stays local

- Microphone audio is processed in memory only, neither stored nor sent.
- Speech recognition (Whisper) runs on the Mac; the models are downloaded once from Hugging Face.
- Voice profiles are biometric data. They live only under `~/Library/Application Support/Dolmetscher/profiles/`, readable only by you, are never sent and can be deleted in the app.
- The API key for Claude is kept in the Mac's Keychain.
- The log (`~/Library/Logs/Dolmetscher/engine.log`) contains conversation text only with `--log-text`.
- The conversation history is off by default. It contains text, no audio, sits unencrypted in `history.sqlite` (file permissions 0600) and ends up in backups. Delete with `--history-purge N` or `--history-clear`.

## Mac: leaves the computer

- **Recognised text** (not the audio) goes to Google Translate for translation, MyMemory as fallback, as POST in the request body. With Claude translation on, text plus the last sentences (default 8) and the glossary go to Anthropic.
- **Translated text** goes to Microsoft (edge-tts) to be read aloud. With `--tts say` or offline the local macOS voice speaks and nothing is sent.
- **Back-translation** (default: off) additionally sends the translated sentence to Google Translate.
- At start a short probe request ("hi") goes to Google or Microsoft, without conversation content. **Private mode** (`--private`, default: off) omits it and never falls back to a request with the text in the URL.
- Python, packages and models are downloaded from Astral, PyPI, Hugging Face and GitHub during setup; no conversation content is sent.
- There is no "never send" switch.

## iPhone

- Speech recognition on the device; the audio is neither sent nor stored.
- MyMemory (only as fallback, only with "Online translator as fallback" on) is queried with GET, so the text is in the URL.
- History local in `history.json`, 30 days by default (adjustable, 0 switches it off), lockable with Face ID. "Delete all data" is in the settings.
- Location is only used on the "Help now" screen and is neither stored nor sent by the app.
- The app only downloads the Whisper model when you tap "Download model" (from Hugging Face).

## Browser

- Before the first microphone start the page asks for consent once.
- Chrome sends the audio to Google's speech recognition, Safari to Apple. Pause and Stop end recognition completely.
- The recognised text goes to Google Translate, MyMemory as fallback, with GET, so it is in the URL.
- Only the browser stores anything (`localStorage`): settings, consent, flashcards and similar. The conversation list disappears when the page is closed.
- The page loads no third-party scripts.
