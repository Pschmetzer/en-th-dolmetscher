# Changelog

User-facing changes, newest first. Numbers in brackets are the pull requests on GitHub (`#35` = pull request 35). Version numbers come from `pyproject.toml`.

## Unreleased (after 1.2, November 2026)

Pull requests #16–#47. Not yet published as a release.

### Highlights

- **19 languages instead of two** on Mac and iPhone: pick “my language” and “partner's language”, e.g. German ⇄ Thai or Spanish ⇄ Japanese. English ⇄ Thai stays the default (#29, #32).
- **The Mac app installs itself** on a Mac without Homebrew or Python: a setup screen downloads everything it needs on first start (#35).
- **Whisper on the iPhone** as an optional, more robust speech recognition (#27, #30).
- **iPhone app in 10 interface languages** and App Store texts prepared (#33).
- **Conversation mode on the iPhone** (#38, #46): split screen, the top half turned around for the person opposite, each half in its own language; answer cards (yes, no, don't know, number) work without a network.
- **Widgets, Live Activity and iPad** (#42): quick-phrase widget, a “Start interpreter” control, the current sentence on the lock screen; on the iPad the app shows the conversation and a tools column side by side.
- **Learning mode** on iPhone and in the browser (#45, #46): saved and translated sentences become flashcards, stored only on your device.
- **Nine new phrase packs with cultural notes** (#40): pharmacy, police, bank, spa, temple, flat rental, scooter, transport and lost child; safety-critical sentences come first and are marked on every platform (#45, #46, #47).
- **Browser version in 19 languages and installable as an app** (#37), with an offline phrasebook.

### Web (round 15)

- **Faster install and start:** the service worker now precaches only the app shell; the phrase packs are downloaded in the background after start (4 at a time, only online and not in data-saver mode). “Ready offline” still appears once all packs are stored; packs from the previous version are carried over, so there is no offline gap on updates.
- **Browser storage full** is reported instead of failing silently; stored translations drop the oldest quarter and retry. Glossary and “translate all” load packs at most 6 at a time. Size budget test added (index.html ≤ 232 KB).

### Engine (speech recognition, translation, voice – used by the Mac app)

- **Language pairs** (#29): any pair of English, Thai, German, Spanish, French, Italian, Portuguese, Dutch, Russian, Chinese, Japanese, Korean, Vietnamese, Indonesian, Arabic, Hindi, Turkish, Polish and Ukrainian. Thai-specific extras (ครับ/ค่ะ, 555 laughter, Thai numbers, the Thai model) are only active when Thai is in the pair; voice commands only when English is.
- **Numbers are checked more carefully** (#22, #25, #26, #34): prices, room and phone numbers no longer lose digits to “555 = haha”; times like 2:30 PM = 14:30 and number words in Thai and English (“three hundred fifty” = สามร้อยห้าสิบ = 350) are understood. If the numbers in a translation still differ, the engine asks a second translation service and keeps the version whose numbers match.
- **Better translations** (#22, #34): your glossary now also works with Google, not only with Claude; questions keep the right Thai particle (คะ); if Claude's answer looks wrong, Google translates the sentence instead; Thai times are passed to Claude correctly; optional **monthly cost limit** for Claude (`--llm-budget`).
- **Voice output more reliable** (#18): falls back cleanly if the fast voice connection fails, stops immediately when you press Stop, never starts a sentence over from the beginning, deletes its temporary audio files on exit and puts less load on the Mac. A self-test at start checks the voice library (#34).
- **More robust pipeline** (#20, #31): the app sees the recognised text before the translation is ready; corrections no longer lose the old bubble if translating fails; hung microphones are detected instead of freezing; every error has a stable code the app can translate; output to the app can no longer block the engine.
- **Voice commands misfire less** (#31): “this time” or “type” no longer switch off Thai, “unmute” and “unpause” mean resume, short words are no longer guessed (“see” ≠ “sleep”).
- **Microphone** (#20, #34): can be chosen by name and switched while running, without a restart.
- **Voice profiles** (#19, #26, #34): deleting a profile removes all its backups too; new “delete all voice data”; own words help recognition in more situations; politeness form (ครับ/ค่ะ) per profile; loading errors are reported with a clear code.
- **“Speak again” with the natural voice** (#26) instead of the system voice.
- **Conversation history** (#28, #31): deleting really overwrites the deleted text in the database; invalid retention values are rejected; a full disk no longer loses the current sentence.
- **Audio without ffmpeg** (#35): microphone, playback and file input run through PyAV, which is installed with the other packages.
- **Back-translation** (#39, optional, off by default): the translation is translated back with Google and shown small underneath, so you can see whether the meaning survived.
- **“Slow and clear” mode** (#39): slower voice, simpler words with Claude, nothing skipped.
- **The glossary learns from corrections** (#39): names you fix by hand are added to the glossary (can be switched off).
- **Offline translation with Apple** (#43, #47): without a network, the Mac can translate on the device with Apple's translation (macOS 26.4 or newer, language packs installed). The helper now ships inside the app.
- **Choose the speaker** (#43): every sound, including the system voice and signal tones, can go to a chosen output device, switchable while running.
- **Private mode** (#47, `--private`): no warm-up requests at start, and the text never ends up in a web address.
- **More robust** (#39, #43, #47): the microphone keeps trying to reconnect instead of giving up; the Claude service's “try again later” times are respected; a speech-detection self-test at start; the log file is rotated; Thai laughter “555” is read as laughter; more single digits and Thai number words are compared; several smaller fixes from the idea list.
- **Engine, round 7** (error fixes and small improvements): voice commands no longer do the opposite (“too loud” = quieter, “not so fast” = slower, “don't translate” = pause, “mute off” = resume, “play” = resume); Claude's timeout now depends on the model and a long pause (“credit balance”) is no longer cut short by a later timeout or kept after you replace the key; quick phrases, “speak again” and repeat are never skipped during catch-up; a stale connection after sleep or a Wi-Fi change no longer costs a sentence; captive Wi-Fi portals are reported (`captive_portal`); date and number checks understand Buddhist-era years, month names, “1½ hours”, “a hundred”; quotes are no longer stripped from the middle of a translation; Thai text is no longer split inside a word; laughter and filler words in more languages; new control field `clear` (wipes conversation context, texts in memory and queued speech), `llm_retry`, `control_invalid`/`overrun`/`profiles_skipped` events; history: new session after a pause, CSV safe in Excel, SRT with blank lines, `--history-sessions`; presets no longer overwrite your own choices; voice profiles can be recorded with the chosen microphone and noise suppression (`--profile-stdin` `mic`/`denoise`).

### Web (round 19)

- **Phrasebook search** tolerates one typo per word (from four letters, Thai and English) and a new filter “Only important ⚠” shows just the critical sentences.

### Web (round 18)

- **Learning mode** (browser): daily goal with a progress bar (a calm line once it is reached, no streak pressure), listening drill (the sentence is read aloud, you type it; the answer ignores case and punctuation), “hard cards only” review (answered, still in box 1 or 2), space bar flips the card (1–4 grade), reduced motion respected, texts in German, English and Thai.

### Web (round 17)

- **Sharing and offline** (browser): text shared to the app stays in the input box and is translated as soon as the network is back; the full-screen view can share the translation as text (clipboard fallback); new “Satzbuch” app shortcut. Share target, offline banner and install hint were already in place.

### Web (round 16)

- **Own phrases and favourites** (browser): the “My cards” box now edits cards, adds an optional translation (via the existing translation chain, correctable by hand) and a group label with a group filter, keeps the 30-card limit, and reorders cards and starred favourites with up/down buttons (keyboard and screen-reader friendly, position announced). Cards export and import as JSON (validated: size limit, control characters removed, unknown fields and `__proto__` dropped, duplicates skipped). A full browser storage is reported instead of silently losing the change. Texts in German, English and Thai; `tests/test_runde16_web_favorites.py`.

### Mac app (round 19)

- **Diagnosis and help**: new "Self-test …" in the Help menu checks microphone, speaker, network, speech models and the Python engine, shows one result line per check with a concrete suggestion and links to the troubleshooting page (`docs/FEHLERHILFE.md`). "Copy diagnostic report" now includes the self-test result and the last error and is redacted (home path, user name, API keys and tokens) without conversation text. Logic in `DiagnosticsLogic.swift` (tested with `swiftc`, including redaction), texts in German, English and Thai; `tests/test_runde19_mac_diagnose.py`.

### Mac app (round 18)

- **Glossary editor** (Settings, "Open glossary editor"): search, per-entry warnings for duplicates, conflicting translations, over-long entries and the 200-entry limit; add, edit and delete with "Undo"; CSV import and export (UTF-8, at most 1000 rows and 256 KB, quoted fields, `,` or `;`; cells starting with `= + - @` are skipped on import and prefixed with `'` on export so spreadsheets never run them); a sample sentence shows which entries apply and what they become. Logic in `GlossaryLogic.swift` (tested with `swiftc`, limits checked against the engine), texts in German, English and Thai, VoiceOver labels for every control; `tests/test_runde18_mac_glossary.py`.

### Mac app (round 17)

- **Menu bar and Dock**: the menu bar icon now has its own shape for listening, speaking, paused, offline, loading and error, each with a spoken text alternative (logic in `MenuBarLogic.swift`, tested with `swiftc`). The menu shows the engine status, start/stop, swap language pair and copy last translation. New command “Swap language pair” (⌥⌘K) with VoiceOver names; the Dock menu gained copy last translation and swap pair.

### Mac app (round 16)

- **Partner view**: presentation mode (P, hides the bar, Esc brings it back); automatic font size by sentence length (logic in `PartnerLogic.swift`, tested with swiftc); high-contrast theme (white on black, no language colours); numbers (prices, times, Thai digits) shown bold, underlined and yellow; the language is also named in text, colour is only an addition; "Again, please" and "Slower, please" on the keys R and S; the window remembers its size, screen and full-screen state; VoiceOver labels for the new controls.

### Mac app (round 15)

- **Settings backup**: export all settings, the quick phrases and the glossary to a JSON file and import them again. The file is versioned, every field is validated (type, range, allowed values, languages; unknown or sensitive entries are skipped and reported) and a preview lists exactly what would change before anything is applied. It never contains the API key, conversations, history, text log, microphone, output device or voice profiles.
- **Recently changed** list in the settings (timestamps only, never values) and a help tooltip for every setting. The rules live in `SettingsLogic.swift` (Foundation only) and are tested with swiftc.

### Mac app (round 14)

- **History window** (View menu and menu bar): saved conversations grouped by day and session with a preview; search with hit count; filters for language, direction (I speak / other person speaks), number warning and weak translation; rename and favorite a session; remove one session from the list with a confirmation and undo (the engine only offers purge/clear, so the data stays on disk until "Delete history"); reopen a session read-only in the main window; keyboard control (arrows, Return, Delete, Cmd-F, Cmd-D) and VoiceOver labels. Built only on `--history-export json`; the grouping and filter logic is in `HistoryLogic.swift`, tested with swiftc.

### Mac app (round 12)

- **Accessibility audit**: headings for VoiceOver on sheets and banners, setup steps announce done / pending / in progress instead of only a symbol, decorative icons hidden; a static test checks icon-only buttons, images and animations (reduce motion).

### Mac app

- **Self-contained app with setup screen** (#35): ships its own `uv`, downloads Python 3.12, the packages and the speech models on first start, with size check, progress, cancel and retry; sets itself up again after updates; “set up again” in the settings. Apple Silicon only.
- **Language pair in the settings** (#29): two pickers, per-language translate switches, voices and lock.
- **Uses everything the engine reports** (#24, #26): localized error messages, “only partly read aloud” with a “Speak again” button, “Translate anyway” for unsure sentences, “Try again” for failed translations (automatic when the network is back), a hint when a model could not be loaded, and a watchdog that notices a hanging engine.
- **No lost lines, no interrupted conversations** (#23): the last messages before an engine crash are kept; changing a setting during a conversation waits for a quiet moment before restarting the engine; the Mac stays awake while listening; global push-to-talk.
- **API key in the Keychain** (#39): the Claude key is now stored in the macOS Keychain. An old key file is kept as `anthropic_key.migrated` instead of being deleted.
- **New settings** (#39, #43, #47): back-translation, slow mode, output device, “Offline translation (Apple) as fallback”, private mode, “Reset learning”; menu shortcuts ⌘↩ start/stop, ⌘P pause, ⌘R repeat last.
- **Phrase packs in the app** (#47): each pack shows its cultural note (ⓘ), important sentences are red, come first and are announced as “Important” by VoiceOver.
- **VoiceOver and messages** (#39, #43, #47): states and banners are announced in the right language; “done” for delete and export only when the engine confirms; a menu with log and restart when loading takes long; a hint when a shortcut could not be registered.
- **Usability** (#34): header bar with direction, read-aloud switch and a field to type a sentence; large “Paused / Microphone off” banner in the partner view; keyboard navigation for bubbles; text zoom; auto-scroll that respects where you scrolled; a notification with “Restart” if the engine crashes while the window is closed; a “Ready?” checklist in the welcome dialog; the model picker shows how much would still be downloaded.

### iPhone app

- **Robustness and new screens** (#17): adaptive pause detection, clean handling of calls, Siri and headphone changes, an emergency screen (Thai emergency numbers 1669/1155/191/199, bilingual emergency card), a Baht calculator, adjustable history retention and a privacy manifest.
- **Whisper recognition, optional** (#27, #30): switch on in the settings and download a model once; Apple's recognition stays the default and takes over if no model is installed. Models are not included in iCloud backups.
- **19 languages** (#32): language pair like on the Mac; only languages the device can actually recognize are offered, with markers for missing downloads and online-only pairs; Thai-only and English-only features are shown only when they apply. Old history and favourites keep working.
- **Interface in 10 languages** (#33): de, en, th plus es, fr, ja, ko, zh-Hans, vi, id (machine-translated, not yet reviewed), including the permission texts; App Store texts for 10 store languages in `ios/AppStore/`.
- **Online translation is off by default** (#32): without the switch “Online translator as fallback”, everything stays on the iPhone.
- **Conversation mode** (#38, #46): split screen with the partner's half turned around, live text on both sides, big “Your turn” buttons; hold your own half to talk.
- **Answer cards** (#38): yes, no, don't know and a number pad for the person opposite, in all 19 languages, spoken right away and without network.
- **Translation help** (#38): back-translation under each translation (on the device, ⚠️ when the meaning drifted) and transliteration for Thai, Japanese, Korean and Chinese; both can be switched off.
- **Emergency** (#38, #42): emergency card with blood type, insurance and embassy; allergy card in 10 languages; a “Help now” screen with a large Thai help sentence, hotel address, your coordinates and direct dialling.
- **Privacy** (#38, #46): privacy overview in the settings; history can be locked with Face ID; “Delete all data” removes history, favourites, emergency card, destinations, learning progress and settings.
- **Widgets and Live Activity** (#42): quick-phrase widget (small, medium, large), a “Start interpreter” control for Control Center, lock screen and Action button, and a Live Activity with the last sentence and a stop button (can be switched off).
- **iPad** (#42): runs on iPad in all orientations; on wide screens the conversation and a tools column (phrasebook, destinations, emergency, Baht) sit side by side.
- **Phrasebook** (#42, #46): sentences moved to a shared file with German glosses and new categories; the 16 scenario packs from the Mac are included, with cultural notes and important sentences first. “Phrasebook first”: if what you typed or said matches a checked sentence, that version is used. Important sentences only match exactly, a “not” is never matched loosely.
- **Learning mode** (#46): favourites and translated sentences become flashcards (5 boxes: now, 1, 3, 7, 14 days), stored only on the iPhone.
- **Travel helpers** (#42, #46): a “Ready to travel?” checklist (microphone, recognisers, language packs, voices); destinations for taxi and tuk-tuk with a large “please take me here” display and Apple Maps link; scan a business card or sign to fill in a destination; a dish lexicon under photo text; prices also shown in your home currency.
- **Other** (#38, #42, #46): push-to-talk, Siri shortcuts “Say in partner language”, “Open emergency card” and “Show last translation”, a warning 30 s before auto-stop, less work when the phone gets hot, an info section with version, licences and source code.

### Web (browser version)

- **No endless restarts** (#19): permission and language errors stop with a clear message; other errors retry with increasing pauses.
- **19 languages** (#37): same language pair choice as on Mac and iPhone, plus a choice of English accent for recognition.
- **Installable app (PWA)** (#37): add it to the home screen; the page and the phrasebook also open without a network (translation still needs one).
- **Phrasebook and show cards** (#37, #45): tap a sentence to show it full screen and read it aloud; yes/no cards in the partner's language; each pack shows its cultural note and important sentences first, marked “⚠ Wichtig”.
- **Learning mode** (#45): star sentences to make flashcards (Leitner, 5 boxes), stored only in this browser; optional automatic adding of recent sentences (off by default).
- **More control** (#37, #45): voice and speed choice with preview, volume slider, voice commands “louder”, “quieter”, “clear” and “help”, a visible stop button, larger or smaller text in the big view, headphone mode (you can talk over the voice), copy or save the conversation, share a sentence as a link.
- **Fixes** (#37): the last sentence is no longer lost when you release push-to-talk; the partner view shows only the partner's language; uncertain sentences are marked; the fallback service is labelled.
- **Privacy and accessibility** (#28): asks for consent before the microphone starts; “Translator pause” really stops recognition (no more audio to Google); screen readers announce finished translations; bigger tap targets on phones; MyMemory answers no longer show HTML codes.

### Phrases and presets

- **Emergency phrases** (#28) in the doctor, restaurant, taxi and travel presets: emergency number, allergies (peanuts, shellfish), chest pain, pregnancy, lost passport, stolen wallet and more.
- **Nine new packs** (#40): pharmacy, police, bank, spa, temple, flat rental, scooter, transport and lost child (show-me sentences with blanks).
- **Cultural notes and important sentences** (#40): packs can carry a short note (e.g. temple etiquette) and mark safety-critical sentences, which always come first. Existing packs were reworked (more natural Thai, more symptoms, vegan/halal/MSG in the restaurant).
- The Thai sentences are machine-written and **not yet checked by native speakers**; see [docs/PRESETS.md](docs/PRESETS.md).

### Infrastructure and documentation

- **iPhone logic tests** (round 16): `Round16Tests.swift` covers edge cases of CSV export, phrasebook search, speech rate, history retention and undo, privacy switches, learning plan (Leitner), language-pair switching, the quick-phrase widget and number and back-translation checks; `tests/test_runde16_ios_tests.py` checks the file statically.
- **Test suite upkeep** (round 17): tests that need faster-whisper or PyAV skip with a clear reason when the package is missing, the LLM cache test no longer needs the `anthropic` SDK, and the one-off `git diff origin/main` test is gone; the iPhone onboarding uses `StatusColor` instead of raw system colours; `tools/check_all.sh` also runs script syntax, shellcheck and the phrase-pack checks like CI.
- **Review tools** (round 16): `tools/review_export.py`, `review_import.py` and `review_status.py` turn the pack phrases into a review sheet (CSV or Markdown) for native speakers, import corrections with a dry-run diff and keep `reviewed` per pack honest; `tests/test_runde16_review_tools.py`.
- **Thai documentation** (round 13): `docs/th/` with README, quick start, FAQ and short privacy notes for Thai users, flagged as machine-translated and not checked by native speakers; `tests/test_runde13_docs_th.py` checks links, paths and the pack and language counts.
- **Reproducible installs** (#21): speech models pinned to fixed versions; all Python packages locked with checksums; security audit includes indirect packages.
- **Code quality** (#16, #21, #25, #28): pytest and ruff updated; ruff checks all modules and blocks merges; CI jobs have time limits; the wake-word tests run against the real code.
- **Tests and CI** (#41, #44): time-dependent tests made stable, a time limit per test, Python tests on Linux (faster), coverage with a lower limit, a shared test corpus in six language pairs, and a benchmark that only runs on demand.
- **CI and developer tools** (round 12): superseded runs of the `Changelog` and CodeQL workflows are cancelled, pip cache for the lint and audit jobs, a failure summary on the job page, `make test-mac`/`web-test`/`check`, and `tools/check_all.sh` (ruff + pytest like CI, no pre-commit needed); `tests/test_runde12_ci.py` checks SHA pins, time limits and permissions.
- **Documentation**: phrase pack format and contribution guide `docs/PRESETS.md` (#40); license overview `docs/LIZENZEN.md` (#21), privacy overview per platform `docs/DATENSCHUTZ.md` (#28 and later), protocol checked against the code by tests (#20), iPhone guide `ios/README.md` and this changelog.
- **Documentation matched to the code** (round 11): shortcuts (Mac menus and iPhone), architecture file list, privacy notes (clipboard, screen recording, echo guard, Live Activity) and the pack and language counts; `tests/test_runde11_docs_abgleich.py` checks the numbers against the files.

### Round 8: engine, iPhone, web, phrase packs

- **New:** eight phrase packs (bus-train, beach, hiking, street-food, massage, nightlife, festival, laundry-repair), 49 in total; safety-critical sentences come first. Thai machine-translated.

**Engine**
- **New:** text echo guard: a recognised sentence that almost exactly repeats what was just spoken is dropped (`echo_guard`, on by default).
- **New:** currency symbols (฿ $ € £) and °C/°F are spoken as words in en, th, de, es and fr; the display stays unchanged.
- **Fixed:** number comparison understands “1 500”, “5 hundred”, “3 ร้อย”, lakh and crore; Thai laughter “555” and phone numbers are left alone.
- **Fixed:** sentence splitting no longer cuts “9 a.m. to 5 p.m.”, “z. B.”, “Prof. Brown”; history short search ignores case for accents; dropped HTTP responses and DNS errors trigger the backoff.
- **Changed:** glossary files accept `#` comments (engine only), ignore duplicates, a BOM and entries over 120 characters.

**Engine (round 11)**
- **New:** politeness level (`formality`: informal / neutral / polite) and speaker sex (`speaker_sex`) as optional controls; the prompt asks for du/Sie, tu/vous, tú/usted, plain/desu-masu/keigo (ja), 반말/해요체/합쇼체 (ko) or casual/everyday/courteous Thai, and Thai output gets its ครับ/ค่ะ/คะ particles matched to the speaker afterwards. Default `auto` behaves as before.

**Engine (round 9)**
- **Fixed:** a pack id with a trailing newline passed validation; `None` in a vocabulary list became the word “None”; the same phone number written with dashes or spaces was reported as a number mismatch.
- **New:** the number check understands fractions (“1/2”, “2 and a half”, ครึ่ง), currencies (a price in baht against dollars is a mismatch) and times of day (“3 in the afternoon” = บ่ายสาม).
- **New:** the number check treats °F/°C, miles/km and lb/kg as equal after rounding (“86 °F” = “30 องศาเซลเซียส”), real differences are still reported.

**Engine (round 11)**
- **Fixed:** very long sentences no longer fail at Google (request is split); Google or MyMemory returning the sentence unchanged or in the wrong language is no longer read aloud (next provider tried); an empty, cut-off or refused Claude answer no longer pauses Claude for a minute.

**Engine (round 12)**
- **Fixed:** log lines and error events no longer carry the account name (home folder paths are masked as `~` or `/Users/<user>`); log entries for errors show only the exception type, not its message, which could quote spoken text; deleting a voice profile also removes leftover `.tmp` files from an interrupted write; a late cache write can no longer re-create `translation_cache.json` after the disk cache was switched off.

**Engine (round 14)**
- **Fixed:** the number check no longer flags the same date written differently (25/12/2026, 25.12.2026, 2026-12-25, 12/25/2026, 25 Dec 2026, 25 ธ.ค. 69, Buddhist year 2569 = 2026); colloquial Thai amounts (พันห้า = 1,500, สามล้านห้า = 3,500,000), "three oh five" = 305 and English ordinals (twenty-fifth, third floor) are read as numbers
- **New:** a wrong weekday or month (Monday vs วันอังคาร, March vs เมษายน) is reported; one side naming more days or months than the other is not

**Engine (round 17)**
- **Fixed:** a glossary name no longer rewrites e-mail addresses and URLs (`pat@example.com` stayed intact only by luck); a sentence that already contains “[1]” is sent without glossary placeholders instead of getting them mixed up; the Thai particle fit leaves words like คะน้า, คะนอง, คับขัน, คับใจ and คับที่ alone

**Engine (round 16)**
- **Fixed:** more silence hallucinations are dropped (“Thank you so much for watching”, “Thanks for watching, see you next time”, Thai greetings and “thanks for watching” variants; a segment set Whisper itself rates as no speech); a sign-off phrase from the second-language check can no longer replace the real sentence; the hotword list treats “Pat”, “pat”, “PAT.” as one word and one over-long entry no longer cuts off the rest

**Engine (round 15)**
- **Fixed:** speech output no longer asks the voice for text without anything to say (empty, only punctuation or emoji); emoji are not read out; very long sentences without punctuation are split into chunks of at most 300 characters; Thai digits (๑๒๓) and the abbreviations กทม. and ฯลฯ are spoken correctly; a preset's tempo is limited to -50..+50 % like the speed setting

**Engine (round 18)**
- **Fixed:** a long sentence is split into pieces for Google and the pieces are now requested in parallel (up to 3, order kept, 8 s in total) instead of one after another; the persistent translation cache is written in a background thread, so the sentence no longer waits for the disk; an expired pre-opened voice connection is closed instead of being left open.

**iPhone app**
- **New:** retries sentences that failed to translate when the network returns; error bubbles have buttons (open Settings for a denied microphone); copied text is removed from the clipboard after 2 minutes; optional hiding of the conversation during screen recording; “Recent” category in the phrasebook; share favourites; learning mode with daily count, streak, “Practise all cards” and progress reset; iPad keyboard shortcuts; VoiceOver Magic Tap and copy action.
- **Fixed:** the study log keeps only recent days; Dynamic Type scales icon widths.

**iPhone app (round 10)**
- **New:** a five-step quick guide in the help (start, conversation mode, repeat slowly, privacy, keyboard and VoiceOver); iPad tools column between 320 and 440 pt and ⌘/ opens the help; haptics when repeating slowly and in conversation mode (share, turn).

**iPhone app (round 11)**
- **New:** quick-phrases widget on the Lock Screen (rectangular, inline, and a circular “Start” button) next to small, medium and large; the phrases can come from a phrasebook category that rotates hourly; the language pair is shown; an error note when the phrasebook cannot be read.
- **Changed:** the widget stays free of conversation content (no favourites or history, no App Group); larger text shows fewer, taller phrases, VoiceOver reads each phrase with a hint; new texts in all 10 languages (de/en/th by hand, the rest machine-translated).

**iPhone app (round 14)**
- **New:** welcome flow on first start (language pair, why the microphone and speech recognition are needed before the system dialog appears, offline language packs with an approximate size, a test sentence); “Later” at any time; a band in the conversation with a Settings button when the microphone or speech recognition is denied or restricted (for example by Screen Time); the flow can be shown again from the help. Texts in all 10 languages (de/en/th by hand, the rest machine-translated); logic in `Onboarding.swift` with unit tests, `tests/test_runde14_ios.py`.
- **Fixed:** the welcome flow used raw system green and orange; it now uses the contrast-checked status colours.

**iPhone app (round 13)**
- **New:** accessibility audit of all views: VoiceOver announces start, stop, errors and failed translations; status colours (green, orange, red, blue) now reach 4.5:1 contrast in light and dark mode (computed in a test) and the filled mic and turn buttons keep readable white text; the active turn is marked by a border, not only by colour.
- **Fixed:** the number pad's close and delete buttons and the summary share button had no VoiceOver label; icon-only buttons are at least 44 × 44 pt; the phrasebook category scroll ignored “Reduce Motion”; progress indicators have names; decorative icons are hidden from VoiceOver; the currency code field and the quick-guide icons scale with Dynamic Type; “Help now” is a heading. New texts in all 10 languages (de/en/th by hand, the rest machine-translated).

**iPhone app (round 15)**
- **New:** conversation mode per half: font size, language switch without leaving, “Repeat” and “Slow” buttons, a scrollable full history with numbers highlighted, a state line with text and icon (ready, listening, translating, speaking) that does not rely on colour, side-by-side layout in landscape and on iPad; the turn button is locked and the device’s own output is not recognised again (echo check against the last spoken sentences); the screen stays on. Logic in `ConversationLogic.swift` with XCTest; new texts in all 10 languages (de/en/th by hand, the rest machine-translated).
**iPhone app (round 16)**
- **New:** “Offline language packs” in Settings: per language of the current pair, recognition, translation and voice show ready, missing, loading or unavailable, with a download button and an approximate size; a travel warning says what would be missing without a network; the phrasebook is stated to work offline; “Offline only” mode sends nothing at all (no online translation, exchange rate or Whisper download), is shown in the conversation and in the error text, which names the Settings screen to fix it. Texts in all 10 languages (de/en/th by hand, the rest machine-translated); logic in `OfflineReadiness.swift` with unit tests, `tests/test_runde16_ios.py`.
**iPhone app (round 17)**
- **New:** three more Siri/Shortcuts actions (read the last translation again, swap the language pair, say a phrasebook phrase found by keyword) and two Control Centre / Lock Screen controls (swap languages, read last translation); texts in all 10 languages, logic in `ShortcutLogic.swift` with tests. No new target or entitlement.

**iPhone app (round 18)**
- **New:** conversation history as its own list (menu, “History”): search in sentence and translation, filters by language pair, period (today, 7, 30 days) and favourites, grouping by day, multi-select to share or delete, swipe to delete or favourite, undo after deleting, an empty state with a next step, and a note on how long sentences are kept with a shortcut to the setting. Texts in all 10 languages (de/en/th by hand, the rest machine-translated); logic in `HistoryLogic.swift` with unit tests, `tests/test_runde18_ios_history.py`.

**Web**
- **New:** phrasebook search (`/`), favourites filter, copy button on every translation; history search, CSV export, share and clear with confirmation; learning progress bar, review schedule and arrow keys; “Delete all local data”; hints for a blocked microphone and for going offline; `?` opens help.
- **Fixed:** a shadowed `t()` raised an error on every finished translation and on critical phrases; high-contrast, forced-colors and reduced-motion styles; Safari text-size and zoom behaviour.

**Mac app**
- **New:** the toolbar folds into an overflow menu in narrow windows; model download progress in the empty state, status line and menu bar; error band with a suggested action and buttons per error code, plus a network band; history search shows the hit count and exports only the hits; bubbles can be shared, shown large and have extra VoiceOver actions; glossary quick entry (⌥⌘G); shortcuts ⇧⌘C, ⌥⌘L, ⌥⌘S, ⌘L, ⌘/ with an overview sheet; menu bar extra (direction, speak on/off, copy recent translations) and Dock menu; subtitle window with context menu (size, original, transparency) and remembered position; partner view pages through earlier translations; searchable settings; the main window remembers size and place.

**Web (round 9)**
- **New:** about 115 messages moved into the translation table (de/en/th) with a test that forbids new fixed German strings in the logic; the “no speech recognition” hint has three steps and buttons (“Type instead”, “To the phrasebook”); design Auto/Light/Dark and font size A−/A+; “Slowly” button (speed ×0.6) on cards and in the large view; previous/next topic and a “Recently used” shortcut; print styles for phrase cards.

**Phrase packs**
- **New:** nine packs with cultural notes: emergency, work, school, visa, sport, nomad, diving, market, kids (Thai machine-translated, not yet checked by a native speaker), plus eight more: car-rental, pets, baby, gym, wedding, photo, monk, hospital (41 in total).
- **New:** ten more packs: bus-train, beach, hiking, street-food, massage, nightlife, festival, laundry-repair, pharmacy-otc, mobile-sim (51 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: atm-bank-card, immigration-90day, motorbike-accident, lost-passport, tailor-custom, tuk-tuk-songthaew, thai-cooking-class, elephant-sanctuary, cinema-concert, dating-small-talk (61 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: ferry-boat, island-hopping, snorkel-boat-tour, muay-thai-gym, buddhist-ceremony, rice-field-village, night-market-bargain, hostel-dorm, laundry-deposit, vegan-vegetarian (71 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: visa-extension, tax-refund, car-wash-repair, bicycle-rental, yoga-retreat, kids-playground, bakery-cafe, convenience-store-7eleven, post-office-parcel, wifi-coworking-cafe (81 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: bus-train, beach, hiking, street-food, massage, nightlife, festival, laundry-repair, pharmacy-otc, mobile-sim (51 in total; Thai machine-translated, not yet checked by a native speaker).
- **Tools and docs:** `tools/export_phrasebook.py` (CSV, Markdown, printable cards, Anki), `tools/check_presets.py`, `tools/preset_stats.py`; FAQ, troubleshooting, quick start, shortcuts and voice commands in German and English; issue templates, `SECURITY.md`, store texts, six new test corpora.
- **Infrastructure:** shellcheck without severity limit for `build-support/*.sh`.

### Mac app (round 13)

- **New:** the export dialog has a format menu (Markdown, text, JSON, CSV, SRT, WebVTT), a period (whole conversation, last hour, today) and a privacy note that the file contains the conversation text; file names carry the date.
- **New:** WebVTT subtitles next to SRT; times come from the utterance length, with speaker, original and translation.
- **Safer:** Markdown escapes more characters, subtitle text cannot fake a time line, CSV cells starting with a formula character are defused; the formatting lives in `app/ExportFormats.swift` and is tested with swiftc (`tests/test_runde13_mac_export.py`).

### Mac app (round 11)

- **New:** the welcome dialog walks through first start: why the microphone is needed with an allow button (or a link to System Settings when blocked), language pair, recognition model with a recommendation for this Mac's chip and memory, optional Claude key, and a “say something” test; “Remind me later” hides it for a day. An interrupted setup continues on the next start, and every setup error names the next step (with “smaller model” when space is short).

### Round 7: Mac app, iPhone app, web, phrase packs, CI

**Mac app**
- **New:** translate audio files (menu or drag and drop); floating subtitle window for video calls; quick phrases on ⌘1–⌘9 (pack phrases ⌥⌘1–⌥⌘9), default quick phrases follow the language pair; deleted bubbles can be restored (banner or ⌥⌘Z), “Copied” feedback.
- **New:** partner view with “Once more, please” and “Slower, please”; HUD for global shortcuts; hide the windows from screen recording; microphone off when the window closes; confirmation before quitting mid-conversation; `dolmetscher://` URL scheme (start, stop, pause, say) with a first-use prompt; “What's new” after an update.
- **New:** offline translation shows the status of the active language pair and can load the language pack (macOS 15+); cost estimate per Claude model; warning at 80 % of the monthly limit.
- **Fixed:** voice profile recording uses the chosen microphone and noise suppression; “Delete all” also clears the engine's conversation context; latency display, bubble side after a pair change, VoiceOver text, “Reset all settings” (output device, budget, partner view), a language swap sends `langs` only once, the login switch re-reads the system state.
- **Setup:** never two `setup-env.sh` at once; checksum errors are reported as “download damaged”; models count as downloaded only when complete; the cache location follows `HF_HUB_CACHE`/`HF_HOME`/`XDG_CACHE_HOME`; update by difference; separate disk-space check; progress of the package install.
- **Security:** the Claude key is passed only to the engine process, the Keychain item is this-device-only, release builds ignore the Python override setting and delete plain-text key files.
- **Build:** `--release` requires notarisation (or `--no-notarize`), writes the notarisation log, a DMG and a dSYM, checks bundled libraries; `--bundle-wheels` for offline setup.
- **Other:** fixed texts name the chosen languages instead of English/Thai; auto-restart of a hung engine; hotkeys and network state renewed after sleep; device lists refresh on plug and unplug.

**iPhone app**
- **Fixed:** Apple translation has an 8 s time limit; online limit (429) pauses the provider for 5 minutes; “Now you/Now me” no longer changes the saved mode; stopping a model download no longer blocks the next start; interruptions do not reopen the microphone by themselves; Whisper queue is bounded and failures are shown; back-translation warning works for CJK and Thai; phrasebook favourites no longer collide.
- **Privacy:** learning cards follow the history setting and the Face ID lock and can be deleted; hourly retention; the lock reports when no device passcode is set.
- **New:** keyboard for the other person, decimal point on the number card, quick switch of recent language pairs, CSV export, optional online exchange rate, share location, microphone choice, echo cancellation (iOS 18.2+), voice preview, optional Spotlight favourites, tap-to-talk, transliteration also for ru/uk/ar/hi (marked ≈).
- **Accessibility:** VoiceOver reads source and translation in their language and announces prices; reduce motion; larger tap areas; Dynamic Type in the full-screen views; symbols for “Differentiate without colour”.
- **App Store:** review note for the background audio mode, keywords without duplicates, “Requires iOS 26”.

**Web**
- **New:** text input, number and price card with the Thai number word, allergy and emergency cards, “My cards” (address, “Please take me here”), dictionary, print/PDF per topic, card sequence, “Wrong? Report” (prefilled GitHub issue), emergency numbers as `tel:` links, deep links (`#preset=taxi&l=de`), app shortcuts and share target, interface in German, English and Thai (Thai machine-made), language variants pt/es/zh/ar/de/fr, optional local recognition (Chrome 139+).
- **Learning:** listen first, back-up/restore (JSON, Anki TSV), daily statistics, repeat aloud.
- **Fixed:** back button closes the full-screen card; screen stays on; shared links carry a “not checked” note; the service worker waits at most 4 s on a bad network, stores only complete answers and shows “Offline ready”; Thai text is no longer split inside a word; due cards by calendar day.
- **Phrase packs:** new Dentist, Airport, Answers, Laundry/Hairdresser/Tailor, Islands/Diving, Accessibility, Coworking and Places; allergens in the restaurant pack, emergency phrases in hotel, office, shopping and temple. **The new Thai sentences are machine-made and not checked by a native speaker; each pack says so in its note.** New files `presets-index.json`, `allergens.json`, `docs/presets.schema.json`.

**CI and repository**
- CodeQL, changelog check, quick phrase-pack job, Makefile, dev container, pre-commit; action versions pinned by commit; release job with time limit; `shellcheck` also for `build-support/`.
- Docs: web architecture, hosting, browser matrix, version states (`docs/VERSIONEN.md`).

**Web (round 14)**

- **Show mode:** a button (or `V`) in the big view turns the sentence into huge, high-contrast text on black; the screen stays on and a tap, Enter, Space or Esc closes it. The size follows the sentence length.
- **Share a favourite as a link:** starred phrasebook sentences and the big view get a link button (`S`); the link holds only the pack ID, the sentence number, the language and a checksum, never text or conversation. On opening, pack, number, language and checksum are checked; a mismatch shows a message instead of a wrong sentence. The Web Share dialog is used if present, otherwise the clipboard, otherwise a copy prompt.
- **Not added:** saving a sentence as an image. Thai in a canvas could not be checked here (line breaks inside words, stacked tone marks), so it was left out.

**Web (round 11)**
- **New:** manifest with `id`, `dir`, categories, `display_override`, launch handler; shortcuts and the share target (GET to the static page) are checked without a server. Icons stay “any”: a maskable icon needs a separate image with a safe zone.
- **New:** “✓ Installed as app” label when the page runs as an installed app, announced once after installing; install hint texts now in German, English and Thai.
- **Changed:** the update banner is read aloud, and an open app asks for updates when it comes back to the foreground.
- **Fixed (accessibility audit):** page now has a `main` landmark and section headings; tap targets (buttons, selects, summaries, tiles, speak buttons) are at least 44 px on every screen size, not only on phones.
- **Tests:** heading order, landmarks, focus order, live regions, colour contrast of all colour tokens (light and dark) and tap target sizes are checked statically.

**Web (round 13)**
- **New:** study mode: backup file (`.json`, v1) now carries cards and daily statistics; loading validates every field (known fields only, control characters removed, wrong files rejected, no script or prototype keys) and merges without duplicates. Nothing leaves the device.
- **New:** study deck per topic pack, a real daily limit for new cards, four ratings (1 again, 2 hard, 3 knew it, 4 easy) by Leitner box with a tested planning function (`leitnerGrade`), Thai romanization on the back when the pack provides it, statistics with streak and cards per box, and “reset study progress” with a confirmation (cards are kept). Texts in German, English and Thai.

## 1.2 and earlier

See the [commit history](https://github.com/Pschmetzer/en-th-dolmetscher/commits/main) up to pull request #15.
