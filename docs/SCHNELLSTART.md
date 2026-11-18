# Schnellstart

Drei Wege, je nach Gerät. Mehr zu allem: [README.md](../README.md) (Englisch). Probleme: [FEHLERHILFE.md](FEHLERHILFE.md). Englische Fassung: [en/QUICKSTART.md](en/QUICKSTART.md).

## Mac (Apple Silicon, macOS 14 oder neuer)

Es gibt noch keinen fertigen Download; die App wird aus dem Quellcode gebaut.

1. Voraussetzungen: Mac mit Apple Silicon (M1 oder neuer, kein Intel), Xcode Command Line Tools (`xcode-select --install`) und [uv](https://docs.astral.sh/uv/) (`brew install uv`). Homebrew-Python und ffmpeg werden nicht gebraucht.
2. Code holen: `git clone https://github.com/Pschmetzer/en-th-dolmetscher.git`, dann den Ordner im Terminal öffnen.
3. Bauen und installieren: `./build.sh --install`. Das legt `~/Applications/Dolmetscher.app` an und lädt auf dem Build-Mac die Sprachmodelle (`medium`, `small` und das Thai-Modell, zusammen etwa 3,5 GB, einmalig).
4. App öffnen, **Start** drücken (oder die Leertaste) und den Mikrofonzugriff erlauben.
5. Sprechen. Die App erkennt selbst, welche der beiden Sprachen gesprochen wird (Standard: Englisch und Thai), übersetzt und liest laut vor. Sprachpaar, Mikrofon und Stimmen stehen in den Einstellungen.

**Erster Start auf einem anderen Mac:** Kopierst du die App auf einen Mac ohne die Python-Umgebung, öffnet sich ein Einrichtungsbildschirm. Er zeigt Downloadgröße und freien Speicher, lädt ein eigenes Python 3.12, die Pakete und die Modelle (mit Fortschrittsbalken) und lässt sich abbrechen und wiederholen. Er braucht Internet.

Tastenkürzel: [TASTENKUERZEL.md](TASTENKUERZEL.md). Sprachbefehle („Translator, …“): [SPRACHBEFEHLE.md](SPRACHBEFEHLE.md).

## iPhone / iPad (iOS 26 oder neuer)

Auch hier gibt es keine App-Store-Version; du baust die App selbst, ein kostenloser Apple-Account genügt. Ausführlich: [ios/README.md](../ios/README.md).

1. Xcode 26 oder neuer auf dem Mac. `open ios/Dolmetscher.xcodeproj`.
2. Xcode, Einstellungen, Accounts: Apple-ID hinzufügen.
3. Ziel **Dolmetscher**, Signing & Capabilities: eigenes Team wählen und die Bundle Identifier (`com.pschmetzer.dolmetscher`) auf etwas Eigenes ändern.
4. iPhone anschließen, als Ziel wählen, Run (⌘R). Beim ersten Mal auf dem iPhone: Einstellungen, Allgemein, VPN & Geräteverwaltung, dein Entwicklerzertifikat vertrauen; wenn iOS danach fragt, den Entwicklermodus einschalten.
5. Mikrofon und Spracherkennung erlauben, Start drücken, sprechen.

Übersetzt wird auf dem Gerät, sobald die Offline-Sprachpakete für dein Paar installiert sind. Fehlt eins, geht Text nur ins Netz, wenn „Online-Übersetzer als Ersatz“ eingeschaltet ist (Standard: aus). Mit einem kostenlosen Account laufen selbst gebaute Apps 7 Tage und müssen dann neu aus Xcode installiert werden.

## Browser (Web Lite)

Keine Installation: <https://pschmetzer.github.io/en-th-dolmetscher/> in **Chrome** öffnen (Firefox hat keine Spracherkennung, Safari geht nur mit eingeschaltetem Diktat und mit Einschränkungen).

1. Beim ersten Mikrofon-Start einmal zustimmen und den Mikrofonzugriff des Browsers erlauben.
2. Sprachen wählen (Standard: Englisch und Thai).
3. Selbst wählen, wer spricht: **E** (oder 1) für deine Sprache, **T** (oder 2) für die des Gegenübers, **Leertaste** beendet. Die Seite erkennt die Sprache nicht automatisch.
4. Optional: „Zum Home-Bildschirm hinzufügen“ (PWA). Die Seite und das Satzbuch öffnen dann auch ohne Netz; übersetzt wird nur online.

Lokal starten: `python3 -m http.server` im Repo-Ordner, dann in Chrome öffnen. Eigenes Hosting: [WEB-HOSTING.md](WEB-HOSTING.md). Was die Seite kann und was nicht: [WEB-KOMPATIBILITAET.md](WEB-KOMPATIBILITAET.md).
