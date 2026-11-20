# Web Lite: Browser-Matrix

Es gibt keine automatischen Browser-Tests (siehe Abschnitt „Prüfung“). Die Tabelle ist die Liste dessen, was vor einem
Release von Hand geprüft werden soll. **Alle Zellen sind zu Beginn „offen“**: wer einen Browser prüft, trägt Datum,
Version und Ergebnis ein (✓ geht, ✗ geht nicht, – nicht vorhanden).

| Browser | Version / Datum | Erkennung | Stimme Thai | Satzbuch offline | Installieren (PWA) | Wake Lock | Zurück-Taste schließt Großansicht |
|---|---|---|---|---|---|---|---|
| Chrome Android | offen | offen | offen | offen | offen | offen | offen |
| Chrome Desktop | offen | offen | offen | offen | offen | offen | offen |
| Edge Desktop | offen | offen | offen | offen | offen | offen | offen |
| Safari iPhone | offen | offen (Diktierfunktion an) | offen | offen | „Zum Home-Bildschirm“ | offen | offen |
| Safari Mac | offen | offen | offen | offen | – | offen | offen |
| Samsung Internet | offen | offen | offen | offen | offen | offen | offen |
| Firefox | offen | – (keine Spracherkennung) | offen | offen | – | offen | offen |

## Checkliste vor einem Release

1. Seite über HTTPS öffnen (nicht `file://`): Service Worker registriert, „✓ Offline bereit“ erscheint.
2. Flugmodus: Seite neu laden, Satzbuch (Englisch/Thai) und Ja/Nein gehen.
3. Mikrofon-Einwilligung, E/T-Modus, „Halten zum Sprechen“, Stopp.
4. Großansicht: Zurück-Taste schließt sie, Bildschirm bleibt an, Schrift A+/A−, Thai ohne abgeschnittene Tonmarken.
5. Thema mit Notrufnummer (Arzt): `tel:`-Links sichtbar.
6. 320 px Breite und 400 % Zoom: kein abgeschnittener Inhalt (WCAG 1.4.10).
7. Hell/Dunkel und Hochkontrast: Knöpfe unterscheidbar.
8. Neue Version: `CACHE` in `sw.js` erhöht; Hinweisband „Neue Version geladen“ erscheint beim zweiten Besuch.
9. Drucken eines Themas (Vorschau): nur die Tabelle, Thai groß.
10. Einmal je Oberflächensprache (Deutsch, English, ไทย) durchklicken.
11. Geteilten Text an die App senden (`?text=…`): erst nach „Übersetzen“ wird etwas gesendet.
12. Installieren: Symbol ist auf Android rund/quadratisch ohne Rand (maskable), auf dem iPhone ohne schwarze Ecken.
13. Lernkarte: Taste 1 bis 4 bewertet, schaltet aber kein Mikrofon ein.

## Prüfung

`tests/test_runde7_web_smoke.py` startet das Skript mit Attrappen in node (Startfehler), `tests/test_web_*.py` prüfen
die Logik, den Service Worker und das HTML. Ein echter Browser-Test (Playwright, axe) ist nicht eingerichtet.
