"""Mac-App ⇄ Engine bei der Mehrsprachigkeit: die App schickt `langs` im Protokollformat, alte Einstellungen
(en/th) bleiben gültig. Die Sprachtabelle selbst lesen App und Engine aus derselben Datei (test_languages_json.py)."""
import pathlib


ROOT = pathlib.Path(__file__).resolve().parent.parent
LANG_SWIFT = (ROOT / "app" / "Languages.swift").read_text(encoding="utf-8")
SWIFT = "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift"))
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


def test_app_standardpaar_und_alte_schluessel():
    assert 'defaultMine = "en", defaultPartner = "th"' in LANG_SWIFT
    # alte Einstellungen bleiben: trEN/trTH/voiceEN/voiceTH und dieselben Startargumente beim Standardpaar
    for key in ('forKey: "trEN"', 'forKey: "trTH"', 'forKey: "voiceEN"', 'forKey: "voiceTH"'):
        assert key in SWIFT, key
    assert 'if Langs.isDefaultPair {' in SWIFT
    for flag in ('"--no-en"', '"--no-th"', '"--voice-en"', '"--voice-th"', '"--langs"', '"--no-mine"',
                 '"--no-partner"', '"--voice-mine"', '"--voice-partner"'):
        assert flag in SWIFT, flag


def test_app_sendet_langs_im_protokollformat():
    assert '["langs": ["mine": mineLang, "partner": partnerLang]]' in SWIFT and "push(langsMessage())" in SWIFT
    assert 'd.get("langs")' in (ROOT / "dolmetscher.py").read_text(encoding="utf-8") or '"langs" in d' in \
        (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    assert '{"langs": {"mine": "de", "partner": "th"}}' in DOCS
    assert 'o["langs"] as? [String: Any]' in SWIFT          # `command` trägt das Paar


def test_app_generische_tr_und_voice_felder_sind_steuerfelder():
    assert 'push(["tr_\\(code)": v])' in SWIFT and 'push(["voice_\\(code)": v])' in SWIFT
    assert "tr_<code>" in DOCS and "voice_<code>" in DOCS


def test_hoeflichkeit_nur_mit_thai_im_paar():
    seg = SWIFT.split('if m.mineLang == "th" || m.partnerLang == "th" {', 1)
    assert len(seg) == 2 and 'L.t("polite_label")' in seg[1][:200]
