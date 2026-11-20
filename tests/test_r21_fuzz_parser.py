"""Fuzz-/Eigenschaftstests (seedfest, ohne Zusatzpaket) für Parser an Vertrauensgrenzen:
Verlauf-Import, Presets, Glossar-Text, Deep-Link-Parameter der Webseite."""
import json
import random
import re

import pytest

import dolmetscher as d
import history_store as hs
import presets
from _webhelpers import HAVE_NODE, SCRIPT, func, run

RND = random.Random(20261120)
ALPHA = list("abcxyz019 \t\n=>\"'\\{}[]<>&%;|$`") + ["สวัสดี", "\u0000", "‮", "=HYPERLINK(", "😀", "../", "\r\n"]


def junk_str(n=12):
    return "".join(RND.choice(ALPHA) for _ in range(RND.randint(0, n)))


def junk_val(depth=0):
    k = RND.randint(0, 7 if depth < 3 else 4)
    if k == 0:
        return None
    if k == 1:
        return RND.choice([True, False])
    if k == 2:
        return RND.choice([0, -1, 1, 2**63, 1e308, float("nan"), 3.5])
    if k in (3, 4):
        return junk_str()
    if k in (5, 6):
        return [junk_val(depth + 1) for _ in range(RND.randint(0, 4))]
    return {junk_str(4): junk_val(depth + 1) for _ in range(RND.randint(0, 4))}


@pytest.fixture
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "home"))
    s = hs.Store()
    yield s
    s.close()


def test_verlauf_import_wirft_nur_valueerror(store):
    row = {"ts": 1_700_000_000.0, "text": "a", "translation": "b", "lang": "en", "session": "s"}
    docs = [junk_str(40) for _ in range(40)] + ["[]", "{}", "null", "[null]", "[1,2]", "[[]]", "[{}]"]
    for _ in range(150):
        docs.append(json.dumps([junk_val() if RND.random() < .6 else {**row, RND.choice(list(row)): junk_val()}
                                for _ in range(RND.randint(0, 6))], default=str))
    for doc in docs:
        try:
            r = store.import_json(doc)
        except ValueError:
            continue
        assert len(r) == 3 and all(isinstance(x, int) and x >= 0 for x in r)


def test_presets_validate_gibt_liste_und_wirft_nie():
    for _ in range(400):
        r = presets.validate(junk_val())
        assert isinstance(r, list)
    for _ in range(200):
        p = {"id": RND.choice(["taxi", junk_str(), "../x"]), "names": junk_val(), "phrases": junk_val(),
             "glossary": junk_val()}
        assert isinstance(presets.validate(p), list)


def test_glossar_text_wirft_nie(monkeypatch, tmp_path):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    for _ in range(120):
        d.load_glossary("\n".join(junk_str(30) + RND.choice([" => ", "=>", " ", ""]) + junk_str(30)
                                  for _ in range(RND.randint(0, 8))))
        d.glossary_hits(junk_str(40))


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_web_deeplink_parameter_invarianten():
    max_share = re.search(r"MAX_SHARE = (\d+)", SCRIPT).group(1)
    pre = "const MAX_SHARE = %s;\n%s" % (max_share, func("parseDeepLink"))
    cases = []
    for _ in range(200):
        parts = [f"{RND.choice(['preset', 'l', 'text', 'url', 'title', 'open', 'ui', 'x'])}={junk_str(20)}"
                 for _ in range(RND.randint(0, 4))]
        cases.append(("#" + "&".join(parts), "?" + "&".join(reversed(parts))))
    cases += [("#preset=taxi&l=de", ""), ("", "?text=" + "a" * 5000), ("#%E0%A4%A", "?%")]
    exprs = [f"parseDeepLink({json.dumps(h)}, {json.dumps(s)}, ['taxi', 'hotel'])" for h, s in cases]
    outs = run(pre, exprs)
    for o in outs:
        assert isinstance(o, dict), o
        assert set(o) <= {"preset", "l", "incoming"}
        if "preset" in o:
            assert o["preset"] in ("taxi", "hotel")
        if "l" in o:
            assert 2 <= len(o["l"]) <= 3 and o["l"].isalpha() and o["l"].islower()
        if "incoming" in o:
            assert 0 < len(o["incoming"]) <= int(max_share)
