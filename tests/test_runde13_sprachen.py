"""Runde 13: die Sprachtabelle languages.json gegen alle Plattformen (Engine, Mac-App, iPhone, Web).

Die Apps lesen die Datei zur Laufzeit; hier steht, was daneben fest eincodiert ist (Swift-Konstanten, feste
Textzeilen je Sprache, Web-Fallbacks) – dort darf sich kein Code, keine Schrift und kein Name verlaufen."""
import json
import pathlib
import re

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "languages.json").read_text(encoding="utf-8"))
LANGS = DATA["languages"]
CODES = [x["code"] for x in LANGS]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
IOS = ROOT / "ios" / "Dolmetscher"
SCRIPT_RANGES = {  # Schrift -> ein Zeichen, das dazu gehören muss (Eigenname der Sprache)
    "thai": "th", "cyrillic": "ru", "arabic": "ar", "devanagari": "hi", "lao": "lo",
}


def _read(p):
    return pathlib.Path(p).read_text(encoding="utf-8")


def _in_ranges(ch, script):
    return any(int(a, 16) <= ord(ch) <= int(b, 16)
               for a, b in (r.split("-") for r in DATA["scripts"][script]))


def test_codes_unique_and_pair_known():
    assert len(CODES) == len(set(CODES))
    assert all(c in CODES for c in DATA["default_pair"])


def test_ios_lang_constants_equal_table():
    src = _read(IOS / "Languages.swift")
    block = src[src.index("static let en = Lang(code:"):src.index("/// Reihenfolge wie in languages.json")]
    consts = re.findall(r'(\w+) = Lang\(code: "([a-z]+)"\)', block)
    assert all(name == code for name, code in consts), consts       # `static let ja = Lang(code: "ja")`
    assert sorted(c for _, c in consts) == sorted(CODES)


def test_swift_script_enum_equals_json_scripts():
    src = _read(IOS / "Languages.swift")
    cases = re.search(r"enum Script: String[^{]*\{\s*case ([a-z, ]+)", src).group(1)
    assert set(c.strip() for c in cases.split(",")) == set(DATA["scripts"])
    assert {s for x in LANGS for s in x["scripts"]} <= set(DATA["scripts"])


def test_swift_language_literals_are_known_codes():
    """Lang(rawValue: "xx")/Lang(code: "xx") und feste Code-Listen in beiden Apps nennen nur Codes der Tabelle."""
    unknown = {}
    files = [*(ROOT / "app").glob("*.swift"), *IOS.glob("*.swift"), *(ROOT / "ios" / "Shared").glob("*.swift")]
    for f in files:
        src = f.read_text(encoding="utf-8")
        found = set(re.findall(r'Lang\((?:rawValue|code): "([A-Za-z-]+)"\)', src))
        for m in re.finditer(r'\["([a-z]{2})"(?:, "[a-z]{2})+"\]\.compactMap \{ Lang', src):
            found |= set(re.findall(r'"([a-z]{2})"', m.group(0)))
        bad = found - set(CODES)
        if bad:
            unknown[f.name] = sorted(bad)
    assert not unknown, unknown


def test_default_pair_agrees_in_swift_and_web():
    a, b = DATA["default_pair"]
    mac = _read(ROOT / "app" / "Languages.swift")
    assert f'defaultMine = "{a}", defaultPartner = "{b}"' in mac
    assert f"const DEFAULT_PAIR = ['{a}', '{b}']" in HTML


def test_partner_phrase_rows_cover_every_language():
    src = _read(IOS / "PartnerPhrases.swift")
    curated = re.findall(r"\.([a-z]{2})", re.search(r"static let curated: \[Lang\] = \[([^\]]*)\]", src).group(1))
    assert set(curated) <= set(CODES) and len(curated) == len(set(curated))
    for name in ("rows", "names", "sentences"):
        body = src[src.index(f"private static let {name}:"):]
        body = body[:body.index("\n    ]")]
        got = re.findall(r'^\s+"([A-Za-z-]+)": \[(.*)\],?$', body, re.M)
        want = CODES if name == "rows" else curated      # Allergie-Texte nur für die fest hinterlegten Sprachen
        assert sorted(c for c, _ in got) == sorted(want), f"{name}: {sorted(set(want) ^ {c for c, _ in got})}"
        sizes = {c: len(re.findall(r'"(?:\\.|[^"\\])*"', r)) for c, r in got}
        assert len(set(sizes.values())) == 1 and all(v for v in sizes.values()), (name, sizes)
        assert all('""' not in r for _, r in got), f"{name}: leerer Text"


def test_native_name_has_the_scripts_letters():
    """Der Eigenname einer Sprache in Thai-/Kyrillisch-/Arabisch-/Devanagari-Schrift muss diese Schrift verwenden."""
    by = {x["code"]: x for x in LANGS}
    for script, code in SCRIPT_RANGES.items():
        nat = by[code]["names"]["native"]
        assert any(_in_ranges(c, script) for c in nat), (code, nat)
    for code in ("zh", "ja"):
        assert any(_in_ranges(c, "han") for c in by[code]["names"]["native"])
    assert any(_in_ranges(c, "hangul") for c in by["ko"]["names"]["native"])


def test_language_flags_and_names_distinct():
    flags = [x["flag"] for x in LANGS]
    assert len(set(flags)) == len(flags)
    for key in ("en", "de", "native"):
        names = [x["names"][key] for x in LANGS]
        assert len(set(names)) == len(names), key


def test_web_variants_belong_to_table_languages():
    block = HTML[HTML.index("const VARIANTS = {"):]
    block = block[:block.index("\n};")]
    for code, rest in re.findall(r"\b([a-z]{2}): \[((?:\['[^']+', '[^']+'\],? ?)+)\]", block):
        assert code in CODES, code
        locales = re.findall(r"\['([^']+)',", rest)
        assert all(loc.split("-")[0] in (code, "yue") for loc in locales), (code, locales)
        base = next(x["locale"] for x in LANGS if x["code"] == code).replace("_", "-")
        assert base in locales or code == "zh", (code, base, locales)


def test_engine_and_json_agree_on_names_and_scripts():
    assert set(d.LANGS) == set(CODES)
    for x in LANGS:
        e = d.LANGS[x["code"]]
        assert (e["name"], e["de"]) == (x["names"]["en"], x["names"]["de"]), x["code"]
        assert list(e["script"]) == x["scripts"], x["code"]
        assert e["locale"] == x["macos"]["locale"] and e["say"] == x["macos"]["voice"], x["code"]
    assert set(d.SCRIPTS) == set(DATA["scripts"])


def test_web_ui_languages_equal_mac_and_web_string_tables():
    ui = re.search(r"const UI_LANGS = \[([^\]]*)\]", HTML).group(1)
    ui = re.findall(r"'([a-z]+)'", ui)
    from _webhelpers import web_str
    top = list(web_str())
    assert ui == top == ["de", "en", "th"]
    mac = _read(ROOT / "app" / "L10n.swift")
    cases = re.search(r"enum UILang: String[^{]*\{\s*case ([a-z, ]+)", mac).group(1)
    assert set(c.strip() for c in cases.split(",")) == set(ui)
    assert ui[0] in CODES and set(ui) <= set(CODES)
