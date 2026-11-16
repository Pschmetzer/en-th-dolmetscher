# Dolmetscher for iPhone

Native SwiftUI app: press Start and just talk. It interprets between *My language* and *Partner's language* (default English ⇄ Thai, 19 languages, see the [main README](../README.md#languages)). It does not use the Python engine of the Mac app.

- Recognition: Apple's on-device speech recognition (`SpeechAnalyzer`, one recognizer per language on the same audio), optionally Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit) 1.1.1.
- Translation: Apple's Translation framework on the device; Google Translate / MyMemory only if “Online translator as fallback” is switched on (off by default).
- Voice: iOS system voices.
- Privacy: [docs/DATENSCHUTZ.md](../docs/DATENSCHUTZ.md#iphone-app-ios) (German), `Dolmetscher/PrivacyInfo.xcprivacy`.

## Requirements

- Xcode 26 or newer on a Mac, an iPhone with iOS 26 or newer.
- A free Apple ID is enough to run it on your own iPhone (apps signed with a free account expire after 7 days and have to be installed again from Xcode).
- Swift packages are resolved by Xcode on first open (WhisperKit, pinned in `Package.resolved`).

## Build and run on your iPhone

1. `open ios/Dolmetscher.xcodeproj`
2. Xcode → Settings → Accounts: add your Apple ID.
3. Select the target **Dolmetscher** → *Signing & Capabilities*:
   - *Team*: your (personal) team. The project has no team set, so this is always needed.
   - *Bundle Identifier*: change `io.github.dolmetscher.en-th.ios` to something unique, e.g. `com.yourname.dolmetscher`. A personal team cannot use an identifier that is already registered by someone else.
4. Connect the iPhone, select it as run destination and press **Run** (⌘R). On the iPhone, the first time: Settings → General → VPN & Device Management → trust your developer certificate, and turn on Developer Mode if iOS asks for it.
5. Allow microphone and speech recognition when the app asks.

**Entitlement `increased-memory-limit`.** `Dolmetscher.entitlements` requests more memory for larger Whisper models. If Xcode reports a provisioning error about this entitlement with your team, you can remove the key from `Dolmetscher.entitlements` (or set *Code Signing Entitlements* to empty). The app works without it; only the larger Whisper models may then run out of memory.

**Offline translation.** For translation on the device, install the language packs: in the app's settings (download button for the current pair) or in iOS Settings → Apps → Translate → Downloaded Languages.

## Whisper models (optional)

In the settings: “Use Whisper (experimental)”, pick a model and tap “Download model”. Whisper only shows whole sentences after the pause (no live text) and uses more battery and memory than Apple's recognition.

- The list comes from WhisperKit's table of models supported on this device (no network for that); the preselection is WhisperKit's recommendation. English-only (`.en`) and distil models are left out.
- Models are downloaded **only when you tap download** from Hugging Face (`argmaxinc/whisperkit-coreml`), with size, progress, a Wi-Fi hint and cancel. After the download the model is loaded once, which also fetches the tokenizer and lets Core ML prepare the model for the device; after that no network is needed.
- Stored in the app's Application Support folder under `whisper/`, excluded from iCloud backup. Installing another model deletes the previous one; “Delete” removes models, tokenizer and cache.
- Unlike the Mac app, the model is not pinned to a fixed revision.
- Without a complete model (or if it fails to load) the app falls back to Apple's recognition and says so.
- Small models (tiny/base) are fine for English but weak for Thai.

## Debug switches

Only in **Debug** builds (`#if DEBUG`), ignored in Release. Set them in Xcode (*Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables*) or, for the Simulator, with the `SIMCTL_CHILD_` prefix:

| Variable | Effect |
|---|---|
| `DOLMETSCHER_AUDIO_FILES` | Colon-separated list of audio files that are played into the recognizer instead of the microphone (the Simulator often has no microphone). |
| `DOLMETSCHER_AUTOSTART` | Any value: press Start automatically after launch. Meant for use together with `DOLMETSCHER_AUDIO_FILES`. |
| `DOLMETSCHER_LOG_LANGS` | Any value: writes what this device supports per language (recognition, translation, voice) to the log, subsystem `dolmetscher`, category `langs`. |

```sh
SIMCTL_CHILD_DOLMETSCHER_AUDIO_FILES=/path/a.wav:/path/b.wav SIMCTL_CHILD_DOLMETSCHER_AUTOSTART=1 \
  xcrun simctl launch booted io.github.dolmetscher.en-th.ios
xcrun simctl spawn booted log stream --predicate 'subsystem == "dolmetscher"'   # app log
```

Simulator limits: Apple's Translation framework does not work there, so translations always use the web translator (switch on “Online translator as fallback”). Whisper output in the Simulator is unreliable (Core ML); test Whisper on a real iPhone.

## Tests

```sh
xcodebuild test -project ios/Dolmetscher.xcodeproj -scheme Dolmetscher \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Unit tests live in `DolmetscherTests/` (`LogicTests`, `PairTests`, `WhisperLogicTests`, `FixTests`, `L10nTests`). CI runs the same in `.github/workflows/ios.yml` (device build without signing plus Simulator tests).

## Localisation

The interface is available in de, en, th, es, fr, ja, ko, zh-Hans, vi and id (`L10n.swift`, `L10n+Extra.swift`, permission texts in `*.lproj/InfoPlist.strings`). The app picks the first preferred device language it supports; Traditional Chinese gets English. The wake word and voice commands (“Translator, pause”) stay English on purpose. **es, fr, ja, ko, zh-Hans, vi and id are machine-translated and not reviewed by native speakers.** `L10nTests` checks that every key exists in all languages.

## App Store texts

`AppStore/<locale>/` holds the store listing for en-US, de-DE, th, es-ES, fr-FR, ja, ko, zh-Hans, vi and id:

| File | Limit |
|---|---|
| `name.txt` | 30 characters |
| `subtitle.txt` | 30 |
| `keywords.txt` | 100 |
| `promotional_text.txt` | 170 |
| `description.txt` | 4000 |

`L10nTests.testAppStoreTexts` checks that all files exist, are not empty and stay within these limits. All texts except en-US are machine-translated (including German and Thai) and must be reviewed before submitting. The app has not been submitted to the App Store yet.
