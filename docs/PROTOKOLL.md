# Engine ⇄ App: Protokoll (Version 1)

Die Mac-App startet `dolmetscher.py --json …`. Die Engine schreibt **eine JSON-Zeile pro Ereignis** auf stdout.
Die App schickt Einstellungen als **JSON-Zeilen auf stdin**. Unbekannte Felder werden auf beiden Seiten ignoriert.

## Neu: Sprachausgabe läuft asynchron

Erkennung und Übersetzung des nächsten Satzes laufen, während der vorige noch vorgelesen wird.
Deshalb kann `thinking` für Satz 2 kommen, während Satz 1 noch `speaking` ist.
Jede Äußerung hat eine `id` (String, z. B. `"u7"`). Die App darf den Status „spricht“ nur über
`speaking`/`speak_done` setzen bzw. zurücksetzen, **nicht** über `listening`.

## Beispielablauf und Kompatibilität

Ein Satz (gekürzt; Felder je Ereignis siehe unten). Jede Zeile ist ein JSON-Objekt auf stdout:

```
{"event":"ready","protocol":1,"langs":{"mine":"en","partner":"th"}}
{"event":"thinking","id":"u1"}
{"event":"utt","id":"u1","lang":"en","to":"th","text":"Where is the station?","out":"สถานีอยู่ที่ไหนครับ","provider":"google"}
{"event":"speaking","id":"u1"}
{"event":"speak_done","id":"u1"}
```

Und auf stdin, eine Zeile pro Einstellung: `{"lang": "auto"}` (Sprachsperre aufheben).

Regeln für Änderungen am Protokoll (damit alte App und neue Engine zusammenpassen und umgekehrt):

- **Neue Felder und Ereignisse sind erlaubt**, weil unbekannte Felder und Ereignisse auf beiden Seiten ignoriert werden.
  Die Seite, die sie nicht kennt, muss ohne sie funktionieren.
- **Nichts umbenennen oder entfernen**, solange eine veröffentlichte App es liest. Ein neuer Name kommt zusätzlich; der alte
  fällt erst nach einer Übergangszeit weg und wird hier als veraltet vermerkt.
- **Codes sind stabil** (`dropped.code`, `error.code`): Texte (`reason`, `message`) dürfen sich ändern, die Codes nicht.
- Jede Änderung gehört in diese Datei; `tests/test_protocol_docs.py` prüft Ereignisse, Startargumente und Codes gegen den Code.
- Wird ein Feld zur Pflicht oder ändert sich seine Bedeutung, erhöht man die Protokollversion (Überschrift) und nennt die
  Mindestversion der App im Changelog.

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
| `--source mic\|system` | `mic` | Runde 25: Aufnahmequelle. `system` nimmt statt des Mikrofons ein virtuelles Loopback-Gerät auf (BlackHole, Loopback Audio …, Suche über `avhelper`), z. B. für den Video-Anruf der Partnerin; Steuerfeld `source`. Opt-in |
| `--output-device UID\|NAME\|INDEX` | `` | Ausgabegerät für alle Sprachausgaben (CoreAudio-UID bevorzugt, sonst Name oder Index; leer = Systemstandard). Unbekannt: `error` `output_not_found`, Systemstandard |
| `--mt-order LISTE` | | Reihenfolge der freien Übersetzer nach Claude: `google,mymemory` (Standard) oder `mymemory,google`; auch `DOLMETSCHER_MT_ORDER`. Unbekannte Werte: Standard. Offline-Helfer bleibt immer letzte Stufe |
| `--offline-translator [PFAD]` | | Offline-Übersetzung ohne Netz über `translate-helper` (Apple Translation, on-device): nur wenn Google/MyMemory wegen fehlenden Netzes scheitern und das Sprachpaar installiert ist (`provider: "apple"`, nicht gecacht). Ohne Pfad: `DOLMETSCHER_TRANSLATE_HELPER`, sonst `translate-helper` neben `dolmetscher.py` oder im App-Bundle unter `Contents/Helpers/` (build.sh legt ihn dort ab, signiert mit Hardened Runtime; die Mac-App übergibt den Pfad, Einstellung „Offline-Übersetzung (Apple) als Rückfall“, Standard an ab macOS 26.4). Fehlt der Helfer: `error` `offline_mt_missing` |
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
| `--slow` | | „Langsam und deutlich“ (wie Steuerfeld `slow`) |
| `--let-finish S` | `0.0` | „Ausreden lassen“: nach dem Satzende so viele Sekunden Ruhe abwarten, bevor vorgelesen wird (0 … 5; wie Steuerfeld `let_finish`) |
| `--catch-up skip\|fast\|off` | `skip` | Verhalten bei Rückstand (wie Steuerfeld `catch_up`) |
| `--beam N` | `0` | Beam-Breite der Erkennung 1 … 5 (wie Steuerfeld `beam`); 0 = `DOLMETSCHER_BEAM` bzw. Hardware-Profil |
| `--private` | | Privatmodus: keine Aufwärm-Anfragen an Google/Microsoft beim Start; lehnt ein Anbieter POST ab, kein Rückfall auf GET mit dem Text in der URL (Übersetzung scheitert dann mit `translate_failed`) |
| `--back-translate` | | Rückübersetzung als Ereignis `back` (wie Steuerfeld `back_translate`) |
| `--no-learn-glossary` | | Eigennamen aus Korrekturen nicht ins Glossar übernehmen (Standard: an) |
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
| `--subtitles PFAD` | | mit `--file`: Untertitel (`.srt`/`.vtt`, Zeiten = Position in der Datei) ohne Sprachausgabe; am Ende Ereignis `subtitles` |
| `--history-export FORMAT`, `--history-session ID`, `--history-sessions`, `--out PFAD`, `--history-search TEXT`, `--history-context N`, `--history-lang CODE`, `--history-purge TAGE`, `--history-clear` | | Verlaufs-Befehle (siehe „Gesprächsverlauf“) |

### Umgebungsvariablen

| Variable | Wirkung |
|---|---|
| `ANTHROPIC_API_KEY` (oder `ANTHROPIC_AUTH_TOKEN`) | Claude-Schlüssel. Die Mac-App speichert ihn im Schlüsselbund (Dienst `Dolmetscher`, Konto `anthropic`) und setzt ihn beim Start jedes Engine-Prozesses als `ANTHROPIC_API_KEY`; die Engine ruft `security` nie selbst auf. Die alte Datei bleibt erhalten, bis der Schlüsselbund-Eintrag nachweislich lesbar ist, und wird dann in `anthropic_key.migrated` (0600) umbenannt, nie gelöscht. Rückfall ohne `ANTHROPIC_API_KEY` (Terminal, Schlüsselbund nicht erreichbar): Datei `~/Library/Application Support/Dolmetscher/anthropic_key` (nur der Schlüssel, Rechte 0600), sonst `anthropic_key.migrated` im selben Ordner |
| `DOLMETSCHER_LLM_PRICES` | JSON `{"modell": [eingabe, ausgabe]}` (USD je Mio. Token): überschreibt/ergänzt die eingebaute Preisliste der Claude-Kosten; `llm_cost.price_known` sagt, ob das Modell in der Liste steht |
| `DOLMETSCHER_BEAM` | Beam-Breite der Erkennung (Standard 1; überschreibt `--model auto`) |
| `DOLMETSCHER_FEATURES` | Runde 24: Komma-getrennte Schalter, die beim Start eingeschaltet werden (Standard: keine): `stream`, `router`, `defer`, `parallel_alt`, `stt_prompt`, `speak_numbers` (dieselben wie die Steuerfelder `llm_stream` … `speak_numbers`). Unbekannte Namen werden nur geloggt |
| `DOLMETSCHER_MIC_FILE` | Audiodatei in Echtzeit statt Mikrofon (Ende-zu-Ende-Test) |
| `DOLMETSCHER_MIC_LOOP` | mit `DOLMETSCHER_MIC_FILE`: Datei endlos wiederholen |
| `DOLMETSCHER_TTS_NO_PROXY` | `1`: die Neural-Stimme ignoriert `HTTP(S)_PROXY` der Umgebung |
| `DOLMETSCHER_FFMPEG` | optional: externes ffmpeg statt PyAV für Aufnahme, Wiedergabe und `--file` (nur wenn gesetzt; Standard ist `avhelper.py` mit PyAV) |
| `DOLMETSCHER_HOME` | Ordner für Presets/Verlauf (Standard `~/Library/Application Support/Dolmetscher/`) |
| `DOLMETSCHER_LOG` | Logdatei (Standard `~/Library/Logs/Dolmetscher/engine.log`) |
| `DOLMETSCHER_LOG_MB`, `DOLMETSCHER_LOG_BACKUPS` | Log-Rotation: Größe in MB (Standard 1, 0,1–50) und Zahl der Sicherungen (Standard 3, 1–10) |
| `DOLMETSCHER_CPU_THREADS` | Threads des CPU-Modells (Standard: Zahl der Performance-Kerne, `hw.perflevel0.physicalcpu`; höchstens 16) |
| `DOLMETSCHER_MYMEMORY_EMAIL` | E-Mail-Adresse für MyMemory (Parameter `de`, höheres Tageslimit); nur lokal setzen, nie ins Repo. Treffer mit `match` unter 0,5 werden nicht vorgelesen (nächster Anbieter bzw. `translate_failed`) |
| `DOLMETSCHER_DEBUG` | VAD-Diagnose ins Log |
| `DOLMETSCHER_TUNE` | Feineinstellung ohne Neubau, z. B. `MIN_UTT=0.4,MAX_UTT=12`. Erlaubt: `MIN_UTT` (0,1–2), `MAX_UTT` (3–30), `MIN_LANG_P` (0,05–0,9), `SECOND_LOOK_MIN` (0–0,5), `SECOND_LOOK_TOP` (0,5–1), `HEDGE` (0,2–5), `FIRST_DEADLINE` (0,5–10); Werte werden auf den Bereich begrenzt, Unbekanntes steht im Log und wird ignoriert |
| `DOLMETSCHER_NULL_AUDIO` | keine Tonausgabe (Tests) |
| `DOLMETSCHER_SPEAKER_MODEL`, `DOLMETSCHER_SPEAKER_MODEL_URL` | Stimmprofil-Modell aus Datei bzw. URL |

## Ereignisse (stdout)

| event | Felder | Hinweis |
|---|---|---|
| `loading` | `msg`, `download` (optional, true: Modell wird einmalig heruntergeladen, kann Minuten dauern) | |
| `download_progress` | `model` (Name wie `--model` bzw. Repo-ID), `done_mb` (bereits auf der Platte), `total_mb` (Gesamtgröße laut Hub, sonst Schätzung; `null`, wenn unbekannt), `final` (bool: Download dieses Modells fertig) | nur während ein fehlendes Modell geladen wird (nach `loading` mit `download: true`), höchstens ~2×/s und nur bei Änderung. Gezählt werden die Bytes im Hugging-Face-Cache (auch `.incomplete`), deshalb funktioniert es auch mit hf-xet. Ältere Apps ignorieren das Ereignis |
| `back` | `id`, `text`, `lang` | optional, nur mit `back_translate`/`--back-translate`: Rückübersetzung der Übersetzung von `id` in die gesprochene Sprache `lang` (Google/MyMemory, nie Claude). Kommt **nach** dem `utt` derselben `id`, ohne Garantie (Fehler: nur Log); bei unbekannter `id` ignorieren |
| `state` | wie `command` ohne `text`/`reply`, dazu `mute`, `earcons`, `preset`, `llm` (`{"on", "available", "style"}`), `slow`, `back_translate`, `learn_glossary`, `mic_on`, `let_finish`, `catch_up`, `beam`, `latency` (siehe „Runde 6“), `switches` (Runde 24: `llm_stream`, `llm_router`, `defer`, `parallel_alt`, `stt_prompt`, `speak_numbers`), `latency_hist` (`{stt|tr|sound: {n, p50, p95}}` über Sitzungen) | Antwort auf `{"get_state": true}` (App-Neustart/Reconnect); ändert keinen Status |
| `glossary` | `text` (ganzes eigenes Glossar), `added` (neue Namen) | Engine hat Eigennamen aus einer Korrektur ins Glossar übernommen (Datei schon geschrieben). Die App hängt `added` an ihren Text an (nicht überschreiben: ungesendete eigene Änderungen) |
| `llm_cost` | `usd`, `month_usd` | geschätzte Claude-Kosten der Sitzung bzw. des Kalendermonats (nach Preisliste, über Neustarts) |
| `missed` | `why` (`cut`\|`overlap`), `dur` (s Ausgabe), `rms` | Während der eigenen Sprachausgabe wurde vermutlich gesprochen und der Teil verworfen (Halbduplex): `cut` = ein Satz lief noch, als die Ausgabe begann (der Anfang wird übersetzt, der Rest fehlt); `overlap` = direkt nach Ende der Ausgabe (und des Nachhalls) ist schon Sprache da. Höchstens einmal je Ausgabe; nie mit `--barge-in`. Echo der eigenen Stimme löst es nicht aus (während der Sperre wird nichts gemessen), ein Gespräch über Lautsprecher kann aber trotzdem `overlap` melden |
| `ready` | `msg`, `device`, `llm` (bool: Claude aktiv), `protocol`, `engine_version`, `langs` (`{"mine", "partner"}`), `capabilities` (Liste: `control:<Steuerfeld>` je bekanntem Feld, `feature:<name>` für Zusatzverhalten – so erkennt die App, was die laufende Engine kann); optional `degraded` (Liste: `detect_model`, `thai_model` – Modell nicht geladen, Erkennung läuft schwächer über das Hauptmodell) | |
| `langs` | `mine`, `partner` | Sprachpaar nach `{"langs": …}` geändert |
| `listening` | | Mikrofon bereit; ändert den Sprech-Status nicht |
| `hearing` | `id` (beim Mikrofon) | jemand spricht gerade; die `id` gilt für die ganze Äußerung |
| `thinking` | `id` | Äußerung `id` wird erkannt/übersetzt → Platzhalter-Blase |
| `heard` | `id`, `lang`, `text`, `text_latin` (Thai, optional) | **neu:** erkannter Originaltext, sofort nach der Erkennung, noch vor der Übersetzung (Mikrofon und `reassign`). Die App füllt damit die Platzhalter-Blase; `utt` mit derselben `id` ergänzt die Übersetzung. Ältere Apps ignorieren das Ereignis |
| `dropped` | `reason` (deutscher Freitext), `code` (stabil, siehe unten), `id`; bei `code` `unsure` zusätzlich `text`, `lang`, `lp`; bei `translate_failed` zusätzlich `text`, `lang` | Platzhalter `id` entfernen. Bei `unsure` kann die App den gehörten Text zeigen und „trotzdem übersetzen“ per `retranslate` anbieten, bei `translate_failed` „Erneut versuchen“ (ebenfalls `retranslate`) |
| `utt` | `id`, `lang`, `to`, `text`, `out`, `stt`, `tr` (s), `lp` (Erkennungs-Konfidenz, log-prob, ≈ −0.1 sicher … −1.3 unsicher), `translated`, `provider` (`claude`\|`google`\|`mymemory`\|`apple`\|`none`), `speaker`, `replaces` (optional: id der korrigierten Blase), `source` (`mic`\|`phrase`\|`edit`\|`reassign`); optional: `text_latin`/`out_latin` (lesbare RTGS-Umschrift für Thai, nur mit pythainlp), `alts` (andere Lesarten), `role` (`me`\|`other`), `num_warn` (Ziffern weichen ab), `ready_s`, `dur` (s, Länge der Äußerung; nur Mikrofon), `suggest_vocab`. Ohne Übersetzung (Richtung abgeschaltet): `translated: false`, `provider: "none"`, `out` = `text`, kein `out_latin`, kein Vorlesen | |
| `speaking` | `id`, `first_s` (s bis zum ersten Ton) | nur wenn wirklich Ton kommt (nicht bei stumm, Überspringen, Abbruch vor dem ersten Ton); `id` = `"cmd"` bei Befehlsantworten und „repeat“ |
| `speak_done` | `id`, `skipped` (bool), `interrupted` (bool), optional `partial` (true) | kommt für jede eingereihte Ausgabe **genau einmal**, auch ohne vorheriges `speaking`; `skipped`: wegen Rückstand/Stopp nicht vorgelesen; `partial`: Neural-Stimme riss mitten im Satz ab (nur teilweise vorgelesen, App kann Wiederholen anbieten) |
| `queue` | `stt` (wartende Äußerungen), `tts` (wartende Ausgaben) | bei jeder Änderung |
| `level` | `rms` (0…1, dBFS skaliert), `voice` (bool) | ~7×/s, nur mit `--meter` |
| `net` | `ok` (bool), `what` (`translate`\|`tts`) | nur bei Zustandswechsel |
| `command` | `text`, `reply`, `paused`, `lang`, `tr_en`, `tr_th`, `polite`, `rate`, `volume`, `voice_en`, `voice_th` (fehlende Sprache: `true`/`""`), `langs` (`{"mine", "partner"}`), `tr` und `voices` (Code → Wert, je Sprache des Paars); `clear` (true) nach „Translator, clear“ | App speichert `rate`/`volume` dauerhaft; bei `clear` Verlauf in der App leeren |
| `error` | `msg` (deutscher Freitext), `msg_en` (englischer Text zum Code, wenn bekannt – Runde 24), `code` (stabil, siehe unten), bei `translate_failed` optional `retry_in_s` (s bis zum nächsten Online-Versuch, wenn alle Anbieter pausieren) | |
| `barge_in` | | |
| `mics` | `mics` (Liste `{index, name}`) | Antwort auf `--list-mics`; die App sollte den **Namen** speichern |
| `profiles` | `profiles` (Liste öffentlicher Profilfelder) | Antwort auf `--profiles` |
| `profile_saved` | `profile` | nach `--enroll` bzw. `--vocab` |
| `profile_deleted` | `name`, `ok` (bool) | Antwort auf `--delete-profile` |
| `profile_adapted` | `name`, `role` (`me`\|`other`) | Stimmabdruck wurde nach einem sicher erkannten Satz nachgeführt (höchstens alle 30 s je Rolle) |
| `learning_reset` | `name`, `ok` (bool) | Antwort auf Steuerfeld `reset_learning` bzw. `--profile-stdin` `{"reset_learning": NAME}`; `ok` false: kein nachgeführter Abdruck vorhanden |
| `control_ignored` | `keys` (höchstens 10 unbekannte Steuerfelder) | Steuerzeile enthielt Felder, die die Engine nicht kennt (Tippfehler, ältere Engine) |
| `llm` | `on`, `available` (bool) | Antwort auf Steuerfeld `llm`: `available` false = kein Schlüssel/kein `anthropic`, übersetzt wird dann mit Google |
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
| `stopped` | gestoppt | Mikrofon gestoppt, bevor die Äußerung bearbeitet wurde (Platzhalter entfernen, kein Hinweis) |
| `other` | | unbekannter Grund (App: allgemeine Meldung) |

### `error.code`

| `code` | Bedeutung |
|---|---|
| `mic_denied`, `mic_unavailable`, `mic_no_data`, `mic_timeout`, `mic_failed` | Mikrofon: Zugriff verweigert / Gerät ungültig / keine Daten / erster Block nicht binnen 10 s (Wachhund beendet ffmpeg) / Gerät nach Wiederverbinden weg |
| `mic_not_found` | Mikrofon-Name unbekannt, Standardmikrofon wird genutzt |
| `output_not_found`, `output_invalid`, `output_unsupported` | Ausgabegerät unbekannt (Systemstandard wird genutzt) / Steuerwert `output_device` ungültig / mit `DOLMETSCHER_FFMPEG` nicht wählbar |
| `profile_name_invalid`, `profile_invalid`, `profile_not_found`, `profile_delete_failed` | Profil-Aufrufe: Name ungültig / Profil oder Höflichkeitsform ungültig / Profil fehlt / Stimmdaten nicht löschbar |
| `history_failed`, `history_days_invalid` | Verlauf: Datenbank nicht nutzbar (Aufzeichnung aus) / `history_days` ungültig (es wird nichts gelöscht) |
| `preset_invalid` | Beim Laden der Presets (Wechsel per `preset`) waren Dateien ungültig und wurden übersprungen; `files` = Dateinamen, Details im Log. Je Fehlerbild einmal |
| `offline_mt_missing` | `--offline-translator`: `translate-helper` nicht gefunden oder nicht ausführbar – ohne Netz keine Übersetzung |
| `mic_list_failed` | `--list-mics` konnte ffmpeg nicht abfragen |
| `mic_file_missing`, `ffmpeg_missing` | `DOLMETSCHER_MIC_FILE` fehlt / das per `DOLMETSCHER_FFMPEG` gesetzte ffmpeg fehlt (gleich beim Start gemeldet) oder ist nicht startbar |
| `audio_missing` | Audio-Baustein fehlt: PyAV (`av`) nicht importierbar oder `avhelper.py` fehlt (gleich beim Start gemeldet) – Python-Umgebung neu einrichten |
| `model_offline` | Modell fehlt lokal und kann ohne Internet nicht geladen werden |
| `disk_full` | Zu wenig freier Speicher für den Modell-Download (vor dem Download geprüft, Größe + 10 %) |
| `log_unavailable` | `engine.log` nicht beschreibbar (Platte voll, Rechte): einmal je Lauf gemeldet |
| `translate_failed` | Übersetzung fehlgeschlagen (alle Anbieter) |
| `python_env_broken` | Pflichtmodul fehlt beim Laden der Modelle (kaputte Python-Umgebung); `module` = Modulname. Die Engine beendet sich danach mit Exit-Code 3, die App startet sie nicht neu und zeigt den Hinweis zum Neu-Einrichten |
| `vad_failed` | Selbsttest der Sprach-Aktivitätserkennung (Silero-VAD aus faster-whisper) beim Start gescheitert – Python-Umgebung neu einrichten |
| `llm_billing` | Claude-API: Guthaben oder Kontingent erschöpft – 30 min nur Google/MyMemory, dann neuer Versuch |
| `llm_budget` | eigenes Claude-Monatslimit (`--llm-budget`/`llm_budget`) erreicht – bis Monatsende Google/MyMemory; einmal je Monat |
| `mic_invalid` | Steuerfeld `mic` ungültig (kein Text/keine Zahl); Gerät unverändert |
| `reassign_expired`, `reassign_empty`, `reassign_invalid` | „Das war ich/sie“: Satz nicht mehr im Speicher / nichts erkannt / Anfrage ungültig |
| `phrase_invalid`, `edit_invalid`, `speak_invalid` | Schnellsatz, Korrektur bzw. Vorlesen (`speak_text`) ungültig |
| `profiles_failed` | Stimmprofile/Sprechermodell nicht ladbar – Stimmerkennung aus; `msg` nennt die Ursache |
| `voice_unknown`, `glossary_invalid` | Steuerwert ungültig |
| `langs_invalid` | Sprachpaar ungültig (unbekannter Code oder zweimal dieselbe Sprache); Paar unverändert |
| `file_empty`, `file_failed` | `--file`: keine Audiodaten / Datei nicht lesbar, ein Abschnitt nicht verarbeitbar (die übrigen Abschnitte laufen weiter) oder mit `--subtitles` die Untertitel-Datei nicht schreibbar |


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
| `formality` | `auto`\|`informal`\|`neutral`\|`polite` | Höflichkeitsstufe der Claude-Übersetzung (Runde 11), unabhängig von `style`; `auto` (Standard) = wie bisher aus `style` (casual → informell, sonst formell) |
| `speaker_sex` | `male`\|`female` | Geschlecht der Person, die Thai ausgibt: Klartext-Alias für `polite` (`male` = `krub`, `female` = `ka`); wirkt auf Thai-Partikel in Prompt und Nachbearbeitung |
| `glossary` | string | eigene Wörter, eine Zeile `Wort => Übersetzung` oder nur `Name` |
| `earcons` | bool | Signaltöne statt Sprache bei Befehlen |
| `stop_speaking` | true | laufende und wartende Ausgaben abbrechen |
| `say` | `{"text": "...", "lang": CODE}` (Sprache des Paars, Standard `en`) | Schnellsatz: übersetzen und vorlesen wie eine Äußerung (`source: "phrase"`) |
| `retranslate` | `{"id": "u7", "text": "korrigierter Text", "lang": "en"\|"th"}` | neu übersetzen und vorlesen; `utt` kommt mit `replaces: "u7"`, `source: "edit"` |
| `speak_text` | `{"text": "...", "lang": CODE (Sprache des Paars), "id": "u7"}` | fertigen Text nur vorlesen (Neural-Stimme, keine Übersetzung) – „Nochmal sprechen“; `id` optional, dann kommen `speaking`/`speak_done` mit dieser id (ohne `latency_s`). Ungültig: `error` `speak_invalid`. Nicht verwechseln mit `speak` (bool, stumm schalten) |
| `mic` | string (Index, Gerätename oder `default`) | Mikrofon zur Laufzeit wechseln, ohne Modelle neu zu laden: ist es an, öffnet die Engine ffmpeg mit dem neuen Gerät neu (danach `mic` `on: true`; wartende Äußerungen des alten Geräts verfallen, laufende Ausgaben nicht); ist es aus, gilt das Gerät beim nächsten `listen`. Vor `ready` gesendet: gilt, sobald das Mikrofon angelegt wird. Unbekannter Name: `error` `mic_not_found`, Standardmikrofon |
| `output_device` | string (CoreAudio-UID, Name, Index; `""`/`default` = Systemstandard) | Ausgabegerät zur Laufzeit wechseln; gilt ab der nächsten Ausgabe für Neural-Stimme, macOS-Stimme und Signalton. Unbekannt: `error` `output_not_found` |
| `output_device_me`, `output_device_other` | string (wie `output_device`; `""`/`default` = allgemeines Gerät, sonst Systemstandard) | Runde 27: Ausgabegerät je Richtung. `me`: Ausgaben in meiner Sprache (Antworten an mich, Befehlsantworten, Signalton); `other`: Ausgaben in der Partnersprache. Eine leere Richtung fällt auf `output_device` zurück. Gilt ab der nächsten Ausgabe; ungültiger Wert: `error` `output_invalid` |
| `llm_budget` | float (USD, 0 … 10000) | Claude-Monatslimit wie `--llm-budget`; 0 = keine Grenze |
| `api_key` | string (druckbare Zeichen, 20 … 512) | Claude-Schlüssel der App statt der Umgebungsvariable `ANTHROPIC_API_KEY` (die Umgebung eines Prozesses ist für denselben Nutzer per `ps eww` lesbar). Wird nur im Speicher gehalten, nie geloggt (nicht in `CTRL_LOG_KEYS`); verwirft den gecachten Client |
| `slow` | bool | „Langsam und deutlich“: Ausgabe SLOW_RATE (−25) Prozentpunkte langsamer (zusammen nie unter −50), kein Aufhol-Tempo, nie überspringen; Claude bekommt den Zusatz „einfache Wörter, kurze Sätze“ (eigener Cache-Schlüssel) |
| `back_translate` | bool | Rückübersetzung als Ereignis `back` an/aus (Standard aus; kostet je Satz eine Google-Anfrage) |
| `learn_glossary` | bool | Eigennamen aus Korrekturen (`retranslate`) automatisch ins Glossar (Standard an) |
| `echo_guard` | bool | Runde 8: Text-Echo-Schutz (Standard an): ein erkannter Satz, der in derselben Sprache fast gleich dem vor < 25 s vorgelesenen ist (ab 14 Zeichen), wird mit `dropped` (`reason` „echo“, Code `other`, keine eigene App-Meldung) verworfen; `state` meldet `echo_guard` |
| `reset_learning` | string (Profilname) | nachgeführten Stimmabdruck verwerfen (Stand beim Anlegen); Antwort `learning_reset` |
| `get_state` | true | Zustand als Ereignis `state` senden |
| `let_finish` | float (s, 0 … 5) | „Ausreden lassen“: nach dem Satzende so lange Ruhe abwarten, bevor vorgelesen wird; spricht jemand weiter, beginnt die Wartezeit neu (höchstens bis `MAX_UTT`). 0 = aus (Standard). Mit `--barge-in` (Kopfhörer) wartet die Ausgabe wie bisher nie |
| `catch_up` | `skip`\|`fast`\|`off` | Rückstand: `skip` (Standard) = schneller sprechen und ab 3 wartenden Ausgaben ältere überspringen, `fast` = nur schneller, nie überspringen, `off` = weder noch. `slow` gewinnt (nie schneller, nie überspringen) |
| `beam` | int (0 … 5) | Beam-Breite der Erkennung live: 1 schnell, 5 genau; 0 = zurück zum Startwert (`--beam`, `DOLMETSCHER_BEAM` bzw. Hardware-Profil) |
| `llm_stream` | bool | Runde 24 (Standard aus): Claude per `messages.stream`; die Zeit bis zum ersten Token (`ttft_s`) kommt ins Log, und die erste fertige Teilphrase (Satzende) wird im Hintergrund schon vertont (Sprach-Cache). Auch `DOLMETSCHER_FEATURES=stream` |
| `llm_router` | bool | Runde 24 (Standard aus): Modell-Router – bei Haiku bleiben kurze Sätze dort, lange, zahlenreiche oder unsichere gehen an Sonnet |
| `defer` | bool | Runde 24 (Standard aus): Übersetzen/Vorlesen vom Erkennungs-Thread entkoppeln – die Erkennung der nächsten Äußerung läuft, während die vorige übersetzt wird (Reihenfolge bleibt) |
| `parallel_alt` | bool | Runde 24 (Standard aus): Gegenprobe-Erkennung in der anderen Sprache gleichzeitig starten, wenn sie voraussichtlich gebraucht wird |
| `stt_prompt` | bool | Runde 24 (Standard aus): gemerkte Namen des Gesprächs (höchstens 120 Zeichen) als Erkennungs-Hinweis für Englisch/Thai |
| `speak_numbers` | bool | Runde 24 (Standard aus): Thai-Zahlen als Wörter vorlesen (350 → สามร้อยห้าสิบ); Zimmer-, Telefon- und Kontonummern bleiben Ziffern |
| `group_speakers` | bool | Runde 25 (Standard aus): Gruppenmodus – Sprecher ohne Stimmprofil bekommen stabile Nummern; `utt` trägt dann `group_speaker` (Ganzzahl ab 1, additiv) und, wenn kein Profil erkannt wurde, `speaker` = `"Sprecher N"`. Nummern werden nie umnummeriert; „Gespräch löschen" (`clear`) beginnt wieder bei 1. Lädt bei Bedarf das Sprechermodell; scheitert das, kommt `error` `profiles_failed` (Text nennt den Gruppenmodus) und der Modus geht aus |
| `source` | `"mic"` \| `"system"` | Runde 25 (Standard `mic`): Aufnahmequelle (siehe `--source`); bei laufender Aufnahme wird mit der neuen Quelle neu geöffnet. Ohne Loopback-Gerät `error` `system_audio_missing`; beim Start im Systemton-Modus kommt `hint` `system_audio` (die Ausgabe der Engine nicht auf das Loopback-Gerät legen). Ungültiger Wert: `control_invalid` |
| `history_password` | string | Runde 25: verschlüsselter Verlauf (optional, Standard aus). Mit gesetztem Passwort schreibt `history` in die eigene Datei `history-enc.sqlite` (Text, Übersetzung, Umschrift und Sprechername feldweise verschlüsselt, Schlüssel per scrypt einmal je Öffnen aus Passwort und Salz der Datei, nur Standardbibliothek; Zeitstempel, Sprache, Sitzung, Rolle bleiben lesbar). Die Klartext-Datei `history.sqlite` wird nicht umgewandelt oder weiterbeschrieben. Suche und Statistik laufen ohne FTS-Index. Das Passwort steht nur im Speicher der Engine, nie im Log, in `state` oder in Fehlertexten (kein Feld in `CTRL_LOG_KEYS`); `""`/`null` löscht es. Vor `history` senden (oder in derselben Zeile). Falsches Passwort: `error` `history_failed` (Text nennt das Passwort), Verlauf bleibt aus. Mit `--history` beim Start liest die Engine `DOLMETSCHER_HISTORY_PASSWORD` schon vor dem ersten Schreiben (und entfernt sie aus der Umgebung der Kindprozesse); Abfragen per CLI (`--history-export` …) lesen den Verlauf mit derselben Umgebungsvariable (`--history-clear`/`--history-purge` ohne sie betreffen nur die Klartext-Datei); ohne verschlüsselte Datei oder mit falschem Passwort Exit-Code 2 und `{"error": …}` |
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
- `mic` kann `reconnecting` (true) und `attempt` enthalten: die Quelle (Gerät) ist weggefallen, die Engine verbindet mit Wartezeit neu (5 schnelle Versuche, danach alle 10 s, bis es klappt oder der Nutzer `listen: false` sendet; Runde 4, Nr. 192 – vorher nach 5 Versuchen `error` und Ende).
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

- optional `note` `{de, en, th?}` (max. 500 Zeichen): Kultur- bzw. Sicherheitshinweis zum Szenario
- optional je Schnellsatz `critical: true`: wichtiger Satz (Notfall, Allergie, Polizei), die App hebt ihn hervor
- optional `hotwords`: bis 30 Begriffe (max. 60 Zeichen) als zusätzliche Whisper-Hotwords, je nach Schrift für
  die passende Sprache (Runde 6, Nr. 243)
- optional `llm_hint` (max. 300 Zeichen): Hinweis zu Ton und Fachwörtern für Claude, solange das Preset aktiv ist

Ereignis `preset` beim Wechsel: `id` und `name` (englisch), `note` (`{de, en, th?}` oder `null`) und `phrases`
(`[{en, th, critical}]`, Reihenfolge wie in der Datei); `id`/`name`/`note` `null` und `phrases` `[]` bei
"kein Preset". Die Mac-App zeigt den Hinweis in der Oberflächensprache (sonst Englisch) über ein ⓘ in der
Schnellsatz-Leiste und stellt kritische Sätze vorn und rot mit Warnsymbol dar (VoiceOver: „Wichtig“). Nach einem
Neuverbinden (`state` kennt nur die id) liest sie dieselben Felder aus `presets/*.json`.

## Gesprächsverlauf (optional, Standard: aus)

Lokal, nur auf Wunsch. Modul `history_store.py`, Datei `history.sqlite` unter
`$DOLMETSCHER_HOME` bzw. `~/Library/Application Support/Dolmetscher/` (Ordner 0700, Datei 0600).
Gespeichert wird pro `utt`: Zeit (UTC), Quellsprache, Originaltext, Übersetzung, Umschrift,
Konfidenz (`exp(lp)`), Anbieter, Sitzungs-ID, ab Schema 2 auch Sprechbeginn (`t_begin` = Zeitpunkt − `ready_s` −
`dur`), Rolle (`me`/`other`) und Profilname. Eine Korrektur (`replaces`) ersetzt den alten Eintrag.
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

## Runde 3 (Ideenliste)

Neue Felder kommen nur dazu, `PROTOCOL` bleibt 1.

- **Rückübersetzung:** eigenes Ereignis `back` nach `utt` (wie `heard` vor `utt`), damit weder Blase noch Ton auf
  die zweite Anfrage warten. Standard aus.
- **Langsam und deutlich:** Steuerfeld `slow`, Start `--slow`.
- **Glossar lernt aus Korrekturen:** Schreibt der Nutzer bei `retranslate` einen Eigennamen (Großbuchstabe mitten im
  Satz, lateinische Schrift, im erkannten Text in keiner Schreibweise vorhanden; nicht Wochentage, Monate, „I“), kommt
  er als Zeile `Name` (unverändert lassen, zugleich Erkennungs-Hotword) ins eigene Glossar – höchstens 3 je Korrektur,
  nie über 200 Einträge. Danach `glossary` {`text`, `added`}. Die Vokabel-Vorschläge `suggest_vocab` enthalten jetzt
  auch Eigennamen (vorher fälschlich verworfen).
- **Steuerzeilen:** Mehrere Aufgaben in einer Zeile (z. B. `listen` + `say`) laufen alle (früher nur die letzte).
  Scheitert eine Aktion, laufen die übrigen trotzdem. stdin wird als UTF-8 mit Ersatzzeichen gelesen.
- **JSON:** NaN/±Infinity werden als `null` gesendet (vorher ungültiges JSON).
- **Erkennung:** Grenze „zu schnell“ je Schrift (`MAX_CPS`: Latein 22, Thai 26, Han 13, Kana 16, Hangul 13 Zeichen/s);
  `MIN_LOGPROB` für ja/zh/ko/tr/uk/id −1.1, vi/ar/hi −1.2 (vorher alle −1.0).
- **Netz:** Ein 404/405/413 auf POST sperrt POST nur 10 min; Backoff-Zeiten laufen auf `time.monotonic()`; Offline
  wird auch erkannt, wenn Google im Backoff übersprungen wurde.
- **Cache:** Claude-Ergebnisse mit Gesprächskontext werden nicht gecacht; der Sprachbefehl „clear“ leert auch den
  Übersetzungs- und den Sprach-Cache.
- **Temp-Dateien:** Reste abgestürzter Läufe werden schon beim Start gelöscht (eigenes Verzeichnis trägt die PID).
- **Verlauf:** Schreiben unter Lock in einer Transaktion.

## Runde 4 (Ideenliste)

Neue Felder kommen nur dazu, `PROTOCOL` bleibt 1.

- **Ausgabegerät (Nr. 24/357):** Start `--output-device`, Steuerfeld `output_device`. Alle eigenen Wiedergabewege
  laufen dann über `avhelper.py play` (`--device`, für Dateien `--file`); ohne Gerät bleibt `afplay` für Dateien.
  `avhelper.py list` liefert zusätzlich `outputs` [{`index`, `name`, `uid`}] (alle CoreAudio-Geräte, auch reine
  Eingänge). Die Geräte-Nummer wird erst kurz vor dem Abspielen ermittelt (Hot-Plug). Mit `DOLMETSCHER_FFMPEG`
  gilt der Systemstandard (`error` `output_unsupported`). Die lokale Vorlese-Stimme der Mac-App
  (AVSpeechSynthesizer) folgt der Einstellung nicht.
- **Offline-Übersetzung (Nr. 28/165):** `--offline-translator [PFAD]` (opt-in). Dritte Stufe nach Google/MyMemory,
  nur bei fehlendem Netz (Offline-Schalter oder Netzfehler) und nur für ein laut `ready`-Zeile installiertes
  Sprachpaar; `utt.provider` ist dann `apple`. Höchstens 6 s je Satz, Start des Helfers höchstens 5 s
  (danach 60 s kein neuer Versuch). Das App-Bundle liefert den Helfer noch nicht mit.
- **Verhalten ohne neue Felder:** Websocket der Neural-Stimme bricht nach 8 s ohne Nachricht ab (36);
  `play_span` nur noch im Debug-Log (48); Thai-Lachen „555“ wird als ฮ่าฮ่าฮ่า vorgelesen, die Anzeige bleibt (52);
  einstellige Zahlen zählen im Zahlenvergleich, wenn beide Seiten Ziffern tragen (53); `k`, `thousand`, พัน,
  หมื่น, แสน hinter Ziffern werden umgerechnet (54); weitere Abspann-Floskeln, auch „Subtitles by <Name>“ (55);
  Claude-429/529 nutzen `retry-after` (1 … 600 s), 529 ohne Angabe 20 s (57); das Log filtert Gesprächstext
  auch in verschachtelten Werten (62).
- **Neue Ereignisse/Felder:** `profile_adapted`, `learning_reset`, `control_ignored` (182, 188), `llm` {`on`,
  `available`} nach dem Steuerfeld `llm` (190), `error.retry_in_s` bei `translate_failed` (66). Profil-Fehler tragen
  jetzt Codes (184); Verlauf meldet `history_failed`/`history_days_invalid` statt still auszugehen (191).
- **Robustheit:** Die vorab gerenderte macOS-Ersatzstimme bricht bei Stopp/Barge-in ab, auch während die
  Ausgabe auf sie wartet (169/170). Das Mikrofon verbindet nach 5 schnellen Versuchen dauerhaft alle 10 s neu
  (192; `mic.attempt` zählt weiter). Stimmprofile werden atomar neu geladen (198).
- **Verlauf-CLI:** `--history-export … --out PFAD` meldet Erfolg als JSON-Zeile `{"exported": true, "bytes": N}`
  (388); die App zeigt „Fertig“ bei Export und Löschen nur noch mit dieser bzw. der `deleted`-Antwort (387/388).

## Runde 6 (Ideenliste)

Neue Felder kommen nur dazu, `PROTOCOL` bleibt 1.

- **Neue Steuerfelder/Startargumente:** `let_finish`/`--let-finish` (69), `catch_up`/`--catch-up` (171),
  `beam`/`--beam` (176); alle drei stehen auch in `state`.
- **`state.latency`** (70): `{stt|tr|sound: {n, p50, p90}}` über die letzten 50 Mikrofon-Sätze (Erkennung,
  Übersetzung, Satzende bis erster Ton, Sekunden). Fehlende Reihen fehlen im Objekt. Nur Zahlen, kein Text.
- **`utt.dur`** (205): Länge der Äußerung in Sekunden. Der Verlauf berechnet daraus den Sprechbeginn; `srt`/`vtt`
  laufen damit nicht mehr dem Ton nach. Verlauf Schema 2 (`PRAGMA user_version` 2) mit `t_begin`, `role`,
  `speaker`; ältere Datenbanken werden beim Öffnen ergänzt. Export: Markdown zeigt „ich“/„Partner“ bzw. den
  Profilnamen, CSV hängt `role`/`speaker` an, JSON hat die Felder nur, wenn sie bekannt sind (206).
- **Preset-Felder** `hotwords` und `llm_hint` (243), siehe „Szenario-Presets“.
- **Stimmprofil anlegen** (420): `enroll_retry` trägt zusätzlich `code` (`too_short`, `other_sentence`, `skipped`),
  `enroll_failed` `code` (`too_few`, `inconsistent`). `reason` bleibt (deutsch, fürs Log); die App zeigt den Grund
  über `code` in der Sprache des Assistenten.
- **Fehlercode `python_env_broken`** (402) mit `module`; Exit-Code 3. Die App erkennt die kaputte Umgebung daran
  und sucht im Log nur noch für ältere Engines nach „No module named“.
- **Verhalten ohne neue Felder:** `faster_whisper` wird erst beim Laden importiert, `loading` kommt sofort (42);
  das Thai-Modell wärmt auf Thai auf (46); Claude erfährt bei Thai→Englisch das Geschlecht aus ค่ะ/คะ/ครับ (51);
  der zuletzt vorgelesene lange Satz bleibt für „repeat“ gespeichert, auch offline (67); die Hedge-Zeit folgt der
  gemessenen Claude-Dauer (p90 × 1,2 der letzten 20, 1 s … 1,5 × Modellwert) (74); `DOLMETSCHER_TUNE` (81);
  das Anlegen eines Stimmprofils normalisiert wie der Betrieb (177); ครับ/ค่ะ vs. คะ erkennt englische Fragen
  auch ohne „?“ an Fragewort bzw. vorangestelltem Hilfsverb (181); `process` liest die Stimmprofile einmal je
  Satz, ein `reload_profiles` mittendrin stört nicht mehr (221).

## Runde 7 (Engine)

Nur additiv: neue Ereignisse, Felder und Codes, keine bestehenden ändern sich. `PROTOCOL` bleibt 1. Eine App, die
sie nicht kennt, kann sie ignorieren.

### Neue Steuerfelder

| Feld | Wert | Wirkung |
|---|---|---|
| `clear` | `true` | Gesprächskontext und Texte im Speicher leeren (wie der Sprachbefehl „clear“, Mac-Punkt 9): Verlauf für Claude, „repeat“, Roh-Audio, Übersetzungs- und Sprach-Cache, **dazu wartende und laufende Sprachausgabe** (sie enthält den Text als Audio). Antwort: Ereignis `cleared`. Der gespeicherte Verlauf (`history`) bleibt unberührt, dafür gibt es `--history-clear` |
| `llm_retry` | `true` | Claude sofort wieder versuchen: verwirft die Pause nach einem Fehler/„Guthaben leer“ und den Client (neuer Schlüssel). `llm` (an/aus) setzt die Pause ebenfalls zurück |

`history_days` wirkt jetzt auch allein (ohne `history`): ändert die Aufbewahrungsfrist und setzt sie gleich
durch (`0` = nie löschen, Ungültiges: `error` `history_days_invalid`).

### Neue Ereignisse

| Ereignis | Felder | Bedeutung |
|---|---|---|
| `cleared` | | Antwort auf `{"clear": true}` |
| `control_invalid` | `key`, `reason` (`value`) | Ein **bekanntes** Steuerfeld hatte einen ungültigen Wert (falscher Typ, unbekannte Auswahl: `lang`, `polite`, `sensitivity`, `style`, `catch_up`; nicht numerische Zahlenfelder wie `rate`, `volume`, `silence`, `tts_race`, `let_finish`, `llm_budget`, `beam`). Der Rest der Zeile wird trotzdem angewendet. Früher still ignoriert bzw. `TypeError` bei Liste/Objekt |
| `overrun` | `frames`, `total` | Mikrofon-Puffer übergelaufen: Audio-Blöcke gingen verloren (Lücke mitten im Wort bei CPU-Spitze). Höchstens alle 5 s |
| `profiles_skipped` | `skipped` (`[{name, reason}]`, höchstens 10) | Stimmprofile, die nicht geladen wurden (anderes Erkennungsmodell, ungültig); die Stimmerkennung läuft dafür nicht |
| `captive_portal` | `msg`, `url` (Test-URL zum Öffnen des Portals) | Ein API-Host lieferte HTML bzw. eine Weiterleitung (Anmeldeseite im Hotel-/Flughafen-WLAN). Höchstens einmal je Minute; der Anbieter pausiert dann 15 s, statt jeden Satz zu versuchen. Die App kann „Im WLAN anmelden“ zeigen. Bewusst kein `error` (ältere Apps kennen den Code nicht) |
| `llm_budget_warn` | `usd`, `limit` | einmal je Monat bei 80 % des `llm_budget`-Limits (davor kam nur die Meldung beim Erreichen) |

`state` (Antwort auf `get_state`) enthält zusätzlich `silence`, `sensitivity` (`low`\|`normal`\|`high`),
`fast_endpoint`, `partial`, `tts_race`, `two_person`, `history` (bool) und `events_dropped` (Zeilen, die die
App-Pipe nicht schnell genug abnahm, siehe Log).

### Neue Codes

- `dropped.code` `backlog`: Die Arbeits-Warteschlange war voll (mehr als 15 wartende Äußerungen, z. B. bei
  Netz-/Übersetzungsstau); die **älteste** wurde verworfen. Der Platzhalter der App kann entfernt werden.
- `error.code` `languages_invalid`: `languages.json` unlesbar/unvollständig; kommt als JSON-Zeile **vor** `ready`,
  danach beendet sich die Engine mit Exit-Code 4.
- `dropped.code` `error` kommt jetzt auch bei einem Verarbeitungsfehler im Arbeits-Thread (früher fehlte `code`).

### Stimmprofil mit gewähltem Mikrofon und Rauschunterdrückung

`--profile-stdin` kennt zwei weitere Schlüssel für `enroll` (sie wirken wie die Startargumente `--mic` und
`--denoise`; die Argumente selbst gehen weiterhin):

```json
{"enroll": "Name", "enroll_lang": "en", "mic": "MacBook Pro Microphone", "denoise": true}
```

- `mic`: Name oder Index wie bei `--mic`; fehlt er, gilt `--mic` bzw. `0`.
- `denoise`: dieselbe Rauschunterdrückung wie im Betrieb (`afftdn`). Fehlt der Schlüssel, gilt `--denoise`.
- Mit `--meter` kommen beim Aufnehmen `level`-Ereignisse (`rms`, `voice`), damit die App einen Pegel zeigen und
  „zu leise/zu laut“ melden kann. Der Ablauf (`enroll_prompt`, `enroll_retry`, `enroll_done` …) ist unverändert.

### Verhalten ohne neue Felder

- **Sprachbefehle:** „too loud“ = leiser, „too quiet“ = lauter, „not so fast“ = langsamer, „don't translate“ ohne
  Sprache = Pause, „mute off“/„sound on“ = weiter, „mute on“/„sound off“ = Pause; „play“, „go ahead“, „carry on“,
  „start again“ = weiter; „one more time“, „once more“, „what did you say“ = wiederholen. „volume 3“ ist kein
  Befehl mehr (früher „lauter“).
- **Schnellsätze, „Nochmal sprechen“, „repeat“ und Befehlsantworten** werden im Aufhol-Modus `skip` nie mehr
  übersprungen; ein ausdrücklich ausgelöster Notfall-Satz geht nicht verloren.
- **Neuerkennung `reassign`:** gleiche Schutzfilter wie bei Äußerungen (Halluzination, Floskel, Wiederholung),
  Höflichkeitsform des Profils; der Stimmabdruck wird erst nachgeführt, wenn etwas erkannt wurde.
- **Ungültige Stimme** (`voice_*`) behält die bisherige Wahl (nur `error` `voice_unknown`); Preset-Stimmen, die
  nicht in der Stimmenliste stehen, werden ignoriert; ein Preset-Ende stellt Stil/Höflichkeit/Stimmen nur zurück,
  wenn sie noch den Preset-Wert haben.
- **Claude:** Zeitlimit je Modell (mindestens 5 s, sonst 2 × Hedge-Zeit), eine lange Pause („Guthaben leer“) wird
  von einem späteren kurzen Fehler nicht mehr verkürzt, `llm_billing` nur beim Übergang.
- **Utterance-IDs** tragen ein Kennzeichen des Engine-Laufs (`u<run>-<n>`, z. B. `uk3f-12`): nach einem Neustart
  treffen alte und neue IDs nicht mehr aufeinander. Die App behandelt IDs ohnehin als undurchsichtigen Text.
- **Zahlenprüfung:** buddhistisches Jahr (2569 = 2026), Monatsnamen = 1-12, „ชั่วโมงครึ่ง“ = 1:30, „a hundred“,
  „half a million“.
- **Verlauf:** neue Sitzung nach 30 min Pause oder Tageswechsel; Aufbewahrungsfrist stündlich; kurze
  Datenbank-Sperren (parallel laufender Export) schalten die Aufzeichnung nicht mehr ab (erst nach drei Fehlern in
  Folge); CSV schützt gegen Formelinjektion (`'` vor `=`, `+`, `-`, `@`); `--history-sessions` listet Sitzungen
  als JSON `[{"id", "start", "count"}]`.


### Runde 7, zweiter Teil

- **Zahlbefehle** (E1-5): „translator, volume 3“ und „speed 5“ (Skala 0-10; Lautstärke 0 = 0,2 … 10 = 2,0; Tempo 5 = normal,
  je Stufe 10 %). Ohne Zahl bleiben „louder/quieter/slower/faster“ in festen Schritten. Der Befehlsschlüssel in
  `command` ist `volume:N` bzw. `speed:N`.
- **`net`** hat jetzt auch `what: "llm"` (Claude pausiert nach einem Fehler) und dabei `retry_in_s` (Sekunden bis zum
  nächsten Claude-Versuch); `ok: true`, sobald Claude wieder antwortet.
- **Mikrofon-Reconnect** wechselt bei einem verschwundenen *benannten* Gerät nicht mehr aufs Standardmikrofon; die
  Engine wartet (`mic` `reconnecting`) auf das Gerät.
- **`--file`**: Sätze werden nie übersprungen (Aufhol-Modus aus, Verarbeitung wartet aufs Vorlesen, kein 120-s-Limit).
- **Ausgabe-Pipe**: ist sie voll, werden zuerst Pegel/Teiltext-Zeilen verworfen, dann erst die älteste Zeile.
- **Verlauf**: SQLite im WAL-Modus (Export blockiert die Aufzeichnung nicht); nach Löschen wird die WAL-Datei
  geleert. Schreiben läuft im Engine-Betrieb in einem eigenen Thread (nicht mehr im Ausgabe-Lock).
- **Hilfsprozesse**: der Apple-Offline-Übersetzer-Helfer wird nach 5 min Leerlauf und beim Beenden beendet; die
  Neural-Stimme öffnet nach zwei Fehlschlägen 30 s lang keine neuen Verbindungen.

- **`cache_persist`** (Steuerfeld, bool): Übersetzungs-Cache übersteht den Neustart (Datei `translation_cache.json` im Datenordner,
  0600, höchstens 300 Einträge). Standard aus; ausschalten oder `clear` löscht die Datei. So gehen schon übersetzte
  Standardsätze auch ohne Netz.
- **`utt.num_diff`** (E1-50): wenn `num_warn` gesetzt ist, `{src: [...], out: [...]}` mit den Zahlen, die nur im Original bzw. nur in der
  Übersetzung stehen (normalisiert, höchstens 8 je Seite), damit die App genau sie markieren kann.
- `llm_cost.price_known` (bool): Modell steht in der Preisliste (sonst Schätzung mit dem Opus-Preis).
- **Höflichkeitsstufe** (Runde 11): `formality` und `speaker_sex` sind neue, optionale Steuerfelder; ältere Apps senden sie nicht
  und die Engine ignoriert sie dort wie jedes unbekannte Feld (Apps, die sie senden, an einer älteren Engine bekommen
  `control_ignored`). `formality` gibt dem Prompt je Zielsprache aus der Anrede-Tabelle eine Stufe vor: de Sie/du,
  fr vous/tu, es usted/tú …, ja einfache Form / desu-masu (Teineigo) / volles Keigo, ko 반말/해요체/합쇼체, th lockeres
  / alltägliches / förmliches Thai. Die Sprachtabelle `languages.json` wird nur gelesen. Nach Claude ordnet die
  Engine bei Zielsprache Thai die Partikel dem Sprechergeschlecht zu (ค่ะ/คะ ↔ ครับ, Frage am Satzende คะ); Text mit
  beiden Formen oder ohne Partikel bleibt unverändert. `state.llm` enthält zusätzlich `formality`.
- **Claude-Anrede** (E1-20): der Prompt nennt je Zielsprache die Anrede nach dem Stil (de du/Sie, es tú/usted, fr tu/vous,
  ja einfache/höfliche Form, ko 반말/존댓말 …). **Fragen ohne „?“** erkennt die Engine jetzt auch für de, es, fr (ครับ/คะ).

- **`history_speakers`** (Steuerfeld, bool, Standard an): `false` schreibt keine Profilnamen in die Verlaufsdatenbank
  (Rolle `me`/`other` bleibt).
- **`hint`** `{code, …}` (selten, je Code höchstens alle 5 min): `slow` (`what` = `stt`\|`tr`\|`sound`, `p90`: Latenz dauerhaft
  hoch – kleineres Modell, Beam 1, `tts_race`), `mic_far` (viele sehr leise, zu kurze Äußerungen: Mikrofon näher oder
  Empfindlichkeit anheben), `mic_gap` (Runde 24: der Mikrofon-Puffer lief über, der folgende Satz kann unvollständig sein), `device_fallback` (`device: "cpu"`: die Apple-GPU (MPS) fiel im Betrieb aus, die Modelle laufen jetzt einmalig neu geladen auf der CPU). Die App lokalisiert über `code`.
- **`tts_fallback`** `{reason: "offline"\|"slow"\|"error"}`: die macOS-Ersatzstimme statt der Neural-Stimme spricht; einmal je Wechsel,
  bis die Neural-Stimme wieder Ton liefert. Dann kommt **`tts_fallback`** `{ended: true}` (ohne `reason`): Anzeige „Ersatzstimme“
  ausblenden. Ältere Apps ignorieren das Feld `ended`.
- **`speak_failed`** `{reason: "say", rc}`: auch die macOS-Stimme hat nichts gesprochen (Fehler/Zeitgrenze); die App kann den
  Text groß anzeigen oder „Wiederholen“ anbieten. Zusätzlich zu `speak_done` der Ausgabe.
- **`price`** `{id, code, items: [{thb, value?}]}` (nur wenn das Steuerfeld `currency` gesetzt ist): in der Äußerung (Quelle oder
  Übersetzung) wurden Baht-Beträge erkannt (höchstens 3, ohne Doppelte); `value` = Betrag in der Heimwährung `code`.
  Kommt direkt nach `utt` derselben `id`. Reine Anzeigehilfe, der Kurs stammt von der App.
- **Steuerfeld `currency`** `{"code": "EUR", "per_baht": 0.026}`: Heimwährung und Kurs für `price`; `null` schaltet ab. Ungültig:
  `control_invalid` (`key: "currency"`).
- **Hinweis `noisy`** (`hint`): lange durchgehend laute Umgebung ohne Sprache (Markt, Verkehr) – Tipp: Kopfhörer-Mikrofon oder
  `--denoise`. Nicht gesendet, wenn Rauschunterdrückung schon an ist.
- **Hinweis `mic_ambiguous`** (`hint`, `n`): mehrere Mikrofone heißen gleich; die Engine nimmt das erste – für ein bestimmtes Gerät den Index
  in `mic` angeben.
- **Neural-Stimme und Proxy:** ohne `DOLMETSCHER_TTS_NO_PROXY` läuft der Text über den in `HTTP(S)_PROXY` eingestellten Proxy. Bei 403 wegen falscher Systemuhr übernimmt die Engine die Serverzeit automatisch.
- **`power`** `{battery, beam}` (nur mit `--model auto`): Akku/Netz hat zur Laufzeit gewechselt; im Akkubetrieb rechnet die Engine mit Beam 1,
  im Netzbetrieb wieder mit dem vorherigen Wert. Beim Start im Netzbetrieb kommt nichts.
- **Sprachbefehle** `repeat_slow` („repeat slowly“) und `repeat_prev` („repeat the previous one“) erscheinen als Befehlsschlüssel in `command`.
- **`subtitles`** `{path, cues}`: `--file … --subtitles` fertig geschrieben.
- **Preset-Feld `tuning`** (optional): `{silence 0.4-2, sensitivity low|normal|high, let_finish 0-5, catch_up
  skip|fast|off, rate -50…50}` – gilt, solange das Preset aktiv ist; „kein Preset“ stellt den Stand davor wieder her.
- **`--tts say`** rendert Teilsätze vorab (keine Pausen dazwischen). **`--model auto`** wählt im Akkubetrieb eine Stufe
  sparsamer (Beam 1, `best` → `medium`). `DOLMETSCHER_TUNE` kennt zusätzlich `WAKE_S`, `ROLE_PREV_GAP`, `DEGRADE_AT`,
  `PRE_AT`, `SKIP_AT`, `PRESTART`, `FAST_BOOST`.
- **`--history-search`** liefert mit `--history-context N` je Treffer `context` (N Zeilen davor/danach derselben Sitzung)
  und filtert mit `--history-lang`/`--history-session`.
- **Notfall-Phrasen** (`critical` im Preset): beim Aktivieren rendert die Engine sie (en und th, nur mit Neural-Stimme, nicht im
  Privatmodus/stumm) im Hintergrund in den Sprach-Cache (Speicher). Wird derselbe Text später gesprochen, kommt der Ton ohne
  Latenz und ohne Netz. Der Cache liegt nur im Speicher (nicht auf der Platte).
- **`repeat` nach Neustart**: ist der Verlauf an, merkt sich die Engine beim Start/Einschalten die letzte Übersetzung wieder.
- **Privatmodus** lädt das Sprechermodell nicht nach; **Anki-Export** hat `#guid column`, `#deck` und Tags (Sprache, Sitzung).
- **Runde 24 (Engine):** Spur je Satz im Log (`trace`: Zeitpunkt von `thinking`, `heard`, `utt`, `speaking`, `speak_done`/`dropped`
  seit der ersten Meldung), p50/p95 der Latenz über Sitzungen (`latency_history.json` im Datenordner, Log `latency_hist`),
  Schnellmodus der Erkennung (Beam 1) ab 5 wartenden Äußerungen statt Verwerfen, Prompt-Injektionsschutz für Glossar,
  Preset-Hinweis, Verlauf und Alternativen (keine Tags, keine Zeilenumbrüche), Positivliste im Log (lange Texte unter
  unbekannten Schlüsseln werden nie geloggt).
- **Runde 25 (Engine):** Gruppenmodus (`group_speakers`, `utt.group_speaker`), Systemton-Quelle (`--source`, Steuerfeld `source`,
  Fähigkeiten `feature:group_speakers`, `feature:system_audio`), `state` meldet `group_speakers` und `source`. Fehlercode
  `system_audio_missing` (nur `msg`/`msg_en`; die App zeigt den Freitext, bis sie den Code lokalisiert).
- **Runde 25 (Schalter):** `llm_stream`, `llm_router`, `defer`, `parallel_alt`, `stt_prompt`, `speak_numbers` bleiben nach Prüfung
  Standard aus (keine Messung für Router, Stream, Prompt, Zahlen; sie ändern Text/Ton oder die Reihenfolge). Erkennung und
  Transkription sind nicht zusammengelegt: die Erkennung läuft mit `m_det`, Sperre, Profil-Vorrang, Rolle und Gegenprobe brauchen
  die Sprache vor dem Dekodieren.

## Runde 27 (Engine)

Additiv, `PROTOCOL` bleibt 1.

- **Ausgabegerät je Richtung:** Steuerfelder `output_device_me` / `output_device_other` (Format wie `output_device`).
  Der Speaker bestimmt die Richtung je Ausgabe aus der Zielsprache (`PAIR[0]` = `me`, sonst `other`; Befehlsantworten
  und Signaltöne immer `me`) und wählt das Gerät beim Abspielen; leere Richtung = `output_device` = Systemstandard.
  Die Mac-App sendet die Felder (`AudioRouteLogic.protocolFields`, `Engine.sendAudioRoute`) nach `ready` und bei jeder Änderung, aber nur an eine Engine, deren `capabilities` sie nennen.
