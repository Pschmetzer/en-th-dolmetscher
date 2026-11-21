# Veröffentlichen

Gilt für die Mac-App. Die Web-Version wird bei jedem Merge auf `main` über GitHub Pages ausgeliefert (kein eigener
Release-Schritt); die iPhone-App hat ihren Ablauf in [../ios/README.md](../ios/README.md).

## Checkliste

1. `version` in `pyproject.toml` anheben (nur dort) und die Zeile „Mac-App und Engine“ in [VERSIONEN.md](VERSIONEN.md) angleichen.
2. In `CHANGELOG.md` den Abschnitt *Unreleased* in `## X.Y (Tag Monat Jahr)` umbenennen und darüber einen neuen, leeren
   *Unreleased*-Abschnitt anlegen.
3. Prüfen: `make docs-check` (Form des Changelogs, Versionen) und `tools/check_all.sh`; CI auf `main` grün.
4. Benchmark gegen die Basis, Gespräch mit echter Stimme, `--release`-Build: Schritte in [CONTRIBUTING.md](../CONTRIBUTING.md#release-checklist).
5. Tag setzen und pushen:

   ```bash
   git tag -a vX.Y -m "X.Y" && git push origin vX.Y
   ```

## Was der Workflow `release.yml` macht

Beim Tag `v*`:

1. **Prüfen:** Tag = Version aus `pyproject.toml` (`tools/check_version_sync.py --tag`), Form des Changelogs, und es gibt
   einen nicht leeren Abschnitt zur Version (`tools/changelog_extract.py`). Sonst bricht der Lauf ab, bevor etwas gebaut wird.
2. **Bauen:** Tests, App mit Ad-hoc-Signatur ohne Modelle, ZIP und SHA256 als Workflow-Artefakt.
3. **Release-Entwurf** (letzter Schritt des Bau-Jobs, nur dort `contents: write`): ein GitHub-Release als **Entwurf** (`draft`) mit dem Changelog-Auszug als Notes und dem ZIP samt
   Prüfsumme. Der Entwurf wird **nicht** veröffentlicht: Notes lesen, bei Bedarf kürzen, dann von Hand auf „Publish“ klicken.

Es gibt keine Signier-Secrets und keinen Upload in einen Store; signierte, notarisierte Builds entstehen lokal.

## Release-Notes vorab ansehen

```bash
make changelog-notes V=1.3        # Abschnitt einer Version
make changelog-notes              # Unreleased
python3 tools/changelog_extract.py --list
```

Die Notes sind der Abschnitt im Changelog ohne Überschrift. Kurze, für Anwender verständliche Sätze dort sparen
Nacharbeit im Entwurf. Die Einteilung der automatisch erzeugten Zusatzliste (falls man sie im Entwurf aktiviert) steht in
`.github/release.yml`.

## Wenn etwas schiefgeht

- *Tag stimmt nicht mit der Version überein:* Tag löschen (`git push --delete origin vX.Y`, `git tag -d vX.Y`), Version
  korrigieren, neu taggen.
- *Abschnitt im Changelog fehlt:* Abschnitt ergänzen, Tag verschieben wie oben; der Workflow baut nichts ohne Notes.
- *Entwurf existiert schon:* der Workflow ersetzt die Dateien des Entwurfs und die Notes (`gh release edit`).
