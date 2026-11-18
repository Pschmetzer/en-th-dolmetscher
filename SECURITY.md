# Security policy

## Supported versions

Only the latest version on `main` (and the latest release, if there is one) gets security fixes. The current version is in `pyproject.toml`.

| Component | Supported |
|---|---|
| Mac app and engine (`app/`, `dolmetscher.py`) | latest `main` |
| iPhone / iPad app (`ios/`) | latest `main` |
| Browser version (Web Lite, GitHub Pages) | the deployed version |

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report it privately through GitHub: **Security → Report a vulnerability** on this repository (private vulnerability reporting). If that is not available, open an issue that only says you have a security report and would like a private contact, without any details.

Helpful to include:

- what is affected (Mac app, engine, iPhone app, browser version, build scripts),
- the steps to reproduce, and the version or commit,
- what an attacker could do with it.

Please leave out real conversation text, voice recordings and logs with personal content.

This is a small volunteer project: expect a first answer within about a week. Once a fix is ready, it is released and the report is credited, unless you prefer to stay anonymous.

## What counts

Especially interesting, because the app handles speech and conversation text:

- conversation text, voice profiles (biometric data), the conversation history or the Anthropic API key leaving the device in a way [docs/DATENSCHUTZ.md](docs/DATENSCHUTZ.md) does not describe,
- files in `~/Library/Application Support/Dolmetscher/` readable by other users,
- code execution through presets, imported files, the JSON protocol between app and engine, or the first-start environment setup (downloaded packages and models are hash- or checksum-verified),
- cross-site scripting or similar in the browser version.

Out of scope: problems in the third-party translation and voice services themselves (Google, MyMemory, Microsoft, Anthropic) and translations that are wrong but harmless. Please report wrong or impolite translations as normal issues.
