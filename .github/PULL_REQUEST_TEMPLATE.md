## What and why

<!-- What does this change, and why? Link the issue if there is one (Fixes #123). -->

## Affected parts

- [ ] Engine (`dolmetscher.py` and other Python modules)
- [ ] Mac app (`app/`)
- [ ] iPhone / iPad app (`ios/`)
- [ ] Browser version (`index.html`, `sw.js`)
- [ ] Phrase packs / presets (`presets/`)
- [ ] Docs, CI or tooling only

## Checklist

- [ ] Tests pass locally (`pytest`, or `make test-web` for the browser version) and `ruff` is clean
- [ ] `CHANGELOG.md` has a line under *Unreleased* for anything a user would notice (or the PR has the `no-changelog` label)
- [ ] For files the service worker caches: `CACHE` in `sw.js` is bumped
- [ ] For a new network call: [docs/DATENSCHUTZ.md](../docs/DATENSCHUTZ.md) is updated
- [ ] Thai or other non-English text is reviewed by a native speaker, **or** marked here as machine-translated and unreviewed
- [ ] For engine or Mac app changes: tried with `./build.sh --install` and a real conversation
- [ ] No personal paths, names, email addresses, recordings or logs committed

## How to test

<!-- Steps a reviewer can follow. Screenshots help for UI changes. -->
