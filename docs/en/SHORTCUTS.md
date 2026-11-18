# Keyboard shortcuts

All shortcuts are taken from the code (`app/DolmetscherApp.swift`, `app/HotKeys.swift`, `app/BubbleViews.swift`, `app/PartnerView.swift`, `ios/Dolmetscher/Views.swift`, `index.html`). German version: [TASTENKUERZEL.md](../TASTENKUERZEL.md).

## Mac app

### Everywhere, even when the app is in the background (global)

| Shortcut | Effect |
|---|---|
| ⌃⌥D | start / stop |
| ⌃⌥P | pause / resume |
| ⌃⌥S | stop speaking |
| ⌃⌥R | say the last translation again |
| ⌃⌥T (hold) | talk; only assigned while push-to-talk is on |

If another program already uses a shortcut, the app shows a notice listing the affected ones and tries again the next time it is activated.

### In the app's menus

| Shortcut | Effect |
|---|---|
| Space | start / stop; only in the main window and only without a text field focused; can be switched off ("Space starts/stops" in the settings) |
| ⌘Return | start / stop |
| ⌘P | pause / resume (there is no printing) |
| ⌘. | stop speaking |
| ⌘R | say the last translation again |
| ⌘1 to ⌘9 | speak your first nine quick phrases |
| ⌥⌘1 to ⌥⌘9 | speak the first nine sentences of the selected scenario pack |
| ⌘F | search the conversation |
| ⌘+ / ⌘- / ⌘0 | text larger / smaller / reset (⌘= works like ⌘+) |
| ⇧⌘P | open the partner view |
| ⌥⌘T | keep the window on top |
| ⇧⌘E | export the conversation |
| ⌥⌘Z | undo delete |
| ⇧⌘C | copy the last translation |
| ⌥⌘L | switch direction (automatic, then one language of the pair each) |
| ⌥⌘G | add a word to the glossary |
| ⌘L | put the cursor in the typing field |
| ⌥⌘S | speech output on / off |
| ⌘/ | shortcut overview (Help menu) |

### Partner view

| Shortcut | Effect |
|---|---|
| ⌃⌘F | full screen on / off |
| Left / right arrow | one translation back / forward |

### On a bubble (reach it with Tab)

| Key | Effect |
|---|---|
| Return | read aloud (stops it if already playing) |
| Esc | stop reading aloud |
| E | correct the bubble and translate again |
| C | copy the translation (⌘C too) |

## Browser (Web Lite)

Single-key shortcuts do not work in input fields or with Ctrl, Alt or Cmd. They can be switched off in the settings ("Single-key shortcuts"). They work with a Thai keyboard layout too because the page reads the key position.

| Key | Effect |
|---|---|
| E or 1 | I speak (only where speech recognition exists) |
| T or 2 | the other person speaks |
| Space | end recording (not on buttons or in input fields) |
| P | partner view on / off |
| L | jump to the newest entry in the conversation |
| Esc | closes the partner view, otherwise stop; always closes dialogs |
| Right / Left arrow | in the partner view with a card sequence: next / previous |
| Enter | in the "type instead of speaking" text box: translate (with Shift+Enter it is not sent) |
| Tab | everything can also be used without shortcuts with Tab and the buttons |

"Hold to speak" is a button: hold it, speak, release. With the keyboard it stays a toggle.

## iPhone and iPad

With a hardware keyboard the iPhone and iPad app has three shortcuts (`ios/Dolmetscher/Views.swift`):

| Shortcut | Effect |
|---|---|
| ⌘Return | start / stop |
| ⌘B | open the phrasebook |
| ⌘/ | open help |

Besides that there are Siri shortcuts, a control for Control Center, lock screen and Action button, and widgets; see [ios/README.md](../../ios/README.md).
