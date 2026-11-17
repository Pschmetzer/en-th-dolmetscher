"""Gemeinsame Sprachtabelle languages.json: Schema, Vollständigkeit und „alle Plattformen lesen dieselbe Datei“.

Format (eine Datei für Engine, Mac-App, iPhone-App und Web):
  version        1
  default_pair   ["en", "th"]
  scripts        {name: ["0E00-0E7F", …]}  Unicode-Bereiche (hex) je Schrift
  languages      Liste (Reihenfolge = Auswahllisten), je Sprache:
    code         Whisper-/Engine-Code ("en", "zh" …)
    names        {"en": englischer Name (Claude-Prompt, Sprachbefehle), "de": deutscher Name (Log, Web),
                  "native": Eigenname}
    flag         Flaggen-Emoji
    scripts      Schriften aus `scripts` (für Plausibilität und Richtungserkennung)
    locale       Gebietsschema für Erkennung/Stimme in den Apps und im Browser ("th_TH")
    edge         edge-tts-Stimmen: m/f = Standard nach Geschlecht, voices = alle auswählbaren (m und f zuerst)
    app_voices   optional: Auswahl der Mac-App, wenn kürzer als edge.voices (Englisch ohne Multilingual)
    macos        macOS-Stimme für `say` (Rückfall ohne edge-tts) mit Locale
    min_logprob  Whisper-Schwelle (MIN_LOGPROB) der Engine
    mt           optional: Code für Google/MyMemory ("zh-CN")
    apple_translation  optional: Code für Apples Translation ("zh-Hans")
    phrases      please_speak (Partner-Ansicht Mac), yes/no (Ja/Nein-Karten Web)
"""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILE = ROOT / "languages.json"
DATA = json.loads(FILE.read_text(encoding="utf-8"))
LANGS = DATA["languages"]
CODES = [x["code"] for x in LANGS]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SCRIPT = re.search(r"<script>(.*?)</script>", HTML, re.S).group(1)
REQUIRED = {"code", "names", "flag", "scripts", "locale", "edge", "macos", "min_logprob", "phrases"}
OPTIONAL = {"app_voices", "mt", "apple_translation"}


# --- Schema und Vollständigkeit ---------------------------------------------------------------------------

def test_top_level():
    assert set(DATA) == {"version", "default_pair", "scripts", "languages"}
    assert DATA["version"] == 1
    assert DATA["default_pair"] == ["en", "th"]


def test_same_19_languages_in_order():
    assert CODES == ["en", "th", "de", "es", "fr", "it", "pt", "nl", "ru", "zh", "ja", "ko", "vi", "id", "ar",
                     "hi", "tr", "pl", "uk"]


def test_scripts_are_hex_ranges():
    assert set(DATA["scripts"]) == {"latin", "thai", "cyrillic", "han", "kana", "hangul", "arabic", "devanagari"}
    for name, ranges in DATA["scripts"].items():
        assert ranges, name
        for r in ranges:
            assert re.fullmatch(r"[0-9A-F]{4}-[0-9A-F]{4}", r), (name, r)
            a, b = (int(x, 16) for x in r.split("-"))
            assert a <= b, (name, r)


def test_every_language_complete():
    for x in LANGS:
        c = x["code"]
        assert REQUIRED <= set(x) and set(x) <= REQUIRED | OPTIONAL, (c, set(x) ^ REQUIRED)
        assert re.fullmatch(r"[a-z]{2}", c), c
        assert set(x["names"]) == {"en", "de", "native"} and all(x["names"].values()), c
        assert x["flag"] and x["scripts"] and all(s in DATA["scripts"] for s in x["scripts"]), c
        assert re.fullmatch(r"[a-z]{2}_[A-Z]{2}", x["locale"]) and x["locale"].startswith(c + "_"), c
        e = x["edge"]
        assert set(e) == {"m", "f", "voices"} and e["voices"][:2] == [e["m"], e["f"]], c
        assert len(set(e["voices"])) == len(e["voices"]), c
        assert all(re.fullmatch(r"[a-z]{2}-[A-Z]{2}-\w+Neural", v) for v in e["voices"]), c
        if "app_voices" in x:
            assert set(x["app_voices"]) <= set(e["voices"]) and {e["m"], e["f"]} <= set(x["app_voices"]), c
        assert set(x["macos"]) == {"voice", "locale"} and all(x["macos"].values()), c
        assert -2 < x["min_logprob"] < 0, c
        p = x["phrases"]
        assert set(p) == {"please_speak", "yes", "no"} and all(p.values()) and p["yes"] != p["no"], c
    assert len(set(CODES)) == len(CODES)


def test_defaults_unchanged():
    by = {x["code"]: x for x in LANGS}
    assert by["en"]["edge"]["f"] == "en-US-AriaNeural" and by["en"]["edge"]["m"] == "en-US-GuyNeural"
    assert (by["th"]["edge"]["m"], by["th"]["edge"]["f"]) == ("th-TH-NiwatNeural", "th-TH-PremwadeeNeural")
    assert by["th"]["min_logprob"] == -1.3 and by["en"]["min_logprob"] == -1.0
    assert by["zh"]["mt"] == "zh-CN" and by["zh"]["apple_translation"] == "zh-Hans"
    assert by["ar"]["macos"]["locale"] == "ar_001" and by["ar"]["locale"] == "ar_SA"


# --- Engine -----------------------------------------------------------------------------------------------

def test_engine_reads_the_file():
    assert pathlib.Path(d.LANGS_FILE).resolve() == FILE and list(d.LANGS) == CODES and d.DEFAULT_PAIR == ("en", "th")
    for x in LANGS:
        v = d.LANGS[x["code"]]
        assert (v["name"], v["de"], list(v["script"]), v["m"], v["f"], v["voices"]) == \
            (x["names"]["en"], x["names"]["de"], x["scripts"], x["edge"]["m"], x["edge"]["f"], x["edge"]["voices"])
        assert (v["say"], v["locale"], v["min_lp"], v["mt"]) == \
            (x["macos"]["voice"], x["macos"]["locale"], x["min_logprob"], x.get("mt"))


def test_builtin_copy_equals_file():
    """Die eingebaute Kopie in dolmetscher.py (nur wenn die Datei fehlt) darf nicht auseinanderlaufen."""
    assert d.SCRIPTS == d._BUILTIN_SCRIPTS
    assert d.LANGS == d._BUILTIN_LANGS


def test_engine_fallback_only_when_missing(tmp_path):
    scripts, langs, pair = d.load_lang_table(str(tmp_path / "fehlt.json"))
    assert scripts == d._BUILTIN_SCRIPTS and langs == d._BUILTIN_LANGS and pair == ("en", "th")
    bad = tmp_path / "kaputt.json"
    bad.write_text("{", encoding="utf-8")
    with pytest.raises(ValueError):
        d.load_lang_table(str(bad))


def test_build_copies_file_next_to_engine():
    assert 'cp languages.json "$NEWAPP/Contents/Resources/languages.json"' in (ROOT / "build.sh").read_text()


# --- Mac-App und iPhone: aus dem Bundle, keine eigene Tabelle ------------------------------------------------

def test_mac_reads_bundle_file():
    src = (ROOT / "app" / "Languages.swift").read_text(encoding="utf-8")
    assert 'Bundle.main.url(forResource: "languages", withExtension: "json")' in src
    assert src.count("LangInfo(code:") == 3          # Einlesen + Notfall-Rückfall en/th
    assert 'defaultMine = "en", defaultPartner = "th"' in src


def test_ios_reads_bundle_file():
    src = (ROOT / "ios" / "Dolmetscher" / "Languages.swift").read_text(encoding="utf-8")
    assert 'Bundle.main.url(forResource: "languages", withExtension: "json")' in src
    assert src.count("Lang.Info(english:") == 3      # Einlesen + Notfall-Rückfall en/th
    assert "static let table: [String: Info] = LangTable.shared.info" in src


def test_ios_project_bundles_file_in_app_target():
    pbx = (ROOT / "ios" / "Dolmetscher.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    ref = re.search(r"(\w+) /\* languages.json \*/ = \{isa = PBXFileReference;[^}]*path = \.\./languages\.json;", pbx)
    assert ref
    build = re.search(r"(\w+) /\* languages.json in Resources \*/ = \{isa = PBXBuildFile; fileRef = "
                      + ref.group(1), pbx)
    assert build
    app_resources = re.search(r"D00000000000000000004001 = \{isa = PBXResourcesBuildPhase;[^\n]*", pbx).group(0)
    assert build.group(1) in app_resources


# --- Web: per fetch, offline aus dem Service Worker ----------------------------------------------------------

def test_web_fetches_file_and_has_no_own_table():
    assert "fetch('languages.json')" in SCRIPT
    assert "const SCRIPTS = {}, LANGS = {};" in SCRIPT
    assert "NiwatNeural" not in HTML and '"Niederländisch"' not in HTML
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    core = re.search(r"const CORE = \[(.*?)\]", sw, re.S).group(1)
    assert "'languages.json'" in core
    assert int(re.search(r"const CACHE = 'dolmetscher-web-v(\d+)'", sw).group(1)) >= 6


def _web_tables():
    """applyLangTable aus index.html in node mit languages.json ausführen -> (SCRIPTS, LANGS) der Web-Version."""
    funcs = [re.search(r"^const hexRange = .*?;$", SCRIPT, re.M).group(0),
             re.search(r"^const SCRIPT_RX = .*?;$", SCRIPT, re.M).group(0)]
    for n in ("applyLangTable", "buildScriptRx"):
        funcs.append(re.search(r"^function " + n + r"\(.*?^\}", SCRIPT, re.S | re.M).group(0))
    js = "const SCRIPTS = {}, LANGS = {};\n" + "\n".join(funcs) + \
        f"\napplyLangTable({json.dumps(DATA)});\nprocess.stdout.write(JSON.stringify([SCRIPTS, LANGS]));"
    out = subprocess.run(["node", "-e", js], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


@pytest.mark.skipif(not shutil.which("node"), reason="node nicht installiert")
def test_web_builds_same_tables_as_engine():
    scripts, langs = _web_tables()
    assert scripts == d.SCRIPTS
    assert list(langs) == list(d.LANGS)
    for k, v in d.LANGS.items():
        j = langs[k]
        assert (j["name"], j["de"], j["script"], j.get("mt")) == (v["name"], v["de"], list(v["script"]), v["mt"]), k
        assert j["native"] and j["yes"] and j["no"], k
    assert langs["ar"]["loc"] == "ar-SA" and langs["th"]["loc"] == "th-TH"
