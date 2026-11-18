# Fehlerhilfe (Troubleshooting)

Was tun, wenn etwas nicht klappt – nach Plattform. Die Fehlercodes der Engine (`error.code`, `dropped.code`) sind
vollständig in [PROTOKOLL.md](PROTOKOLL.md) beschrieben; hier stehen die häufigsten mit Abhilfe.
Erste Schritte: [SCHNELLSTART.md](SCHNELLSTART.md), allgemeine Fragen: [FAQ.md](FAQ.md).

## Wo stehen Details?

| Was | Ort |
|---|---|
| Engine-Log (Mac) | `~/Library/Logs/Dolmetscher/engine.log`, rotiert bei ~1 MB (`engine.log.1`); anderer Ort mit `DOLMETSCHER_LOG` |
| Einrichtungs-Log (Mac, Erststart) | `~/Library/Application Support/Dolmetscher/setup.log` |
| App-Log (iPhone) | Subsystem `dolmetscher` in der Konsole bzw. `xcrun simctl spawn booted log stream --predicate 'subsystem == "dolmetscher"'` |

Gesprächstext steht **nicht** im Engine-Log, außer die Engine lief mit `--log-text`. Vor dem Teilen eines Logs trotzdem
persönliche Inhalte entfernen.

## Mac: Bauen (`build.sh`)

| Meldung | Ursache und Abhilfe |
|---|---|
| „Gebaut wird nur auf Apple Silicon …“ | Die App ist arm64-only; auf Intel-Macs geht weder Bau noch Betrieb |
| „uv fehlt …“ / „Hinweis: uv fehlt …“ | `brew install uv`. Ohne uv kann die App ihre Umgebung auf anderen Macs nicht einrichten; `--release` bricht ab |
| „uv X statt 0.12.7 …“ | Nur ein Hinweis für lokale Bauten; `--release` verlangt genau die in `build.sh` gepinnte Version (`UV_VERSION`) |
| „uv ist gegen fremde Bibliotheken gelinkt …“ | Ein Homebrew-uv mit `/opt/homebrew`-Bibliotheken startet auf fremden Macs nicht – das offizielle, eigenständige uv-Binary nutzen |
| „Python >= 3.12 nötig, die venv hat …“ | Alte venv löschen: `rm -rf ~/Library/Application\ Support/Dolmetscher/venv`, dann `./build.sh` erneut (uv lädt Python 3.12 selbst) |
| „--release braucht DOLMETSCHER_SIGN_IDENTITY …“ | Für lokale Bauten `./build.sh` ohne `--release` nutzen; für Releases siehe [CONTRIBUTING.md](../CONTRIBUTING.md#release-build) |
| „--release braucht DOLMETSCHER_NOTARY_PROFILE …“ | Notar-Profil anlegen (`xcrun notarytool store-credentials`) oder ausdrücklich `--no-notarize` |
| macOS fragt nach jedem Neubau wieder nach dem Mikrofon | Ad-hoc-Signatur ändert sich bei jedem Bau. Mit fester Identität bauen: `DOLMETSCHER_SIGN_IDENTITY="Dolmetscher Dev" ./build.sh --install` ([Anleitung](../CONTRIBUTING.md#stable-code-signing)) |

## Mac: Einrichtungs-Bildschirm (Erststart)

Die App zeigt ihn, wenn die Python-Umgebung fehlt oder ihr Stempel nicht zur App passt (z. B. nach einem Update mit
geänderten Paketen). Nach einem Fehler: Ursache beheben, dann „Erneut versuchen“.

| Meldung | Abhilfe |
|---|---|
| Keine Internetverbindung | Für die Einrichtung wird Internet gebraucht (Python, Pakete, Modelle). Verbinden, erneut versuchen |
| Nicht genug freier Speicher / Der Speicher ist voll | Platz schaffen: ~0,4 GB für die Umgebung, ~3,5 GB mit den Standardmodellen |
| Ein Download ist beschädigt (Prüfsumme stimmt nicht) | Hash-Prüfung gescheitert; Wiederholen hilft meist nicht sofort – App aktualisieren oder später erneut versuchen |
| Dieser Mac wird nicht unterstützt | Apple Silicon (M1 oder neuer) nötig |
| Diese App-Kopie ist unvollständig | Im Bundle fehlen uv, Lock, Stempel oder `setup-env.sh` – App neu bauen bzw. neu laden |
| Einrichtung fehlgeschlagen | Details in `setup.log` (siehe oben) |
| Abgebrochen | Ohne Einrichtung übersetzt die App nicht; erneut starten |

Eine fremde venv (etwa von `build.sh` mit conda- oder Homebrew-Python angelegt) wird nie gelöscht, sondern als
`venv.vorher-DATUM` beiseitegelegt. Neu aufsetzen von Hand: Einstellungen → „Python-Umgebung neu einrichten …“.

## Mac: Laufzeit

### Mikrofon

| Code / Symptom | Abhilfe |
|---|---|
| `mic_denied` – „Kein Mikrofon-Zugriff“ | Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon → Dolmetscher erlauben. Zurücksetzen: `tccutil reset Microphone io.github.dolmetscher.en-th` |
| `mic_not_found` | Der eingestellte Mikrofon-Name ist unbekannt; die Engine nimmt das Standardmikrofon. In den Einstellungen neu wählen (Name ist stabiler als Index) |
| `mic_unavailable`, `mic_no_data`, `mic_timeout` | Gerät ungültig / liefert nichts / erster Block kam nicht binnen 10 s. Anderes Mikrofon wählen, USB/Bluetooth neu verbinden |
| Mikrofon weg (AirPods aus, USB gezogen) | Die Engine verbindet selbst neu (5 schnelle Versuche, danach alle 10 s), bis es klappt oder du stoppst |
| `audio_missing` | PyAV (`av`) oder `avhelper.py` fehlt – Python-Umgebung neu einrichten |

### Erkennung

| Symptom | Abhilfe |
|---|---|
| Viele Fehl-Erkennungen (Lärm, TV, Tippen) | Empfindlichkeit senken (`--sensitivity low`), Rauschunterdrückung an (`--denoise`) |
| Leise oder kurze Sätze gehen verloren | Empfindlichkeit erhöhen (`--sensitivity high`); für Thai ein Stimmprofil anlegen |
| Blase verschwindet mit „unsicher“ | Erkennung zu unsicher (`dropped` `unsure`); die App bietet „Trotzdem übersetzen“ an |
| „weder Englisch noch Thai“ | Geräusch, Musik oder eine Sprache außerhalb des Paars (`other_language`). Die Erkennung wählt nur zwischen den zwei Sprachen des Paars |
| Thai wird schlecht erkannt | Stimmprofil für die Person anlegen, `--model best` |
| Satz wird zu früh abgeschnitten | Längere Pause bis Satzende (`--silence`, 0,4–2,0 s, Standard 0,7) |
| Verzögerung zu hoch | `--model small`; Teiltext (`--partial`) aus lassen (Standard). Auf der CPU ist es deutlich langsamer als auf der Apple-GPU |
| `model_offline` | Modell fehlt lokal und kann ohne Internet nicht geladen werden – einmal mit Netz starten |
| `vad_failed`, `python_env_broken` | Python-Umgebung kaputt (Pflichtmodul fehlt; bei `python_env_broken` beendet sich die Engine mit Exit-Code 3). Neu einrichten bzw. `./build.sh` erneut |

### Übersetzung und Stimme

| Code / Symptom | Abhilfe |
|---|---|
| `translate_failed`, Knopf „Erneut versuchen“ | Alle Anbieter gescheitert. Netz prüfen; die App versucht es automatisch erneut, sobald das Netz wieder da ist |
| Ohne Netz keine Übersetzung | Ab macOS 26.4 übersetzt „Offline-Übersetzung (Apple) als Rückfall“ (Standard an) auf dem Mac – Sprachpakete in den Systemeinstellungen laden. `offline_mt_missing`: `translate-helper` fehlt im Bundle (beim Bau ohne macOS-26-SDK übersprungen) |
| Hotel- oder Flughafen-WLAN | Ereignis `captive_portal`: erst im WLAN anmelden (Anmeldeseite im Browser) |
| Warnung an Zahlen | Die Zahlen der Übersetzung passten nicht zum Original, auch nicht beim zweiten Anbieter – Preis/Uhrzeit nachfragen |
| Eigennamen falsch übersetzt | Ins Glossar eintragen (Einstellungen bzw. `~/Library/Application Support/Dolmetscher/glossary.txt`) |
| Übersetzung klingt steif | Claude nutzen (`--llm`), Ton `--style casual\|neutral\|polite` |
| `llm_billing` | Claude-Guthaben/Kontingent erschöpft – 30 min Google/MyMemory, dann neuer Versuch |
| `llm_budget` | Eigenes Monatslimit (`--llm-budget`) erreicht – bis Monatsende Google/MyMemory |
| Claude wird nicht benutzt | Schlüssel fehlt (Einstellungen → Schlüsselbund; Terminal: `ANTHROPIC_API_KEY`) oder Paket `anthropic` fehlt – die Engine fällt dann still auf Google zurück |
| App übersetzt ihre eigene Stimme (Echo) | Kopfhörer nutzen. `--barge-in` (Unterbrechen durch Sprechen) nur mit Kopfhörern |
| Keine natürliche Stimme | Die Microsoft-Neural-Stimme (edge-tts) braucht Netz; sonst nimmt die Engine `say`. Thai-Systemstimme nachinstallieren: Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten → Thai (Kanya) |
| `output_not_found` | Ausgabegerät unbekannt, Systemstandard wird genutzt – in den Einstellungen neu wählen |
| `voice_unknown` | Unbekannte Stimme, die bisherige Wahl bleibt |
| Ältere Übersetzungen werden nicht vorgelesen | Rückstand: der Aufholmodus `--catch-up skip` (Standard) spricht schneller und überspringt alte Sätze (sie bleiben sichtbar). `fast` spricht nur schneller, `off` weder noch |

### Sprachbefehle

- Funktionieren nur mit **Englisch im Paar** und auf Englisch („Translator, …“ oder „Hey translator, …“).
- Einen Befehl auf einmal sagen; bei Lärm oder starkem Akzent kann er falsch verstanden werden.
- Nach „Translator, pause“ hört die Engine weiter auf Befehle: „Translator, resume“.

### Sonstiges

- Die Engine stürzt ab, während das Fenster zu ist: macOS zeigt eine Mitteilung mit „Neu starten“.
- Verlauf zeichnet nicht auf: `history_failed` (Datenbank nicht nutzbar) – Log prüfen. Der Verlauf ist standardmäßig aus (`--history`).
- `preset_invalid`: Eine Datei in `presets/` ist ungültig und wurde übersprungen; Format in [PRESETS.md](PRESETS.md).
- `langs_invalid`: Unbekannter Sprachcode oder zweimal dieselbe Sprache – das Paar bleibt unverändert.
- Stimmprofil scheitert (`too_few`, `inconsistent`): ruhiger Raum, alle 8 Sätze deutlich vorlesen, erneut versuchen.

## iPhone / iPad

| Symptom | Abhilfe |
|---|---|
| Xcode: Signatur-/Provisioning-Fehler | *Team* setzen und die *Bundle Identifier* auf etwas Eigenes ändern ([ios/README.md](../ios/README.md#build-and-run-on-your-iphone)) |
| Fehler zum Entitlement `increased-memory-limit` | Den Schlüssel aus `Dolmetscher.entitlements` entfernen; nur große Whisper-Modelle können dann knapp an Speicher werden |
| App startet nach 7 Tagen nicht mehr | Mit kostenloser Apple-ID signierte Apps laufen nach 7 Tagen ab – erneut aus Xcode installieren |
| „Nicht vertrauenswürdiger Entwickler“ | Einstellungen → Allgemein → VPN & Geräteverwaltung → Zertifikat vertrauen; ggf. Entwicklermodus einschalten |
| Sprache fehlt in der Liste | Für sie gibt es auf diesem Gerät keine Erkennung; ⬇︎ heißt: Modell, Sprachpaket oder Stimme fehlt noch |
| 🌐 an einem Sprachpaar | Apple übersetzt dieses Paar nicht auf dem Gerät – nur online („Online-Übersetzer als Ersatz“ einschalten) |
| Keine Übersetzung ohne Netz | Offline-Sprachpakete für das Paar laden (Einstellungen der App oder iOS → Apps → Übersetzen) |
| „Automatisch“ fehlt | Bei Paaren in derselben Schrift (z. B. Englisch ⇄ Deutsch) wählst du die Richtung durch Tippen |
| Whisper zeigt keinen Live-Text | So gewollt: Whisper liefert ganze Sätze nach der Pause. Ohne vollständiges Modell fällt die App auf Apples Erkennung zurück |
| Simulator übersetzt nicht | Apples Translation läuft im Simulator nicht – Online-Übersetzer einschalten oder auf echtem Gerät testen |

## Browser (Web Lite)

| Meldung / Symptom | Abhilfe |
|---|---|
| Knöpfe ausgegraut, „Keine Spracherkennung in diesem Browser“ | Der Browser hat keine Spracherkennung (z. B. Firefox). Chrome (Computer, Android) oder Safari (Mac, iPhone, Diktierfunktion an) nutzen, oder „Stattdessen tippen“; das Satzbuch geht trotzdem |
| „Mikrofon blockiert …“ | In den Website-Einstellungen erlauben (Chrome: Symbol links in der Adresszeile) |
| „Spracherkennung nicht erlaubt …“ | Safari/iPhone: Diktierfunktion einschalten (Einstellungen → Allgemein → Tastatur). Chrome: im Profil gesperrt |
| „Kein Mikrofon gefunden …“ | Mikrofon anschließen bzw. in den Systemeinstellungen für den Browser freigeben |
| „Diese Sprache wird … nicht unterstützt“ | Die Erkennung des Browsers kann diese Sprache nicht |
| „Die Spracherkennung antwortet nicht …“ | Chrome braucht für die Erkennung eine Verbindung zu Google – Netz prüfen, dann erneut `E`/`T` |
| Übersetzung bleibt aus | Netz nötig; nach zwei Fehlern wird ein Anbieter 60 s übersprungen. Fehler- oder Kontingentmeldungen werden nie als Übersetzung angezeigt |
| Nach einem Update alte Version | Seite neu laden; wer selbst hostet, muss nach Änderungen `CACHE` in `sw.js` erhöhen ([WEB-HOSTING.md](WEB-HOSTING.md)) |
| Selbst gehostet: kein Mikrofon, kein Offline | HTTPS ist Pflicht (oder `localhost`) |

Browser-Unterschiede im Detail: [WEB-KOMPATIBILITAET.md](WEB-KOMPATIBILITAET.md).

## Fehler melden

Issue im Repository öffnen und angeben: Plattform und Version (macOS/iOS/Browser), App-Version (`version` in
`pyproject.toml`, aktuell 1.2), Sprachpaar, was du erwartet hast und was passiert ist, und – ohne persönliche Inhalte –
die passenden Log-Zeilen. Falsche Sätze im Satzbuch: in der Web-Version in der Großansicht über ⚑ „Falsch? Melden“ (öffnet ein
vorbefülltes GitHub-Issue, es wird nichts automatisch gesendet).
