# Quick start

Three ways, depending on your device. More on everything: [README.md](../../README.md). Problems: [TROUBLESHOOTING.md](TROUBLESHOOTING.md). German version: [SCHNELLSTART.md](../SCHNELLSTART.md).

## Mac (Apple Silicon, macOS 14 or newer)

There is no ready-made download yet; you build the app from source.

1. Requirements: a Mac with Apple Silicon (M1 or later, no Intel), the Xcode Command Line Tools (`xcode-select --install`) and [uv](https://docs.astral.sh/uv/) (`brew install uv`). Homebrew Python and ffmpeg are not needed.
2. Get the code: `git clone https://github.com/Pschmetzer/en-th-dolmetscher.git`, then open the folder in Terminal.
3. Build and install: `./build.sh --install`. This installs `~/Applications/Dolmetscher.app` and, on the build Mac, downloads the speech models (`medium`, `small` and the Thai model, about 3.5 GB in total, once).
4. Open the app, press **Start** (or the space bar) and allow microphone access.
5. Talk. The app detects which of the two languages is spoken (default: English and Thai), translates and reads aloud. Language pair, microphone and voices are in the settings.

**First start on another Mac:** if you copy the app to a Mac without the Python environment, a setup screen opens. It shows the download size and free disk space, downloads its own Python 3.12, the packages and the models (with progress bars), and can be cancelled and retried. It needs internet.

Shortcuts: [SHORTCUTS.md](SHORTCUTS.md). Voice commands ("Translator, ..."): [VOICE-COMMANDS.md](VOICE-COMMANDS.md).

## iPhone / iPad (iOS 26 or newer)

There is no App Store version either; you build the app yourself, a free Apple ID is enough. Details: [ios/README.md](../../ios/README.md).

1. Xcode 26 or newer on a Mac. `open ios/Dolmetscher.xcodeproj`.
2. Xcode, Settings, Accounts: add your Apple ID.
3. Target **Dolmetscher**, Signing & Capabilities: choose your team and change the bundle identifier (`com.pschmetzer.dolmetscher`) to something unique.
4. Connect the iPhone, select it as destination, Run (⌘R). The first time on the iPhone: Settings, General, VPN & Device Management, trust your developer certificate; turn on Developer Mode if iOS asks.
5. Allow microphone and speech recognition, press Start, talk.

Translation runs on the device once the offline language packs for your pair are installed. If one is missing, text only goes online when "Online translator as fallback" is on (default: off). With a free account, self-built apps expire after 7 days and must be installed again from Xcode.

## Browser (Web Lite)

No installation: open <https://pschmetzer.github.io/en-th-dolmetscher/> in **Chrome** (Firefox has no speech recognition; Safari works only with dictation switched on and with limits).

1. Agree once before the first microphone start and allow microphone access in the browser.
2. Pick the languages (default: English and Thai).
3. Choose who speaks yourself: **E** (or 1) for your language, **T** (or 2) for the other person's, **Space** ends. The page does not detect the language automatically.
4. Optional: "Add to home screen" (PWA). The page and the phrasebook then also open offline; translation needs the network.

Run locally: `python3 -m http.server` in the repo folder, then open it in Chrome. Self-hosting: [WEB-HOSTING.md](../WEB-HOSTING.md) (German). What the page can and cannot do: [WEB-KOMPATIBILITAET.md](../WEB-KOMPATIBILITAET.md) (German).
