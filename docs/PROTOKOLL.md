# Engine ⇄ App: Protokoll (Version 1)

Die Mac-App startet `dolmetscher.py --json …`. Die Engine schreibt **eine JSON-Zeile pro Ereignis** auf stdout.
Die App schickt Einstellungen als **JSON-Zeilen auf stdin**. Unbekannte Felder werden auf beiden Seiten ignoriert.

## Neu: Sprachausgabe läuft asynchron

Erkennung und Übersetzung des nächsten Satzes laufen, während der vorige noch vorgelesen wird.
Deshalb kann `thinking` für Satz 2 kommen, während Satz 1 noch `speaking` ist.
Jede Äußerung hat eine `id` (String, z. B. `"u7"`). Die App darf den Status „spricht“ nur über
`speaking`/`speak_done` setzen bzw. zurücksetzen, **nicht** über `listening`.

## Sprachpaar (mehrsprachig)

Die Engine dolmetscht zwischen **zwei** Sprachen: „meine Sprache“ (`mine`, Rolle „ich“) und „Partnersprache“
(`partner`). Standard ist `en` + `th` – ohne Angabe verhält sich alles wie früher. Die Erkennung wählt nur
zwischen den zwei Sprachen des Paars; andere Sprachen gelten als `other_language`.

- Start: `--langs MEINE,PARTNER` (z. B. `--langs de,th`), zur Laufzeit `{"langs": {"mine": "de", "partner": "th"}}`.
  Ungültig (unbekannter Code, zweimal dieselbe Sprache): `error` `langs_invalid`, das Paar bleibt (beim Start: `en,th`).
- Bestätigung: Ereignis `langs` (`mine`, `partner`); `ready` und `command` tragen `langs` ebenfalls.
- Codes (Sprachtabelle `LANGS` in `dolmetscher.py`): `en` `th` `de` `es` `fr` `it` `pt` `nl` `ru` `zh` `ja` `ko`
  `vi` `id` `ar` `hi` `tr` `pl` `uk`. Ereignisse tragen weiter `lang`/`to` als Code.
- Thai-Sonderlogik (ครับ/ค่ะ nach `polite`, 555 = Lachen, Thai-Füllwörter, Thai-Zahlwörter, Thai-Satztrennung,
  asiatische Erkennungs-Labels zählen als Thai, Thai-Modell) greift nur mit Thai im Paar.
- Sprachbefehle („Translator, …“) sind Englisch und werden **nur mit Englisch im Paar** ausgewertet. Neben
  „Thai only“/„English only“ versteht die Engine die englischen Namen der Tabelle („German only“, „Spanish off“).
- Zwei-Personen-Modus und Stimmprofile: Profile werden weiter auf Englisch oder Thai angelegt (`--enroll-lang`).
  Rolle „ich“ (englisches Profil) = Englisch, wenn Englisch im Paar ist, sonst meine Sprache; „other“ = die andere.
- Schrift-Plausibilität (Übersetzung „unübersetzt“ oder in falscher Schrift) nur bei Sprachen mit getrennter
  Schrift (en/th, de/ja, es/ru …); bei gleicher Schrift (de/es, ru/uk, zh/ja) entfällt sie.

## Startargumente

Die Tabelle wird per Test (`tests/test_protocol_docs.py`) mit `argparse` abgeglichen: jedes Argument muss
hier stehen, Standardwerte in der Spalte „Standard“.

| Argument | Standard | Bedeutung |
|---|---|---|
| `--model small\|medium\|best\|auto` | `medium` | Erkennungsmodell; `best` = large-v3-turbo + Thai-Modell, `auto` nach Chip/RAM (Ereignis `hwprofile`) |
| `--device auto\|mps\|cpu` | `auto` | Rechengerät (Apple-GPU, sonst CPU) |
| `--mic INDEX\|NAME\|default` | `0` | Mikrofon: Index aus `--list-mics`, besser der **Name** (Indizes verschieben sich, sobald AirPods/USB-Mikros dazukommen; der Name wird erst beim Öffnen auf den aktuellen Index abgebildet). Unbekannter Name: `error` `mic_not_found`, Standardmikrofon |
| `--list-mics` | | gibt `{"event":"mics","mics":[{"index":"0","name":"MacBook Pro Microphone"}]}` aus und beendet sich; bei Fehler (ffmpeg fehlt/hängt) zuerst `error` (`mic_list_failed`), dann `mics` mit leerer Liste |
| `--polite krub\|ka` | `krub` | Höflichkeitswort/Stimme Thai |
| `--langs MEINE,PARTNER` | `en,th` | Sprachpaar (siehe „Sprachpaar“) |
| `--lang auto\|CODE` | `auto` | Sprach-Sperre auf eine Sprache des Paars (sonst `auto`) |
| `--tts edge\|say` | `edge` | Neural-Stimme (edge-tts) oder macOS `say` |
| `--file DATEI …` | | Dateien statt Mikrofon übersetzen (Test/Benchmark); lange Dateien werden an leisen Stellen in Stücke bis 30 s geteilt, eine kaputte Datei ergibt `error` (`file_empty`/`file_failed`) und bricht die übrigen nicht ab |
| `--mute` | | nicht vorlesen |
| `--json` | | Ereignisse als JSON-Zeilen (App), Steuerung über stdin |
| `--no-en`, `--no-th` | | Englisch bzw. Thai nicht übersetzen (nur anzeigen) |
| `--no-mine`, `--no-partner` | | meine Sprache bzw. Partnersprache nicht übersetzen (nur anzeigen) |
| `--profiles` | | Stimmprofile als `profiles` ausgeben |
| `--enroll NAME`, `--enroll-lang en\|th` | `en` | Stimmprofil anlegen (8 Sätze vorlesen) |
| `--delete-profile NAME` | | Stimmprofil löschen (`profile_deleted`) |
| `--delete-all-profiles` | | alle Stimmprofile samt Sicherungen löschen (`profiles_deleted_all`) |
| `--vocab NAME WÖRTER` | | eigene Wörter eines Profils, kommagetrennt (`profile_saved`) |
| `--profile-stdin` | | Profilname/Wörter als JSON-Zeile von stdin statt argv (siehe unten) |
| `--barge-in` | | Sprechen unterbricht die Ausgabe (nur mit Kopfhörer) |
| `--log-text` / `--no-log-text` | aus | Gesprächstexte ins Log schreiben |
| `--rate N` | `0` | Sprechtempo in %, −50 … 50 |
| `--volume F` | `1.0` | Lautstärke 0.2 … 2.0 |
| `--silence S` | `0.7` | Sekunden Stille bis Satzende, 0.4 … 2.0 |
| `--sensitivity low\|normal\|high` | `normal` | Empfindlichkeit der Sprach-Erkennung (VAD) |
| `--denoise` | | Rauschunterdrückung im Mikrofon-Filter |
| `--voice-en NAME`, `--voice-th NAME` | | Neural-Stimme (z. B. `en-US-JennyNeural`, `th-TH-PremwadeeNeural`); ohne Angabe: Englisch `en-US-AriaNeural`, Thai nach `--polite` |
| `--voice-mine NAME`, `--voice-partner NAME` | | Neural-Stimme für meine Sprache bzw. die Partnersprache (aus `LANGS`); ohne Angabe: Partnersprache nach `--polite` (Mann/Frau), meine Sprache Frauenstimme, Englisch Aria |
| `--llm` | | Übersetzung mit Claude (braucht API-Schlüssel, sonst automatisch Google) |
| `--llm-model ID` | `claude-haiku-5-5` | günstig und schnell; `claude-sonnet-5-5` genauer |
| `--llm-budget USD` | `0.0` | Claude-Monatslimit in US-Dollar (0 = keins). Darüber übersetzt Google bis Monatsende; einmal `error` `llm_budget`. Monatssumme in `llm_spend.json` (0600) im Application-Support-Ordner |
| `--style casual\|neutral\|polite` | `casual` | Ton der Claude-Übersetzung |
| `--earcons` | | Signalton statt gesprochener Bestätigung bei Sprachbefehlen |
| `--meter` | | Pegel-Ereignisse `level` senden |
| `--no-two-person` | | Zwei-Personen-Modus aus |
| `--fast-endpoint` / `--no-fast-endpoint` | aus | schnelles Satzende, nur Englisch |
| `--no-pre` | | keine Vorab-Erkennung |
| `--partial` / `--no-partial` | aus | Teiltext während des Sprechens |
| `--tts-race S` | `1.4` | s bis die vorbereitete macOS-Stimme einspringt (0 = aus) |
| `--idle` | | Modelle laden, Mikrofon erst mit `{"listen": true}` öffnen |
| `--profile-polite NAME FORM` | | Höflichkeitsform der Person für Thai-Ausgaben (`krub`, `ka`, `-` = wie Einstellung); antwortet mit `profile_saved`. Spricht diese Person (erkanntes Profil oder Rolle), endet die Thai-Übersetzung mit ihrer Form statt mit `--polite` |
| `--history` | | Gesprächsverlauf lokal speichern |
| `--history-days N` | | Verlauf älter als N Tage beim Start löschen |
| `--history-export FORMAT`, `--history-session ID`, `--out PFAD`, `--history-search TEXT`, `--history-purge TAGE`, `--history-clear` | | Verlaufs-Befehle (siehe „Gesprächsverlauf“) |

### Umgebungsvariablen

| Variable | Wirkung |
|---|---|
| `ANTHROPIC_API_KEY` (oder `ANTHROPIC_AUTH_TOKEN`) | Claude-Schlüssel; alternativ Datei `~/Library/Application Support/Dolmetscher/anthropic_key` (nur der Schlüssel, Rechte 0600) |
| `DOLMETSCHER_BEAM` | Beam-Breite der Erkennung (Standard 1; überschreibt `--model auto`) |
| `DOLMETSCHER_MIC_FILE` | Audiodatei in Echtzeit statt Mikrofon (Ende-zu-Ende-Test) |
| `DOLMETSCHER_MIC_LOOP` | mit `DOLMETSCHER_MIC_FILE`: Datei endlos wiederholen |
| `DOLMETSCHER_FFMPEG` | optional: externes ffmpeg statt PyAV für Aufnahme, Wiedergabe und `--file` (nur wenn gesetzt; Standard ist `avhelper.py` mit PyAV) |
| `DOLMETSCHER_HOME` | Ordner für Presets/Verlauf (Standard `~/Library/Application Support/Dolmetscher/`) |
| `DOLMETSCHER_LOG` | Logdatei (Standard `~/Library/Logs/Dolmetscher/engine.log`) |
| `DOLMETSCHER_DEBUG` | VAD-Diagnose ins Log |
| `DOLMETSCHER_NULL_AUDIO` | keine Tonausgabe (Tests) |
| `DOLMETSCHER_SPEAKER_MODEL`, `DOLMETSCHER_SPEAKER_MODEL_URL` | Stimmprofil-Modell aus Datei bzw. URL |

## Ereignisse (stdout)

| event | Felder | Hinweis |
|---|---|---|
| `loading` | `msg`, `download` (optional, true: Modell wird einmalig heruntergeladen, kann Minuten dauern) | |
| `download_progress` | `model` (Name wie `--model` bzw. Repo-ID), `done_mb` (bereits auf der Platte), `total_mb` (Gesamtgröße laut Hub, sonst Schätzung; `null`, wenn unbekannt), `final` (bool: Download dieses Modells fertig) | nur während ein fehlendes Modell geladen wird (nach `loading` mit `download: true`), höchstens ~2×/s und nur bei Änderung. Gezählt werden die Bytes im Hugging-Face-Cache (auch `.incomplete`), deshalb funktioniert es auch mit hf-xet. Ältere Apps ignorieren das Ereignis |
| `llm_cost` | `usd`, `month_usd` | geschätzte Claude-Kosten der Sitzung bzw. des Kalendermonats (nach Preisliste, über Neustarts) |
| `missed` | `why` (`cut`\|`overlap`), `dur` (s Ausgabe), `rms` | Während der eigenen Sprachausgabe wurde vermutlich gesprochen und der Teil verworfen (Halbduplex): `cut` = ein Satz lief noch, als die Ausgabe begann (der Anfang wird übersetzt, der Rest fehlt); `overlap` = direkt nach Ende der Ausgabe (und des Nachhalls) ist schon Sprache da. Höchstens einmal je Ausgabe; nie mit `--barge-in`. Echo der eigenen Stimme löst es nicht aus (während der Sperre wird nichts gemessen), ein Gespräch über Lautsprecher kann aber trotzdem `overlap` melden |
| `ready` | `msg`, `device`, `llm` (bool: Claude aktiv), `protocol`, `engine_version`, `langs` (`{"mine", "partner"}`); optional `degraded` (Liste: `detect_model`, `thai_model` – Modell nicht geladen, Erkennung läuft schwächer über das Hauptmodell) | |
| `langs` | `mine`, `partner` | Sprachpaar nach `{"langs": …}` geändert |
| `listening` | | Mikrofon bereit; ändert den Sprech-Status nicht |
| `hearing` | `id` (beim Mikrofon) | jemand spricht gerade; die `id` gilt für die ganze Äußerung |
| `thinking` | `id` | Äußerung `id` wird erkannt/übersetzt → Platzhalter-Blase |
| `heard` | `id`, `lang`, `text`, `text_latin` (Thai, optional) | **neu:** erkannter Originaltext, sofort nach der Erkennung, noch vor der Übersetzung (Mikrofon und `reassign`). Die App füllt damit die Platzhalter-Blase; `utt` mit derselben `id` ergänzt die Übersetzung. Ältere Apps ignorieren das Ereignis |
| `dropped` | `reason` (deutscher Freitext), `code` (stabil, siehe unten), `id`; bei `code` `unsure` zusätzlich `text`, `lang`, `lp`; bei `translate_failed` zusätzlich `text`, `lang` | Platzhalter `id` entfernen. Bei `unsure` kann die App den gehörten Text zeigen und „trotzdem übersetzen“ per `retranslate` anbieten, bei `translate_failed` „Erneut versuchen“ (ebenfalls `retranslate`) |
| `utt` | `id`, `lang`, `to`, `text`, `out`, `stt`, `tr` (s), `lp` (Erkennungs-Konfidenz, log-prob, ≈ −0.1 sicher … −1.3 unsicher), `translated`, `provider` (`claude`\|`google`\|`mymemory`\|`none`), `speaker`, `replaces` (optional: id der korrigierten Blase), `source` (`mic`\|`phrase`\|`edit`\|`reassign`); optional: `text_latin`/`out_latin` (lesbare RTGS-Umschrift für Thai, nur mit pythainlp), `alts` (andere Lesarten), `role` (`me`\|`other`), `num_warn` (Ziffern weichen ab), `ready_s`, `suggest_vocab`. Ohne Übersetzung (Richtung abgeschaltet): `translated: false`, `provider: "none"`, `out` = `text`, kein `out_latin`, kein Vorlesen | |
| `speaking` | `id`, `first_s` (s bis zum ersten Ton) | nur wenn wirklich Ton kommt (nicht bei stumm, Überspringen, Abbruch vor dem ersten Ton); `id` = `"cmd"` bei Befehlsantworten und „repeat“ |
| `speak_done` | `id`, `skipped` (bool), `interrupted` (bool), optional `partial` (true) | kommt für jede eingereihte Ausgabe **genau einmal**, auch ohne vorheriges `speaking`; `skipped`: wegen Rückstand/Stopp nicht vorgelesen; `partial`: Neural-Stimme riss mitten im Satz ab (nur teilweise vorgelesen, App kann Wiederholen anbieten) |
| `queue` | `stt` (wartende Äußerungen), `tts` (wartende Ausgaben) | bei jeder Änderung |
| `level` | `rms` (0…1, dBFS skaliert), `voice` (bool) | ~7×/s, nur mit `--meter` |
| `net` | `ok` (bool), `what` (`translate`\|`tts`) | nur bei Zustandswechsel |
| `command` | `text`, `reply`, `paused`, `lang`, `tr_en`, `tr_th`, `polite`, `rate`, `volume`, `voice_en`, `voice_th` (fehlende Sprache: `true`/`""`), `langs` (`{"mine", "partner"}`), `tr` und `voices` (Code → Wert, je Sprache des Paars); `clear` (true) nach „Translator, clear“ | App speichert `rate`/`volume` dauerhaft; bei `clear` Verlauf in der App leeren |
| `error` | `msg` (deutscher Freitext), `code` (stabil, siehe unten; fehlt nur bei alten Meldungen) | |
| `barge_in` | | |
| `mics` | `mics` (Liste `{index, name}`) | Antwort auf `--list-mics`; die App sollte den **Namen** speichern |
| `profiles` | `profiles` (Liste öffentlicher Profilfelder) | Antwort auf `--profiles` |
| `profile_saved` | `profile` | nach `--enroll` bzw. `--vocab` |
| `profile_deleted` | `name`, `ok` (bool) | Antwort auf `--delete-profile` |
| `profiles_deleted_all` | `ok` (bool), `files` (Anzahl) | Antwort auf `--delete-all-profiles`: alle Profile samt Sicherungen (`.bak`) und Quarantäne-Kopien (`.bad`) gelöscht |

### `dropped.code`

| `code` | `reason` (Beispiel) | Bedeutung |
|---|---|---|
| `too_short` | zu kurz | unter 0,3 s Sprache |
| `command` | befehl | Sprachbefehl erkannt (Antwort kommt als `command`) |
| `other_language` | weder Englisch noch Thai (bzw. die Namen des Paars) | Geräusch, Musik, andere Sprache |
| `locked` | nur Thai aktiv / nur Englisch aktiv / nur Deutsch aktiv … | Sprach-Sperre |
| `paused` | pausiert | „Translator, pause“ aktiv |
| `unsure` | unsicher | Erkennung zu unsicher; mit `text`, `lang`, `lp` (App bietet „Trotzdem übersetzen“ per `retranslate` mit dieser `id` an) |
| `hallucination` | halluzination (…) | typische Whisper-Erfindung |
| `filler` | floskel | „Thank you.“ u. ä. bei sehr leiser, kurzer Aufnahme |
| `empty` | nichts erkannt | kein Text |
| `translate_failed` | übersetzung fehlgeschlagen | zusätzlich `error` mit `code` `translate_failed`; mit `text`, `lang` für „Erneut versuchen“ |
| `error` | fehler | interner Fehler bei diesem Satz |
| `other` | | unbekannter Grund (App: allgemeine Meldung) |

### `error.code`

| `code` | Bedeutung |
|---|---|
| `mic_denied`, `mic_unavailable`, `mic_no_data`, `mic_timeout`, `mic_failed` | Mikrofon: Zugriff verweigert / Gerät ungültig / keine Daten / erster Block nicht binnen 10 s (Wachhund beendet ffmpeg) / Gerät nach Wiederverbinden weg |
| `mic_not_found` | Mikrofon-Name unbekannt, Standardmikrofon wird genutzt |
| `mic_list_failed` | `--list-mics` konnte ffmpeg nicht abfragen |
| `mic_file_missing`, `ffmpeg_missing` | `DOLMETSCHER_MIC_FILE` fehlt / das per `DOLMETSCHER_FFMPEG` gesetzte ffmpeg fehlt (gleich beim Start gemeldet) oder ist nicht startbar |
| `audio_missing` | Audio-Baustein fehlt: PyAV (`av`) nicht importierbar oder `avhelper.py` fehlt (gleich beim Start gemeldet) – Python-Umgebung neu einrichten |
| `model_offline` | Modell fehlt lokal und kann ohne Internet nicht geladen werden |
| `translate_failed` | Übersetzung fehlgeschlagen (alle Anbieter) |
| `llm_billing` | Claude-API: Guthaben oder Kontingent erschöpft – 30 min nur Google/MyMemory, dann neuer Versuch |
| `llm_budget` | eigenes Claude-Monatslimit (`--llm-budget`/`llm_budget`) erreicht – bis Monatsende Google/MyMemory; einmal je Monat |
| `mic_invalid` | Steuerfeld `mic` ungültig (kein Text/keine Zahl); Gerät unverändert |
| `reassign_expired`, `reassign_empty`, `reassign_invalid` | „Das war ich/sie“: Satz nicht mehr im Speicher / nichts erkannt / Anfrage ungültig |
| `phrase_invalid`, `edit_invalid`, `speak_invalid` | Schnellsatz, Korrektur bzw. Vorlesen (`speak_text`) ungültig |
| `profiles_failed` | Stimmprofile/Sprechermodell nicht ladbar – Stimmerkennung aus; `msg` nennt die Ursache |
| `voice_unknown`, `glossary_invalid` | Steuerwert ungültig |
| `langs_invalid` | Sprachpaar ungültig (unbekannter Code oder zweimal dieselbe Sprache); Paar unverändert |
| `file_empty`, `file_failed` | `--file`: keine Audiodaten / Datei nicht lesbar |

### Reihenfolge und Garantien

- Je `id`: `hearing` (nur Mikrofon) → `thinking` → optional `heard` → **genau ein** `utt` oder `dropped`.
  `dropped` für „zu kurz“ kommt ohne `thinking`, aber mit der `id` aus `hearing`.
- `speak_done` kommt für jede eingereihte Ausgabe genau einmal (siehe oben).
- `retranslate`/`reassign`: neue `id` mit `thinking` → `utt` mit `replaces`. Schlägt es fehl, kommt `dropped`
  (neue `id`) bzw. `error` – die alte Blase bleibt dann stehen. Eine ersetzte Äußerung fällt aus dem
  Claude-Kontext und wird von „Translator, repeat“ nicht mehr wiederholt.
- Schnellsätze, Korrekturen und Mikrofon-Start aus der App werden vor wartenden Äußerungen bearbeitet.
  Ab 3 wartenden Äußerungen spart die Engine Zusatz-Läufe (zweite Sprachprüfung, zweite Thai-Lesart).
- Sprachbefehle nimmt die Engine nicht von der Partner-Stimme an (`role` `other` bei Stimmprofil).
  Nach „Translator“ gilt ein Folgesatz (höchstens 4 Wörter) 6 s lang als Befehl – ab Ende des „Yes?“.
- `say`/`retranslate`: Ist der Text klar in der eigenen Schrift einer Paarsprache geschrieben (Thai, Japanisch,
  Russisch …; bzw. klar in der Schrift der anderen bei `lang` = so eine Sprache), korrigiert die Engine `lang`.
  Bei gleicher Schrift (de/es) gilt die Angabe der App.
- stdout ist UTF-8 (unabhängig von der Locale). Mit `--json` schreibt ein eigener Thread: liest die App die
  Pipe nicht, blockiert nur dieser, nie Erkennung oder Stopp. Läuft die Warteschlange (2000 Zeilen) voll,
  fallen zuerst `level`/`partial`/`queue` weg, danach die ältesten Zeilen. Beim Beenden wartet die Engine
  höchstens 1,5 s auf das Leeren.

## Steuerung (stdin)

Grundfelder: `langs` (`{"mine": CODE, "partner": CODE}`, zuerst angewandt), `tr_en`, `tr_th` (bool; allgemein `tr_<code>` für jede Sprache der Tabelle, `tr_mine`, `tr_partner`), `lang` (`auto` oder eine Sprache des Paars), `polite` (`krub`\|`ka`), `speak` (bool, false = stumm), `paused` (bool), `listen` (bool, siehe unten), `ping`.

Neu:

| Feld | Typ | Wirkung |
|---|---|---|
| `rate` | int | Sprechtempo |
| `volume` | float | Lautstärke |
| `silence` | float | Satzende-Pause |
| `sensitivity` | `low\|normal\|high` | VAD-Schwellen |
| `voice_en`, `voice_th` | string | Stimme (leer = Standard); allgemein `voice_<code>` für jede Sprache der Tabelle |
| `llm` | bool | Claude-Übersetzung an/aus |
| `style` | `casual`\|`neutral`\|`polite` | Ton der Claude-Übersetzung |
| `glossary` | string | eigene Wörter, eine Zeile `Wort => Übersetzung` oder nur `Name` |
| `earcons` | bool | Signaltöne statt Sprache bei Befehlen |
| `stop_speaking` | true | laufende und wartende Ausgaben abbrechen |
| `say` | `{"text": "...", "lang": CODE}` (Sprache des Paars, Standard `en`) | Schnellsatz: übersetzen und vorlesen wie eine Äußerung (`source: "phrase"`) |
| `retranslate` | `{"id": "u7", "text": "korrigierter Text", "lang": "en"\|"th"}` | neu übersetzen und vorlesen; `utt` kommt mit `replaces: "u7"`, `source: "edit"` |
| `speak_text` | `{"text": "...", "lang": CODE (Sprache des Paars), "id": "u7"}` | fertigen Text nur vorlesen (Neural-Stimme, keine Übersetzung) – „Nochmal sprechen“; `id` optional, dann kommen `speaking`/`speak_done` mit dieser id (ohne `latency_s`). Ungültig: `error` `speak_invalid`. Nicht verwechseln mit `speak` (bool, stumm schalten) |
| `mic` | string (Index, Gerätename oder `default`) | Mikrofon zur Laufzeit wechseln, ohne Modelle neu zu laden: ist es an, öffnet die Engine ffmpeg mit dem neuen Gerät neu (danach `mic` `on: true`; wartende Äußerungen des alten Geräts verfallen, laufende Ausgaben nicht); ist es aus, gilt das Gerät beim nächsten `listen`. Vor `ready` gesendet: gilt, sobald das Mikrofon angelegt wird. Unbekannter Name: `error` `mic_not_found`, Standardmikrofon |
| `llm_budget` | float (USD, 0 … 10000) | Claude-Monatslimit wie `--llm-budget`; 0 = keine Grenze |
| `reassign` | `{"id": "u7", "role": "me"\|"other"}` | „Das war ich/Partner“: Satz in der Sprache dieser Person (ich = Englisch bzw. meine Sprache, Partner = die andere Sprache des Paars) neu erkennen und übersetzen; `utt` kommt mit `replaces: "u7"`, `source: "reassign"`, `role`. Führt den Stimmabdruck des Profils nach (Gewicht 0,15). Behalten werden die letzten 30 Sätze |

## Tempo-Ausbau (Branch feat/tempo)

### Engine bleibt geladen (kein Modell-Laden bei jedem Start)

- Neues Startargument `--idle`: Modelle laden, Mikrofon **aus**. Die App startet die Engine damit
  gleich beim App-Start im Hintergrund.
- Steuerung `{"listen": true}` öffnet das Mikrofon (Start-Knopf), `{"listen": false}` schließt es
  wieder (Stopp-Knopf; Mikrofon-Anzeige von macOS geht aus). Die Modelle bleiben geladen.
- Ereignis `mic` mit `on` (bool) bestätigt den Zustand. `ready` kommt einmal nach dem Laden.
- Laufende/wartende Ausgaben werden bei `listen: false` abgebrochen.

### Teiltext und Vorab-Erkennung

- Jede Äußerung bekommt ihre `id` schon beim Sprechbeginn (`hearing` hat jetzt `id`).
- Neues Ereignis `partial` mit `id`, `text`, `lang`: vorläufiger Text, während noch gesprochen wird
  (etwa alle 2 s, nur wenn die Engine nicht ausgelastet ist). Die App zeigt ihn in der Platzhalter-Blase.
  **Standard aus** (`--partial` schaltet ein): Die Engine hat nur einen Arbeits-Thread, ein Teiltext
  kann die eigentliche Erkennung um bis zu ~0,5 s verzögern.
- Vorab-Erkennung (`--no-pre` schaltet aus): nach 0,35 s Pause wird schon erkannt; ist die Äußerung
  bei der vollen Pause unverändert, wird das Ergebnis wiederverwendet. Die Erkennung selbst ändert sich nicht.
- Danach kommen wie bisher `thinking` → `utt`/`dropped` mit derselben `id`.

### Latenz

- `speaking` hat zusätzlich `latency_s`: Sekunden vom Ende der Äußerung (letzter Sprach-Frame)
  bis zum ersten Ton. `utt` hat zusätzlich `ready_s`: Sekunden vom Ende der Äußerung bis die
  Übersetzung fertig ist.

### Neue Einstellungen

| Startargument | Steuerung | Bedeutung |
|---|---|---|
| `--tts-race S` (Standard 1.4, 0 = aus) | `tts_race` (float) | kommt die Neural-Stimme nicht in S Sekunden, spricht sofort die vorbereitete macOS-Stimme |
| `--fast-endpoint` (Standard aus) | `fast_endpoint` (bool) | schnelles Satzende, **nur Englisch**: endet der vorab erkannte Text mit . ? ! (und ist sicher erkannt), nicht bis zur vollen Pause warten. Thai nie, weil ครับ/ค่ะ/นะ auch Teilsätze beenden. Standard aus, weil Whisper fast immer einen Punkt setzt und Sätze sonst bei kurzen Denkpausen zerteilt werden |
| `--partial` | `partial` (bool) | Teiltext während des Sprechens (Standard aus) |

## Zwei-Personen-Modus und lockeres Thai (Branch feat/rollen)

- `two_person` (bool, Standard an; Startargument `--no-two-person`): Englisch kommt von der Person mit
  englischem Stimmprofil, jede andere Stimme spricht Thai. Ohne englisches Profil wirkungslos.
  Unklare Ähnlichkeit oder klar andere Sprache in der Erkennung → wie bisher.
- `reload_profiles` (true): Stimmprofile neu laden (App schickt es nach Anlegen/Löschen).
- Ereignis `roles` mit `me` (Profilname oder null) und `on` (bool).
- Lachen (555, ฮ่าๆ, haha, lol) wird nicht übersetzt, sondern als Lachen der Zielsprache angehängt.

## Schneller Ton, Laden, Sprachprüfung (Branch feat/schneller-ton-und-ui)

Am Protokoll ändert sich nichts (keine neuen Ereignisse oder Felder). Verhalten der Engine:

- **Englische Standardstimme `en-US-AriaNeural`** statt `en-US-AvaMultilingualNeural`. Gemessen: Die
  Multilingual-Stimmen liefern den ersten Ton erst nach 1,5–4 s (dann sprang fast immer die macOS-Stimme
  ein), Aria/Jenny/Guy nach 0,4–0,7 s. `th-TH-AcharaNeural` gibt es beim Dienst nicht mehr.
- **Vorab geöffnete Verbindung zur Neural-Stimme:** Bei Sprechbeginn (`hearing`) und vor dem Übersetzen
  öffnet die Engine bis zu zwei Websockets und schickt die Audio-Konfiguration. Der Text folgt, sobald die
  Übersetzung da ist. Erster Ton gemessen nach ~0,12 s statt ~0,5 s. Verbindungen älter als 20 s werden
  nicht mehr benutzt; schlägt eine fehl, wird einmal frisch geöffnet. Ändern sich die Interna von edge-tts,
  läuft automatisch der alte Weg (`edge_tts.Communicate`). Im Log: `tts … "pooled": true`.
- **Überholte Vorab-Erkennung:** Wurde nach der kurzen Pause weitergesprochen, wird eine noch wartende
  Vorab-Erkennung übersprungen (Log `pre … "skipped": "überholt"`), statt den Arbeits-Thread zu blockieren.
- **`--model best`** lädt large-v3-turbo als Hauptmodell (Englisch, Rückfall, zweite Lesart) und kein
  zusätzliches medium mehr; small und das Thai-Modell laden gleichzeitig. Start gemessen 8–10 s statt 14–19 s,
  ~0,45 GB weniger Speicher.
- **Zweite Sprachprüfung:** Würde ein Satz als „weder Englisch noch Thai“ verworfen, obwohl Englisch oder
  Thai mindestens 5 % haben und die fremde Sprache unter 85 % liegt (typisch: Englisch mit Akzent, vom kleinen
  Modell für Deutsch/Spanisch gehalten), entscheidet das Hauptmodell. Log: `second_look`, `times.detect2`.

## Beenden, Handshake, Härtung (Branch feat/verbesserungen-rundum, Engine-Seite)

- `ready` hat zusätzlich `protocol` (Zahl, aktuell `1`) und `engine_version` (String).
- stdin `{"ping": <id>}` -> Ereignis `pong` (mit derselben `id`, wenn Zahl/Text bis 64 Zeichen). Zeigt, dass die Steuerung lebt.
- Ende von stdin (App beendet oder abgestürzt) beendet die Engine geordnet (Ausgabe stumm, ffmpeg beendet, Exit 0). SIGTERM/SIGINT ebenso; ein zweites Signal beendet sofort.
- Steuerwerte: Wahrheitswerte nur `true`/`false` (auch `"true"`/`"false"`, `0`/`1`), anderes wird ignoriert. Unbekannte Stimme (`voice_en`/`voice_th`) -> `error`-Ereignis, Standardstimme. `glossary` max. 20000 Zeichen, `say`/`retranslate`-Text max. 1000 Zeichen, sonst `error`.
- `mic` kann `reconnecting` (true) und `attempt` enthalten: die Quelle (Gerät) ist weggefallen, die Engine verbindet mit Wartezeit neu (bis 5 Versuche); danach `error` und (ohne `--idle`) Ende.
- `error` bei Mikrofonproblemen nennt Zugriff verweigert / ffmpeg fehlt / Quelle ungültig.
- `--profile-stdin`: Profilname und Wörter als eine JSON-Zeile von stdin statt per Startargument: `{"enroll": "Name", "enroll_lang": "en", "delete_profile": "Name", "vocab": ["Name", "wort1, wort2"], "polite": ["Name", "krub"|"ka"|""]}`.
- Befehle: `repeat` nutzt wie alle Befehle den gemeinsamen Abschluss (`command`-Ereignis, Log); „Clear“ leert auch Texte, Wiederholung und Roh-Audio im Speicher. Ein Folgesatz nach „Translator“ gilt nur bei höchstens 4 Wörtern als Befehl.

## Hardware-Auswahl und Korrektur-Vorschläge

- `--model auto` wählt Modell und Beam nach Chip/RAM (Standard bleibt `medium`). Stufen: `small` (Intel
  oder unter 8 GB), `medium` (Apple Silicon ab 8 GB, Beam 1; ab 16 GB Beam 3), `best` (Pro/Max/Ultra ab 24 GB,
  Beam 5). `DOLMETSCHER_BEAM` überschreibt den Beam. Ereignis `hwprofile`: `chip`, `ram_gb`, `model`, `beam`,
  `reason` (kommt direkt nach `ready`).
- `utt` mit `source: "edit"` (Antwort auf `retranslate`) trägt optional `suggest_vocab`: Liste von Wörtern, die
  der Nutzer gegenüber dem alten erkannten Text geändert oder ergänzt hat (ohne Eigennamen, Zahlen, Einheiten;
  Thai per pythainlp-Segmentierung, sonst Thai-Läufe). Nur ein Vorschlag: die Engine speichert nichts, die App
  fragt den Nutzer und schickt es ggf. per `--vocab` bzw. Glossar.
- Ungültige Profilnamen bei `--vocab`/`--enroll` ergeben ein `error`-Ereignis statt eines Tracebacks.

## Szenario-Presets (Branch feat/presets)

Presets sind Daten: `presets/*.json` neben der Engine (mitgeliefert: `travel`, `restaurant`, `hotel`, `taxi`,
`doctor` (nur Verständigung, kein medizinischer Rat), `office`, `shopping`) und eigene Dateien in
`$DOLMETSCHER_HOME/presets/` (Standard `~/Library/Application Support/Dolmetscher/presets/`; gleiche `id`
überschreibt das mitgelieferte Preset, ungültige Dateien werden übersprungen). Aufbau je Datei:

- `id` (a-z, 0-9, `_`, `-`, max. 32), `names` `{de, en, th}` (max. 40 Zeichen), `style` (`casual`/`neutral`/`polite`)
- optional `polite` (`krub`/`ka`), `voice` `{en?, th?}` (Stimmnamen aus der Stimmenliste)
- `glossary`: bis 100 Paare `{en, th}` (max. 60 Zeichen), gelten in beide Richtungen
- `phrases`: bis 50 Schnellsätze `{en, th}` (max. 200 Zeichen), werden nur geliefert, nicht automatisch gesprochen

Steuerfeld (stdin): `preset: "<id>"` setzt den Stil und fügt das Glossar zum eigenen hinzu (eigene Einträge
haben Vorrang). `preset: "none"` (oder `null`) stellt Stil, Höflichkeit, Stimmen und Glossar von vorher wieder
her. Eigene `style`/`glossary`-Änderungen während eines Presets werden zur neuen Basis. Unbekannte `id`: nichts
ändert sich. Sprachbefehl: "Translator, hotel mode" / "preset taxi" / "preset off" (höchstens 5 Wörter).

Ereignis `preset` beim Wechsel: `id` und `name` (englisch); beide `null` bei "kein Preset".

## Gesprächsverlauf (optional, Standard: aus)

Lokal, nur auf Wunsch. Modul `history_store.py`, Datei `history.sqlite` unter
`$DOLMETSCHER_HOME` bzw. `~/Library/Application Support/Dolmetscher/` (Ordner 0700, Datei 0600).
Gespeichert wird pro `utt`: Zeit (UTC), Quellsprache, Originaltext, Übersetzung, Umschrift,
Konfidenz (`exp(lp)`), Anbieter, Sitzungs-ID. Eine Korrektur (`replaces`) ersetzt den alten Eintrag.
Nichts davon geht ins Log.

Aufnahme:

| Argument / stdin-Feld | Wirkung |
|---|---|
| `--history` / `{"history": true\|false}` | Aufzeichnung an/aus (live umschaltbar; Steuerfeld `history`) |
| `--history-days N` / `{"history_days": N}` | beim Einschalten Einträge älter als N Tage löschen (Steuerfeld `history_days`, zusammen mit `history`) |

Befehle (beenden sich sofort, laden keine Modelle):

| Argument | Wirkung |
|---|---|
| `--history-export md\|json\|csv\|srt\|vtt\|anki [--history-session ID] [--out PFAD]` | Export nach stdout oder Datei (0600). `srt`/`vtt` ohne ID: neueste Sitzung, Zeiten relativ zum Sitzungsstart. `anki`: Tab-getrennt Phrase, Übersetzung, Umschrift |
| `--history-search TEXT` | Volltextsuche (FTS5 trigram, sonst LIKE), JSON-Liste auf stdout |
| `--history-purge TAGE` | ältere Einträge löschen, `{"deleted": n}` |
| `--history-clear` | alles löschen, `{"deleted": n}` |

## Runde 2 (Ideenliste): Verhalten ohne neue Felder

- **Hotwords:** Whisper bekommt eigene Wörter der Stimmprofile und zusätzlich Glossar-/Preset-Begriffe in der
  Schrift der jeweiligen Sprache (höchstens 300 Zeichen). Die Vorab-Erkennung nutzt dieselben Hotwords wie die
  eigentliche Erkennung und wird deshalb auch mit Profil-Vokabular wiederverwendet.
- **Zahlenvergleich (`num_warn`):** Uhrzeiten in Worten zählen als Uhrzeit (Thai: ตี, โมงเช้า, บ่าย…โมง,
  โมงเย็น, ทุ่ม, เที่ยง, เที่ยงคืน, ครึ่ง; Englisch: half past, quarter past/to, o'clock, noon, midnight) und
  gelten im 12-Stunden-Abstand als gleich. Weichen Zahlen ab, fragt die Engine den jeweils anderen Anbieter
  (Claude ↔ Google/MyMemory, höchstens 4 s) und nimmt die zahlentreue Fassung (`provider` nennt dann diesen).
- **Modelle laden:** Nur wenn ein Modell im lokalen Cache fehlt, meldet die Engine `loading` mit `download`
  und lädt herunter. Andere Ladefehler (Gerät, Compute-Typ) gehen ohne Netzzugriff an den Rückfall.
- **edge-tts:** Beim Start prüft ein Selbsttest die genutzten Interna (Version gepinnt in `requirements.in`);
  schlägt er fehl, läuft die Neural-Stimme gleich über den alten Weg (Log `tts_ws`).
