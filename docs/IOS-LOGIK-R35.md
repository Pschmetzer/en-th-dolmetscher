# iPhone: Logik-Bausteine der Runde 35

Alle in `ios/Dolmetscher/Round35.swift`, nur Foundation, ohne Systemaufrufe. Tests: `ios/DolmetscherTests/Round35Tests.swift`.
Die Bausteine sind noch **nicht in Oberflächen eingebunden** (kein Mac in dieser Runde, Oberflächencode ohne Compiler wäre riskant);
sie sind fertig getestet und warten auf die Anbindung.

| Baustein | Zweck |
|---|---|
| `R35Accessibility.bubbleLabel` | VoiceOver-Text einer Sprechblase: "Ich, 14:05: Hallo" |
| `R35Accessibility.confidence` | Erkennungssicherheit als Stufe (niedrig/mittel/hoch), nicht nur Farbe |
| `R35Accessibility.clampedSize` | Systemschrift-Faktor, begrenzt (große Schrift sprengt kein Layout) |
| `R35Accessibility.animationDuration` | 0 bei "Bewegung reduzieren" |
| `R35RetryQueue` | Texte ohne Verbindung: begrenzt, ohne Dopplung, ältester zuerst, Codable |
| `R35ErrorKind.classify` | NSURLError/HTTP-Status zu offline, Zeitüberschreitung, TLS, abgebrochen, Server, Anmeldung, Kontingent |
| `R35Backoff` | Wartezeit 1, 2, 4 ... s (gedeckelt) und Wiederholregel nur für behebbare Fehler |
| `R35Storage.verdict` | reicht der freie Platz für einen Modell-Download (ok / knapp / zu wenig) |
| `R35Storage.format` | Größenangabe mit Punkt, unabhängig von der Region |
| `R35Clock.format` / `spoken` | Sitzungsdauer "1:02:03" und für VoiceOver "1 Stunde 2 Minuten" |
| `R35Clock.isQuiet` | Ruhezeit über Mitternacht |
| `R35Locale.resolve` | Oberflächensprache aus der Geräteliste ("zh-Hans-CN" zu "zh-Hans") |
| `R35Text.truncate` | Kürzen nach Zeichen, zerreißt weder Thai-Zeichen noch Emoji |
| `R35Text.sanitized` / `shareText` | Steuerzeichen und Richtungsumschalter vor dem Teilen entfernen |
| `R35Retention.keep` | Verlauf nach Alter und Anzahl aufräumen |
| `R35Debounce` | Aktion höchstens alle n Sekunden, robust gegen zurückgestellte Uhr |
| `R35Version.compare` | Versionsvergleich "1.10.0" gegen "1.9.2" |

Zusätzliche Tests für bestehende Logik der Runden 32 bis 34: Reise-Tabelle, Hotelkarte, Planer (Hash-Schlüssel, Aufräumen, UserDefaults),
Kartenthemen, Whisper-Teiltext-Entscheidung, Speisekarten-Namen.
