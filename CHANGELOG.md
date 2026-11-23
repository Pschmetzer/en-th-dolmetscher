# Changelog

User-facing changes, newest first. Numbers in brackets are the pull requests on GitHub (`#35` = pull request 35). Version numbers come from `pyproject.toml`.

## Unreleased

## 1.4 (23 November 2026)

### Lao

- **Lao (`lo`) is the 20th language:** pick it as *My language* or *Partner's language* in the Mac app and the web version, with any other language as the pair. Lao script is recognised, spoken aloud with the Microsoft Lao voices (Keomany, Chanthavong) and translated through Google/MyMemory (Claude when a key is set). Lao is new and not yet checked by native speakers. macOS has no Lao voice, so without the neural voices the Thai voice is the only fallback. Speech recognition for Lao is weaker than for Thai.

### Thai language logic, round 28

Only the pure Thai modules (`thaiparticles`, `thaitime`, `numwords`, `textnorm`, `textsplit`, `correction_learning`, `satzbuch`), 20 improvements with about 100 tests (`tests/test_r28_thai_logic.py`):

- **Particles and politeness:** stretched tone marks (`ค่่่ะ`), spelling variants of ครับ (คร้าบ, คร๊าบ, ครัช) for speaker sex and particle fitting, `thai_politeness_level` (rude / formal / polite / casual, the roughest wins; Google and สวะ are no false hits), `normalize_ka` (question -> คะ, statement -> ค่ะ).
- **Time and date:** noon (`เที่ยง`, `เที่ยงครึ่ง`, not ไม่เที่ยง/เที่ยงธรรม), `14 นาฬิกา 30 นาที` and `10.30 น.` -> `HH:MM`, Thai dates with Buddhist years (`15 มกราคม 2569` -> `15 January 2026`, invalid days and non-leap 29 Feb stay), `พ.ศ.`/`ค.ศ.` years.
- **Numbers:** `thai_words_to_number` (inverse of `thai_number_words`, round-trip tested up to 10^12), Thai digits read aloud, `speak_digits_th` for phone and room numbers.
- **Normalising and splitting:** cache key ignores zero-width characters and Thai digits, `strip_thai_fillers` (เอ่อ, อืม; not อ่านหนังสือ), `split_thai_sentences` at particles without punctuation, Thai abbreviations (`น.`, `พ.ศ.`, `ม.ค.` ...) no longer end a sentence.
- **Names and phrase books:** `name_key` (Phuket = Puket, Chiang Mai = Chiang-Mai) now drives `name_alignment`, `thai_honorific_names` (name after คุณ/นาย/พี่ ...), more Thai particles skipped as vocabulary, `satzbuch.py check --thai` (zero-width characters, gender-bound "I", ค่ะ in questions, double ๆ; all packs are clean).

### Docs, CI and tooling, round 29

No app behaviour changes; for contributors and maintainers:

- **Docs map and onboarding:** new `docs/README.md` (all documents by audience, kept complete by a CI check), `docs/ENTWICKLUNG.md` (setup in 10 minutes, folder map, "I change X, so I check Y", typical tasks, pitfalls), `docs/CI.md` (every workflow, how to reproduce it locally, caches, adding a workflow) and `docs/RELEASE.md` (checklist, release notes, recovery). `.github/SUPPORT.md` points people to the right place; README and CONTRIBUTING link to the new pages.
- **Architecture, protocol, privacy:** sequence diagram of one utterance and an error-path table in `docs/ARCHITEKTUR.md`; example exchange and compatibility rules (add fields, never rename, stable codes, when to bump the version) in `docs/PROTOKOLL.md`; "at a glance" table in `docs/DATENSCHUTZ.md`. `docs/VERSIONEN.md` said 1.2 while `pyproject.toml` is 1.3: fixed.
- **Release workflow:** `release.yml` now checks tag, version and changelog first (fast, no macOS machine) and creates a **draft** GitHub release with the changelog section as notes and the ZIP plus SHA256. Nothing is published automatically; write access exists only in the build job. `.github/release.yml` sorts GitHub's generated notes.
- **CI:** new fast job "Doku, Changelog, Versionen, Workflow-Regeln"; ruff cache; `workflow_dispatch` for `ci.yml`; `PIP_DISABLE_PIP_VERSION_CHECK`, `PYTHONDONTWRITEBYTECODE`, `PYTHONUNBUFFERED`.
- **Dependabot:** 3-day cooldown for new versions, commit prefixes, labels, fixed weekday, and the Dev Container features as a fourth ecosystem.
- **New scripts in `tools/` (standard library only, with tests in `tests/test_r29_infra_docs.py`):** `changelog_extract.py` (section of a version for release notes), `changelog_lint.py` (form of the changelog), `check_workflows.py` (house rules: actions pinned to a commit with version comment, `timeout-minutes` on every job, top-level `permissions`, no `pull_request_target`, no auto-deploys), `check_docs_index.py` (every doc is linked from the map), `check_version_sync.py` (`pyproject.toml`, `VERSIONEN.md`, tag).
- **Local checks:** `tools/check_all.sh --docs` and `make docs-check` run the five fast checks in seconds; `make changelog-notes V=1.3` shows release notes; the full `check_all.sh` includes them.

### Security and privacy review, round 28

- Engine: the three remaining child-process calls (`say -v ?`, two ffmpeg device queries) no longer inherit `ANTHROPIC_API_KEY`; a test checks every `subprocess` call in `dolmetscher.py` for a filtered environment
- `docs/DATENSCHUTZ.md`: documents the optional password-encrypted history (`history-enc.sqlite`) and lists what the review checked

### iPhone app, round 35: tested logic building blocks

- 17 new small logic blocks in `ios/Dolmetscher/Round35.swift` (Foundation only): VoiceOver bubble label, confidence as a level instead of colour only, clamped text size, reduced motion, offline retry queue, error classes with retry rules and back-off, free-space check and size format for model downloads, session time (also spoken), quiet hours across midnight, UI language resolution, grapheme-safe truncation, share-text sanitising (control and bidi-override characters), history retention by age and count, debounce, version compare. Overview in `docs/IOS-LOGIK-R35.md`.
- Not wired into screens yet (no Mac in this round, so no UI code without a compiler); the unit tests in `Round35Tests.swift` plus extra tests for round 32 to 34 logic (travel table, hotel card, planner, card topics, Whisper partials, menu scan) are the gate in the CI job "iOS".

### Web, round 28

- **8 new phrase packs (251 in total):** lost property on transport, e-wallet and top-up, stings (scorpion, centipede, bees), bed bugs and pests, drinking water and ice, overnight temple stay, barber shop, condo visitors and parcels. Gender-neutral Thai without subject pronouns, `rom` filled, existing wordings reused for shared sentences (`check_presets.py --strict` and `preset_lint.py` clean). Categories, search terms, index and service-worker list are in sync (`sw.js` 17.4 KB, budget 17.5 KB).

### Mac app, round 28

New testable logic in `app/R28Logic.swift` (Foundation only, 16 types, about 45 Swift tests in `R28Tests.swift`); the views pick these up in later rounds, so this round changes no screen:

- **VoiceOver sentence per bubble** (speaker, original, translation, time; empty parts skipped).
- **Settings search:** all words must match, ignoring case and accents.
- **Shortcut guard:** custom global shortcuts are checked against keys macOS uses (⌘Q, ⌘Space, screenshots ...), regardless of modifier order; a global shortcut without ⌘/⌃/⌥ is unsafe.
- **Session clock** (`1:05:03`) and spoken duration ("1 hour 5 minutes"), correct plurals (de/en/th).
- **Sensitive text guard:** API keys, card numbers (Luhn) and IBAN-like strings are detected before translating or copying.
- **Engine restart plan:** 2, 4, 8 ... at most 30 s pause, give up after 5 attempts.
- **Disk space advice** (ok / low under 3 GB / critical under 500 MB) with texts.
- **Microphone level:** dBFS to 0...1, band and spoken text (silence, quiet, good, too loud).
- **No-input advice:** muted microphone, or no speech for 30 s while listening.
- **Export file names:** `dolmetscher_2026-11-21_1405_en-th.pdf`, sanitized.
- **Character counter** states (ok, 90 % warning, over) and label.
- **Settings migration:** old keys renamed to new ones without overwriting new values; idempotent.
- **Language pair spoken** ("Englisch nach Thai"), **menu bar title** shortened at a word boundary, **history day groups** (today, yesterday, date).
- New check `tests/test_r28_mac.py`: Foundation-only, linked into swift-tests, every type tested, no name clash.

### Web, round 27

- **17 new phrase packs (243 in total):** snake bite, jellyfish and sea urchins, locksmith, power outage, stray dogs, online orders and parcels, phone repair, traffic fines, air pollution (PM2.5), asthma and inhaler, anaphylaxis and adrenaline pen, seafood by weight, tipping and service charge, card payment surcharge, theft in a hotel room, Chao Phraya express boat, foreigner ticket prices. Index, categories and search terms are in place; the new packs pass `check_presets.py --strict` and `preset_lint.py`.
- **Transliteration (`rom`) for the older packs:** the 201 older packs now carry the machine-made reading aid too (`tools/preset_rom.py --fill`), about 94 % of all sentences; a sentence whose words cannot all be romanized (drug names, loanwords) gets none instead of an incomplete reading (`preset_rom.py` no longer drops words silently). Pack size budgets still hold (no pack above 22 KB, all packs below 1.9 MB), so loading `rom` on demand was not needed.
- **Review status in the phrasebook:** each pack shows "Thai sentences: x % checked by native speakers" under its note (from `reviewed` in `presets-index.json`); medical, emergency and police packs with red sentences add a hint to have a Thai speaker double-check them first.
- **See-also instead of duplicates:** new `tools/preset_dupes.py` lists packs sharing three or more sentences and adds "See also: ..." to their notes (73 packs), so each pack stays usable alone.
- **History tags:** each entry of the existing history has a tag button (star, medical, money, taxi, hotel); tags are searchable and show in the text, share and CSV export (extra `tag` column only if something is tagged). Session only, like the history itself.
- **Offline travel checklist export:** the checklist tab saves the list with its ticks as `reise-checkliste.txt`, made on the device.
- **Longer share links:** a card pack link above one QR code (271 bytes) is split into up to 12 QR codes; each code is its own link (`#part=`), the page collects the parts on the phone and opens the pack when all are there (checksum). Links up to about 2 KB (around 24 cards) work.
- **Lighthouse CI:** new workflow `lighthouse.yml` runs Lighthouse against the locally served page (3 runs, desktop preset) with budgets for performance, accessibility, SEO, weight, LCP, CLS and blocking time in `.github/lighthouse/lighthouserc.json`. Not blocking (job and step `continue-on-error`), report stored as artifact, nothing uploaded to a third party.
- **Browser flow test:** `tests/web-e2e/flow.mjs` (Playwright): open the page, wait for the service worker to cache packs, open a pack, check the review status, show a card, search, reload offline; new CI job `e2e` in `web-a11y.yml`.
- Budget: service worker limit raised to 17,500 bytes (17 more pack IDs).


### Engine, round 28

- **Three new modules, re-exported from `dolmetscher.py`** (and registered in `build.sh`/`pyproject.toml`): `sttquality.py` (`mean_logprob`, `segment_flags`, `seg_float`), `llmtext.py` (`strip_quotes`, `looks_like_name`, `neutralize`, `unspeech`, `strip_tags`), `retryafter.py` (`retry_after`, `parse_seconds`). Type hints on all three; each imports without the engine.
- **Speech recognition tolerates odd segments:** a segment whose `avg_logprob`, `no_speech_prob`, `compression_ratio`, `start`/`end` is missing, `None`, text or NaN no longer raises a `TypeError` in `mean_logprob`/`looks_hallucinated` (such a segment simply does not count); a segment with `text=None` gives an empty piece instead of an exception in `_stt`; a non-numeric duration does not break the speed check.
- **`Retry-After` in one place:** seconds, HTTP date (relative to now, past = 1 s), the Anthropic header `retry-after-ms` (preferred), any header spelling in a plain dict; `inf`/`nan`/junk fall back to the default. Used by Google/MyMemory (`_retry_after`) and Claude (`_llm_retry_after`). An overloaded HTTP 503 from Claude now honours the server hint like 429/529 (20 s without a hint, was 60 s).
- **Quote stripping:** also `‚…‘`, `‹…›`, `「…」`, `『…』`, `＂…＂`; text with a second quoted part stays untouched as before.
- **Number comparison, English:** "two and a half thousand" (2500), "a million and a half" (1500000), "one and a half million" were read as 2.5 / 1000000.5 / 1.5 and raised a false warning against the correct Thai; fixed. Year pairs "nineteen ninety nine" (1999), "twenty twenty-six" (2026) count as numbers now; ambiguous pairs ("twenty thirty", "nineteen eighty": time or price) stay words on purpose.
- **Reading aloud (`speak_form`):** ISO codes before or after an amount ("THB 1,000", "20 USD", "EUR 5.50") are spoken like the symbol ("1,000 บาท"), not spelled "T H B"; for the Thai voice `km`, `km/h`, `kg`, `cm`, `mm`, `ml` after a number become words (letters inside a word, "kmh" and the like stay).
- **Speaking rate:** `_clamp_rate` returns 0 for `None`, text, NaN and infinity instead of raising in the speaker thread.
- **Log and event line hardening:** `_finite` has a depth limit (a self-referencing value gave a `RecursionError` in the emit path); `_scrub_deep` no longer lets structures deeper than 6 levels pass unscrubbed (they become "…"), and scrubs sets as well.
- **Measured:** `bench/micro_bench.py` times `speak_form`, `en_words_to_digits`, `strip_quotes`, `mean_logprob`, `looks_hallucinated` (results in `bench/results/micro_r28.json`: 1 to 40 µs, none matters next to a translation).
- Tests: `tests/test_r28_engine_modules.py`, `tests/test_r28_engine_text.py`.

### Engine, round 27

- **Output device per direction:** new control fields `output_device_me` / `output_device_other` (same format as `output_device`, empty = general device, then system default). The speaker picks the device per output from the target language (own language = `me`, partner language = `other`; command replies and earcons always `me`); the Mac app sends them (`Engine.sendAudioRoute`, only to an engine whose `ready.capabilities` list the fields, on change and after `ready`); this needed a small change in `app/Engine.swift` and `app/SettingsR25.swift`, because a Mac test requires it once the protocol docs know the fields. Documented in `docs/PROTOKOLL.md`.
- **Thai clock with minutes:** "สี่โมงสิบห้านาที" (4:15), "สามทุ่มห้านาที" (21:05) and the like were read as two separate numbers, so a correct translation "4:15" raised a false number warning. Fixed in the number comparison; the offline translator input (`th_times_for_mt`) now keeps the minutes as well (`21:05` instead of `21:00 ห้านาที`).
- **Thai pronouns:** `fit_thai_particles` also swaps the unambiguous gendered "I" (ดิฉัน for a male voice, กระผม for a female voice); quotes with both forms and the ambiguous "ผม" (also "hair") stay untouched. 22-case test corpus incl. idempotence.
- **Refactoring:** `textnorm.py` (cache key `_norm`, `squash_repeats`) and the abbreviation logic of the sentence splitter (now in `textsplit.py`), re-exported from `dolmetscher.py`; `build.sh` and `pyproject.toml` know the new module.
- **Measured instead of guessed:** `bench/micro_bench.py` times cache, `_norm`, `split_sentences`, number reading; results in `bench/results/micro_r27.json`. None of the hot paths matters next to a translation (cache hit 0.18 µs, key 0.2 µs, split 2 to 6 µs, number comparison about 115 µs); `_norm` uses precompiled patterns now.
- **Device check per direction:** a device set per direction is checked in the background like `output_device` (`output_not_found`, shared helper `_check_output_async`).
- **Thai clock module:** `thaitime.py` (`th_times_for_mt`, `th_minutes`, the clock patterns), re-exported; "ห้าทุ่มนาที" (empty minute word) no longer swallows the unit "นาที".
- **Percent read aloud:** `100%` is spoken "หนึ่งร้อย เปอร์เซ็นต์", `3.5%` likewise; ranges (`3-4`), phone numbers, room numbers and times stay digits.
- **Review of the hot paths** (what was looked at, not only what was changed): the translation cache (all reads and writes under `_CACHE_LOCK`, byte counter rebuilt when the dict is replaced: fine); the new per-direction route (thread-local, reset in `finally`, so an error never leaves a stale direction; the player warm-up thread builds no playback command: fine; all playback commands run on the speaker thread: checked); `lru_cache` of the number comparison (key contains `thai_active()`: fine); the `OUTPUT` dict is read by the speaker thread and written by the control thread (single-key dict writes, atomic in CPython: fine). Found and fixed: the false number warning for Thai clock times with minutes, the empty minute token, `%` spoken as a bare symbol.
- Tests: `tests/test_r27_engine_output.py` (incl. real playback path with earcon and spoken voice), `tests/test_r27_engine_text.py`.
### Mac app, round 27

- Key test (Settings, API key) and self test (Help menu) are cancelled when their window closes; a late network or Python answer no longer overwrites the display. The key test result is announced to VoiceOver.
- Select all (Cmd-A) in the multi-select bar no longer blocks selecting text in a text field (local key monitor instead of a menu shortcut on the button).
- `onAppear`/`onReceive`/`onDisappear` moved from `Section` to its first row (microphone, output device and per-direction output sections), so they fire once and reliably inside a grouped form.
- Statistics charts are one VoiceOver element each (title as label, values as a sentence; hours without data are skipped).
- `Engine.swift` split without behaviour change (now under 1990 lines): code-to-text tables, line framing, bubble trimming and log tail are separate, tested logic files. Trimming 500+ bubbles is a single pass; a 5000-bubble session stays at 500 in memory.
- Every `error.code` and `dropped.code` in `docs/PROTOKOLL.md` has an app text (new Swift test reads the document).
- Output device per direction: the engine does not know `output_device_me`/`output_device_other` yet, so the app still sends nothing; a test fails as soon as the protocol document lists them without the app sending them.
- Tests: `R27Tests` in `swift-tests` (24 tests), `tests/test_r27_mac.py`.

### Web, round 25

- **25 new phrase packs (226 in total):** sunburn and heat rash, toothache emergency, coffee and tea order, Muay Thai stadium, temple photography, massage prices, apartment hunting, electricity and water bill, waste and recycling, plumber/electrician/air con, car breakdown, bicycle touring and repair, kindergarten and daycare, pet boarding and travel, childbirth in hospital, glasses and lens repair, digital arrival card (TDAC), street food custom order, smoothie and juice stall, golf caddie and tips, banking app and OTP problems, self-service laundromat, car insurance claim, tour agency booking, minivan and airport transfer. The Thai is machine-made and not checked by native speakers.
- **Thai quality:** new `tools/preset_lint.py` (register, doubled requests, emergency numbers vs. service, questions without a question word, spelling of loanwords); five clumsy sentences corrected across all packs. `tools/preset_rom.py --fill` now splits words first (without that, pythainlp output was garbage); the 25 new packs carry `rom` as a trial.
- **QR code offline:** `web-qr.js` is a small own encoder (byte mode, level L, up to 271 bytes) without any library. "Share" shows a QR code for the pack link, calculated on the device. Decoded back with an independent decoder in the development check.
- **Search in a Web Worker:** the dictionary tab searches words and sentences of all packs in `web-search-worker.js` (falls back to the main thread).
- **CSP hash:** the inline script is now also allowed by its SHA-256 hash (`tools/sync_web.py` keeps it current); browsers that know hashes ignore `'unsafe-inline'` for scripts, older ones fall back to it. Style attributes still need `'unsafe-inline'`.
- **Audio storage (opt-in, prepared):** the service worker can keep audio files below `audio/` offline in a separate cache, only after the "Audio" tab switch is turned on; off clears it. No audio files ship yet, so this is infrastructure for later; the browser's speech voice cannot be cached.
- **Accessibility:** the large yes/no text on the dark show screen had 2.3 to 2.7:1 contrast; new `--yes-text`/`--no-text` colors reach 6.8:1 and 9.9:1. The light accent for language B (`--th`) is slightly darker (3.3:1 instead of 2.97:1). A contrast matrix test covers all three color schemes.
- Budget: service worker limit raised to 17,000 bytes (25 more pack IDs, audio storage).

### Mac app, round 26

- Group mode (Settings, Audio): speakers without a voice profile get a number, a colour dot and a name ("Speaker 2" in your UI language); the "Speakers" menu in the conversation bar renames them (app-side only, reset by "Clear conversation").
- Recording source: microphone or system audio (loopback device such as BlackHole). New error text for `system_audio_missing` in all UI languages, plus a banner reminding not to route the app's output into the loopback device.
- Encrypted history (Settings, Advanced): password in the keychain only, passed to the engine as `DOLMETSCHER_HISTORY_PASSWORD` at start and for `--history-*` calls and as `history_password` control field. The plain-text `history.sqlite` stays; "Clear history" affects both files while the password is saved.
- New "Experimental" settings tab: the six round-24 switches (stream, router, defer, parallel check, name prompt, Thai numbers), shown by the engine's `ready.capabilities`, off by default, with a warning. Latency distribution (median and 95 %) from `state.latency_hist`.
- `mic_gap` hint shows as a banner (90 s); unknown engine errors use `msg_en` when the UI is not German.
- `Views.swift` split (`ViewsToolbar.swift`, `ViewsBanners.swift`; now under 1000 lines, no behaviour change; `Dolmetscher --smoke-test` still passes). Output per direction stays app-only: the engine does not know `output_device_me`/`output_device_other` yet.
- Review fixes: amounts with 20+ digits crashed the price helper; the mic test timer could end a later test early and kept the mic open after closing the window; learn mode kept the revealed answer for a new sentence; the partner window's full-screen state reacted to other windows; the "translating" line was not rotated for the partner.
- Tests: `R26Tests` in `swift-tests`, `tests/test_r26_mac.py`.

### iPhone app, round 34: travel features in the interface

- Menu scan ("More" menu): photo or camera, text recognised on the device, lines with ingredients from your emergency-card allergies are marked as certain ("Contains") or possible; no match is never shown as safe, with a reminder to ask.
- Travel mode card: when the iPhone's time zone points to another country, a card suggests the partner language and shows emergency numbers and currency. It uses no location, appears once per country and never changes anything until you tap; switch in Settings.
- Offline traffic light on top of the offline packs screen (green, yellow, red with icon and text), taking the installed voice quality into account, with one tap to download everything the app can load.
- Learn: pronunciation coach (compares the recognised text with the sentence, an approximation), a third rating "Easy", the review planner (FSRS state per card in its own store, keyed by a hash so no sentence text lands in the backup, forecast of due cards and average recall) and place chips (airport, restaurant, hotel, ...) that show due cards fitting the place first. The Leitner boxes and `learn.json` are unchanged.
- Travel diary: sentences, days, longest streak, languages, share translated offline; computed on the device and hidden while the history is locked.
- Hotel card as QR code (vCard from the emergency card, optional phone number) for drivers and reception.
- Two-device mode: two iPhones nearby exchange text via MultipeerConnectivity (encrypted, invitation needs an explicit Accept, no history; translation works as in a conversation, online only if allowed). New `Info.plist` entries `NSBonjourServices` and `NSLocalNetworkUsageDescription` (translated in all interface languages).
- Whisper partial text while speaking (Settings, default off): at most one preview decode at a time, never while a final result is being decoded, only the stable part is shown and the final result always replaces it.
- Not done: Apple Watch companion (`WatchBridge`) needs a new watchOS target in the Xcode project, left out to avoid project risk; `FileGuardApply` is not wired into the storage because complete file protection would block reading emergency data on a locked iPhone.
- Logic in `Round34.swift`, views in `Round34Views.swift`, texts in `L10n+R34.swift`, tests in `Round34Tests.swift`.

### Mac app, round 25

- Fix: a full stop inside a number (`10.30`, `3.5`, `฿1.200`) no longer splits a sentence, so a to-do like "Meet at 10.30 at the pier." stays whole in the summary.
- Fix: the learn-mode blank hid the first matching letters instead of the chosen word (`a` inside "banana"); it now uses the exact word range.
- Fix: euro amounts are rounded to cents before formatting (12.995 showed `12.99 €`, now `13 €`).
- Fix: SRT/VTT export no longer lets a cue run into the next one when sentences follow each other closely.
- Fix: history search ignores spaces at the edges ("hello " found nothing) and also searches the romanization; the field now filters after a 0.2 s typing pause instead of on every key.
- Fix: the Handoff language-code check accepted a letter plus a combining accent (character range a…z); it is ASCII-only now.
- Error banner: more engine codes get a concrete next step (disk full, ffmpeg/audio missing, history/file errors, invalid language pair) and "no network" also offers the network settings. The rules moved to `ErrorAdviceLogic.swift`.
- History export: Markdown table and PDF with two columns (Thai left, Latin right; optional romanization column), decided by script, not by direction. The PDF is made locally from an HTML table with page breaks.
- Menu bar: live line with finished and waiting sentences and the median latency of the last five; the Learn window is in the menu bar menu.
- Output per direction (settings): choose a device for my translations and one for the other person. Only preferences for now; the engine fields `output_device_me` / `output_device_other` are prepared in `AudioRouteLogic` but not sent until the engine knows the direction per sentence. A missing device is reported, not silently replaced.
- Handoff (off by default, never during a sensitive session): the last sentence can be continued on another Mac as a show card (`NSUserActivityTypes` in Info.plist). Prepared, not tested between two Macs (ad-hoc signed builds may not support Handoff).
- Window self-test: Help menu "Window self-test" or `Dolmetscher --smoke-test` builds every window view once and checks layout (all 12 windows listed in `WindowCatalog`, checked against the scenes by a test).
- Accessibility: "Show big" buttons name their amount, learn-mode word rows read as one sentence, the revealed blank is announced, the invalid-rate warning is announced, "Copied" resets when the summary changes. The show-card phrasebook is built once instead of on every key press.
- `SettingsView.swift` split further (`SettingsAudioSections.swift`, `SettingsAPIKey.swift`, `SettingsR25.swift`); texts in `L10n+R25.swift`; the other long-open ideas (App Intents, bubble list diffing) were checked: bubbles are already `Equatable`; App Intents are left out because plain `swiftc` does not produce the metadata Shortcuts needs.
- Tests: `R25Tests` (27 cases) in `swift-tests`, `tests/test_r25_mac.py` (window ids, three-language tables, shortcut catalog against the code, wiring).

### Mac app, round 24

- Numbers & prices (⇧⌘N): prices in the conversation (฿, baht, บาท, €, euro) with conversion at a manually entered rate (baht per euro), "show big" for any amount, and a negotiation helper (counter-offers at 70/80/90 %, next bid under a budget).
- Summary (⇧⌘U): built locally from the history (no AI call): to-dos, open questions, prices, numbers; copy or save as Markdown. After a longer conversation a notification with Copy and Open actions appears when the app is in the background.
- Learn (⇧⌘L): sentence word by word (also Thai), fill-in-the-blank, Anki cards straight from the conversation (choose the front language).
- Show card (⇧⌘Y): large text for the other person; without a translator the phrasebook fallback finds the closest scenario phrase (English or Thai) and suggests alternatives. Shortcuts links: `dolmetscher://card?text=` and `dolmetscher://summary`; the card can copy a `dolmetscher://say` link.
- Scenario suggestion: when the last sentences sound like a scenario pack (taxi, doctor, market …) a banner offers to load its phrases (needs two matching checks in a row; can be dismissed).
- Live captions: position (bottom, top, free), bold text, click-through (undo via the menu bar item) and windows that were off-screen after unplugging a monitor are moved back.
- Keyboard shortcuts window with search; new windows remember their position. Quick-phrase settings: a note when more than nine phrases exist (only the first nine get ⌘1–⌘9); the section moved from `SettingsView.swift` to `SettingsQuickPhrases.swift`.
- Fix: the number warning no longer fires when only the thousands separator differs (1,200 vs 1200).
- Logic in `PriceLogic`, `SummaryLogic`, `LearnLogic`, `ScenarioDetect`, `OfflineFallback`, `WindowLogic`, `ShortcutCatalog` with tests in `swift-tests`; texts in `L10n+R24.swift`.

### Engine, round 25

- Group mode (`group_speakers`, default off): speakers without a voice profile get stable numbers ("Sprecher 3"); `utt` carries the additive field `group_speaker`. A stable layer (`online_speakers.py`) sits on top of `profiles.cluster_speakers`, which relabels by group size on every call: numbers are never renumbered, a new person's first sentence is not folded into a big group, two numbers of one voice are merged for later sentences only. Reuses the voice fingerprint that is already computed (no extra model run); `clear` restarts at 1.
- System audio as an opt-in source (`--source system`, control field `source`): records a virtual loopback device (BlackHole, Loopback Audio …) found through `avhelper` on every start; without one `error` `system_audio_missing`; a `hint` `system_audio` warns not to route the engine's own speech into that device.
- Optional encrypted history (`history_password` control field, secret, never logged): own file `history-enc.sqlite`, text, translation and transliteration encrypted per field (stdlib only, key derived once per open, wrong password is a clean error). The plaintext database is never converted or written to while a password is set; CLI queries read it with `DOLMETSCHER_HISTORY_PASSWORD`.
- Switches: all six round-24 switches stay off by default after review (no measurement exists for router, stream, prompt and numbers; they change text or speech); a test pins the defaults. Language detection and transcription are not merged: detection runs on the small `m_det` model and the lock, profile prior, role and counter-check logic need the language before decoding. Characterization tests for the lock path were added instead.
- Bugs fixed: Thai times with a dot (`10.30 น.`) were read as a decimal number, space-grouped thousands (`10 000`) were torn apart in spoken numbers, `thai_number_words(True)` returned a word, `"Infinity"`/`"NaN"` in `llm_spend.json` locked Claude permanently, the history writer queue could be created twice when `emit` was called from several threads at once (lost ordering, two writer threads), `chunk_long` with a limit under 3 looped forever, `cluster_speakers` crashed on mixed fingerprint sizes and let NaN/inf fingerprints poison the groups, `kmeans_centroids([])` raised.
- Code split (no behaviour change, all names re-exported from `dolmetscher.py`): `numwords.py` (Thai number words), `thaiparticles.py` (particles, speaker sex, stretches), `textsplit.py` (first clause, chunking, cut points). New modules are copied into the app bundle by `build.sh`.

### Engine, round 24

- Switches that only existed in code are now control fields (all default off, also via `DOLMETSCHER_FEATURES`): `llm_stream` (streaming; the first finished sentence is pre-rendered into the speech cache), `llm_router` (Haiku for short, Sonnet for hard sentences), `defer` (recognition runs while the previous sentence is translated), `parallel_alt`, `stt_prompt`, `speak_numbers` (Thai numbers as words). `ready` lists `capabilities`; `error` events carry `msg_en` next to the stable `code`.
- Bugs fixed: a huge integer in a control field (`"rate"` with 400 digits) raised `OverflowError` in the control thread; the first-clause splitter cut `10:30`, `1,500` and `3,5` apart; the `<speech>` tag could be re-assembled from nested input (`</spe</speech>ch>`); non-text recognition alternatives crashed the Claude prompt.
- Prompt-injection hardening: glossary, scenario hint, history, names and alternatives lose tag-like text and line breaks before they enter the prompt; test corpus in `tests/test_r24_engine_prompt.py`.
- Resilience: with 5 or more waiting utterances recognition switches to beam 1 instead of dropping sentences; if the Apple GPU (MPS) fails at run time the models are reloaded once on the CPU and the sentence is retried (`hint` `device_fallback`); a microphone buffer overrun marks the next sentence (`hint` `mic_gap`).
- Diagnostics: per-sentence trace in the log (`trace`), persistent p50/p95 latency history (`latency_history.json`), allow-list in the log layer (long text under unknown keys is never logged).
- Not done in this round: merging language detection into transcription, Edge-TTS PCM instead of MP3.

### iOS travel features, round 33

- Bluetooth (HFP) hint now comes from the L10n table in all ten interface languages instead of inline text.
- Whisper partials: only the part that stayed the same across the last results is shown (never mid-word), hallucination filter on every partial, the final result always replaces it.
- Menu photo: `MenuAllergens` marks lines that match your allergies (en/de/th, ids from `allergens.json`), with guards for "eggplant", Thai "ขนม" (snack, not milk) and squid (not fish); a bare "ถั่ว" is only "maybe peanut".
- Travel mode: country suggests partner language, emergency numbers and currency (a suggestion, never a silent switch); two-device message codec and state (MultipeerConnectivity prototype, not offered in the UI yet); pronunciation coach score; FSRS-like spaced repetition with place triggers (foreground only); travel diary statistics; QR hotel card text; Apple Watch message codec (no Watch target yet).
- Optional Spotlight search of the history (off by default, last 200 sentences, cleared on Face ID lock and when history changes); offline traffic light that also checks for enhanced/premium voices; backup-exclusion and file-protection rules with tests; offline translation through English is marked "via English" on the bubble.
- Tests: `Round33Tests` (37 cases).

### Web round 24: tools and 23 new packs

- New tools dialog (button 🧰, loaded on demand from `web-extras.js`, cached for offline use): price check with a manually entered rate and a big number card (with Thai number words), negotiation helper with counter offers, travel checklist, offline dictionary from the pack glossaries, tour guide pack shared as a link (own cards compressed into the URL fragment, nothing uploaded), travel diary with tags and file export, tone trainer with minimal pairs and quiz, microphone level hint for noisy places. No photo/text recognition: it cannot work offline without a model download.
- 23 new phrase packs (201 in total): camping, night bus, business meeting, contractors, caves and waterfalls, climbing, surf lessons, herbal medicine, blood tests, meditation retreat, longtail boat, condo office, used vehicles, vet, school enrollment, electronics mall, copy shop, gold shop, notary and translation, work permit, neighbours and noise, orchard visit, wildlife safari. Thai lines are machine-made, not reviewed.
- The CSP now allows `'self'` scripts for the extras file; the hash-based CSP is not done yet (the inline script still needs `'unsafe-inline'`).

### Modules, tools and docs, round 24

- Phrase book tool: `satzbuch.py report` (Markdown or JSON, by code and pack, with size) and `check --ignore CODE --pack ID`. Bug fixed: a wrong or empty `--dir` reported "0 errors" with exit code 0; it is now an error.
- Speaker clustering: `profiles.cluster_speakers` separates voiceprints of a session into up to eight people (greedy plus k-means refinement, outliers merged); not yet wired into the engine.
- Audio helper: `avhelper.py list` also reports loopback devices (BlackHole and similar) and the new `prep` command tells whether system audio can be captured (nothing is installed or redirected).
- History: optional password-protected export (`Store.export_encrypted` / `import_encrypted`, scrypt with PBKDF2 fallback, encrypt-then-MAC, standard library only, no Keychain). The running database is not encrypted.
- Corrections: `ConfusionMap.apply` replaces in one pass (a->b and b->c no longer chain) and picks the most frequent correction per word; `from_dict` ignores booleans and respects the size limit.
- Benchmark: `bench/latency_budget.py` with `bench/latency_budget.json` (time budget per language, regression per case against the baseline, `--scale` for slow runners); the manual benchmark workflow reports it as a hint.
- CI and docs: the Pages smoke test also compares the service worker pack list with `presets-index.json` and no longer treats a missing cache version as success; Dependabot updates merged (actions group, web-e2e group); roadmap, architecture and benchmark docs updated.
- Tests: `tests/test_r24_modules_a.py`.

### Engine latency, round 23 (Python)

- Faster Claude path: worker pools instead of a thread per call, warm-up at start plus keepalive while idle (only when the prompt cache applies), cache hit/write counters and cost by the model actually used.
- Hedge: long sentences start Google in parallel; pre-translated text replaces a slow Claude answer. Translation cache is also limited in bytes.
- Earlier sentence end for Thai (ครับ/ค่ะ/คะ) and for ?/! in other languages (only with fast endpointing); unambiguous Thai clock times are translated deterministically.
- Back-translation by Claude for critical sentences (numbers, health, emergency); a second budget warning at 95 %.
- Protocol unchanged (no new events, fields or start arguments); streaming, router and deferred worker are opt-in and off by default.

### iOS speech, audio and translation, round 31

- Whisper: time budget per recognition, fewer temperature fallbacks on low battery or heat, vocabulary prompt from names in the conversation, warm-up decode, adaptive pause threshold, language stickiness, skip clicks and silence.
- Audio: `setCategory` only when it changes, one-time warning for narrow-band Bluetooth (HFP) input.
- Translation: in-memory LRU cache, name protection for online translators, offline pivot via English, circuit breaker with backoff and visible remaining pause.
- Model constants instead of magic numbers; haptics throttle; English units for the voice.

### Infrastructure and docs, round 23

- Tests: `tests/test_thai_zahlen.py` is collectable again (a foreign `tests` package in site-packages shadowed the folder); tests that need `edge_tts`/`aiohttp` skip with `pytest.importorskip` instead of failing; the download-progress test no longer depends on the Hugging Face cache layout or fixed sleeps.
- CI: Dependabot also watches `tests/web-e2e` (npm); new workflows for external doc links (lychee) and a smoke test of the published Pages site (`tools/pages_smoke.py`); shellcheck also covers `tools/*.sh`; `tools/check_doc_links.py` checks relative links.
- Docs: FAQ entry for the browser version on iPhone (Safari), `docs/TH-QUALITAET.md`, ready-made hosting configs (Netlify, Cloudflare, nginx, Caddy) in `docs/hosting/`, short intro in the README, roadmap additions. Privacy pages now say that the iPhone online fallback starts MyMemory in parallel when Google has not answered after 1.2 s, and that MyMemory is queried with POST (the text is never in the URL).
- Benchmark: 12 new cases for numbers, clock times and phone numbers (`th43` to `th48`, `en21` to `en26`); the baseline needs a new measurement on `main`.
- `build.sh`: `--release` runs pip-audit on `requirements.txt` and aborts on findings; an ad-hoc signature is now reported loudly.

### Phrase packs, round 23 (presets)

- 22 new scenario packs (178 in total): diabetes and insulin, travel vaccinations, bringing medication in, tourist police report, Thai massage boundaries, ride-hailing price dispute, prescription and refills, night train and sleeper, SIM / eSIM / data, dive medical clearance, sprain / fracture / X-ray, travelling with elderly parents, complaint to customer service, hotel deposit dispute, visa run and border crossing, respect for the King and royals, temple donations and etiquette, EV charging, hospital payment and insurance, food poisoning, apartment host and self check-in, international money transfer. Thai lines machine-made, not checked by native speakers.
- Checks: same English sentence now needs the same Thai and the same `critical` flag across all packs; Thai strings must be NFC, free of invisible characters and use Arabic digits and `บาท`. German and Thai search keywords in `presets-index.json`; optional `rom` (romanisation) per phrase with `tools/preset_rom.py`.

### Web Lite, round 23 (web)

- Service worker: navigation preload, retry with backoff (0.5 s, 1 s, 2 s) when loading packs, byte progress ("x MB loaded"), update hint while a new version loads, cache version shown as tooltip.
- Privacy: "Online translation off" switch, one-time warning before online translation in sensitive topics (doctor, police, visa, bank ...), export and import of local data as a file (validated, known keys only), optional automatic deletion of old local data (30/90/365 days), storage size display, iOS note about Safari deleting site data after 7 days.
- SOS button with emergency numbers (191, 1669, 199, 1155, 1193, 112) and large Thai sentences for ambulance and police; focus returns to the button when the dialog closes.
- Taxi and hotel card: destination or hotel (with address) as a large Thai sentence, popular destinations, read aloud, saved on the device only.
- Interface language now follows the whole browser language list; focus styles for dialog and tabs, forced-colors support; four more allergens (NSAIDs, iodine/contrast dye, kiwi, buckwheat).

### Mac app main window, round 23

- Search shows the current match as "2 / 7" with previous/next buttons (⇧⌘G / ⌘G); the matching bubble is highlighted and scrolled into view.
- Select several bubbles (context menu or the "More" menu): copy (with or without times), export (also one language only) or delete them together.
- Bubble context menu: "Copy as …" with original, translation, both or with time; VoiceOver announces the bubble position ("3/12").
- Number mismatches are much easier to see: a filled warning with the differing numbers, numbers highlighted in the bubble and in the partner view.
- Page through alternative readings of unsure speech; per-bubble back-translation button.
- Empty history shows a daily tip; the header shows a latency sparkline with trend, a "too loud" hint when the microphone clips, and an offer to switch to Auto when the last sentences do not match the forced language.
- Partner view: Thai text is set larger. Mini window: copy button and space bar for pause/resume.
- Engine: partial text is throttled under load, the watchdog uses a monotonic clock, and a sentence cut off by an engine crash stays as a bubble marked "interrupted".

### iPhone round 32 (iOS)

- New: taxi card with large Thai script, price and haggling helper, step-by-step emergency flow, tap-a-word lexicon; emergency numbers per country; three Shortcuts actions that return values (emergency numbers, taxi phrase, counter-offers).
- Control Center: listening toggle, emergency and taxi controls; the Live Activity goes stale after 5 minutes when paused or interrupted.
- Storage schema version with migration; content is hidden during screen recording or mirroring (can be switched off in Settings).
- Accessibility: layouts stack at the largest text sizes, solid backgrounds with Reduce Transparency, focus outlines without relying on colour, more voice-control names.

### Web Lite and phrase packs, round 22 (web)

- 14 new scenario packs (156 in total): numbers and prices, negotiating, Buddhism and etiquette, scooter rental damage and deposit, describing symptoms in detail, avoiding tuk-tuk scams, embassy and consulate, spice level in food, deaf / hard of hearing / unable to speak, wheelchair and limited mobility, halal food and prayer, returns and complaints in shops, hotel room problems, lost wallet and cards. Thai lines machine-made, not checked by native speakers.
- Offline: the service worker loads emergency and safety packs first; in data-saver mode or with little free storage it loads only those. The cache version now follows a content hash (`tools/sync_web.py`), `PRESET_IDS` in the page and the worker are generated from `presets-index.json`.
- Installed app asks the browser to keep its storage (`navigator.storage.persist()`), manifest gets shortcuts for emergency and pharmacy and `handle_links`.
- Page: canonical link, Open Graph and Twitter tags, JSON-LD, stricter CSP (`frame-src`, `object-src`, `script-src-attr` none), `robots.txt`, `sitemap.xml`, `llms.txt`; keyboard Home/End on the tabs, visible focus for links, text areas and tabs, stronger focus and borders with `prefers-contrast: more`, 44 px touch targets for all buttons on touch screens.

### Mac app: settings, history, setup and menu, round 23

- Settings: smarter search (several words, accent-insensitive, help text), "Reset this tab" per area with confirmation (language pair, model and interface language stay), preview of the backup file (never contains keys, history or conversations; export is blocked if anything looks like a key).
- History: multi-select with Cmd/Shift, filters by speaker and period, merged Markdown/SRT/WebVTT export of several sessions (long pauses shortened), Anki card export (CSV), statistics dashboard with Swift Charts (per day, hour, language, speaker, recognition confidence).
- "Sensitive session" (menu, menu bar): private mode on, local history and text log off until switched off or the app restarts (resets and imports cannot undo it); the previous settings are restored.
- Setup: microphone level test, headphone tip against echo, "Test key" (one request to api.anthropic.com), pre-check for internet and free space, remaining-time estimate for model downloads.
- Menu: Help gets What's New, Report a Problem (pre-filled GitHub issue without personal data) and Run Setup Again; hotkey conflicts explain the cause and suggest a free letter; menu bar extra shows the last translation; locking the screen pauses the microphone and resumes on unlock (setting).

## 1.3 (20 November 2026)

Pull requests #16–#192. First tagged release since 1.2: engine hardening, Mac and iPhone round 21, Web Lite tabs and i18n files, 142 phrase packs, security fixes.

### Engine robustness, round 21 (Python 2)

- Engine: a deeply nested JSON line on stdin (or `--profile-stdin`) no longer stops the engine; `history_days: false` and `llm_retry: "false"` are read strictly; `say` without `lang` uses my language; a mic drop after speech keeps the recording.

### Engine, round 22 (py1)

- Log/error paths: a home folder such as `/Users/x` no longer turns `/Users/xavier/...` into `~avier/...`; nested path lists in events are masked too.
- Spoken output: `5€`, `500฿` and a bare `20°` are read as words; learned glossary names can no longer inject glossary lines; the plain console no longer fails on sparse events.

### Phrase packs, round 21 (tooling, wave 2)

- 11 new scenario packs (142 in total): tattoo and piercing, driving licence, opening a bank account, long-term lease, pregnancy, drone and camera rules, fruit market and durian, Songkran, private driver and day tour, luggage storage, Grand Palace and museum. Thai lines machine-made, not checked by native speakers.
### iPhone, round 21 (8)

- iPhone: a cancelled translation (sentence deleted or re-translated) no longer continues to Google/MyMemory; it ends without any network access.

### Security review, round 21

- Mac: allowing a `dolmetscher://` call in the confirmation dialog now applies to that one call only; permanent permission is set only with the Settings switch.
- iPhone: the recognised sentence is no longer written to the system log as public text (it is private now); the optional exchange-rate request no longer uses the shared URL cache or cookies and only accepts a three-letter currency code.
- Tests: seeded fuzz tests for the history import, presets, glossary text and the web share/deep-link parameters.
- CI: checkouts no longer keep the repository token in the working copy.

### Interface texts audit (round 21)

- iPhone: the language picker in the settings now says when the chosen interface language is machine-translated and not checked by native speakers (all languages except German and English).
- New glossary of interface terms ([docs/GLOSSAR-UI.md](docs/GLOSSAR-UI.md)); a test locks the variants it forbids. English texts use US spelling throughout; one word per language for flashcards, partner language, retry and stop reading aloud.
- Fixed machine-translation slips in the emergency-numbers and phrasebook texts: "partner" was rendered as spouse or business partner in Spanish, French, Vietnamese and Indonesian; Chinese "voices" now reads 声音.
- Counts read "Matches: 1" instead of "1 matches" (Mac history, search, glossary, settings transfer; iPhone learning streak; web flashcard messages). Thai Mac texts say โปรด/ไมโครโฟน like iPhone and web.
- Tests now check every iPhone table (rounds 13 to 25), that each round is registered in the lookup, and shared Mac/iPhone keys.
- Units and number formats follow the interface language: iPhone settings show "0,8 Sek.", "75 %" and "10 Min." (German) instead of fixed English text; the web speed slider and the voice command "slower" use the decimal sign of the chosen language; the Mac conversation export always writes a Gregorian date, also on a Thai system.

### Mac app, round 21

- History window: a session can now also be exported as plain text, JSON or WebVTT (besides Markdown, CSV and SRT).

### Web version, round 21

- Less layout shift while the phrasebook loads (CLS 0.37 to 0.04): the "useful now" row, the phrase of the day and the quick answers reserve their space.
- Offline travel checklist (10 items, ticks stay in the browser), allergy warnings on phrase cards (keyword match on the English sentence, follows the allergy card selection) and a 7-day bar chart in the learning statistics.
- Learning cards: keys 1-4 no longer also start the microphone; held keys no longer toggle modes repeatedly; Space still opens sections and links.
- Own phrases in English on the default EN ⇄ TH pair are no longer stored as Thai; history search ignores button labels and respects new entries.
- Shared text (`?text=`) is only sent to Google Translate after a confirmation; the learning timer no longer speaks in the background.
- Emergency numbers (1669, 191, 199, 1155) for more than 40 topics instead of 12.
- Fixed German texts (consent dialog, allergy card, learning box) are now translated; Android voice tags (`eng-USA`) are recognised and local voices are preferred; the iPhone hint can be closed; Thai digit tiles read aloud; sliders are announced with their value.
- Web page in four sections (tabs: Speak, Phrasebook, Cards, Learn); the notes are folded after the first visit; new two-person screen where each side types in their own language (also without speech recognition); English and Thai interface texts moved to `i18n/*.json` (page 242 → 192 KB).
- Allergy card and shown sentences can be shared as an image (for chat apps); a Playwright + axe-core scan of the web page runs in CI (informational).
- Numbers box: time of day and phone numbers in Thai words; allergy card with mushrooms, coriander and an EpiPen line; the Back button closes the two-person screen.
- The conversation CSV now has time and languages per line.
- Web page: interface texts load without blocking (German first, then the chosen language); warnings follow a language switch; the 40 newest phrase packs are listed in the page and the offline cache.
- Show mode can swap to black on white (sunlight); offline, a path outside the app now gets an honest offline page; the axe accessibility scan now blocks pull requests.
- Yes/No and quick-answer buttons no longer print the same word twice when the interface language equals the partner's language.
- Web page: exchange-rate calculator in the numbers box (the rate is remembered), slow-repeat button (turtle) on every phrase card, print my cards (hotel, address) as an A4 sheet, direct links to sections (`#book`, `#cards`, `#speak`, `#learn`), real screenshots for the install dialog (`tools/web_screenshots.py`).
- Keyboard docs list the tab-bar arrows and Esc for the two-person screen; the Back button returns focus when it closes that screen.
- Web phrasebook: find topics by name or keyword, filter by trip type (backpacker, family, digital nomad, medical) and by category, topic suggestions by time of day, and a phrase of the day (all computed locally).
- Installable app: separate maskable icons, opaque 180 px Apple icon, iOS meta tags; the service worker refuses an install without page and language table and checks for updates hourly.

### Phrase packs and tooling (round 21)

- **New:** 10 more phrase packs: physiotherapy-injury, car-accident, gas-station-parking, mosque-visit, spirit-house-shrine, earthquake-evacuation, mental-health-counseling, sexual-health-clinic, thai-language-lesson, babysitter-housekeeper (131 in total; Thai machine-translated, not yet checked by a native speaker). They are listed in `tools/web_pending_presets.txt` until the web lists (`index.html`, `sw.js`) include them.

- **New:** 10 more phrase packs: motorcycle-taxi, promptpay-qr-payment, water-park-zoo, home-repair, volunteering, birthday-celebration, funeral-condolence, skin-clinic, fishing-trip, badminton-tennis (131 in total; Thai machine-translated, not yet checked by a native speaker). They are listed in `tools/web_pending_presets.txt` until the web lists (`index.html`, `sw.js`) include them.

- **New (tooling, part 6):** `presets-index.json` has `keywords` per pack and `routes` (backpacker, family, digital nomad, medical tourism bundles from `tools/preset_routes.json`); `tools/preset_search.py` searches all packs in de/en/th; `tools/preset_quality.py` reports length, number and glossary consistency per pack; `Store.stats()` gives sentences and words per day and the most repeated sentences; `Recorder.enable(keep_days="suggested")` offers a 30-day retention (the default stays unlimited).

- **Changed (tooling, part 5):** notes of the new packs on cannabis, customs, volunteering, dengue and PEP no longer state specific rules or deadlines that could be wrong (they point to current local rules or a doctor); voiceprint enrolment sentences for German, Spanish and French; CI lints the workflows with actionlint and zizmor.

- **Fixed (tooling, part 4):** a voiceprint is only adapted from an utterance that is at least moderately similar to it and with a smaller maximum weight, so a wrongly recognised foreign voice cannot drag it away; `PresetState.dropped` reports glossary entries that did not fit; `hwprofile.low_power_mode()` and `power_saving()` detect Low Power Mode.

- **New (tooling, part 3):** `presets-index.json` carries a `category` per pack (from `tools/preset_categories.json`) and `tools/preset_stats.py --by-category` reports coverage by topic; the history store can export translations only (`txt`) and import a JSON export again (`Store.import_json`, duplicates skipped); `make stats|cov|audit|lock`; a non-blocking CI run on Python 3.13; pytest runs with `-ra` and `xfail_strict`; the tests no longer expect the lower-case pull request template name.

- **Fixed (tooling, part 2):** the speaker-model download accepts only `https://` (or `file://`) sources, aborts above 200 MB, waits at most 10 s for the profile lock and writes its check stamp straight away; old quarantine files (`*.bad`, voiceprints) expire after 7 days (at most 5 kept) and stale `*.tmp` files are removed. Correction suggestions skip stop words and Thai particles and long Thai runs without a tokenizer. `build.sh --install` copies next to the old app first, so a failed copy no longer leaves no app; `setup-env.sh` verifies all runtime packages; `make-stamp.sh` takes Python version and architecture as arguments. `allergens.json` gained mustard, lupin, sulphites, corn, coconut, mango, chilli, MSG, fish sauce, shrimp paste, molluscs and diet rules (no pork or beef, halal, vegetarian, jay, no alcohol, low salt).

- **New:** 20 more phrase packs: scams-overcharge, lost-phone, police-checkpoint, tm30-address-report, karaoke, golf, kayak-national-park, hair-beauty, cannabis-vape, chronic-conditions, lost-luggage, customs-duty-free, heat-health, mosquito-dengue, border-crossing, currency-exchange, optician-eye-care, souvenir-jewelry, buffet-bbq, adventure-park (131 in total; Thai machine-translated, not yet checked by a native speaker). They are listed in `tools/web_pending_presets.txt` until the web lists (`index.html`, `sw.js`) include them.

- **Fixed (tooling):** `presets.find` and spoken scenario commands now normalise names and input the same way (hyphens, slashes, Thai tone marks); German and Thai commands (“Notfall-Modus”, “โหมดโรงแรม”) work; oversized preset files are skipped and duplicate ids in one folder are reported. The history store closes its connection when opening fails, has indexes for replace and session queries, filters searches in SQL (no silent cut-off after 5000 hits), reads under the lock, retries transient database errors, bounds its write queue, refuses to export through a symlink and reports an unknown session. `avhelper` rejects `--volume nan` and bad sample rates and stops on an empty looped file. CSV exports of the phrasebook are formula-safe and carry a BOM for Excel. CI: the `ci.yml` workflow had invalid YAML (an unquoted colon) and is fixed; weekly dependency audit for both lock files; preset consistency check in CI; release builds check out the full history for the build number; ruff also checks `tools/`.

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

### Engine, round 21 (voice output)

- A cut-off Neural voice (connection closed before the sentence end) is no longer cached or counted as complete; a missing player or `say` no longer crashes the speaking path.
- The echo guard starts when a sentence is actually heard, not when it is queued; muted output reports as interrupted.
- New events: `tts_fallback` with `ended: true` when the Neural voice is back, and `speak_failed` when even the fallback voice could not speak.

### Engine, round 21 (control, microphone, travel helpers)

- Voice commands “repeat slowly” and “repeat the previous one”; optional price display (`currency` control field, `price` event) turns Baht amounts into your home currency; a hint when the surroundings stay loud (`noisy`).
- Non-numeric values for `rate`, `volume`, `silence`, `tts_race`, `let_finish`, `llm_budget`, `beam` are reported (`control_invalid`) instead of silently ignored; Stop/Mute run before slow actions; oversized control lines are read with a bound.
- Backlog counts only waiting utterances; confidence is weighted by segment length; Thai gets a higher token cap; abbreviations (“Dr.”, “5 p.m.”) no longer end a sentence early; changing the language pair clears pre-recognition state.
- Speaking path: a sentence no longer waits 180 s for a stuck player (limit follows the audio length); the Neural-voice connection is only opened after 0.35 s of speech; wrong system clock (HTTP 403) is corrected from the server time; open connections are closed on exit; duplicate microphone names are reported (`mic_ambiguous`).
- Backlog handling also considers how much text is waiting (long sentences are skipped earlier, without pre-loading voices); a microphone that stops delivering data reconnects after 5 s; with `--model auto` the engine adapts to battery/mains while running (`power` event).
- The `queue` event counts only waiting utterances (not pending app tasks); `slow` hints for recognition, translation and sound no longer suppress each other; leftover temp folders of a dead run are cleaned even when its process id was reused; `--file` rejects audio longer than 4 hours instead of exhausting memory.
- Emergency phrases of the active scenario are re-rendered when the speaking speed changes (they were cached for the old speed); duplicate emergency sentences are rendered once; “clear” and corrections also drop the timestamps of forgotten sentences.
- The wait before the fallback voice takes over now adapts to the measured speed of the Neural voice (shorter on a good network, up to twice as long on a poor one; `tts_race` stays the base and 0 still turns it off).
- Internal: numeric control fields now come from one table (`CTRL_NUMERIC`) with consistency tests (first step of a declarative control table; behaviour unchanged).
- Internal: the known control fields and the loggable ones now come from one table (`CTRL_SPEC`), unchanged in behaviour; the pre-warmed player process is ended on shutdown.
- Switching the microphone to a device that cannot be opened no longer ends the engine (it reports the error and the microphone stays off); a `listen` sent before the models finished loading no longer makes a `--idle` engine quit on a later microphone error; `--file` runs now also write the history to the end, remove their temporary folder, close the offline helper and report an unwritable subtitle file as `file_failed`; “clear” also forgets the text kept for the echo guard.
- A sentence played from the voice cache no longer counts as “online” (offline, the fallback-voice banner stayed hidden and the next sentence waited the full race time); Stop before the first sound ends the wait at once; a Stop arriving just as the next sentence was taken from the queue now also stops that sentence (and the confirmation tone); a failing pre-render of the fallback voice (temp folder gone or full) no longer drops the whole spoken output; a half-opened speech connection is closed when its configuration cannot be sent.
- Control lines: `listen: true` followed by a Stop no longer opens the microphone afterwards; `mic` together with `listen: true` really switches a running microphone; `say`, `speak_text`, `reassign` and `retranslate` in one line all run (they used to exclude each other silently); a Stop during microphone start no longer leaves it marked as on; a failing voice-activity model now leads to a reconnect instead of a silent dead microphone; a long utterance split at the maximum length no longer reuses the pre-recognition of the unsplit audio.
- “Clear” (or Stop) while a sentence is still playing no longer stores that sentence in the voice cache afterwards; a translation answered from the cache or a pure laugh no longer counts as “online” again; Stop during the fallback-voice wait no longer shows “fallback voice active”; a missing player or temp folder is no longer reported as “offline”.
- Subtitle export removes its temporary database; a failing chunk of a `--file` run no longer stops the rest; engine start errors report `engine_init_failed`.

### Engine (speech recognition, translation, voice – used by the Mac app)

- **Engine round 21 (8):** the Mac app now shows “disk full” and “log not writable” errors in its own language, well-known Thai places (Sukhumvit, Siam, Pattaya …) stay names with Google/MyMemory, and fixes from a second review: “ER”/“err” are no longer removed as filler sounds, particles in unspaced Thai are matched, “pass me the salt” is no longer a pause command, คะน้า is not a particle, URLs are not touched by name protection, a billing error no longer disables effort mode.
- **Engine round 21 (7):** the persistent translation cache is no longer deleted on every glossary change or scenario switch (entries are keyed by a glossary/scenario signature instead), learning a name during an active scenario no longer switches the scenario off and on, a normal Thai translation starting with “ขออภัย” is no longer mistaken for a Claude refusal, “งาน”/“นิ้ว” are no longer treated as land/length units in the number check, Slavic currency/degree wording is left to the voice, the system-voice refresh now also applies to languages already in use, and a not-yet-connected output device stays selected. (`disk_full`/`log_unavailable` reach the app as plain `error` events without a code.)
- **Engine round 21 (6):** more Whisper outro hallucinations are dropped in 12 languages, Claude's label prefixes (“**Translation:**”, “Traducción:”) are stripped, accented place and brand names (“Café Müller”) count as names, and the Thai romanizer is warmed up at start so the first Thai sentence is not delayed.
- **Engine round 21 (5):** laughter is recognised and answered in all 19 languages, temperatures are read aloud in 14 languages, question words for Polish/Turkish/Ukrainian/Indonesian/Hindi/Arabic choose the right Thai particle, forms of address for Chinese/Indonesian/Vietnamese/Arabic go to Claude, region codes like `en-US` or `pt_BR` are accepted for the language pair, a fresh connection that is reset is retried once, a Claude answer that drops nearly the whole sentence falls back to Google, and saving the conversation history no longer blocks level events.
- **Engine round 21 (4):** “Ja ja ja …” loops are shortened cleanly (and Thai laughter without inserted spaces), filler sounds are removed in Italian, Portuguese, Dutch, Polish, Turkish, Russian, Ukrainian, Hindi and Vietnamese, the number check understands feet, inches, ounces, gallons, rai, ngan and square wah (no false warnings for “6 feet” = “1.8 เมตร”), and the offline translator no longer loses lines when the helper answers in bursts.
- **Engine round 21 (3):** a number re-check now replaces the cached wrong translation, a changed Anthropic key in the environment is picked up without a restart, the cache file expires after 30 days unused, captive-portal hints carry a test URL, newly installed system voices are found within 10 minutes, damaged preset tuning values no longer abort a preset switch, and greetings like “Guten Morgen” are no longer mistaken for names.
- **Engine round 21 (2):** a full disk is detected before a model download, an unwritable log is reported once, Claude gets room for long sentences (and a changed key/limit counts correctly), refusals in German/Spanish/French/Thai are recognised, question words for Italian/Portuguese/Dutch/Russian pick the right Thai particle, yuan/won/rupee/ringgit amounts are checked like baht, longer Google requests via POST.
- **Engine round 21 (1):** phone numbers are read digit by digit, Thai text is never cut inside a character cluster when read aloud, more currency words and laughter forms for all languages, “volume three” works, oversized proxy replies are rejected, `Retry-After` dates are understood, and a key change really drops the old Claude client.
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

### iPhone app (round 21)

- **Travel helpers** (Baht calculator, new first row): tip and split the bill, convert °C/°F, km/mi and kg/lb, say the time in Thai (14:30 = บ่ายสองโมงครึ่ง) and read a phone number digit by digit in Thai for taxi drivers and receptionists.
- **Privacy:** "Delete all data" now also clears the Spotlight favourites; old CSV exports in the temp folder are removed on start; the online translators use a session without disk cache or cookies (the text of a sentence sits in the MyMemory URL); backup copies of damaged history files stay out of backups, are protected like the original and are limited to the newest three.
- **More travel helpers:** bargaining counter-offers (50–80 % of the asking price with the Thai number words) and today's date in Thai (Buddhist year).
- **Emergency card and allergy card are never translated online** (health data); they need the offline language pack. "Delete all data" also removes downloaded Whisper models. Going to the background no longer counts as a finished conversation; running translations are cancelled when a sentence is deleted; a hanging speech finalisation no longer blocks later sentences; downloading a language pack is noticed at once; "Load speech model" in the travel checklist no longer switches the microphone on.
- **Smoother and lighter:** transliteration and back-translation checks are computed once per sentence instead of on every redraw; speech voice lookups are cached; the voice of the language's own region wins over a higher-quality voice of another region (zh-CN vs zh-HK).
- **Battery:** silence is no longer fed to the speech recognisers (only speech plus a 0.7 s lead-in), which roughly halves idle CPU in automatic mode.
- **Phrasebook and emergency card without Thai in the pair:** the built-in English phrases are translated into the partner's language automatically (marked as unchecked); the emergency card lists the emergency numbers of the partner language's country (only numbers confirmed by several sources: ja, vi, id, de, fr, es; otherwise just a hint to ask locally) as a guide.
- **Language packs:** "Load all" and single downloads ask first when mobile data or a hotspot is active; the travel checklist rows keep their action buttons reachable for VoiceOver.
- **Phrase of the day** (Settings, optional): a local notification at 9 am for the next 7 days with a built-in Thai phrase; nothing leaves the phone. The phrasebook lists packs that fit the time of day first.
- **Smaller fixes:** several parts of the app can now listen to network changes at once; observers no longer hold the global model; flash cards keep their progress when you switch between ครับ and ค่ะ (old cards are migrated); "Replay the welcome" no longer waits a fixed 450 ms; tapping a favourite in Spotlight opens the phrasebook filtered to that phrase.
- **Whisper models** only count as installed when every Core ML model folder holds its data (an aborted download left empty folders).
- **Fixes:** a failed microphone start no longer leaves a tap that crashes the next start; "nan"/"inf" are no longer accepted as an amount; the list of dismissed flash cards is capped.
- **VoiceOver:** history rows, the big translation view and conversation lines are read with the voice of their own language.

### Web (round 19)

- **Phrasebook search** tolerates one typo per word (from four letters, Thai and English) and a new filter “Only important ⚠” shows just the critical sentences.

### Web (round 18)

- **Learning mode** (browser): daily goal with a progress bar (a calm line once it is reached, no streak pressure), listening drill (the sentence is read aloud, you type it; the answer ignores case and punctuation), “hard cards only” review (answered, still in box 1 or 2), space bar flips the card (1–4 grade), reduced motion respected, texts in German, English and Thai.

### Web (round 17)

- **Sharing and offline** (browser): text shared to the app stays in the input box and is translated as soon as the network is back; the full-screen view can share the translation as text (clipboard fallback); new “Satzbuch” app shortcut. Share target, offline banner and install hint were already in place.

### Web (round 16)

- **Own phrases and favourites** (browser): the “My cards” box now edits cards, adds an optional translation (via the existing translation chain, correctable by hand) and a group label with a group filter, keeps the 30-card limit, and reorders cards and starred favourites with up/down buttons (keyboard and screen-reader friendly, position announced). Cards export and import as JSON (validated: size limit, control characters removed, unknown fields and `__proto__` dropped, duplicates skipped). A full browser storage is reported instead of silently losing the change. Texts in German, English and Thai; `tests/test_runde16_web_favorites.py`.

### Mac app (round 21)

- **Sturdier helper processes**: a hanging Python helper is now killed after the timeout (SIGKILL fallback), the Python check no longer stalls on large output, and a failed start no longer leaves handlers behind (#116).
- **History window "Open"** now finds the main window (it was looked up by a title that no longer matched), un-minimizes it and brings it forward (#116).
- **Accessibility**: the stop button uses the accessible red, the level meter is logarithmic and marked as frequently updating, bubble actions for VoiceOver depend on context, banners are announced when their text changes, and the microphone-denied banner is announced (#116).
- **Quick phrases**: long phrases are truncated with the full text in the tooltip, duplicates are rejected, new phrases are limited to 200 characters, and the scroll bar stays visible (#116).
- **Partner view**: when turned around, the "again" and "slower" buttons and the stop notice turn with the text (#116).
- **Search** ignores diacritics; the glossary file is written with 0600 permissions and a failed save is shown; error details are redacted of the user name and home path (#116).
- **Wave 2** (#120): the microphone error banner clears itself when the microphone works again; the network-offline banner can be closed; "say" before the engine is ready is announced instead of silently dropped; broken engine output (20+ invalid lines) shows a notice; file translation has a Cancel button; the shortcut sheet lists the global shortcuts and resizes; Tips and shortcut sheets fit small windows; the Quit dialog asks again after an export; the HUD shows the real state after a hotkey; numbers and seconds use the Thai locale in the Thai UI; the history shows transcription lines and language names; a history reload no longer starts a second Python process while one is running; the setup script's stderr goes to `setup.log` (0600) and a cancelled setup is killed after 6 s; the empty-state example sentence also exists for German pairs.
- **Wave 3** (#125): typed draft, search text and language filter survive a UI-language switch; the toolbar has a third, very narrow variant (start + menu, status on its own line); the commands popover and Tips fit small windows; the stop-speaking tool has its own icon (muted speaker stays "mute"); a muted speaker is shown in orange; the typing field shows a visible placeholder while loading and a counter from 900 characters; ⌘↓ jumps to the newest bubble; bubbles get a visible focus ring and a warning icon for low confidence; the back-translation line keeps a minimum size; LLM models are shown with plain names; a hung engine is also restarted while "busy" after 4.5 minutes.
- **Wave 4** (#129): the hotkey HUD appears on the screen with the mouse pointer and has an accessibility label; "Undo delete" stays available for 15 seconds; quick phrases can be moved to the front from the context menu.
- **Wave 5** (#136): notice banners are capped in height (scrollable) so the conversation stays visible; the status line shows SF Symbols instead of emoji; a cancelled setup also stops uv/pip child processes; the engine pipe parser tolerates CRLF/BOM and resynchronises after an overlong line; the Claude key is passed to the engine over stdin (`api_key` control field, never logged) instead of the process environment; Settings has a separate "Advanced & privacy" tab; the Tips sheet has three pages with progress dots; sheets, the settings tab and search text survive a UI-language switch; real XCTest tests for the pure logic files (`cd swift-tests && swift test`).
- **Wave 6**: rolling captions (1-3 lines) in the caption window; a Settings switch to revoke the `dolmetscher://` permission; XCTest tests for glossary and export logic; fixes a slow-to-typecheck expression in the preset phrase bar.
- **Wave 7**: the scroll position of the conversation is restored after a UI-language switch; the history search ignores diacritics; 32 XCTest tests now also cover the history logic.
- **Wave 8**: exports spanning several days carry the date in every line; the ⌘= zoom shortcut only acts in the main window.
- **Wave 11** (#163, new features): the global shortcuts (⌃⌥ + letter) can be changed in Settings > Advanced & privacy, duplicates are refused and an invalid stored choice falls back to the defaults; a Mini window (⌥⌘M, floating) shows the status, the last translation and a start/stop button; the shortcut overview lists the current letters. Not done: volume ducking of other apps (macOS has no public per-app volume API that works without extra permissions).
- **Wave 12** (review fix): a text to be spoken (service, menu bar, clipboard) that arrives before the engine is ready is now queued and spoken once it is loaded instead of being dropped.
- **Wave 13** (new feature): quick phrases can be exported to a text file and imported (merged, duplicates skipped, 200 characters per line) in Settings.
- **Wave 14** (new feature): a history session can be exported as SRT subtitles (translation, then original, timed from the first line).
- **Wave 15** (new features): History statistics popover (utterances, sessions, words, last 7 days, most frequent sentences); the menu bar menu shows the median latency.
- **Wave 16** (new features): Phrasebook window searches all scenario phrases (English, Thai, scenario name) and speaks them; the Glossary editor suggests names and places from the current conversation; the scenario menu suggests scenarios by time of day; the bubble context menu has "Look up word" (system dictionary popover).
- **Wave 17** (review fix): name suggestions in the Glossary editor only scan the last 100 bubbles, so long sessions stay responsive.
- **Wave 9** (#155, new features): "Translate clipboard" (menu bar item and global shortcut ⌃⌥C; text is flattened, shortened to 1000 characters and spoken in the language of its script); the macOS fallback voice volume is clamped in one place and Settings explains that more than 100 % applies to the neural voice only; the diagnostic report is now in English for support; new XCTest tests for the clipboard and volume logic.
- **Wave 10** (new features): the system Services menu offers "Translate with Dolmetscher" for selected text in any app (`NSServices`, the text is spoken, not replaced); a single history session can be exported as Markdown with timestamps or as CSV; 40 XCTest tests.

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

**iPhone app (round 19)**
- **Fixed:** the audio session no longer rebuilds the microphone when only an output device (headphones without a microphone) comes or goes, the pause indicator no longer stays on “call” after stopping during an interruption, a route or configuration change during a call no longer triggers a failing restart, and the auto-stop timer does not run while a call or Siri holds the microphone. Listening resuming after an interruption is announced. Logic in `AudioSessionPolicy.swift` with tests, texts in all 10 languages (de/en/th by hand, the rest machine-translated).
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
- **Fixed:** content review of all packs (round 15): British spelling throughout, every note ends with the machine-translation remark, emergency sentences and the same sentence in several packs are marked `critical` consistently, German notes use Touristenpolizei and one fee figure; rules checked on all packs by `tests/test_runde15_presets_quality.py`.
- **New:** ten more packs: ferry-boat, island-hopping, snorkel-boat-tour, muay-thai-gym, buddhist-ceremony, rice-field-village, night-market-bargain, hostel-dorm, laundry-deposit, vegan-vegetarian (71 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: visa-extension, tax-refund, car-wash-repair, bicycle-rental, yoga-retreat, kids-playground, bakery-cafe, convenience-store-7eleven, post-office-parcel, wifi-coworking-cafe (81 in total; Thai machine-translated, not yet checked by a native speaker).
- **New:** ten more packs: bangkok-skytrain, food-allergy, grab-ride-hailing, food-delivery, floating-market, jet-ski-rental, animal-bite-rabies, travel-insurance-claim, flight-delay-change, monsoon-flood-storm (91 in total; Thai machine-translated, not yet checked by a native speaker).
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
- Engine round 21 (10): Offline-Helfer startet mit --pairs, Helfer-Fehlertexte vor dem Log bereinigt, Ortsnamen-Schutz beachtet Groß-/Kleinschreibung.
- Engine round 21 (11): Fixes aus dem dritten Review (Thai-Partikel, Sprechform an Thai-Grenzen, Zahlenvergleich BE-Jahr/Maßstab/Bereiche, $1.5 million, Refusal-Filter, Cache-Race), Übersetzerreihenfolge per --mt-order/DOLMETSCHER_MT_ORDER.
