"""Web-Sprachtabelle (index.html) = Sprachtabelle der Engine (dolmetscher.py LANGS/SCRIPTS).

Liest dolmetscher.py per ast (kein Import nötig), index.html per Regex + JSON."""
import ast
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
TREE = ast.parse((ROOT / "dolmetscher.py").read_text(encoding="utf-8"))


def _py_assign(name):
    for n in TREE.body:
        if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None) == name:
            return n.value
    raise AssertionError(name)


def _py_langs():
    out = {}
    for k, call in zip(_py_assign("LANGS").keys, _py_assign("LANGS").values):
        args = [ast.literal_eval(a) for a in call.args]
        kw = {x.arg: ast.literal_eval(x.value) for x in call.keywords}
        name, de, script, _m, _f, _say, locale = args[:7]
        out[ast.literal_eval(k)] = {"name": name, "de": de, "script": script.split("+"), "locale": locale,
                                    "mt": kw.get("mt")}
    return out


def _js_obj(name):
    m = re.search(r"const " + name + r" = (\{.*?\n?\});", HTML, re.S)
    assert m, name
    return json.loads(m.group(1))


PY = _py_langs()
JS = _js_obj("LANGS")


def test_same_languages_in_same_order():
    assert list(JS) == list(PY)


def test_names_scripts_mt_match_engine():
    for k, p in PY.items():
        j = JS[k]
        assert (j["name"], j["de"], j["script"]) == (p["name"], p["de"], p["script"]), k
        assert j.get("mt") == p["mt"], k


def test_locales_match_engine():
    for k, p in PY.items():
        want = "ar-SA" if p["locale"] == "ar_001" else p["locale"].replace("_", "-")
        assert JS[k]["loc"] == want, k


def test_scripts_table_matches_engine():
    assert _js_obj("SCRIPTS") == ast.literal_eval(_py_assign("SCRIPTS"))


def test_default_pair_and_ui_words():
    assert ast.literal_eval(_py_assign("DEFAULT_PAIR")) == ("en", "th")
    assert "const DEFAULT_PAIR = ['en', 'th'];" in HTML
    for k, j in JS.items():
        assert j["native"] and j["yes"] and j["no"] and j["yes"] != j["no"], k
