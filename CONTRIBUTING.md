# Contributing

Thanks for helping! Issues and pull requests are welcome.

## Layout

- `dolmetscher.py` – engine (microphone → VAD → faster-whisper → translation → voice). `--json` emits events for the app.
- `profiles.py` – voice profiles (speaker recognition).
- `app/*.swift` – SwiftUI app that starts the engine. Built by `build.sh` with `swiftc` (all Swift files in `app/`).
- `docs/PROTOKOLL.md` – JSON protocol between app and engine (events on stdout, settings on stdin).
- `docs/ARCHITEKTUR.md` – process model, threads, states, demo mode. `docs/DATENSCHUTZ.md` – what leaves the Mac, when and to whom (update it when you add a network call).
- `index.html` – browser version (Web Lite, GitHub Pages).
- `bench/` – latency and quality benchmark, see [bench/README.md](bench/README.md).
- `tests/` – pytest tests.

## Development setup

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
pytest
ruff check dolmetscher.py profiles.py bench/
```

Ruff settings are in `pyproject.toml` (E, F, W, line length 120; the compact one-line style is allowed).

`tests/conftest.py` keeps every test from writing to the real `engine.log`. Coverage (optional): `pytest --cov=dolmetscher --cov=profiles` (`pytest-cov` is in `requirements-dev.txt`).

The tests import `dolmetscher.py` directly. They need no Whisper model, no network and no microphone. Keep it that way: importing `dolmetscher` must not load models or touch devices. Put new logic into small pure functions so it can be tested.

If the wake word / command logic in `Engine` changes, update the `detect()` helper in `tests/test_commands.py`. Add real misheard phrases from `~/Library/Logs/Dolmetscher/engine.log` as test cases (no personal content). The log contains conversation text only if the engine ran with `--log-text` (off by default).

Tests must never call the Claude API or need a key. `anthropic` is optional: the engine has to start and translate (via Google) without it.

Dependencies are pinned in `requirements.txt`. When you bump a version, check that `faster_whisper.audio.decode_audio` still works (PyAV 19 broke it) and the app still runs. Check the pins resolve together in a fresh venv, e.g. `uv venv /tmp/chk && uv pip install --dry-run --python /tmp/chk/bin/python -r requirements-dev.txt`.

`pythainlp` is optional at runtime (Thai transliteration); the engine must work without it, but it is pinned in `requirements.txt`, so the tests run with it. Type-check the Swift app locally without building: `swiftc -typecheck -parse-as-library app/*.swift` (CI does the same on macOS).

If you change events or settings between app and engine, update `docs/PROTOKOLL.md`.

## Pull requests

- CI (GitHub Actions) runs the tests (Python 3.12 with the pinned versions, Python 3.10 with unpinned ones), ruff, shellcheck for `build.sh`, a Swift typecheck and compile, and a non-blocking `pip-audit`. Ruff is blocking for `bench/` and `tests/conftest.py`; for the engine and the older tests it only reports (known E501/E741 findings). Tests, shellcheck and compile must be green. Dependabot proposes updates for the Actions and the pinned Python packages weekly.
- Thai text (UI strings in `app/L10n.swift`, the Thai parts of `bench/cases.json`, voice-guide texts): have a Thai speaker review it before merging, or say in the PR that it is machine-translated and unreviewed. Native review matters most for politeness particles (ครับ/ค่ะ), formal vs. casual register and anything shown to a Thai speaker without an English fallback.
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

The `Release` workflow in GitHub Actions only builds an unsigned ZIP with a SHA256 file as a workflow artifact; it has no signing secrets.

## Benchmarks

`python bench/run_bench.py --repeat 5` reports median and p95 times and stores device and package versions in the JSON. `--compare baseline.json --fail-above 10` exits with code 2 if a metric is more than 10 % worse than the baseline. Details: [bench/README.md](bench/README.md).

## License

By contributing you agree that your contribution is licensed under the MIT License.
