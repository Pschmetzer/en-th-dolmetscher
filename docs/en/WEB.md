# Web version (Web Lite)

German version: [WEB-HOSTING.md](../WEB-HOSTING.md) (hosting) and [TASTENKUERZEL.md](../TASTENKUERZEL.md). Thai version (machine-translated, not checked by native speakers): [ภาษาไทย](../th/WEB.md).

The web page `index.html` runs in the browser without installation: https://pschmetzer.github.io/en-th-dolmetscher/. It is the lightest way to use the translator and works on any phone or computer. The Mac and iPhone apps are better at recognising speech.

## Sections

The page has four tabs. The last one you used is remembered.

| Tab | What is in it |
|---|---|
| Speak | choose who speaks (buttons or keys), type instead of speaking, the **two-person screen** (each side types in their own language on a split screen), the conversation list |
| Phrasebook | 91 topics with show cards (large Thai text, read aloud), numbers and prices, dictionary |
| Cards | my own cards (hotel, address), allergy and emergency card (can be shared as an image) |
| Learn | flashcards from the sentences you marked with a star |

The notes about the Lite version and privacy are open on the first visit and folded afterwards.

## Offline and installing

Open the page once with a network connection. A service worker then stores the page, the language table, the interface texts (`i18n/`) and the phrasebook, so the phrasebook and show cards work without internet. Translation and speech recognition always need the network. "Add to home screen" (Android: "Install app") installs it like an app.

## What leaves the device

- Speech recognition is done by the browser: Chrome sends audio to Google, Safari to Apple. The page asks once before the microphone is used.
- Recognised or typed text goes to Google Translate (fallback: MyMemory). Both are unofficial web endpoints and can change or stop.
- Text shared into the page from another app is only translated after you tap "Translate".
- Everything else (settings, cards, learning state, allergy card) stays in this browser. More: [DATENSCHUTZ.md](../DATENSCHUTZ.md) (German) and [PRIVACY-SHORT.md](PRIVACY-SHORT.md).

## Languages and quality

The English and Thai sentences come with the topics; the Thai sentences are not checked by native speakers ([MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md)). Other languages are machine-translated when first needed and marked as such. The interface is available in German, English and Thai.

## Problems

[TROUBLESHOOTING.md](TROUBLESHOOTING.md). Keys: [SHORTCUTS.md](SHORTCUTS.md).
