# Versionsstände

| Teil | Wo | Stand |
|---|---|---|
| Mac-App und Engine | `pyproject.toml` (`version`) | 1.2 |
| iPhone-App | `ios/Dolmetscher.xcodeproj/project.pbxproj` (`MARKETING_VERSION`) | 1.0 |
| Web Lite | `sw.js` (`CACHE`) | wird bei jeder Änderung an den Vorab-Dateien erhöht |

**Bekannte Abweichung (Stand dieser Datei):** Die iPhone-App meldet 1.0, die Mac-App 1.2. Das ist gewollt, solange
die iPhone-App nicht im App Store ist; `tests/test_runde7_web_versions.py` liest beide Stellen und scheitert, sobald
sie sich **anders** unterscheiden als hier eingetragen. Wer die Versionen angleicht (Vorschlag: `MARKETING_VERSION`
aus `pyproject.toml` ableiten, z. B. in `build.sh`/Skript), passt dort `KNOWN_IOS` an und entfernt diesen Absatz.

Eintrag für den Test: iPhone `1.0`.
