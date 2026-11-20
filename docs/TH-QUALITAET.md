# Thai-Qualität: was geprüft ist und was nicht

Thai ist die schwierigste Sprache im Paar: keine Leerzeichen zwischen Wörtern, Tonmarken, Höflichkeitspartikeln, eigene
Zahlwörter. Diese Seite sagt ehrlich, was automatisch gemessen wird, was nur von Menschen beurteilt werden kann und wie
du helfen kannst. Überblick zu Muttersprachlern: [MUTTERSPRACHLER.md](MUTTERSPRACHLER.md).

## Was automatisch geprüft wird

| Bereich | Wie | Wo |
|---|---|---|
| Thai-Zahlwörter gegen Ziffern („สามร้อยห้าสิบ“ = 350) beim Zahlenvergleich der Übersetzung | Unit-Tests | `tests/test_thai_zahlen.py` |
| Klauseltrennung fürs Vorlesen, Frage-Partikel aus dem Original | Unit-Tests | `tests/test_thai_zahlen.py`, `tests/test_fix_thai.py` |
| Schrift-Plausibilität (kam Thai heraus, wo Thai erwartet wird, oder blieb der Satz unübersetzt?) | Korpus-Tests | `tests/corpus/`, `tests/test_corpus.py` |
| Erkennungsfehler (WER/CER), Zahlen, Uhrzeiten, Telefonnummern, Übersetzungsähnlichkeit | Benchmark mit synthetischen Stimmen | `bench/`, Tags `num`, `time`, `phone`, `digits` in `bench/cases.json` |
| Form der Phrasenpakete (Pflichtfelder, kritische Sätze zuerst, keine Pronomen ฉัน/ผม in Satzbuch-Sätzen) | Schema und Tests | `docs/presets.schema.json`, `tests/test_presets*.py` |

## Was nur Menschen beurteilen können

- **Natürlichkeit und Höflichkeit** der Sätze: passen ครับ/ค่ะ zum Sprecher, ist der Ton im Restaurant, beim Arzt oder
  bei der Polizei richtig?
- **Kulturhinweise** (`note.th` in den Paketen): stimmen sie, wirken sie respektvoll?
- **Die Oberfläche** in Thai (Mac, iPhone, Web): Wortwahl, Länge der Texte, Umbrüche.
- **Echte Stimmen**: Der Benchmark nutzt synthetische Stimmen („Kanya“). Dialekte, Hintergrundlärm und schnelles Sprechen
  sind damit nicht abgedeckt. Siehe [ROADMAP.md](ROADMAP.md).

## Bekannte Grenzen

- Alle Thai-Sätze und die meisten Oberflächentexte entstanden mit maschineller Hilfe; sie sind **nicht von Muttersprachlern
  geprüft** (auch im README vermerkt).
- Online-Übersetzer (Google, MyMemory) liefern bei Thai häufiger Auslassungen oder falsche Zahlen. Darum vergleicht die
  Engine Zahlen mit dem Original und fragt bei Abweichung den anderen Anbieter. Das fängt Ziffern ab, nicht Bedeutung.
- Eine Umschrift (Aussprachehilfe) gibt es nur maschinell; sie ist bei Thai oft falsch und deshalb nicht in den Paketen.
- Die Erkennungsschwellen sind für Thai mit synthetischen Stimmen kalibriert, nicht mit Sprechern.

## So hilfst du

1. Ein Paket aus `presets/` öffnen (`th`-Felder) und Sätze prüfen; Regeln in [PRESETS.md](PRESETS.md).
2. Einen Fehler melden: mit der Vorlage *Thai-Satz prüfen* im Issue-Tracker oder mit dem Knopf „falsch? melden“ im Web.
3. Einen Prüfbogen exportieren und zurückgeben: `python3 tools/review_export.py --critical --out bogen.csv`, danach `tools/review_import.py` (Ablauf in [MUTTERSPRACHLER.md](MUTTERSPRACHLER.md)).
4. Eigene Aufnahmen für den Benchmark: als `bench/audio/real/<id>.wav` ablegen (siehe `bench/README.md`); der Referenztext
   wird wörtlich vorgelesen.

## Wie wir den Stand führen

Ändert sich etwas an der Prüflage (ein Paket ist geprüft, eine Baseline wurde erneuert), wird das in dieser Datei, im
[CHANGELOG](../CHANGELOG.md) und im Kopf des betroffenen Pakets vermerkt, nicht nur im Commit.
