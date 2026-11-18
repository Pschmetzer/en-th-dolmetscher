# Sicherheit

## Sicherheitslücke melden

Bitte **kein öffentliches Issue** für Sicherheitslücken. Nutze stattdessen auf GitHub im Reiter *Security* den Punkt
*Report a vulnerability* (privater Sicherheitshinweis des Repositorys). Ist er dort nicht sichtbar, öffne ein Issue
ohne Einzelheiten („Ich möchte eine Sicherheitslücke melden“); wir melden uns dann auf einem privaten Weg.

Hilfreich sind: betroffene Plattform (Mac, iPhone, Browser, Engine), Version, Schritte zum Nachstellen und die
mögliche Auswirkung. Bitte keine echten Gesprächsinhalte, Sprachaufnahmen oder API-Schlüssel mitschicken.

Das ist ein Hobby-Projekt ohne feste Antwortzeit. Wir bemühen uns um eine kurze Rückmeldung und nennen dich auf
Wunsch im Changelog.

## Was zählt

- Abfluss von Audio, Text, Schlüsseln oder Stimmprofilen, die laut [docs/DATENSCHUTZ.md](docs/DATENSCHUTZ.md) lokal bleiben sollen
- Ausführen fremden Codes über Phrasenpakete, Einstellungen, das JSON-Protokoll zwischen App und Engine oder die Web-Version
- Fehler im Umgang mit dem Claude-Schlüssel (Schlüsselbund auf dem Mac)

Nicht dazu zählen falsche oder unhöfliche Übersetzungen. Dafür gibt es die Vorlage *Thai-Übersetzungsfehler* bzw. *Fehler melden*.

## Unterstützte Versionen

Gepflegt wird der jeweils neueste Stand auf `main` und die letzte Version.

## Hinweise für Mitwirkende

Schlüssel, Tokens und persönliche Daten gehören nie ins Repository (siehe [CONTRIBUTING.md](CONTRIBUTING.md)).
Abhängigkeiten sind in `requirements.txt` festgenagelt; Dependabot und CodeQL laufen über `.github/`.
