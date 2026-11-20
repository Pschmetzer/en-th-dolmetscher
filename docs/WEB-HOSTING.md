# Web Lite auf eigener Domain bereitstellen

Für Vereine, Schulen, Hotels: die Seite besteht nur aus statischen Dateien, ohne Server-Code.

## Dateien

`index.html`, `sw.js`, `manifest.webmanifest`, `languages.json`, `presets-index.json`, `allergens.json`, `icon.svg`,
`icon-192.png`, `icon-512.png`, `icon-maskable-192.png`, `icon-maskable-512.png`, `apple-touch-icon-180.png`, die Ordner
`presets/` (alle `*.json`), `i18n/` (`en.json`, `th.json`) und `screenshots/` (nur für die Installationsansicht). Alles andere im Repository wird nicht gebraucht.
Das Skript `tools/make_presets_index.py` erzeugt `presets-index.json` neu, falls du Pakete änderst.

## Bedingungen

- **HTTPS ist Pflicht**: Service Worker und Mikrofon gibt es nur über HTTPS (oder `localhost`).
- Unterordner (`https://example.org/dolmetscher/`) geht: alle Pfade sind relativ, der Service Worker nutzt seinen Scope.
- **Eigener Ursprung empfohlen**: `localStorage` gilt pro Ursprung. Läuft die Seite neben anderen Seiten unter derselben
  Domain, können diese die gespeicherten Lernkarten und Einstellungen lesen (siehe `docs/DATENSCHUTZ.md`).
- `CACHE` in `sw.js` erhöhen, wenn Dateien dazukommen oder sich Vorab-Dateien (Pakete, Icons, `i18n/`) ändern. `index.html` selbst wird immer zuerst vom Netz geholt; die Seite fragt stündlich nach einem neuen Service Worker.

## Empfohlene Header

```
Content-Security-Policy: wie im <meta> von index.html (default-src 'none'; script-src 'unsafe-inline' ...)
Permissions-Policy: microphone=(self), camera=(), geolocation=()
Referrer-Policy: no-referrer
Content-Security-Policy: ... frame-ancestors 'none'   (im <meta> wirkungslos; nur als Header, schützt vor Einbetten)
Cross-Origin-Opener-Policy: same-origin
X-Content-Type-Options: nosniff
Cache-Control: no-cache            (für sw.js und index.html, damit Updates ankommen)
```

`Content-Type` für `manifest.webmanifest`: `application/manifest+json`.

## Ohne Netz ausprobieren

`python3 -m http.server 8000` im Repository-Ordner, dann http://localhost:8000 (localhost zählt als sicherer Kontext).

## QR-Code für Gäste

Ein Link wie `https://example.org/dolmetscher/#preset=hotel&l=de` öffnet direkt das Thema Hotel mit der Sprache des Gasts
(`l`) als „Ich spreche“. Jeden QR-Generator verwenden; die Seite selbst enthält keinen.
