# Sprachbefehle

Gilt für die Mac-App (Engine `dolmetscher.py`), die iPhone-App und im Auszug für die Browser-Version. Quelle der Befehle: `COMMANDS` und `parse_command()` in `dolmetscher.py`. Englische Fassung: [en/VOICE-COMMANDS.md](en/VOICE-COMMANDS.md).

## So geht es

- Der Befehl beginnt mit dem Weckwort **„Translator“** (auch „Hey translator“, „OK translator“). Danach folgt der Befehl: „Translator, pause“.
- Befehle werden **auf Englisch** gesprochen, nie übersetzt und **nur erkannt, wenn Englisch eine der beiden Sprachen des Paars ist**.
- Nur kurze Äußerungen zählen: höchstens 5 Wörter nach dem Weckwort. Längeres ist Gespräch und wird übersetzt.
- Sagst du nur „Translator“ und machst eine Pause, antwortet die App mit „Yes?“ und nimmt den nächsten Satz als Befehl.
- Ein Befehl pro Äußerung. Die Befehle steuern nur die App; allgemeine Fragen beantwortet sie nicht.
- Bei Lärm oder starkem Akzent kann ein Befehl falsch verstanden werden. Die Erkennung toleriert typische Verhörer („Translate or pause“) und einfache Verneinungen („too loud“ macht leiser, „too fast“ langsamer, „mute off“ hebt Stumm auf).

## Befehle (Mac und iPhone)

| Sage | Wirkung |
|---|---|
| Translator, pause (auch stop, mute, sleep, be quiet) | Übersetzen anhalten; die App hört weiter auf Befehle |
| Translator, resume (auch continue, start, unmute, unpause) | weitermachen |
| Translator, repeat (auch again, say that again) | letzte Übersetzung nochmal sprechen |
| Translator, repeat slowly | letzte Übersetzung einmal langsamer sprechen (hilft, wenn der Zuhörer sie nicht verstanden hat) |
| Translator, repeat the previous one | die Übersetzung davor nochmal sprechen |
| Translator, slower / faster | Sprechtempo |
| Translator, louder / quieter | Lautstärke |
| Translator, volume 3 / speed 5 | Lautstärke bzw. Tempo auf einer Skala von 0 bis 10 (bei Tempo ist 5 normal) |
| Translator, Thai only / English only / auto | Sprache festlegen oder wieder automatisch erkennen |
| Translator, German only (und andere Sprachen des Paars, englisch benannt) | nur diese Sprache; auch „Spanish off“ usw. |
| Translator, English off / Thai off | diese Sprache wird nur angezeigt, nicht übersetzt oder gesprochen |
| Translator, English on / Thai on / translate both | die Richtung wieder einschalten |
| Translator, female voice / male voice | Thai-Stimme und Höflichkeitsform (ค่ะ / ครับ) |
| Translator, clear | Gespräch leeren |
| Translator, help | Befehle anzeigen |
| Translator, hotel mode / preset taxi | Szenario-Paket wählen; „preset off“ schaltet es ab |

## Browser

Die Browser-Version versteht die Befehle nur im Englischen-Modus und am Satzanfang: pause, repeat, slower, faster, louder, quieter, clear, help. **Pause** beendet die Erkennung ganz, es geht dann kein Audio mehr an den Spracherkennungsdienst; weiter mit E oder T beziehungsweise den Knöpfen.

## Siehe auch

[TASTENKUERZEL.md](TASTENKUERZEL.md), [FEHLERHILFE.md](FEHLERHILFE.md), [PRESETS.md](PRESETS.md) (Szenario-Pakete).
