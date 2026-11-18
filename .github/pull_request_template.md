## Was ändert sich und warum?

<!-- Ein bis drei Sätze. Verweis auf das Issue, falls es eins gibt: Closes #… -->

## Betroffen

- [ ] Engine (`dolmetscher.py`, `profiles.py`, …)
- [ ] Mac-App (`app/`)
- [ ] iPhone-App (`ios/`)
- [ ] Browser-Version (`index.html`, `sw.js`)
- [ ] Phrasenpakete (`presets/`)
- [ ] Doku / Store-Texte

## Checkliste

- [ ] Tests laufen (`pytest`, für Web `make test-web`, `make lint`)
- [ ] `CHANGELOG.md`: Zeile unter *Unreleased* oder Label `no-changelog`
- [ ] Neuer Netzwerkaufruf oder neue Daten? Dann `docs/DATENSCHUTZ.md` angepasst
- [ ] Datei, die der Service Worker zwischenspeichert, geändert? Dann `CACHE` in `sw.js` erhöht
- [ ] Phrasenpakete: `make presets-index` ausgeführt, Hinweis unten, ob ein Muttersprachler die Sätze geprüft hat
- [ ] Keine persönlichen Pfade, Namen, Mail-Adressen, Logs oder Schlüssel im Diff

## Muttersprachlich geprüft?

<!-- Nur bei Sprachänderungen: Sprache, wer geprüft hat (gern anonym), was geprüft wurde. -->
