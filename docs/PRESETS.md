# Phrasenpakete (presets/*.json)

> **Maschinell übersetzt – muttersprachlich prüfen.** Die Thai-Sätze wurden mit KI-Hilfe geschrieben und
> noch nicht von Muttersprachlern geprüft. Sie sind für den Notbehelf gedacht, nicht als verbindliche Übersetzung.
> Das Arzt- und das Apotheken-Paket helfen nur bei der Verständigung und ersetzen keinen medizinischen Rat.

Ein Paket ist eine JSON-Datei in `presets/`. Die Engine (`presets.py`), die Mac-App (`app/Presets.swift`) und
die Web-Version (`index.html`, Satzbuch und Zeige-Karten) lesen dieselben Dateien. Eigene Pakete liegen in
`$DOLMETSCHER_HOME/presets/`; gleiche `id` ersetzt das mitgelieferte Paket.

## Format

| Feld | Pflicht | Inhalt |
|---|---|---|
| `id` | ja | `a-z`, `0-9`, `_`, `-`, höchstens 32 Zeichen, gleich dem Dateinamen |
| `names` | ja | `{de, en, th}`, je 1–40 Zeichen |
| `style` | ja | `casual`, `neutral` oder `polite` (Stil der KI-Übersetzung) |
| `polite` | nein | `krub` oder `ka` (Höflichkeitspartikel erzwingen) |
| `voice` | nein | `{en?, th?}` Stimmnamen |
| `note` | nein | Kultur- oder Sicherheitshinweis `{de, en, th?}`, je 1–500 Zeichen |
| `glossary` | nein | bis 100 Paare `{en, th}` (je 1–60 Zeichen), gelten in beide Richtungen |
| `phrases` | nein | bis 50 Sätze `{en, th, critical?}` (je 1–200 Zeichen) |

`critical: true` markiert sicherheitskritische Sätze (Notruf, Allergie, Unfall, vermisstes Kind). Sie stehen
immer am Anfang der Liste. Ältere Dateien ohne `note`/`critical` bleiben gültig; Programme, die die Felder nicht
kennen, ignorieren sie.

## Regeln für Thai-Sätze

- Keine Höflichkeitspartikel (ครับ/ค่ะ) in der Datei: die Engine ergänzt sie passend zur Sprecherin oder zum Sprecher.
- Kein Pronomen ฉัน/ผม: Thai lässt das Subjekt meist weg, so passt der Satz für alle.
- Kein vertrautes นะ am Satzende; höflich fragen mit ขอ … / ช่วย … หน่อย / … ได้ไหม.
- Lücken für Zeige-Sätze als `___` (in `en` und `th` gleich), kein `{p}`-Platzhalter.
- Keine Dubletten innerhalb eines Pakets. `tests/test_presets_inhalt.py` prüft das alles.

## Ein Paket beitragen

1. Datei `presets/<id>.json` anlegen (Vorlage: ein vorhandenes Paket), 15–25 praxisnahe Sätze, kritische zuerst.
2. `python -m pytest tests/test_presets.py tests/test_presets_inhalt.py` ausführen.
3. Für die Web-Version die `id` in `PRESET_IDS` von `index.html` und `sw.js` eintragen
   (`tests/test_web_pwa.py` prüft, dass die Listen zum Ordner passen).
4. Im Pull Request vermerken, ob ein Muttersprachler die Thai-Sätze geprüft hat.

## Pakete

| id | Thema | Sätze mit `critical` |
|---|---|---|
| `doctor` | Arzt (nur Verständigung) | Notruf 1669, Atemnot, Brustschmerz, Allergien, Schwangerschaft, Diabetes |
| `pharmacy` | Apotheke | Allergien, Schwangerschaft, Kinder, Wechselwirkung |
| `police` | Polizei / Diebstahl | Hilfe, Tourist Police 1155, Rettung, Überfall, Verfolgung |
| `lostchild` | Kind verloren (Zeige-Sätze) | fast alle; Sätze mit หนู zeigt das Kind |
| `restaurant` | Restaurant | Erdnuss- und Schalentierallergie |
| `travel` | Reise | Hilfe, Polizei, Rettung, Krankenhaus |
| `taxi` | Taxi | Fahrt ins Krankenhaus |
| `bank` | Bank / Geldautomat | Karte eingezogen, Karte gestohlen, Geld nicht ausgegeben |
| `spa` | Massage / Spa | Schmerz, Schwangerschaft, Verletzung, Blutdruck, Öl-Allergie |
| `scooter` | Werkstatt / Roller | Unfall, Verletzte, Bremsen |
| `transport` | Fähre / Bus / Zug | Schwimmwesten |
| `rental` | Wohnung mieten | Gasgeruch |
| `temple` | Tempel / Kultur | – |
| `hotel` | Hotel | – |
| `shopping` | Einkaufen | – |
| `office` | Büro | – |

## Unsichere Sätze (bitte zuerst prüfen)

| Paket | Satz | Zweifel |
|---|---|---|
| `lostchild` | หนูหลงทาง ช่วยโทรหาพ่อแม่ให้หน่อย | หนู als Selbstbezeichnung des Kindes, passt für Jungen und Mädchen? |
| `lostchild` | ช่วยพาไปหาตำรวจหรือ รปภ. ด้วย | Abkürzung รปภ. (Wachmann) verständlich genug? |
| `lostchild` | ช่วยเฝ้าทางออกด้วย | „Ausgänge bewachen“: klingt das dringlich genug? |
| `bank` | ตู้เอทีเอ็มกลืนบัตร | umgangssprachlich „Automat hat die Karte geschluckt“ |
| `bank` | แลกเงินที่ช่องไหน | heißt „an welchem Schalter“, englisch „Where can I exchange money?“ |
| `police` | ถูกทำร้ายร่างกาย ได้รับบาดเจ็บ | amtlich; gesprochen eher โดนทำร้าย? |
| `spa` | ไม่ต้องนวดคอ / ช่วยนวดไหล่เยอะๆ หน่อย | natürliche Wortwahl im Massagesalon? |
| `scooter` | ไม่ฝากพาสปอร์ต ขอวางมัดจำเป็นเงินสดได้ไหม | Ton gegenüber Vermieter zu schroff? |
| `rental` | ค่าไฟหน่วยละเท่าไหร่ | übliche Frage nach dem Strompreis pro Einheit? |
| `transport` | ถ้าคลื่นแรงเรือยังออกไหม | verständlich als „Fährt die Fähre bei hohem Wellengang?“ |
| `transport` | ขอตู้นอน เตียงล่าง | Bezeichnung für das untere Bett im Schlafwagen |
| `temple` | วิหารอยู่ที่ไหน | วิหาร oder โบสถ์/อุโบสถ für die Haupthalle? |
| `pharmacy` | มีผงเกลือแร่ไหม | gängiges Wort für Elektrolytpulver? |
| `shopping` | ขอเอกสารขอคืนภาษี VAT Refund ด้วย | doppeltes ขอ, Formulierung im Laden üblich? |
| `doctor` | ใช้ประกันสุขภาพนี้ได้ไหม | ersetzt „รับประกันของฉันไหม“ (mehrdeutig, Garantie) |
