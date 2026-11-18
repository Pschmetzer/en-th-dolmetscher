# Muttersprachler gesucht

Dolmetscher übersetzt Sprache, und Sprache lebt von Feinheiten. Fast alle Thai-Texte und die neueren
Oberflächensprachen (es, fr, ja, ko, zh-Hans, vi, id) sind maschinell oder mit KI-Hilfe entstanden und **noch nicht
muttersprachlich geprüft** (Ausnahme: Deutsch und Englisch). Der Stand steht auch in [PRESETS.md](PRESETS.md) und im README.

Schon ein einziger korrigierter Satz hilft. Du musst nicht programmieren können.

## Wo helfen?

| Was | Wo | Wichtig |
|---|---|---|
| Thai-Sätze in den Phrasenpaketen | `presets/*.json` (Feld `th`), eingebautes Satzbuch `ios/Shared/phrases.json` | Sätze mit `critical` (Notfall, Allergie, Polizei) zuerst |
| Thai-Oberfläche | `app/L10n.swift` (Mac), `ios/Dolmetscher/L10n*.swift` (iPhone) | Ton: freundlich, nicht zu förmlich |
| Höflichkeitsformen ครับ / ค่ะ | Einstellungen und Stimmprofile | stimmt die Form zum Sprecher? |
| Kulturhinweise (`note.th`) | `presets/*.json` | stimmen die Hinweise, wirken sie respektvoll? |
| Andere Oberflächensprachen | `ios/Dolmetscher/<sprache>.lproj/`, `ios/AppStore/<locale>/` | siehe Tabelle in [PRESETS.md](PRESETS.md) |
| Live-Übersetzung | in der App | klingt das Ergebnis natürlich und höflich? |

## So meldest du etwas

1. **Ohne GitHub-Kenntnisse:** Mach einen Screenshot aus der App und schreibe, wie es richtig heißt. Öffne dazu ein
   Issue mit der Vorlage *Thai-Übersetzungsfehler* (oder nutze „Falsch? Melden“ in der Web-Version).
2. **Mit GitHub:** Pull Request mit der geänderten Datei. Im Text stehen alte und neue Fassung, ein kurzer Grund
   („klingt unhöflich“, „sagt man so nicht“) und deine Muttersprache.
3. Bei Phrasenpaketen danach `make presets-index` ausführen (siehe [CONTRIBUTING.md](../CONTRIBUTING.md)).

## Ablauf mit Prüfbogen (Phrasenpakete)

Für viele Sätze auf einmal gibt es Werkzeuge in `tools/` (nur Python-Standardbibliothek):

1. `python3 tools/review_export.py --critical --out bogen.csv` erzeugt den Bogen (Filter `--pack ID`, Format `--format md`). Die CSV öffnet in Excel mit Umlauten und Thai.
2. Muttersprachler tragen je Zeile in *Status* `ok`, `korrigiert` oder `unklar` ein, bei `korrigiert` die neue Fassung in *Korrektur*, optional einen *Kommentar*. Die Spalten `id`, `en` und `th` nicht ändern.
3. `python3 tools/review_import.py bogen.csv` prüft den Bogen und zeigt die Änderungen als Diff (Trockenlauf). Mit `--apply` werden `presets/*.json` und `presets-index.json` geschrieben. Bei einem Fehler wird nichts geschrieben. Ein gleicher englischer Satz bekommt in allen Paketen dasselbe Thai.
4. Ein Paket steht erst auf `reviewed: true`, wenn der Bogen **alle** seine Sätze mit `ok` oder `korrigiert` bestätigt.
5. `python3 tools/review_status.py` zeigt den Fortschritt je Paket (mit `--sheet bogen.csv` auch je Satz).

## Worauf achten?

- **Bedeutung:** Wird nichts verdreht, vor allem bei Zahlen, Preisen, Zeiten, Allergien, Medikamenten?
- **Ton:** Zu förmlich, zu locker, grob? Passt die Höflichkeitsform?
- **Natürlichkeit:** Würde man das so sagen, oder klingt es wie eine Übersetzungsmaschine?
- **Schrift und Aussprache:** Stimmt die Umschrift, werden Wörter richtig getrennt?
- **Mehrdeutigkeit:** Gibt es ein besseres Wort, wenn ein Satz zwei Bedeutungen haben kann?

## Datenschutz und Anerkennung

Bitte keine echten Gespräche, Namen oder persönlichen Daten einsenden. Ein nachgestellter Beispielsatz genügt.
Wer möchte, wird im Changelog genannt. Im Pull Request vermerken wir, ob ein Muttersprachler die Sätze geprüft hat,
damit der Stand nachvollziehbar bleibt.
