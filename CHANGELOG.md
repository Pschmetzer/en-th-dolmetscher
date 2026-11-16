# Changelog

User-facing changes, newest first. Numbers in brackets are the pull requests on GitHub (`#35` = pull request 35). Version numbers come from `pyproject.toml`.

## Unreleased (after 1.2, November 2026)

Pull requests #16–#35. Not yet published as a release.

### Highlights

- **19 languages instead of two** on Mac and iPhone: pick “my language” and “partner's language”, e.g. German ⇄ Thai or Spanish ⇄ Japanese. English ⇄ Thai stays the default (#29, #32).
- **The Mac app installs itself** on a Mac without Homebrew or Python: a setup screen downloads everything it needs on first start (#35).
- **Whisper on the iPhone** as an optional, more robust speech recognition (#27, #30).
- **iPhone app in 10 interface languages** and App Store texts prepared (#33).

### Engine (speech recognition, translation, voice – used by the Mac app)

- **Language pairs** (#29): any pair of English, Thai, German, Spanish, French, Italian, Portuguese, Dutch, Russian, Chinese, Japanese, Korean, Vietnamese, Indonesian, Arabic, Hindi, Turkish, Polish and Ukrainian. Thai-specific extras (ครับ/ค่ะ, 555 laughter, Thai numbers, the Thai model) are only active when Thai is in the pair; voice commands only when English is.
- **Numbers are checked more carefully** (#22, #25, #26, #34): prices, room and phone numbers no longer lose digits to “555 = haha”; times like 2:30 PM = 14:30 and number words in Thai and English (“three hundred fifty” = สามร้อยห้าสิบ = 350) are understood. If the numbers in a translation still differ, the engine asks a second translation service and keeps the version whose numbers match.
- **Better translations** (#22, #34): your glossary now also works with Google, not only with Claude; questions keep the right Thai particle (คะ); if Claude's answer looks wrong, Google translates the sentence instead; Thai times are passed to Claude correctly; optional **monthly cost limit** for Claude (`--llm-budget`).
- **Voice output more reliable** (#18): falls back cleanly if the fast voice connection fails, stops immediately when you press Stop, never starts a sentence over from the beginning, deletes its temporary audio files on exit and puts less load on the Mac. A self-test at start checks the voice library.
- **More robust pipeline** (#20, #31): the app sees the recognised text before the translation is ready; corrections no longer lose the old bubble if translating fails; hung microphones are detected instead of freezing; every error has a stable code the app can translate; output to the app can no longer block the engine.
- **Voice commands misfire less** (#31): “this time” or “type” no longer switch off Thai, “unmute” and “unpause” mean resume, short words are no longer guessed (“see” ≠ “sleep”).
- **Microphone** (#20, #34): can be chosen by name and switched while running, without a restart.
- **Voice profiles** (#19, #26, #34): deleting a profile removes all its backups too; new “delete all voice data”; own words help recognition in more situations; politeness form (ครับ/ค่ะ) per profile; loading errors are reported with a clear code.
- **“Speak again” with the natural voice** (#26) instead of the system voice.
- **Conversation history** (#28, #31): deleting really overwrites the deleted text in the database; invalid retention values are rejected; a full disk no longer loses the current sentence.
- **Audio without ffmpeg** (#35): microphone, playback and file input run through PyAV, which is installed with the other packages.

### Mac app

- **Self-contained app with setup screen** (#35): ships its own `uv`, downloads Python 3.12, the packages and the speech models on first start, with size check, progress, cancel and retry; sets itself up again after updates; “set up again” in the settings. Apple Silicon only.
- **Language pair in the settings** (#29): two pickers, per-language translate switches, voices and lock.
- **Uses everything the engine reports** (#24, #26): localized error messages, “only partly read aloud” with a “Speak again” button, “Translate anyway” for unsure sentences, “Try again” for failed translations (automatic when the network is back), a hint when a model could not be loaded, and a watchdog that notices a hanging engine.
- **No lost lines, no interrupted conversations** (#23): the last messages before an engine crash are kept; changing a setting during a conversation waits for a quiet moment before restarting the engine; the Mac stays awake while listening; global push-to-talk.
- **Usability** (#34): header bar with direction, read-aloud switch and a field to type a sentence; large “Paused / Microphone off” banner in the partner view; keyboard navigation for bubbles; text zoom; auto-scroll that respects where you scrolled; a notification with “Restart” if the engine crashes while the window is closed; a “Ready?” checklist in the welcome dialog; the model picker shows how much would still be downloaded.

### iPhone app

- **Robustness and new screens** (#17): adaptive pause detection, clean handling of calls, Siri and headphone changes, an emergency screen (Thai emergency numbers 1669/1155/191/199, bilingual emergency card), a Baht calculator, adjustable history retention and a privacy manifest.
- **Whisper recognition, optional** (#27, #30): switch on in the settings and download a model once; Apple's recognition stays the default and takes over if no model is installed. Models are not included in iCloud backups.
- **19 languages** (#32): language pair like on the Mac; only languages the device can actually recognize are offered, with markers for missing downloads and online-only pairs; Thai-only and English-only features are shown only when they apply. Old history and favourites keep working.
- **Interface in 10 languages** (#33): de, en, th plus es, fr, ja, ko, zh-Hans, vi, id (machine-translated, not yet reviewed), including the permission texts; App Store texts for 10 store languages in `ios/AppStore/`.
- **Online translation is off by default** (#32): without the switch “Online translator as fallback”, everything stays on the iPhone.

### Web (browser version)

- **No endless restarts** (#19): permission and language errors stop with a clear message; other errors retry with increasing pauses.
- **Privacy and accessibility** (#28): asks for consent before the microphone starts; “Translator pause” really stops recognition (no more audio to Google); screen readers announce finished translations; bigger tap targets on phones; MyMemory answers no longer show HTML codes.

### Phrases and presets

- **Emergency phrases** (#28) in the doctor, restaurant, taxi and travel presets: emergency number, allergies (peanuts, shellfish), chest pain, pregnancy, lost passport, stolen wallet and more.

### Infrastructure and documentation

- **Reproducible installs** (#21): speech models pinned to fixed versions; all Python packages locked with checksums; security audit includes indirect packages.
- **Code quality** (#16, #21, #25, #28): pytest and ruff updated; ruff checks all modules and blocks merges; CI jobs have time limits; the wake-word tests run against the real code.
- **Documentation**: license overview `docs/LIZENZEN.md` (#21), privacy overview per platform `docs/DATENSCHUTZ.md` (#28 and later), protocol checked against the code by tests (#20), iPhone guide `ios/README.md` and this changelog.

## 1.2 and earlier

See the [commit history](https://github.com/Pschmetzer/en-th-dolmetscher/commits/main) up to pull request #15.
