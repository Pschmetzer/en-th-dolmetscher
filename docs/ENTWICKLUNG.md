# Einstieg für Mitwirkende

Für den ersten Pull request: einrichten, die Ordner kennen, wissen, was man nach einer Änderung prüft. Die Regeln
(Lock-Dateien, Signieren, Thai-Review) stehen in [CONTRIBUTING.md](../CONTRIBUTING.md), die Technik in [ARCHITEKTUR.md](ARCHITEKTUR.md).

## In 10 Minuten startklar (ohne Mac)

```bash
git clone https://github.com/Pschmetzer/en-th-dolmetscher && cd en-th-dolmetscher
python3 -m venv .venv && . .venv/bin/activate
pip install --require-hashes -r requirements-dev.txt     # Python 3.12 oder neuer
tools/check_all.sh --docs                                # Sekunden: Doku, Changelog, Versionen, Workflows
make test                                                # alle Tests ohne Marker "macos" (keine Modelle, kein Netz)
```

Ohne Python-Einrichtung geht auch der Dev-Container (`.devcontainer/`) oder ein Codespace. Für die Mac-App brauchst du
macOS 14 und Xcode-Werkzeuge (`./build.sh --install`), für die iPhone-App Xcode ([../ios/README.md](../ios/README.md)).

## Wo liegt was?

| Du willst … | Dann schau in … |
|---|---|
| die Erkennung, Übersetzung oder Sprachausgabe ändern | `dolmetscher.py` und die kleinen Module daneben (`numwords.py`, `textsplit.py`, `thaiparticles.py`, `retryafter.py`, `llmtext.py`, `sttquality.py`) |
| Ereignisse oder Einstellungen zwischen App und Engine ändern | `dolmetscher.py` **und** `app/Engine.swift`, dazu [PROTOKOLL.md](PROTOKOLL.md) |
| ein Phrasenpaket hinzufügen oder korrigieren | `presets/*.json` ([PRESETS.md](PRESETS.md#ein-paket-beitragen)), danach `make presets-index` |
| die Web-Version ändern | `index.html`, `sw.js`, `i18n/*.json`; danach `python3 tools/sync_web.py` |
| die Mac-App ändern | `app/*.swift`; neue Logik als reine Funktionen (testbar) |
| die iPhone-App ändern | `ios/` |
| Doku, CI oder Werkzeuge ändern | `docs/`, `.github/`, `tools/` ([CI.md](CI.md)) |
| eine neue Sprache oder UI-Text | `languages.json`, `i18n/`, `app/L10n.swift`, `ios/` (alle Oberflächen gleichzeitig) |

## „Ich ändere X, also prüfe ich Y“

| Änderung | Prüfung vor dem Pull request |
|---|---|
| Python-Code | `ruff check ./*.py bench/ tests/ tools/` und `pytest -m "not macos"` |
| `presets/*.json` | `python3 tools/check_presets.py --strict`, `python3 tools/preset_lint.py`, `python3 tools/make_presets_index.py`, `python3 tools/sync_web.py` |
| Web-Dateien, die der Service Worker speichert | `python3 tools/sync_web.py` (erhöht `CACHE`), `make test-web`, Checkliste [WEB-KOMPATIBILITAET.md](WEB-KOMPATIBILITAET.md) |
| neuer Netzaufruf (egal wo) | [DATENSCHUTZ.md](DATENSCHUTZ.md) ergänzen, in der Tabelle „Verlässt den Mac“ |
| neues Ereignis, Argument oder Steuerfeld | [PROTOKOLL.md](PROTOKOLL.md); `tests/test_protocol_docs.py` prüft die Übereinstimmung |
| Swift-Dateien | `swiftc -typecheck -parse-as-library app/*.swift` (nur Mac) |
| Markdown, Workflows, Changelog | `make docs-check` |
| alles zusammen | `tools/check_all.sh` |

Das Label `no-changelog` am Pull request genügt, wenn Anwender nichts merken (Doku, CI, Werkzeuge, Tests). Sonst eine Zeile
unter *Unreleased* in `CHANGELOG.md`.

## Typische Aufgaben

**Neues Protokollereignis.** In `dolmetscher.py` mit `emit("name", …)` senden, in `app/Engine.swift` verarbeiten (unbekannte
Ereignisse werden ignoriert, die App darf also nie darauf angewiesen sein), in [PROTOKOLL.md](PROTOKOLL.md) unter
„Ereignisse“ mit Feldern beschreiben, einen Test in `tests/` ergänzen.

**Neues Werkzeug in `tools/`.** Ein Skript, nur Standardbibliothek, Docstring mit Aufruf und Exit-Codes, Logik in kleinen
Funktionen, `main(argv=None)`. Ein Test lädt es mit `importlib` (Beispiel: `tests/test_r29_infra_docs.py`). In
[CI.md](CI.md) und, falls es eine Prüfung ist, in `tools/check_all.sh` eintragen.

**Neue Doku.** Datei in `docs/` anlegen, in [README.md](README.md) (Landkarte) verlinken. Relative Links, keine
persönlichen Pfade, Namen oder Adressen. `make docs-check` meldet tote Links und fehlende Einträge.

**Fehler nachstellen.** Ein Test, der ohne den Fix scheitert, gehört in denselben Pull request. Echte Beispiele
(falsch verstandene Wake-Wörter, Texte) ohne Personenbezug.

## Häufige Stolpersteine

- `tests/test_env_logic_swift.py` und `tests/test_setup_env.py` brauchen einen Apple-Silicon-Mac; sonst
  `make test PYTEST_ARGS="--ignore=tests/test_env_logic_swift.py --ignore=tests/test_setup_env.py"`.
- `requirements*.txt` nie von Hand ändern (Hashes), siehe [CONTRIBUTING.md](../CONTRIBUTING.md).
- Der Service Worker liefert alte Dateien aus, bis `CACHE` erhöht ist: nach Web-Änderungen immer `sync_web.py`.
- Konflikte im `CHANGELOG.md` entstehen, wenn mehrere Pull requests unter *Unreleased* schreiben: beide Einträge behalten.
- Parallel arbeitende Pull requests: vor dem Zusammenführen `origin/main` einmergen und `make docs-check` wiederholen.
