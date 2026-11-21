# CI: Workflows, lokal nachstellen, Zwischenspeicher

Alle Workflows liegen in `.github/workflows/`. Regeln für alle (geprüft von `tools/check_workflows.py`, `actionlint` und
`zizmor` im Job „Workflow-Lint“):

- Fremde Actions sind auf einen **Commit-SHA** festgelegt, dahinter steht die Version als Kommentar. Dependabot hebt sie an.
- Jeder Job hat `timeout-minutes`; jede Datei setzt `permissions:` auf oberster Ebene (Standard `contents: read`).
- `concurrency` bricht veraltete Läufe desselben Zweigs ab (außer beim Release).
- **Keine Auto-Deploys:** nichts veröffentlicht von allein (kein `deploy-pages`, keine Store-Uploads, keine Signatur-Secrets).
  Die Web-Version liefert GitHub Pages aus dem Zweig `main` aus; `pages-smoke.yml` prüft nur, was dort ankommt.
- Kein `pull_request_target`: Code aus Forks läuft nie mit Schreibrechten.

## Übersicht

| Workflow | Wann | Blockiert den PR? | Was |
|---|---|---|---|
| `ci.yml` | Push auf `main`, jeder PR, montags, von Hand | ja (außer Python 3.13, Audit) | Tests (Linux, 3.12 gepinnt mit Abdeckung ≥ 77 %, 3.10 ungepinnt, 3.13 Vorschau), macOS (Marker `macos`, Swift typprüfen und kompilieren), ruff, Workflow-Lint, Phrasenpakete, Shell, Doku-Prüfungen, `pip-audit` |
| `changelog.yml` | PR | ja | Änderungen an App, Web, Paketen oder Engine brauchen einen Eintrag unter *Unreleased* (oder Label `no-changelog`) |
| `docs-links.yml` | PR/Push mit `*.md`, montags | intern ja, extern nein | Relative Links (Skript) und externe Links (lychee) |
| `ios.yml` | PR/Push mit `ios/**`, `presets/**`, `languages.json` | ja | iPhone-App bauen und testen |
| `web-a11y.yml` | PR mit Web-Änderungen | ja | Playwright und axe-core auf `index.html` |
| `lighthouse.yml` | PR mit Web-Änderungen | nein | Lighthouse-Budgets, Bericht als Artefakt |
| `pages-smoke.yml` | Push auf `main`, montags | nein | Prüft die ausgelieferte Web-Version |
| `tools.yml` | Änderungen in `tools/`, montags | nein | Swift-Prototypen in `tools/` typprüfen (macOS 26 SDK) |
| `codeql.yml` | PR, Push, montags | ja | Statische Analyse (Python, JavaScript, Workflows) |
| `bench.yml` | nur von Hand | – | Benchmark (lädt Modelle; läuft nie im normalen CI) |
| `release.yml` | Tag `v*` | – | ZIP bauen, Release-Entwurf mit Notes aus dem Changelog ([RELEASE.md](RELEASE.md)) |

## Lokal nachstellen

```bash
tools/check_all.sh          # ruff, Skripte, Pakete, Doku-Prüfungen, pytest: wie die CI-Linux-Jobs
tools/check_all.sh --docs   # nur die schnellen Doku- und Workflow-Prüfungen (Sekunden, ohne Pakete)
make docs-check             # dasselbe als Make-Ziel
make test-web               # nur Web, Pakete, Sprachen
```

Die schnellen Prüfungen im Einzelnen (alle nur Standardbibliothek, ohne Netz):

| Skript | Prüft |
|---|---|
| `tools/check_doc_links.py` | relative Links in allen Markdown-Dateien |
| `tools/check_docs_index.py` | jede Datei in `docs/` steht in [README.md](README.md) |
| `tools/changelog_lint.py` | Form von `CHANGELOG.md` (Reihenfolge, Duplikate, leere Abschnitte) |
| `tools/check_version_sync.py` | `pyproject.toml`, [VERSIONEN.md](VERSIONEN.md) und (beim Release) Tag stimmen überein |
| `tools/check_workflows.py` | die Hausregeln oben |

## Zwischenspeicher (Caches) und Geschwindigkeit

- **pip:** `actions/setup-python` mit `cache: pip`; der Schlüssel hängt an den Lock-Dateien (`requirements*.txt`) bzw. an
  `requirements-dev.in` im Lint-Job. Ändert Dependabot eine Lock-Datei, baut der erste Lauf den Cache neu.
- **ruff:** `.ruff_cache` wird je Ruff-Version und Konfiguration zwischengespeichert (`actions/cache`); ein Fehlen kostet nur Zeit.
- **Aufteilung:** schnelle Jobs (Lint, Pakete, Shell, Doku) laufen parallel zu den langen Tests; die macOS-Maschine wird nur für
  das gebraucht, was macOS braucht. Workflows für `ios/` und `tools/` laufen nur bei Änderungen dort (`paths:`).
- **Umgebung:** `PIP_DISABLE_PIP_VERSION_CHECK`, `PYTHONDONTWRITEBYTECODE` und `PYTHONUNBUFFERED` stehen im Kopf von `ci.yml`.
- Läuft ein Job länger als sonst, zuerst `--durations=10` im Testschritt ansehen (Ausgabe im Log).

## Abhängigkeiten

`.github/dependabot.yml` schlägt wöchentlich Updates vor: GitHub Actions (eine Gruppe), Python (eine Gruppe, die Pins
hängen zusammen), `tests/web-e2e` (npm) und die Dev-Container-Features. Pull requests tragen das Label `dependencies`.
Python-Updates: Lock-Dateien neu erzeugen, wie in [CONTRIBUTING.md](../CONTRIBUTING.md) beschrieben; vor dem Zusammenführen
die App einmal starten.

## Einen neuen Workflow hinzufügen

1. `permissions:` auf `contents: read` lassen und nur im Job erhöhen, der es braucht.
2. `timeout-minutes` und `concurrency` setzen; Actions auf SHA festlegen (`gh api repos/OWNER/REPO/commits/TAG --jq .sha`).
3. `paths:` verwenden, wenn der Job nur für einen Teil des Repos gilt (iOS, Web, Tools).
4. `tools/check_workflows.py` und `actionlint` lokal laufen lassen; die Tabelle oben ergänzen.
