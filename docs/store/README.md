# App-Store-Texte

Texte für den Mac und das iPhone in Deutsch, Englisch und Thai, Grundlage ist der Stand im Repository
(README, CHANGELOG, `ios/AppStore/`). Die Thai-Texte sind maschinell erstellt und noch nicht muttersprachlich geprüft
(siehe [../MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md)).

Aufbau: `<plattform>/<sprache>/` mit `name.txt`, `subtitle.txt`, `keywords.txt`, `description.txt`, `whats_new.txt`.

Limits (geprüft in `tests/test_runde8_community_neu.py`): Name und Untertitel höchstens 30 Zeichen, Stichwörter höchstens
100 Zeichen, Beschreibung höchstens 4000 Zeichen. Bei neuen Fakten zuerst README und CHANGELOG ändern, dann diese Texte.
