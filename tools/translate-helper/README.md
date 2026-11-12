# translate-helper (Prototyp)

Apples Translation-Framework (on-device, offline, kostenlos) als Kommandozeilen-Dienst für EN⇄TH, **ohne SwiftUI**.

## Ergebnis

- **API ohne SwiftUI vorhanden, echte Übersetzung aus dem CLI aber noch ungetestet.** Bestätigt: kompiliert,
  Sitzung lässt sich aus einem nackten CLI-Binary (ohne Bundle/Info.plist) erzeugen, Statusabfrage und Fehlerpfad
  (`notInstalled`) funktionieren. Auf diesem Mac ist **kein einziges** Sprachpaar installiert (auch nicht en-de o. ä.),
  daher konnte keine Übersetzung durchlaufen. Hauptrisiko: dass ein unbundled Binary trotz installierter Pakete
  abgewiesen wird – erst nach Installation prüfbar.
- Seit macOS 26.0 gibt es den öffentlichen Initializer
  `TranslationSession(installedSource:target:)` (ab 26.4 zusätzlich `preferredStrategy: .highFidelity | .lowLatency`).
  Dazu `translate(_:)`, `translations(from:)`, `prepareTranslation()`, `isReady`, `canRequestDownloads`
  und `LanguageAvailability().status(from:to:)` → `.installed | .supported | .unsupported`.
- Einschränkung des Initializers: Er nutzt **nur bereits installierte** Sprachpakete; gemessen:
  `canRequestDownloads == false`, `isReady == false` (TH→EN). Herunterladen per Dialog gibt es laut API nur über eine
  SwiftUI-Sitzung (`.translationTask`, `prepareTranslation()`) – hier nicht ausprobiert.
- Geprüft auf macOS 26.6.2, Command Line Tools SDK. Der Helfer braucht macOS 26.4+ (wegen `--fast`), sonst meldet er
  `{"ready":false,"error":"macOS 26.4 oder neuer nötig"}`.

## Stand auf diesem Mac

```
$ /tmp/translate-helper --check
{"pairs":{"en-th":"supported","th-en":"supported"},"ready":true}
```

Die Pakete sind **nicht installiert** (`supported` = möglich, aber nicht geladen). Jede Anfrage liefert dann sofort:

```
{"error":"notInstalled: Sprachpaket fehlt (Systemeinstellungen > Allgemein > Sprache & Region > Übersetzungssprachen)","id":1}
```

Latenzmessung steht deshalb noch aus. Nach Installation der Pakete einfach den Test unten wiederholen.

**Installieren (macht der Nutzer selbst):** Systemeinstellungen → Allgemein → Sprache & Region → ganz unten
„Übersetzungssprachen …“ → Englisch und Thai laden. Danach sollte
`--check` `installed` für beide Richtungen.

## Bauen und testen

```sh
swiftc -O -parse-as-library -o /tmp/translate-helper tools/translate-helper/main.swift
/tmp/translate-helper --check
printf '%s\n' \
  '{"id":1,"text":"ฉันง่วงนอนมาก อยากกลับบ้านแล้ว","src":"th","dst":"en"}' \
  '{"id":2,"text":"Where is the nearest train station?","src":"en","dst":"th"}' \
  | /tmp/translate-helper            # oder --fast für .lowLatency
```

## Protokoll (JSON-Zeilen über stdin/stdout)

| Richtung | Inhalt |
|---|---|
| Start (stdout, erste Zeile) | `{"ready":true,"pairs":{"en-th":"installed\|supported\|unsupported","th-en":"..."}}` |
| Anfrage (stdin) | `{"id":1,"text":"...","src":"th","dst":"en"}` |
| Antwort | `{"id":1,"out":"...","ms":123}` oder `{"id":1,"error":"..."}` |

Anfragen werden der Reihe nach abgearbeitet, eine Sitzung pro Sprachpaar wird wiederverwendet (nach einem Fehler
neu erzeugt). EOF auf stdin beendet den Prozess.

## Nutzung aus der Engine (Skizze)

```python
p = subprocess.Popen([HELPER], stdin=PIPE, stdout=PIPE, text=True, bufsize=1)
hello = json.loads(p.stdout.readline())
if hello["pairs"].get("th-en") == "installed":
    p.stdin.write(json.dumps({"id": n, "text": t, "src": "th", "dst": "en"}, ensure_ascii=False) + "\n")
    p.stdin.flush()
    r = json.loads(p.stdout.readline())   # r["out"] oder r["error"] -> Fallback auf bisherigen Übersetzer
```

Sinnvoll: Helfer einmal beim Engine-Start öffnen, bei `supported`/`error` auf den bisherigen Übersetzer zurückfallen.

## Einschränkungen

- Keine Downloads aus dem CLI; Pakete müssen vorher über die Systemeinstellungen installiert sein.
- `--fast` (`.lowLatency`) prüft den Status mit derselben Strategie (hier ebenfalls `supported`).
- Nur sequenziell (eine Anfrage nach der anderen); für Batches gäbe es `translations(from:)`.
- Qualität für Thai noch nicht bewertet (keine Pakete installiert).
