# Voice commands

Applies to the Mac app (engine `dolmetscher.py`), the iPhone app and, in part, the browser version. Source of the commands: `COMMANDS` and `parse_command()` in `dolmetscher.py`. German version: [SPRACHBEFEHLE.md](../SPRACHBEFEHLE.md).

## How it works

- A command starts with the wake word **"Translator"** (also "Hey translator", "OK translator"), then the command: "Translator, pause".
- Commands are spoken **in English**, are never translated and are **only recognised when English is one of the two languages of the pair**.
- Only short utterances count: at most 5 words after the wake word. Anything longer is conversation and gets translated.
- If you say just "Translator" and pause, the app answers "Yes?" and takes the next sentence as a command.
- One command per utterance. Commands only control the app; general questions are not answered.
- In noise or with a strong accent a command can be misheard. Recognition tolerates typical mishearings ("Translate or pause") and simple negations ("too loud" means quieter, "too fast" slower, "mute off" lifts mute).

## Commands (Mac and iPhone)

| Say | Effect |
|---|---|
| Translator, pause (also stop, mute, sleep, be quiet) | stop translating; the app keeps listening for commands |
| Translator, resume (also continue, start, unmute, unpause) | carry on |
| Translator, repeat (also again, say that again) | say the last translation again |
| Translator, slower / faster | speaking rate |
| Translator, louder / quieter | volume |
| Translator, volume 3 / speed 5 | volume or speed on a scale of 0 to 10 (5 is normal for speed) |
| Translator, Thai only / English only / auto | lock the language or detect automatically |
| Translator, German only (and other languages of the pair, named in English) | only that language; also "Spanish off" etc. |
| Translator, English off / Thai off | that language is only shown, not translated or spoken |
| Translator, English on / Thai on / translate both | turn the direction back on |
| Translator, female voice / male voice | Thai voice and politeness form (ค่ะ / ครับ) |
| Translator, clear | clear the conversation |
| Translator, help | show the commands |
| Translator, hotel mode / preset taxi | choose a scenario pack; "preset off" switches it off |

## Browser

The browser version understands the commands only in English mode and at the start of a sentence: pause, repeat, slower, faster, louder, quieter, clear, help. **Pause** stops recognition completely, so no more audio goes to the speech service; continue with E or T or the buttons.

## See also

[SHORTCUTS.md](SHORTCUTS.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md), [PRESETS.md](../PRESETS.md) (scenario packs, German).
