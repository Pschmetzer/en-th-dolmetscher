"""Mac-App ⇄ Engine bei der Mehrsprachigkeit: Swift-Sprachtabelle (app/Languages.swift) passt zur Engine-Tabelle
LANGS, die App schickt `langs` im Protokollformat, alte Einstellungen (en/th) bleiben gültig."""
import pathlib
import re

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANG_SWIFT = (ROOT / "app" / "Languages.swift").read_text(encoding="utf-8")
SWIFT = "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift"))
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


def _swift_table():
    rows = {}
    for m in re.finditer(r'LangInfo\(code: "([a-z]+)".*?voices: \[(.*?)\]', LANG_SWIFT, re.S):
        rows[m.group(1)] = re.findall(r'"([^"]+)"', m.group(2))
    return rows


def test_swift_tabelle_gleich_engine_tabelle():
    rows = _swift_table()
    assert list(rows) == list(d.LANGS), "Codes/Reihenfolge der App-Tabelle weichen von LANGS ab"
    for code, voices in rows.items():
        assert voices, code
        assert set(voices) <= set(d.VOICES[code]), f"{code}: Stimmen, die die Engine ablehnt: " \
                                                   f"{sorted(set(voices) - set(d.VOICES[code]))}"
        assert d.LANGS[code]["m"] in voices and d.LANGS[code]["f"] in voices, code


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
