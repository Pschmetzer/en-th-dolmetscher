"""Runde 3, Mac-App (Quelltext-Verträge, ohne laufende App): Schlüsselbund (23), Formatwarnung (390),
Schnellsätze erst nach ready (361), Wachhund nur auf pong (362), lokales Vorlesen mit Tempo (363),
VoiceOver mit Sprache (366), Menükürzel (375/376), Rückübersetzung/Langsam/Glossar-Lernen."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_schluesselbund_statt_datei():
    p = src("Paths.swift")
    assert "SecItemAdd" in p and "SecItemUpdate" in p and "errSecDuplicateItem" in p
    assert "kSecAttrAccessibleAfterFirstUnlock" in p
    # Migration: Datei nie ersatzlos löschen – nur nach nachweislich lesbarem Eintrag umbenennen (0600)
    mig = p[p.index("static func migrate()"):p.index("private static func writeFile")]
    assert "removeItem(at: url)" not in mig
    assert "guard keychainRead() == k || (keychainWrite(k) && keychainRead() == k) else { return }" in mig
    assert "moveItem(at: url, to: migratedURL)" in mig and "chmod(migratedURL.path, 0o600)" in mig
    assert 'appendingPathComponent("anthropic_key.migrated")' in p
    # Speichern: Rückfall-Datei bekommt den neuen Schlüssel, bevor die alte weg ist
    assert "if writeFile(k, to: migratedURL) { try? FileManager.default.removeItem(at: url) }" in p
    # Lesen: Schlüsselbund, dann beide Dateien
    assert "readFile(url) ?? readFile(migratedURL)" in p
    # Engine bekommt den Schlüssel per Umgebung, eine gesetzte Umgebungsvariable hat Vorrang
    assert 'if env["ANTHROPIC_API_KEY"] == nil, let k = APIKeyStore.read()' in p
    assert "APIKeyStore.migrate()" in src("DolmetscherApp.swift")


def test_engine_ruft_security_nicht_auf():
    eng = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    assert "find-generic-password" not in eng          # keine ACL-Abfrage aus Python


def test_formatwarnung_api_schluessel():
    assert 'hasPrefix("sk-ant-")' in src("Paths.swift")
    s = src("SettingsView.swift")
    assert "APIKeyStore.looksValid(key)" in s and 'L.t("key_format_warn")' in s


def test_schnellsaetze_erst_nach_ready():
    e = src("Engine.swift")
    assert re.search(r"func say\(_ text: String, lang: String = \"en\"\) \{[^}]*guard engineReady", e)
    v = src("Views.swift")
    assert v.count("!m.engineReady") >= 4
    assert "m.engineReady else { return }" in src("BubbleViews.swift")


def test_wachhund_nur_pong():
    e = src("Engine.swift")
    assert 'if !pongSeen || ev == "pong" {' in e


def test_lokales_vorlesen_mit_tempo_und_lautstaerke():
    e = src("Engine.swift")
    assert "s.rate = Self.localRate(rate)" in e and "s.volume = Float(" in e
    assert "AVSpeechUtteranceDefaultSpeechRate * 0.95\n" not in e


def test_voiceover_mit_sprache():
    assert ".accessibilityLanguage" in src("Support.swift")
    assert "Announcer.post(u.out, lang: Langs.bcp47(u.to))" in src("Engine.swift")


def test_menue_kuerzel():
    a = src("DolmetscherApp.swift")
    assert '.keyboardShortcut(.return, modifiers: .command)' in a
    assert '.keyboardShortcut("p", modifiers: .command)' in a
    assert '.keyboardShortcut("r", modifiers: .command)' in a and "model.replayLast()" in a
    assert "CommandGroup(replacing: .printItem)" in a
    # kein anderes ⌘P/⌘R/⌘↩ in der App
    for f in APP.glob("*.swift"):
        if f.name != "DolmetscherApp.swift":
            t = f.read_text(encoding="utf-8")
            assert '.keyboardShortcut("p", modifiers: .command)' not in t, f.name
            assert '.keyboardShortcut("r", modifiers: .command)' not in t, f.name


def test_neue_einstellungen_an_engine():
    e = src("Engine.swift")
    for flag, key in (("--slow", "slow"), ("--back-translate", "back_translate"),
                      ("--no-learn-glossary", "learn_glossary")):
        assert f'"{flag}"' in e and f'send(["{key}":' in e
    eng = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    for flag in ("--slow", "--back-translate", "--no-learn-glossary"):
        assert f'"{flag}"' in eng


def test_app_verarbeitet_back_und_glossary():
    e = src("Engine.swift")
    assert 'case "back":' in e and "items[i].back = t" in e
    assert 'case "glossary":' in e and 'o["added"] as? [String]' in e
    # Glossar: anhängen statt überschreiben (ungesendete eigene Änderungen bleiben)
    seg = e[e.index('case "glossary":'):e.index('case "llm_cost":')]
    assert "glossary = (glossary" in seg and 'o["text"]' not in seg
    assert "u.back" in src("BubbleViews.swift")
