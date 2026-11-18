# Tastenkürzel

Alle Kürzel stehen so im Code (`app/DolmetscherApp.swift`, `app/HotKeys.swift`, `app/BubbleViews.swift`, `app/PartnerView.swift`, `ios/Dolmetscher/Views.swift`, `index.html`). Englische Fassung: [en/SHORTCUTS.md](en/SHORTCUTS.md).

## Mac-App

### Überall, auch wenn die App im Hintergrund ist (globale Kürzel)

| Kürzel | Wirkung |
|---|---|
| ⌃⌥D | Start / Stopp |
| ⌃⌥P | Pause / Fortsetzen |
| ⌃⌥S | Vorlesen abbrechen |
| ⌃⌥R | letzte Übersetzung nochmal sprechen |
| ⌃⌥T (halten) | sprechen, nur belegt, wenn Push-to-Talk eingeschaltet ist |

Wenn ein anderes Programm ein Kürzel schon belegt, zeigt die App einen Hinweis mit den betroffenen Kürzeln. Sie versucht es bei der nächsten Aktivierung erneut.

### In den Menüs der App

| Kürzel | Wirkung |
|---|---|
| Leertaste | Start / Stopp, nur im Hauptfenster und nur ohne Eingabefokus; abschaltbar („Leertaste startet/stoppt“ in den Einstellungen) |
| ⌘Return | Start / Stopp |
| ⌘P | Pause / Fortsetzen (Drucken gibt es nicht) |
| ⌘. | Vorlesen abbrechen |
| ⌘R | letzte Übersetzung nochmal sprechen |
| ⌘1 bis ⌘9 | die ersten neun eigenen Schnellsätze sprechen |
| ⌥⌘1 bis ⌥⌘9 | die ersten neun Sätze des gewählten Szenario-Pakets sprechen |
| ⌘F | Suche im Gespräch |
| ⌘+ / ⌘- / ⌘0 | Schrift größer / kleiner / zurücksetzen (⌘= wirkt wie ⌘+) |
| ⇧⌘P | Partneransicht öffnen |
| ⌥⌘T | Fenster immer im Vordergrund |
| ⇧⌘E | Gespräch exportieren |
| ⌥⌘Z | Löschen rückgängig machen |
| ⇧⌘C | letzte Übersetzung kopieren |
| ⌥⌘L | Richtung wechseln (automatisch, dann je eine Sprache des Paars) |
| ⌥⌘G | Wort zum Glossar hinzufügen |
| ⌘L | Cursor ins Tippfeld |
| ⌥⌘S | Vorlesen ein / aus |
| ⌘/ | Kürzel-Übersicht (Hilfe-Menü) |

### Partneransicht

| Kürzel | Wirkung |
|---|---|
| ⌃⌘F | Vollbild ein / aus |
| Pfeil links / rechts | eine Übersetzung zurück / vor |

### Auf einer Sprechblase (mit Tab anwählen)

| Taste | Wirkung |
|---|---|
| Return | vorlesen (läuft es schon, stoppt es) |
| Esc | Vorlesen stoppen |
| E | Blase korrigieren und neu übersetzen |
| C | Übersetzung kopieren (⌘C ebenfalls) |

## Browser (Web Lite)

Einzeltasten-Kürzel gelten nicht in Eingabefeldern und nicht mit Strg, Alt oder Cmd. Sie lassen sich in den Einstellungen abschalten („Einzeltasten-Kürzel“). Sie gehen auch mit thailändischem Tastaturlayout, weil die Seite die Tastenposition auswertet.

| Taste | Wirkung |
|---|---|
| E oder 1 | ich spreche (nur wo Spracherkennung vorhanden ist) |
| T oder 2 | das Gegenüber spricht |
| Leertaste | Aufnahme beenden (nicht auf Knöpfen und in Eingabefeldern) |
| P | Partneransicht ein / aus |
| L | zum neuesten Eintrag im Gespräch springen |
| Esc | schließt die Partneransicht, sonst Stopp; schließt Dialoge immer |
| Pfeil rechts / links | in der Partneransicht bei einer Kartenfolge vor / zurück |
| Enter | im Textfeld „Tippen statt Sprechen“ übersetzen (mit Umschalt+Enter wird nicht abgeschickt) |
| Tab | alles ist auch ohne Kürzel mit Tab und den Knöpfen bedienbar |

„Halten zum Sprechen“ ist ein Knopf: gedrückt halten, sprechen, loslassen. Mit der Tastatur bleibt es ein Umschalter.

## iPhone und iPad

Auf dem iPhone und iPad gelten mit angeschlossener Tastatur nur drei Kürzel (`ios/Dolmetscher/Views.swift`):

| Kürzel | Wirkung |
|---|---|
| ⌘Return | Start / Stopp |
| ⌘B | Satzbuch öffnen |
| ⌘/ | Hilfe öffnen |

Sonst gibt es Siri-Kurzbefehle, ein Steuerelement für Control Center, Sperrbildschirm und Aktionstaste sowie Widgets; siehe [ios/README.md](../ios/README.md).
