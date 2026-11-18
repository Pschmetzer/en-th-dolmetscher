# Fehlerhilfe

Zuerst der Blick ins Protokoll: `~/Library/Logs/Dolmetscher/engine.log` (ab etwa 1 MB rotiert). Gesprächstext steht nur drin, wenn die Engine mit `--log-text` lief; entferne Persönliches, bevor du ein Log teilst. Das Log der Ersteinrichtung liegt in `~/Library/Application Support/Dolmetscher/setup.log`. Englische Fassung: [en/TROUBLESHOOTING.md](en/TROUBLESHOOTING.md).

## Mikrofon

**Meldung „Kein Mikrofon-Zugriff“ (Mac)**
1. Systemeinstellungen, Datenschutz & Sicherheit, Mikrofon: Dolmetscher einschalten. Alternativ im Terminal zurücksetzen und beim nächsten Start neu erlauben: `tccutil reset Microphone io.github.dolmetscher.en-th`.
2. Fragt macOS nach jedem Neubauen erneut, liegt das an der Ad-hoc-Signatur. Mit stabiler Signatur bleibt die Erlaubnis: [CONTRIBUTING.md](../CONTRIBUTING.md#stable-code-signing).

**„Mikrofon liefert keine Daten“ oder „Mikrofon weg“**
1. In den Einstellungen das richtige Mikrofon wählen und die Mikrofonliste neu laden („Mikrofonliste neu laden“). Die Wahl gilt sofort.
2. Bei einem getrennten Mikrofon versucht die App es selbst erneut, zuerst mehrfach, dann alle 10 Sekunden. Stecke es wieder an.
3. Prüfe, ob der Zugriff erlaubt ist (siehe oben).

**Browser:** Meldung „Mikrofon blockiert“: in den Website-Einstellungen des Browsers das Mikrofon erlauben (Chrome: Symbol links in der Adresszeile). Meldung „Spracherkennung nicht erlaubt“ in Safari oder auf dem iPhone: Diktierfunktion einschalten (Einstellungen, Allgemein, Tastatur, Diktierfunktion). Firefox hat keine Spracherkennung, nimm Chrome.

**iPhone:** Mikrofon und Spracherkennung in den iOS-Einstellungen für die App erlauben.

## Modelle laden dauert

- Beim ersten Mal zeigt die App „Lade Modell zum ersten Mal herunter – das kann einige Minuten dauern“. Das ist einmalig; danach läuft die Erkennung ohne Netz. „Lade Sprachmodell …“ beim Start ist das Laden in den Speicher.
- Größen: Umgebung etwa 0,4 GB, mit den Standardmodellen (`medium`, `small`, Thai) etwa 3,5 GB. `best` (large-v3-turbo) braucht rund 1,6 GB mehr.
- Auf dem Build-Mac lädt `./build.sh --install` die Modelle vorab. Überspringen geht mit `DOLMETSCHER_SKIP_MODELS=1`, die App lädt sie dann beim ersten Start. Andere Auswahl: `DOLMETSCHER_MODELS="medium small th best"`.
- Zu langsam im Gespräch? Wähle das Modell `small` (`--model small`). Auf der Apple-GPU dauert ein Satz etwa 3 bis 5 Sekunden, auf der CPU deutlich länger ([bench/README.md](../bench/README.md)).
- Modelle liegen unter `~/.cache/huggingface/hub/`.

## Netz

- Aufnahme und Spracherkennung laufen auch ohne Netz. Übersetzung und die natürlichen Stimmen brauchen es.
- Die App zeigt den Netzstatus. Eine fehlgeschlagene Übersetzung hat den Knopf „Erneut versuchen“ und wird bei zurückkehrendem Netz selbst wiederholt.
- Ohne Netz übersetzt der Mac nur mit „Offline-Übersetzung (Apple) als Rückfall“: Sie braucht macOS 26.4 oder neuer und die Sprachpakete (Systemeinstellungen, Allgemein, Sprache & Region, Übersetzungssprachen). Vorgelesen wird dann mit der macOS-Stimme.
- Sprachausgabe-Dienst nicht erreichbar: die App fällt auf die lokale macOS-Stimme zurück. `--tts say` erzwingt das.
- iPhone: ohne installierte Sprachpakete wird nur mit eingeschaltetem „Online-Übersetzer als Ersatz“ übersetzt (Standard: aus). Sonst weist die App auf das fehlende Paket hin.
- Browser: Übersetzung braucht Netz; die Seite und das Satzbuch öffnen auch ohne.

## API-Schlüssel (Claude-Übersetzung)

Claude-Übersetzung ist optional und kostet pro Satz (Abrechnung bei Anthropic). Ohne Schlüssel übersetzt die App mit Google.

1. Schlüssel in den Einstellungen eintragen („Anthropic-API-Schlüssel“). Die App speichert ihn im Schlüsselbund. Zeigt sie „gespeichert, sieht aber nicht wie ein Anthropic-Schlüssel aus“, beginnt er nicht mit `sk-ant-`: neu kopieren.
2. „Speichern fehlgeschlagen“: Schlüsselbund-Zugriff prüfen und erneut speichern. Zum Entfernen gibt es „Schlüssel entfernen“.
3. Im Terminal gilt die Umgebungsvariable `ANTHROPIC_API_KEY`, sonst die Datei `~/Library/Application Support/Dolmetscher/anthropic_key`.
4. Mit Schlüssel ist Claude standardmäßig an; ausschalten im selben Einstellungsbereich. Auch ohne das Paket `anthropic`, bei Fehlern, unplausiblen Antworten oder erreichtem Monatslimit (`--llm-budget`) übersetzt Google automatisch.

## Thai-Stimme

- Die natürliche Thai-Stimme kommt online von Microsoft (`edge-tts`). Ist sie nicht erreichbar oder wird `--tts say` benutzt, spricht die macOS-Stimme.
- Fehlt die Thai-Systemstimme: Systemeinstellungen, Bedienungshilfen, Gesprochene Inhalte, Systemstimme, Stimmen verwalten, Thai (Kanya) laden.
- Männliche oder weibliche Stimme samt Höflichkeitsform (ครับ/ค่ะ): in den Einstellungen oder per Sprachbefehl „Translator, female voice“ beziehungsweise „male voice“. Mehr: [SPRACHBEFEHLE.md](SPRACHBEFEHLE.md).
- Thai wird unsicher erkannt? Lege ein Stimmprofil für die Person an und nutze `--model best`.

## Echo (die App übersetzt ihre eigene Stimme)

1. Kopfhörer benutzen. Das ist die sicherste Lösung.
2. Auf Laptop-Lautsprechern verwirft die Engine Audio, das während des Vorlesens (plus etwa 300 ms Nachhall) eintrifft. Bei zu vielen Fehlerkennungen die Empfindlichkeit senken (`--sensitivity low`) und die Rauschunterdrückung einschalten (`--denoise`).
3. `--barge-in` (Unterbrechen durch Sprechen) ist nur für Kopfhörer gedacht.
4. Ausgabegerät (Lautsprecher oder Kopfhörer) lässt sich in den Einstellungen wählen, auch während des Betriebs.

## Einrichtung schlägt fehl (Mac, erster Start)

1. Internet prüfen: Der Einrichtungsbildschirm meldet „Keine Internetverbindung“, wenn keins da ist.
2. Freien Speicher prüfen: Die Einrichtung zeigt den Bedarf (etwa 0,4 GB Umgebung, etwa 3,5 GB mit Modellen) und meldet „Nicht genug freier Speicher“ oder „Der Speicher ist voll“.
3. „Erneut versuchen“ drücken. „Log zeigen“ öffnet das Einrichtungs-Log (`setup.log`, siehe oben).
4. „Ein Download ist beschädigt (Prüfsumme stimmt nicht)“: später erneut versuchen oder die App aktualisieren.
5. „Dieser Mac wird nicht unterstützt“: Der Dolmetscher braucht Apple Silicon (M1 oder neuer), Intel-Macs gehen nicht.
6. „Diese App-Kopie ist unvollständig“: App neu laden beziehungsweise neu bauen (`./build.sh --install`).
7. Nach einem App-Update mit geänderten Paketen richtet die App die Umgebung selbst neu ein; manuell geht es in den Einstellungen mit „Python-Umgebung neu einrichten …“.

## Weitere Fälle

| Problem | Abhilfe |
|---|---|
| Zu viele Fehlerkennungen (Lärm, Fernseher, Tippen) | Empfindlichkeit senken, Rauschunterdrückung an |
| Übersetzung klingt steif | Claude-Übersetzung (`--llm`) und Ton `--style casual` |
| Eigennamen werden falsch übersetzt | in den Einstellungen ins Glossar eintragen (`~/Library/Application Support/Dolmetscher/glossary.txt`) |
| Engine stürzt ab, während das Fenster zu ist | macOS zeigt eine Mitteilung mit „Neustart“ |
| App und Engine passen nicht zusammen | beide auf denselben Stand bringen („Protokoll“ in [PROTOKOLL.md](PROTOKOLL.md)) |

Nichts gefunden? Ein Issue mit der Versionsnummer, dem Betriebssystem und dem relevanten Log-Ausschnitt hilft weiter.
