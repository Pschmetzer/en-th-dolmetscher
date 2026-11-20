# Phrasenpakete (presets/*.json)

> **Maschinell übersetzt – muttersprachlich prüfen.** Die Thai-Sätze wurden mit KI-Hilfe geschrieben und
> noch nicht von Muttersprachlern geprüft. Sie sind für den Notbehelf gedacht, nicht als verbindliche Übersetzung.
> Das Arzt- und das Apotheken-Paket helfen nur bei der Verständigung und ersetzen keinen medizinischen Rat.

Ein Paket ist eine JSON-Datei in `presets/`. Die Engine (`presets.py`), die Mac-App (`app/Presets.swift`), die
Web-Version (`index.html`, Satzbuch und Zeige-Karten) und die iPhone-App lesen dieselben Dateien. Eigene Pakete liegen in
`$DOLMETSCHER_HOME/presets/`; gleiche `id` ersetzt das mitgelieferte Paket.

Die iPhone-App liest den Ordner `presets/` ebenfalls (als Ordner-Referenz im Xcode-Projekt). Jedes Paket
erscheint dort als eigener Abschnitt im Satzbuch mit Kulturhinweis; `critical`-Sätze stehen oben und greifen bei
„Satzbuch zuerst“ nur bei genauem Treffer.

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
   (`tests/test_web_pwa.py` prüft, dass die Listen zum Ordner passen), dann `python3 tools/make_presets_index.py` ausführen (erzeugt `presets-index.json`; `tests/test_runde7_web_presets.py` prüft, dass sie aktuell ist). Das JSON-Schema für Editoren liegt in `docs/presets.schema.json`.
4. Im Pull Request vermerken, ob ein Muttersprachler die Thai-Sätze geprüft hat.

## Pakete

| id | Thema | Sätze mit `critical` |
|---|---|---|
| `doctor` | Arzt (nur Verständigung) | Notruf 1669, Atemnot, Brustschmerz, Allergien, Schwangerschaft, Diabetes |
| `pharmacy` | Apotheke | Allergien, Schwangerschaft, Kinder, Wechselwirkung |
| `police` | Polizei / Diebstahl | Hilfe, Tourist Police 1155, Rettung, Überfall, Verfolgung |
| `lostchild` | Kind verloren (Zeige-Sätze) | fast alle; Sätze mit หนู zeigt das Kind |
| `restaurant` | Restaurant | Allergien: Erdnuss, Schalentiere, Ei, Milch, Weizen, Soja, Sesam, Fisch, Sellerie |
| `travel` | Reise | Hilfe, Polizei, Rettung, Krankenhaus |
| `taxi` | Taxi | Fahrt ins Krankenhaus |
| `bank` | Bank / Geldautomat | Karte eingezogen, Karte gestohlen, Geld nicht ausgegeben |
| `spa` | Massage / Spa | Schmerz, Schwangerschaft, Verletzung, Blutdruck, Öl-Allergie |
| `scooter` | Werkstatt / Roller | Unfall, Verletzte, Bremsen |
| `transport` | Fähre / Bus / Zug | Schwimmwesten |
| `rental` | Wohnung mieten | Gasgeruch |
| `temple` | Tempel / Kultur | Schwächegefühl |
| `hotel` | Hotel | Feuer, Arzt nötig |
| `shopping` | Einkaufen | Polizei rufen |
| `office` | Büro | Unwohlsein, Arzt rufen |
| `dentist` | Zahnarzt (nur Verständigung) | Zahnschmerz, Schwellung, Allergien, Stopp |
| `airport` | Flughafen und Gepäck | Rollstuhl, medizinische Hilfe |
| `answers` | Antworten und Höfliches | Hilfe |
| `services` | Wäscherei, Friseur, Schneider | – |
| `island` | Inselausflug und Tauchen | nicht schwimmen können, medizinische Hilfe, Rettungsweste |
| `access` | Barrierefreiheit | Hilfe benötigt |
| `coworking` | Coworking und Langzeitmiete | – |
| `places` | Orte: Bangkok, Phuket, Chiang Mai | – |
| `emergency` | Reise-Notfälle | Hilfe, Rettung, Feuer, Betäubung, Verfolgung, Unfall, Atemnot |
| `work` | Arbeit und Handwerk | Gefahr, Verletzung, Strom aus, Gasgeruch |
| `school` | Schule und Kita | Allergie, Medikamente, Rückruf |
| `visa` | Behörden und Visum | – |
| `sport` | Sport und Fitness | Verletzung, Schwindel, Herzproblem |
| `nomad` | Digitale Nomaden | – |
| `diving` | Tauchen und Schnorcheln | Ohren, Luftmangel, Aufstieg, Unwohlsein, Asthma |
| `market` | Markt und Handeln | Erdnuss-, Schalentier-Allergie |
| `kids` | Reisen mit Kindern | Allergie, Kind verloren, Arzt, nicht schwimmen können |
| `car-rental` | Mietwagen | 4 kritische Sätze zuerst |
| `pets` | Haustiere | 5 kritische Sätze zuerst |
| `baby` | Baby und Kleinkind | 5 kritische Sätze zuerst |
| `gym` | Fitnessstudio | 4 kritische Sätze zuerst |
| `wedding` | Hochzeit und Feier | 4 kritische Sätze zuerst |
| `photo` | Fotografieren | 4 kritische Sätze zuerst |
| `bus-train` | Fernbus und Bahn | kritische Sätze zuerst |
| `beach` | Strand | kritische Sätze zuerst |
| `hiking` | Wandern und Dschungel | kritische Sätze zuerst |
| `street-food` | Streetfood | kritische Sätze zuerst |
| `massage` | Thai-Massage | kritische Sätze zuerst |
| `nightlife` | Nachtleben und Bars | kritische Sätze zuerst |
| `festival` | Feste (Songkran, Loy Krathong) | kritische Sätze zuerst |
| `laundry-repair` | Schneider, Schuster, Handyreparatur | kritische Sätze zuerst |
| `pharmacy-otc` | Apotheke: rezeptfreie Mittel (nur Verständigung) | Allergien, Schwangerschaft, Kinder, Wechselwirkung, Rezept |
| `mobile-sim` | SIM, Internet und Handy | Handy gestohlen, Handy verloren, SIM sperren |
| `monk` | Mönche und Tempelbesuch | 4 kritische Sätze zuerst |
| `hospital` | Krankenhaus | 5 kritische Sätze zuerst |
| `atm-bank-card` | Geldautomat: Karte und Limit | Karte eingezogen, Karte gestohlen, Geld nicht ausgegeben, Beobachtung |
| `immigration-90day` | Immigration: 90-Tage-Meldung | Überziehung, Dolmetscher, Strafe zahlen |
| `motorbike-accident` | Motorrad-Unfall | Notruf, Schwerverletzte, Polizei, Nacken, Kopf |
| `lost-passport` | Reisepass verloren | verloren, gestohlen, Anzeige, Botschaft |
| `tailor-custom` | Maßschneider | Preis schriftlich, Anzahlung, Abbruch |
| `tuk-tuk-songthaew` | Tuk-Tuk und Songthaew | Anhalten, Umweg, Aussteigen, Krankenhaus |
| `thai-cooking-class` | Thai-Kochkurs | Erdnuss, Schalentiere, Schnitt, Verbrennung |
| `elephant-sanctuary` | Elefantenschutzgebiet | Hilfe, Verletzte, Hitze, Insektenstiche |
| `cinema-concert` | Kino und Konzert | Feuer, Ohnmacht, Arzt, Diebstahl |
| `dating-small-talk` | Smalltalk und Kennenlernen | Ablehnen, Unwohlsein, Polizei |
| `ferry-boat` | Fähre und Boot | nicht schwimmen können, Person im Wasser, Rettungsweste, Arzt |
| `island-hopping` | Inselhopping | nicht schwimmen können, Arzt, Rettungsweste, Quallenstich |
| `snorkel-boat-tour` | Schnorchel-Bootstour | nicht schwimmen können, Arzt, Rückkehr zum Boot, Person fehlt, Schwindel, Rettungsweste |
| `muay-thai-gym` | Muay-Thai-Camp | Stopp, Kopftreffer, Atemnot, Arzt, Verletzung |
| `buddhist-ceremony` | Buddhistische Zeremonie | Ohnmacht, Arzt, Sitzen, Weihrauch-Allergie |
| `rice-field-village` | Dorf und Reisfelder | Schlangenbiss, Arzt, Klinik, Hitze, verirrt |
| `night-market-bargain` | Nachtmarkt und Handeln | Polizei, Geldbeutel gestohlen, Erdnuss, Schalentiere, festgehalten |
| `hostel-dorm` | Hostel und Schlafsaal | Diebstahl, Polizei, Feuer, Arzt |
| `laundry-deposit` | Wäsche und Kaution | Pass nicht als Pfand, Quittung, Kaution zurück, Kleidung fehlt |
| `vegan-vegetarian` | Vegetarisch, vegan und Allergene | schwere Allergie, Erdnuss, Nüsse, Soja, Sesam, Weizen, Schalentiere, Arzt |
| `visa-extension` | Visumverlängerung | überzogen, Ablaufdatum, Verlängerung, Strafe |
| `tax-refund` | VAT-Rückerstattung | Tasche gestohlen, Formular verloren, Flug, Beleg fehlt |
| `car-wash-repair` | Autowäsche und Werkstatt | Panne, Bremsen, Reifen, Abschleppwagen |
| `bicycle-rental` | Fahrradverleih | Bremsen, Unfall, Helm, Pass nicht als Pfand |
| `yoga-retreat` | Yoga-Retreat | Rückenverletzung, schwanger, Schwindel, schwere Allergie |
| `kids-playground` | Spielplatz und Kinderwelt | Kind vermisst, Sturz, Arzt, Allergie |
| `bakery-cafe` | Bäckerei und Café | schwere Allergie, Erdnuss, Weizen, Nüsse |
| `convenience-store-7eleven` | Kiosk und 7-Eleven | Erdnuss, Apotheke, halal, Schwein |
| `post-office-parcel` | Post und Paket | zerbrechlich, Batterie, keine Flüssigkeit |
| `wifi-coworking-cafe` | WLAN-Café und Arbeiten | Tasche bewachen, Laptop gestohlen, Ladegerät, Polizei |
| `bangkok-skytrain` | Skytrain und U-Bahn | Ohnmacht, Personal, Belästigung, Diebstahl |
| `food-allergy` | Nahrungsmittelallergie | Allergische Reaktion, Atemnot, Notfallset, Notruf |
| `grab-ride-hailing` | Fahrdienst-App (Grab, Bolt) | falsches Auto, unsicher, anhalten, Tempo |
| `food-delivery` | Essenslieferung | Allergie, Garnelen, Übelkeit nach dem Essen |
| `floating-market` | Schwimmender Markt | Schwimmweste, Sturz ins Wasser, Wassereinbruch |
| `jet-ski-rental` | Jetski und Wassersport | Pass nicht hinterlegen, Touristenpolizei, Bedrohung |
| `animal-bite-rabies` | Tierbisse und Stiche | Hund, Affe, Schlange, Tollwutimpfung, Notruf |
| `travel-insurance-claim` | Reiseversicherung: Schaden melden | Notruf, Krankenhaus, Arzt, erst behandeln |
| `flight-delay-change` | Flugverspätung und Umbuchung | Medikamente, Unwohlsein, Arzt |
| `monsoon-flood-storm` | Regen, Flut und Sturm | Wasser steigt, eingeschlossen, Notruf, Polizei |
| `scams-overcharge` | Betrug / Abzocke | 4 kritische Sätze zuerst |
| `lost-phone` | Handy verloren / gestohlen | 5 kritische Sätze zuerst |
| `police-checkpoint` | Polizeikontrolle / Führerschein | 2 kritische Sätze zuerst |
| `tm30-address-report` | TM30 / Meldung der Unterkunft | 0 kritische Sätze zuerst |
| `karaoke` | Karaoke | 0 kritische Sätze zuerst |
| `golf` | Golf | 0 kritische Sätze zuerst |
| `kayak-national-park` | Kajak / Nationalpark | 4 kritische Sätze zuerst |
| `hair-beauty` | Friseur / Schönheit | 4 kritische Sätze zuerst |
| `cannabis-vape` | Cannabis / E-Zigarette | 2 kritische Sätze zuerst |
| `chronic-conditions` | Chronische Krankheit / Dauermedikation | 5 kritische Sätze zuerst |
| `lost-luggage` | Gepäck verloren | 0 kritische Sätze zuerst |
| `customs-duty-free` | Zoll / Duty-free | 0 kritische Sätze zuerst |
| `heat-health` | Hitze / Dehydrierung | 4 kritische Sätze zuerst |
| `mosquito-dengue` | Mücken / Dengue | 4 kritische Sätze zuerst |
| `border-crossing` | Grenzübertritt / Visa-Run | 3 kritische Sätze zuerst |
| `currency-exchange` | Geldwechsel | 0 kritische Sätze zuerst |
| `optician-eye-care` | Optiker / Augen | 3 kritische Sätze zuerst |
| `souvenir-jewelry` | Souvenirs / Schmuck | 1 kritische Sätze zuerst |
| `buffet-bbq` | Buffet / Moo Kratha | 2 kritische Sätze zuerst |
| `adventure-park` | Zipline / Abenteuerpark | 3 kritische Sätze zuerst |

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
| `shopping` | ขอเอกสารขอคืนภาษีมูลค่าเพิ่มด้วย | doppeltes ขอ, Formulierung im Laden üblich? |
| `doctor` | ใช้ประกันสุขภาพนี้ได้ไหม | ersetzt „รับประกันของฉันไหม“ (mehrdeutig, Garantie) |

## Muttersprachler gesucht

Fast alle Texte in Thai und in den neueren Oberflächensprachen sind maschinell bzw. mit KI-Hilfe entstanden.
Muttersprachlich geprüft ist bisher **nichts davon** (Ausnahme: Deutsch und Englisch). Wer Thai oder eine der
Sprachen unten spricht, hilft sehr, wenn er die Dateien gegenliest. Schon ein einzelner korrigierter Satz zählt.

So geht's: Issue oder Pull Request auf GitHub, mit Datei, alter und neuer Fassung und kurzer Begründung
(z. B. „klingt unhöflich“, „sagt man so nicht“). Bitte dazuschreiben, welche Sprache du als Muttersprache sprichst.
Am wichtigsten sind die Sätze mit `critical` und die Tabelle [Unsichere Sätze](#unsichere-sätze-bitte-zuerst-prüfen).

**Thai**

| Datei | Inhalt |
|---|---|
| `presets/*.json` | 111 Phrasenpakete: Sätze (`th`), Paketnamen (`names.th`), Kulturhinweise (`note.th`) |
| `ios/Shared/phrases.json` | eingebautes Satzbuch der iPhone-App und des Widgets |
| `ios/Dolmetscher/PartnerPhrases.swift` | Antwortkarten, „Sie sind dran“, Allergie-Karte |
| `ios/Dolmetscher/Round4Views.swift` | Hilfesatz auf dem Bildschirm „Hilfe – jetzt“ |
| `ios/Dolmetscher/L10n+R4.swift` | Gerichte-Lexikon (`dish_*`) und weitere Texte |
| `ios/Dolmetscher/L10n.swift`, `L10n+Extra.swift`, `L10n+R4.swift`, `L10n+R5.swift` | Thai-Oberfläche der iPhone-App |
| `ios/Shared/WidgetTexts.swift` | Texte der Widgets und der Live-Aktivität |
| `ios/Dolmetscher/th.lproj/InfoPlist.strings` | Texte der Berechtigungsabfragen (Mikrofon, Standort, Face ID …) |
| `ios/AppStore/th/` | App-Store-Texte |
| `app/L10n.swift` | Thai-Oberfläche der Mac-App |
| `index.html` | Ja/Nein-Karten (`LANGS`) der Web-Version |

**Oberflächensprachen der iPhone-App: es, fr, ja, ko, zh-Hans, vi, id**

| Datei | Inhalt |
|---|---|
| `ios/Dolmetscher/L10n.swift`, `L10n+Extra.swift`, `L10n+R4.swift`, `L10n+R5.swift` | alle Texte der Oberfläche, Paketnamen (`packNames`) |
| `ios/Shared/WidgetTexts.swift` | Widgets und Live-Aktivität |
| `ios/Dolmetscher/<sprache>.lproj/InfoPlist.strings` | Berechtigungsabfragen |
| `ios/Dolmetscher/PartnerPhrases.swift` | Antwortkarten und Allergie-Karte (dort in allen 19 Sprachen) |
| `ios/AppStore/<locale>/` | App-Store-Texte (auch `de-DE` und `th` sind maschinell übersetzt) |

Wer Code nicht anfassen will: Ein Screenshot aus der App mit der richtigen Fassung reicht auch.
