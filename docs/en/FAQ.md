# FAQ

Thai version (machine-translated, not checked by native speakers): [ภาษาไทย](../th/FAQ.md).

German version: [FAQ.md](../FAQ.md). Start here: [QUICKSTART.md](QUICKSTART.md). Problems: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## General

**What is Dolmetscher?** A hands-free speech interpreter: you talk, it is translated into the other person's language and read aloud, and their answer comes back in yours. The default is English and Thai.

**Which languages are there?** 19: English, Thai, German, Spanish, French, Italian, Portuguese, Dutch, Russian, Chinese (Mandarin), Japanese, Korean, Vietnamese, Indonesian, Arabic, Hindi, Turkish, Polish and Ukrainian. Every pair works. The newer languages are not yet tested with real speakers.

**Which devices?** Mac (Apple Silicon, macOS 14 or newer), iPhone and iPad (iOS 26 or newer) and the browser (Web Lite, best in Chrome). The Mac app can do the most, for example automatic language detection, voice commands, voice profiles and Claude translation.

**Is there a download?** Not yet. You build the Mac and iPhone apps yourself ([QUICKSTART.md](QUICKSTART.md)); the browser version runs directly at <https://pschmetzer.github.io/en-th-dolmetscher/>.

**What does it cost?** The app is MIT licensed. Costs only arise if you turn on the optional Claude translation with your own Anthropic key: according to the README the default model `claude-haiku-5-5` costs about 8 US cents per hour of conversation, billed by Anthropic. The app shows the estimated cost and has a monthly limit (`--llm-budget`).

**Does it work offline?** In part. On the Mac recognition runs locally; translation needs the network unless you use Apple's offline translation (macOS 26.4 or newer, language packs installed). On the iPhone everything runs on the device once the language packs are there. In the browser translation needs the network; the page and the phrasebook also open offline.

## Using it

**Do I have to switch between languages?** Not on Mac and iPhone: the app detects which of the two languages is spoken. In the browser you choose (E or T). For pairs with the same script, such as English and German, the iPhone hides "Automatic"; there you choose the direction by tapping.

**How long does it take?** On the Mac a few seconds after the end of a sentence: roughly 3 to 5 seconds on the Apple GPU, clearly more on the CPU. The `small` model is faster.

**Which recognition model should I use?** `medium` is the default, `small` is faster, `best` (large-v3-turbo) copes better with accents and needs about 1.6 GB more. Thai uses its own model fine-tuned on Thai.

**Which shortcuts and voice commands are there?** See [SHORTCUTS.md](SHORTCUTS.md) and [VOICE-COMMANDS.md](VOICE-COMMANDS.md). Voice commands only work if English is one of the two languages.

**What are voice profiles?** Each person reads 8 short sentences once (about a minute). Then their name appears on the bubble, their language decides when detection is unsure, and own words such as names help recognition. The model is not retrained. Voice profiles exist on the Mac only, and recording is only possible in English or Thai.

**Can I prepare sentences for situations like doctor or taxi?** Yes: there are scenario packs (for example doctor, pharmacy, police, restaurant, taxi) with a cultural note and important sentences first, such as allergies. Format and contributing: [PRESETS.md](../PRESETS.md) (German).

**How do I keep a conversation?** The Mac only stores a history if you turn it on (default: off); export as Markdown, JSON, CSV, subtitles or Anki cards. The iPhone keeps 30 days by default. In the browser you copy the conversation or save it as a text file.

**How good is the Thai?** All Thai sentences and most interface texts were written with machine help and have not been checked by native speakers. Corrections are welcome ([PRESETS.md](../PRESETS.md)).

## Data

**What happens to my voice?** On the Mac audio never leaves the computer; only the recognised text is sent for translation. Short version: [PRIVACY-SHORT.md](PRIVACY-SHORT.md), full version: [DATENSCHUTZ.md](../DATENSCHUTZ.md) (German).

**Are there accounts or telemetry?** No accounts, no own telemetry and no own server.

## Development

**How do I build the app and contribute?** [CONTRIBUTING.md](../../CONTRIBUTING.md). Engine design: [ARCHITEKTUR.md](../ARCHITEKTUR.md); protocol between app and engine: [PROTOKOLL.md](../PROTOKOLL.md); licenses of models and services: [LIZENZEN.md](../LIZENZEN.md) (all German).

**What changes between versions?** [CHANGELOG.md](../../CHANGELOG.md). Current version per part: [VERSIONEN.md](../VERSIONEN.md).
