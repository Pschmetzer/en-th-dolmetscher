# Contributing

Thanks for helping! Issues and pull requests are welcome.

## Layout

- `dolmetscher.py` – engine (microphone → VAD → faster-whisper → translation → voice). `--json` emits events for the app.
- `profiles.py` – voice profiles (speaker recognition).
- `presets.py`, `presets/*.json` – scenario presets and phrase packs (data). `history_store.py` – optional local conversation history. `hwprofile.py` – picks a model for `--model auto`. `correction_learning.py` – suggestions from corrected bubbles.
- `app/*.swift` – SwiftUI Mac app that starts the engine (`Engine.swift`: process and protocol, `Views.swift`/`BubbleViews.swift`/`SettingsView.swift`: UI, `L10n.swift`: de/en/th strings). Built by `build.sh` with `swiftc` (all Swift files in `app/`). `app/make_icon.py` draws the icon.
- `build-support/` – entitlements for the release build, `setup-env.sh` (the app's first-start environment setup with the bundled uv) and `make-stamp.sh` (environment stamp: lock hash, Python version, architecture).
- `ios/` – separate iPhone app (Xcode project, own CI workflow `ios.yml`); it does not use the Python engine. Build, signing, Whisper models and debug switches: [ios/README.md](ios/README.md).
- `avhelper.py` – audio via PyAV (microphone, playback, microphone list) as a child process; replaces the external ffmpeg.
- `CHANGELOG.md` – user-facing changes; add a line under *Unreleased* for anything a user would notice.
- `docs/PROTOKOLL.md` – JSON protocol between app and engine (events on stdout, settings on stdin).
- `docs/ARCHITEKTUR.md` – process model, threads, states, demo mode. `docs/DATENSCHUTZ.md` – what leaves the Mac, when and to whom (update it when you add a network call).
- `index.html` – browser version (Web Lite, GitHub Pages); `sw.js`, `manifest.webmanifest`, `presets-index.json`, `allergens.json` belong to it. How it works and how to test it: the “Web Lite” section of `docs/ARCHITEKTUR.md`; browser checklist: `docs/WEB-KOMPATIBILITAET.md`; self-hosting: `docs/WEB-HOSTING.md`.
- `bench/` – latency and quality benchmark, see [bench/README.md](bench/README.md).
- `tests/` – pytest tests.
- `tools/` – prototypes for Apple's on-device speech recognition and translation (macOS 26, not part of the Mac app).
- `docs/LIZENZEN.md` – licenses of models, packages and services.

## Without a Mac (presets, web, docs)

Presets, the web page and the docs need no Mac. `make test-web` (Python + node), `make lint`, `make presets-index`, or open the repo in a Dev Container / Codespace (`.devcontainer/`). `pre-commit install` adds local hooks (ruff, JSON check, `node --check sw.js`, shellcheck, presets index). When you change a file that the service worker caches, bump `CACHE` in `sw.js`. Pull requests that touch the app, web, presets or engine need a `CHANGELOG.md` entry (or the `no-changelog` label); the `Changelog` workflow checks it.

## Development setup

You need Python 3.12 or newer – the lock files are resolved for 3.12. The easiest way is [uv](https://docs.astral.sh/uv/), which you need for `build.sh` anyway and which downloads Python 3.12 by itself (`brew install python@3.12` works too; the macOS system Python 3.9 is too old). The engine code itself stays compatible with 3.10 (CI checks it with unpinned packages).

```bash
uv venv --python 3.12 .venv && . .venv/bin/activate     # or: python3.12 -m venv .venv && . .venv/bin/activate
uv pip install --require-hashes -r requirements-dev.txt  # or: pip install --require-hashes -r requirements-dev.txt
pytest
ruff check ./*.py bench/ tests/                         # same paths as CI
```

Ruff settings are in `pyproject.toml` (E, F, W, line length 120; the compact one-line style is allowed).

`tests/conftest.py` keeps every test from writing to the real `engine.log`. Coverage (optional): `pytest --cov=dolmetscher --cov=profiles` (`pytest-cov` is in `requirements-dev.txt`).

The tests import `dolmetscher.py` directly. They need no Whisper model, no network and no microphone. Keep it that way: importing `dolmetscher` must not load models or touch devices. Put new logic into small pure functions so it can be tested.

The wake word logic lives in `match_wake()` in `dolmetscher.py`; `Engine` and `tests/test_commands.py` both call it, so the tests follow any change automatically. Add real misheard phrases from `~/Library/Logs/Dolmetscher/engine.log` as test cases (no personal content). The log contains conversation text only if the engine ran with `--log-text` (off by default).

Tests must never call the Claude API or need a key. `anthropic` is optional: the engine has to start and translate (via Google) without it.

Dependencies: direct pins live in `requirements.in` / `requirements-dev.in`. `requirements.txt` and `requirements-dev.txt` are generated lock files with every transitive package and its hashes; `build.sh` and CI install them with `--require-hashes`. Never edit the `.txt` files by hand. To bump a version, change the `.in` file and regenerate both locks (needs [uv](https://docs.astral.sh/uv/)):

```bash
uv pip compile requirements.in --universal --python-version 3.12 --generate-hashes -o requirements.txt
uv pip compile requirements-dev.in -c requirements.txt --universal --python-version 3.12 --generate-hashes -o requirements-dev.txt
```

Then check that `faster_whisper.audio.decode_audio` still works (PyAV 19 broke it) and the app still runs, e.g. in a fresh venv: `uv venv --python 3.12 .chk && uv pip install --python .chk/bin/python --require-hashes -r requirements-dev.txt && .chk/bin/python -m pytest`. Dependabot proposes bumps; if its PR only touches one file, regenerate the locks as above before merging.

Speech models are loaded at a fixed Hugging Face revision (`MODEL_REVISIONS` in `dolmetscher.py`, used by the engine and by `build.sh`). To move to a newer model version, look up the commit SHA (`https://huggingface.co/api/models/<repo>` → `sha`), check the model card and license ([docs/LIZENZEN.md](docs/LIZENZEN.md)), update the constant and rerun the benchmark.

`pythainlp` is optional at runtime (Thai transliteration); the engine must work without it, but it is pinned in `requirements.txt`, so the tests run with it. Type-check the Swift app locally without building: `swiftc -typecheck -parse-as-library app/*.swift` (CI does the same on macOS).

If you change events or settings between app and engine, update `docs/PROTOKOLL.md`.

## Pull requests

- CI (GitHub Actions) runs the tests (Python 3.12 with the hash-locked versions, Python 3.10 with unpinned ones; `-rs` lists why tests were skipped), ruff, shellcheck for `build.sh`, a Swift typecheck and compile, and a non-blocking `pip-audit` over all locked packages (including transitive ones). The iPhone app has its own workflow (`ios.yml`). Ruff is blocking for all Python modules in the top folder, `bench/` and `tests/`. Every job has a `timeout-minutes` limit, so a hanging test fails the run instead of blocking a runner for hours. Tests, ruff, shellcheck and compile must be green. Dependabot proposes updates for the Actions and the pinned Python packages weekly.
- Machine-translated UI text is marked as such: the iPhone strings in es, fr, ja, ko, zh-Hans, vi and id and the App Store texts in `ios/AppStore/` (all locales except en-US) are unreviewed. Native-speaker reviews are very welcome.
- Thai text (UI strings in `app/L10n.swift`, the phrases and glossaries in `presets/*.json`, the Thai parts of `bench/cases.json`, voice-guide texts): have a Thai speaker review it before merging, or say in the PR that it is machine-translated and unreviewed. Native review matters most for politeness particles (ครับ/ค่ะ), formal vs. casual register and anything shown to a Thai speaker without an English fallback.
- Run `./build.sh --install` and try the app with a real conversation for changes to the engine or the app.
- Don't commit personal paths, names, email addresses or logs.

## Stable code signing

By default `build.sh` signs the app ad hoc. macOS ties the microphone permission to the signature, so it may ask again after each rebuild. With a stable identity it only asks once:

1. Open Keychain Access → menu Keychain Access → Certificate Assistant → Create a Certificate…
   Name e.g. `Dolmetscher Dev`, Identity Type *Self Signed Root*, Certificate Type *Code Signing*. Keep it in the *login* keychain.
2. Check that macOS sees it: `security find-identity -v -p codesigning` should list `Dolmetscher Dev`.
3. Build with it: `DOLMETSCHER_SIGN_IDENTITY="Dolmetscher Dev" ./build.sh --install`. The first time, macOS asks whether `codesign` may use the key: choose *Always Allow*.
4. Once after switching from ad hoc signing: `tccutil reset Microphone io.github.dolmetscher.en-th`, start the app and allow the microphone. From then on rebuilds keep the permission.

The certificate only works on your Mac and is not a Developer ID: it does not make the app trusted for other people. `build.sh` never creates certificates or changes the keychain itself. If signing with the given identity fails, it falls back to ad hoc signing (the app runs, macOS may ask for the microphone again). The app is signed without `--deep`, since the bundle has no nested code.

## Release build

`./build.sh --release` needs a **Developer ID Application** certificate in your keychain and `DOLMETSCHER_SIGN_IDENTITY` set to its name; without it the script stops (no ad hoc fallback). It signs with the hardened runtime (`--options runtime --timestamp`) and the entitlements in `build-support/Dolmetscher.entitlements` (microphone access), verifies the signature and writes `build/Dolmetscher-<version>.zip` and `…zip.sha256`. If `DOLMETSCHER_NOTARY_PROFILE` names a `notarytool` keychain profile (`xcrun notarytool store-credentials`), the app is notarized and stapled first. The version comes from `pyproject.toml`, the build number from the number of Git commits. Bump the version in `pyproject.toml` only, then tag `v<version>`.

The bundle is self-contained (Apple Silicon only): `Contents/Helpers/uv` (the pinned `UV_VERSION` from `build.sh`; its minimum macOS is checked against `LSMinimumSystemVersion`) is signed first with the hardened runtime, then the app; `codesign --verify --deep --strict` checks both. Entitlements: only `com.apple.security.device.audio-input` – without it the microphone delivers silence under the hardened runtime. Python runs as a separate process with its own signature, so `disable-library-validation` is not needed (the app process loads no Python libraries). `PYTHONPYCACHEPREFIX` keeps `.pyc` files out of the bundle. Test a release build on a Mac without Homebrew/Python: the setup screen must appear, set up the environment and download the models (setup log: `~/Library/Application Support/Dolmetscher/setup.log`).

The `Release` workflow in GitHub Actions only builds an unsigned ZIP with a SHA256 file as a workflow artifact; it has no signing secrets.

### Release checklist

1. Version in `pyproject.toml` bumped; *Unreleased* in `CHANGELOG.md` renamed to the version and date; CI green on `main`.
2. Benchmark against the baseline on an otherwise idle Mac (needs models, `say` and network, so it does not run in CI):
   `python bench/run_bench.py --model medium --device cpu --repeat 3 --compare bench/results/baseline_main.json --fail-above 10`.
   If a model, `MODEL_REVISIONS`, the metric or `bench/cases.json` changed on purpose, replace the baseline in the same PR and say why.
3. `./build.sh --install` and a short real conversation (both languages, one voice command).
4. `--release` build, tag `v<version>`.

## Benchmarks

`python bench/run_bench.py --repeat 5` reports median and p95 times and stores device and package versions in the JSON. `--compare baseline.json --fail-above 10` exits with code 2 if a metric is more than 10 % worse than the baseline. The test clips are synthetic voices; read the limits in [bench/README.md](bench/README.md) before quoting numbers.

## License

By contributing you agree that your contribution is licensed under the MIT License.
