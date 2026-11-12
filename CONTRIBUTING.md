# Contributing

Thanks for helping! Issues and pull requests are welcome.

## Layout

- `dolmetscher.py` – engine (microphone → VAD → faster-whisper → translation → voice). `--json` emits events for the app.
- `app/DolmetscherApp.swift` – SwiftUI shell that starts the engine. Built by `build.sh` with `swiftc`.
- `index.html` – browser version (GitHub Pages).
- `tests/` – pytest tests.

## Development setup

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

The tests import `dolmetscher.py` directly. They need no Whisper model, no network and no microphone. Keep it that way: importing `dolmetscher` must not load models or touch devices. Put new logic into small pure functions so it can be tested.

If the wake word / command logic in `Engine` changes, update the `detect()` helper in `tests/test_commands.py`. Add real misheard phrases from `~/Library/Logs/Dolmetscher/engine.log` as test cases (no personal content).

Dependencies are pinned in `requirements.txt`. When you bump a version, check that `faster_whisper.audio.decode_audio` still works (PyAV 19 broke it) and the app still runs.

## Pull requests

- CI (GitHub Actions, macOS) runs the tests and compiles the Swift app. It must be green.
- Run `./build.sh --install` and try the app with a real conversation for changes to the engine or the app.
- Don't commit personal paths, names, email addresses or logs.

## Stable code signing

By default `build.sh` signs the app ad hoc. macOS ties the microphone permission to the signature, so it may ask again after each rebuild. With a stable identity it only asks once:

1. Keychain Access → Certificate Assistant → Create a Certificate… Name e.g. `Dolmetscher Dev`, Identity Type *Self Signed Root*, Certificate Type *Code Signing*.
2. `DOLMETSCHER_SIGN_IDENTITY="Dolmetscher Dev" ./build.sh --install`

`build.sh` never creates certificates itself. If signing with the given identity fails, it falls back to ad hoc signing.

## License

By contributing you agree that your contribution is licensed under the MIT License.
