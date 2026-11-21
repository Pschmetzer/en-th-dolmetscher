# Doku-Landkarte

Alle Dokumente im Überblick, nach Zielgruppe sortiert. Neue Dokumente in `docs/` müssen hier verlinkt werden
(`tools/check_docs_index.py` prüft das in der CI).

## Ich will die App benutzen

| Dokument | Inhalt |
|---|---|
| [SCHNELLSTART.md](SCHNELLSTART.md) | Installieren und das erste Gespräch in fünf Minuten |
| [FAQ.md](FAQ.md) | Häufige Fragen |
| [FEHLERHILFE.md](FEHLERHILFE.md) | Wenn etwas nicht klappt: Mikrofon, Modelle, Netz |
| [TASTENKUERZEL.md](TASTENKUERZEL.md), [SPRACHBEFEHLE.md](SPRACHBEFEHLE.md) | Tastenkürzel und Sprachbefehle |
| [DATENSCHUTZ-KURZ.md](DATENSCHUTZ-KURZ.md) | Datenschutz in einer Minute (die ausführliche Fassung: [DATENSCHUTZ.md](DATENSCHUTZ.md)) |
| [WEB-KOMPATIBILITAET.md](WEB-KOMPATIBILITAET.md) | Welche Browser die Web-Version kann |
| [en/](en/QUICKSTART.md) · [th/](th/README.md) | Englische und thailändische Fassungen der Benutzerdoku |

Englisch: [QUICKSTART](en/QUICKSTART.md), [FAQ](en/FAQ.md), [TROUBLESHOOTING](en/TROUBLESHOOTING.md),
[SHORTCUTS](en/SHORTCUTS.md), [VOICE-COMMANDS](en/VOICE-COMMANDS.md), [PRIVACY-SHORT](en/PRIVACY-SHORT.md), [WEB](en/WEB.md).
Thai: [QUICKSTART](th/QUICKSTART.md), [FAQ](th/FAQ.md), [PRIVACY-SHORT](th/PRIVACY-SHORT.md), [WEB](th/WEB.md).

## Ich will mitarbeiten

| Dokument | Inhalt |
|---|---|
| [ENTWICKLUNG.md](ENTWICKLUNG.md) | Einstieg für Mitwirkende: Einrichtung, Ordnerkarte, „Ich ändere X, also prüfe ich Y“ |
| [ARCHITEKTUR.md](ARCHITEKTUR.md) | Prozessmodell, Threads, Zustände, Datenfluss einer Äußerung |
| [PROTOKOLL.md](PROTOKOLL.md) | JSON-Protokoll zwischen App und Engine (Ereignisse, Steuerung, Codes) |
| [PRESETS.md](PRESETS.md) | Format und Liste der Phrasenpakete |
| [CI.md](CI.md) | Alle Workflows, lokal nachstellen, Zwischenspeicher, Abhängigkeiten |
| [RELEASE.md](RELEASE.md) | Veröffentlichen: Checkliste, Release-Notes aus dem Changelog |
| [VERSIONEN.md](VERSIONEN.md) | Welcher Teil hat welche Versionsnummer |
| [GLOSSAR-UI.md](GLOSSAR-UI.md) | Einheitliche Begriffe in der Oberfläche |
| [IOS-LOGIK-R35.md](IOS-LOGIK-R35.md) | Logik-Bausteine der iPhone-App (Runde 35) |
| [ROADMAP.md](ROADMAP.md) | Ideen (keine Zusagen) |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Regeln für Pull requests, Lock-Dateien, Signieren |

## Qualität, Sprache, Recht

| Dokument | Inhalt |
|---|---|
| [DATENSCHUTZ.md](DATENSCHUTZ.md) | Was den Mac verlässt, wann und wohin; bei jedem neuen Netzaufruf anpassen |
| [LIZENZEN.md](LIZENZEN.md) | Lizenzen von Modellen, Paketen und Diensten |
| [TH-QUALITAET.md](TH-QUALITAET.md) | Wie die Qualität der Thai-Texte gesichert wird |
| [MUTTERSPRACHLER.md](MUTTERSPRACHLER.md) | Aufruf an Muttersprachler: was zu prüfen ist |
| [../SECURITY.md](../SECURITY.md) | Sicherheitslücken melden |

## Betrieb der Web-Version

| Dokument | Inhalt |
|---|---|
| [WEB-HOSTING.md](WEB-HOSTING.md) | Selbst hosten (Header, Cache, HTTPS) |
| [hosting/Caddyfile](hosting/Caddyfile), [hosting/nginx.conf](hosting/nginx.conf), [hosting/cloudflare_headers](hosting/cloudflare_headers), [hosting/netlify_headers](hosting/netlify_headers) | Fertige Konfigurationen |
| [presets.schema.json](presets.schema.json) | JSON-Schema der Phrasenpakete |
| [store/README.md](store/README.md) | Texte und Bilder für die Store-Einträge |
