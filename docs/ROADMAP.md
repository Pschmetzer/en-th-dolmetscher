# Roadmap (Ideen)

> **Das sind Ideen, keine Zusagen.** Sie stammen aus den bekannten Grenzen im README, dem [CHANGELOG](../CHANGELOG.md)
> und dem Aufbau des Codes. Es gibt keine Termine. Was gebaut wird, entscheidet sich im Issue.
> Neue Ideen bitte mit der Vorlage *Funktion vorschlagen* einreichen.

## Sprache und Qualität

- **Muttersprachliche Prüfung** der Thai-Sätze und der sieben neueren Oberflächensprachen (siehe [MUTTERSPRACHLER.md](MUTTERSPRACHLER.md)). Das ist die wichtigste Lücke.
- **Test mit echten Sprechern** für die neuen Sprachen: Die Erkennungsschwellen sind für sie noch nicht kalibriert (README, Abschnitt Sprachen).
- **Benchmark mit echten Stimmen** statt synthetischer (bisher nur synthetische Stimmen, siehe `bench/README.md`).
- **Stimmprofile** auch für weitere Sprachen; bisher werden sie auf Englisch oder Thai aufgenommen.

## Mac

- Wake-Word und Sprachbefehle auch ohne Englisch im Paar (bisher nur mit Englisch).
- Konversationsmodus, Antwortkarten und Lernmodus wie auf dem iPhone (in der Funktionstabelle des README mit „–“ markiert).
- Intel-Macs: Die App ist bisher nur für Apple Silicon gebaut.

## iPhone und iPad

- Claude-Übersetzung als Option (bisher nur Mac).
- Sprachbefehle und Wake-Word jenseits von Englisch.
- Mehr Widgets und Steuerelemente auf Basis der vorhandenen Schnellsatz-Widgets und Live-Aktivität.

## Browser (Web Lite)

- Automatische Erkennung des Sprechers (bisher tippt man die Seite an).
- Konversationsmodus und Notfallbildschirm wie auf dem iPhone.
- Mehr Antwortkarten (bisher nur Ja/Nein).

## Phrasenpakete

- Weitere Szenarien nach Bedarf der Reisenden; jedes Paket mit Kulturhinweis und markierten wichtigen Sätzen.
- Weitere Sprachen für die Pakete, sobald sich Muttersprachler für die Prüfung finden.

## Projekt

- Veröffentlichte Releases mit Signatur und Notarisierung für die Mac-App, regelmäßig statt als „Unreleased“-Stand.
- Gemeinsame Prüfliste für Muttersprachler als einfaches Formular, damit auch Menschen ohne GitHub mitmachen können.
