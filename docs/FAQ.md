# Häufige Fragen

Englische Fassung: [en/FAQ.md](en/FAQ.md). Einstieg: [SCHNELLSTART.md](SCHNELLSTART.md). Bei Problemen: [FEHLERHILFE.md](FEHLERHILFE.md).

## Allgemein

**Was ist der Dolmetscher?** Ein freihändiger Sprachdolmetscher: Du sprichst, es wird in die Sprache des Gegenübers übersetzt und laut vorgelesen, die Antwort kommt in deiner Sprache zurück. Standard ist Englisch und Thai.

**Welche Sprachen gibt es?** 19: Englisch, Thai, Deutsch, Spanisch, Französisch, Italienisch, Portugiesisch, Niederländisch, Russisch, Chinesisch (Mandarin), Japanisch, Koreanisch, Vietnamesisch, Indonesisch, Arabisch, Hindi, Türkisch, Polnisch und Ukrainisch. Jedes Paar geht. Die neuen Sprachen sind noch nicht mit echten Sprecherinnen und Sprechern getestet.

**Auf welchen Geräten läuft er?** Mac (Apple Silicon, macOS 14 oder neuer), iPhone und iPad (iOS 26 oder neuer) und im Browser (Web Lite, am besten Chrome). Die Mac-App kann am meisten, zum Beispiel die automatische Spracherkennung, Sprachbefehle, Stimmprofile und die Claude-Übersetzung.

**Gibt es einen Download?** Noch nicht. Mac-App und iPhone-App baust du selbst ([SCHNELLSTART.md](SCHNELLSTART.md)); die Browser-Version läuft direkt unter <https://pschmetzer.github.io/en-th-dolmetscher/>.

**Was kostet er?** Die App steht unter der MIT-Lizenz. Kosten entstehen nur, wenn du die optionale Claude-Übersetzung mit eigenem Anthropic-Schlüssel einschaltest: das Standardmodell `claude-haiku-5-5` kostet laut README etwa 8 US-Cent pro Gesprächsstunde, abgerechnet bei Anthropic. Die App zeigt die geschätzten Kosten und kennt ein Monatslimit (`--llm-budget`).

**Läuft er ohne Internet?** Teilweise. Auf dem Mac läuft die Spracherkennung lokal, die Übersetzung braucht Netz, außer mit der Offline-Übersetzung von Apple (macOS 26.4 oder neuer, Sprachpakete installiert). Auf dem iPhone läuft alles auf dem Gerät, sobald die Sprachpakete da sind. Im Browser braucht die Übersetzung Netz; Seite und Satzbuch öffnen auch offline.

## Bedienung

**Muss ich zwischen den Sprachen umschalten?** Auf Mac und iPhone nicht: Die App erkennt, welche der beiden Sprachen gesprochen wird. Im Browser wählst du selbst (E oder T). Bei Paaren mit gleicher Schrift, etwa Englisch und Deutsch, blendet das iPhone „Automatisch“ aus; dort wählst du die Richtung per Tippen.

**Wie lange dauert es?** Auf dem Mac ein paar Sekunden nach Satzende: auf der Apple-GPU etwa 3 bis 5 Sekunden, auf der CPU deutlich mehr. Mit dem Modell `small` geht es schneller.

**Welches Erkennungsmodell soll ich nehmen?** `medium` ist Standard, `small` ist schneller, `best` (large-v3-turbo) kommt mit Akzenten besser zurecht und braucht rund 1,6 GB mehr. Thai nutzt ein eigenes, auf Thai nachtrainiertes Modell.

**Warum hört die Browser-Version auf dem iPhone nichts (Safari)?** Safari nutzt Apples Spracherkennung. Sie geht nur, wenn die Diktierfunktion an ist (Einstellungen › Allgemein › Tastatur › Diktierfunktion) und du dem Mikrofon für die Seite zugestimmt hast (Safari: Symbol „aA“ in der Adresszeile › Website-Einstellungen). Starte die Erkennung immer mit einem Tipp; iOS erlaubt weder Mikrofon noch Vorlesen ohne Tipp. Die Seite muss über HTTPS laufen und im Vordergrund bleiben: Wechselst du die App oder sperrst das Gerät, hält iOS die Erkennung an. Andere Browser auf dem iPhone (Chrome, Firefox) nutzen dieselbe Safari-Engine und haben dieselben Grenzen. Die Thai-Stimme hängt von den iOS-Stimmen ab (Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen). Wer mehr braucht, nimmt die iPhone-App ([SCHNELLSTART.md](SCHNELLSTART.md)). Die Browser-Matrix: [WEB-KOMPATIBILITAET.md](WEB-KOMPATIBILITAET.md).

**Welche Tastenkürzel und Sprachbefehle gibt es?** Siehe [TASTENKUERZEL.md](TASTENKUERZEL.md) und [SPRACHBEFEHLE.md](SPRACHBEFEHLE.md). Sprachbefehle gehen nur, wenn Englisch eine der beiden Sprachen ist.

**Was sind Stimmprofile?** Jede Person liest einmal 8 kurze Sätze (etwa eine Minute) vor. Danach steht ihr Name an der Blase, ihre Sprache entscheidet bei Unsicherheit, und eigene Wörter wie Namen helfen der Erkennung. Das Modell wird dabei nicht nachtrainiert. Es gibt Stimmprofile nur auf dem Mac, und die Aufnahme ist nur auf Englisch oder Thai möglich.

**Kann ich Sätze für Situationen wie Arzt oder Taxi vorbereiten?** Ja: Es gibt Szenario-Pakete (zum Beispiel Arzt, Apotheke, Polizei, Restaurant, Taxi) mit Kulturhinweis und wichtigen Sätzen zuerst, zum Beispiel Allergien. Format und Mitmachen: [PRESETS.md](PRESETS.md).

**Wie bewahre ich ein Gespräch auf?** Der Mac speichert einen Verlauf nur, wenn du ihn einschaltest (Standard: aus); Export als Markdown, JSON, CSV, Untertitel oder Anki-Karten. Das iPhone speichert standardmäßig 30 Tage. Im Browser kopierst du das Gespräch oder speicherst es als Textdatei.

**Wie gut ist das Thai?** Alle Thai-Sätze und die meisten Oberflächentexte entstanden mit maschineller Hilfe und sind nicht von Muttersprachlern geprüft. Korrekturen sind willkommen ([PRESETS.md](PRESETS.md)).

## Daten

**Was passiert mit meiner Stimme?** Auf dem Mac verlässt Audio den Rechner nie; nur der erkannte Text geht zur Übersetzung. Kurzfassung: [DATENSCHUTZ-KURZ.md](DATENSCHUTZ-KURZ.md), ausführlich: [DATENSCHUTZ.md](DATENSCHUTZ.md).

**Gibt es Konten oder Telemetrie?** Nein, weder Konten noch eigene Telemetrie noch einen eigenen Server.

## Entwicklung

**Wie baue ich die App, und wie trage ich bei?** [CONTRIBUTING.md](../CONTRIBUTING.md). Aufbau der Engine: [ARCHITEKTUR.md](ARCHITEKTUR.md); Protokoll zwischen App und Engine: [PROTOKOLL.md](PROTOKOLL.md); Lizenzen von Modellen und Diensten: [LIZENZEN.md](LIZENZEN.md).

**Was ändert sich von Version zu Version?** [CHANGELOG.md](../CHANGELOG.md). Aktuelle Versionsstände je Teil: [VERSIONEN.md](VERSIONEN.md).
