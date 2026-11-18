# Web Lite auf eigener Domain bereitstellen

Für Vereine, Schulen, Hotels: die Seite besteht nur aus statischen Dateien, ohne Server-Code.

## Dateien

`index.html`, `sw.js`, `manifest.webmanifest`, `languages.json`, `presets-index.json`, `allergens.json`, `icon.svg`,
`icon-192.png`, `icon-512.png` und der Ordner `presets/` (alle `*.json`). Alles andere im Repository wird nicht gebraucht.
Das Skript `tools/make_presets_index.py` erzeugt `presets-index.json` neu, falls du Pakete änderst.

## Bedingungen

- **HTTPS ist Pflicht**: Service Worker und Mikrofon gibt es nur über HTTPS (oder `localhost`).
- Unterordner (`https://example.org/dolmetscher/`) geht: alle Pfade sind relativ, der Service Worker nutzt seinen Scope.
- **Eigener Ursprung empfohlen**: `localStorage` gilt pro Ursprung. Läuft die Seite neben anderen Seiten unter derselben
  Domain, können diese die gespeicherten Lernkarten und Einstellungen lesen (siehe `docs/DATENSCHUTZ.md`).
- Dateien nach jeder Änderung an Vorab-Dateien: `CACHE` in `sw.js` erhöhen, sonst sehen Besucher die alte Version.

## Empfohlene Header

```
Content-Security-Policy: wie im <meta> von index.html (default-src 'none'; script-src 'unsafe-inline' ...)
Permissions-Policy: microphone=(self), camera=(), geolocation=()
Referrer-Policy: no-referrer
X-Content-Type-Options: nosniff
Cache-Control: no-cache            (für sw.js und index.html, damit Updates ankommen)
```

`Content-Type` für `manifest.webmanifest`: `application/manifest+json`.

## Ohne Netz ausprobieren

`python3 -m http.server 8000` im Repository-Ordner, dann http://localhost:8000 (localhost zählt als sicherer Kontext).

## QR-Code für Gäste

Ein Link wie `https://example.org/dolmetscher/#preset=hotel&l=de` öffnet direkt das Thema Hotel mit der Sprache des Gasts
(`l`) als „Ich spreche“. Jeden QR-Generator verwenden; die Seite selbst enthält keinen.
