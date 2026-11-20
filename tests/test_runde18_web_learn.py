# ruff: noqa: E501
"""Runde 18 Web: Lernmodus (Tagesziel, Hoeruebung, schwierige Karten, Leertaste, reduzierte Bewegung, Texte)."""
import json
import re

import pytest
from _webhelpers import HAVE_NODE, HTML, SCRIPT, prelude, run, web_str

KEYS = ("learnGoal", "learnGoalLine", "learnHardOnly", "learnDictate", "learnKeys")
STR = web_str()
needs_node = pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")


def go(exprs):
    pre = prelude(("localDay", "learnTypedMatch", "learnGoalState", "learnHardCards"))
    return run(pre, exprs)


def test_texts_in_all_languages():
    for lg in ("de", "en", "th"):
        for k in KEYS:
            assert STR[lg][k].strip(), (lg, k)
    assert "{a}" in STR["en"]["learnGoalLine"] and "{b}" in STR["th"]["learnGoalLine"]
    for lg in ("de", "en", "th"):
        assert "1" in STR[lg]["learnKeys"] and "4" in STR[lg]["learnKeys"]
    assert "Leertaste" in STR["de"]["learnKeys"] and "space" in STR["en"]["learnKeys"]


def test_no_pressure_texts():
    bad = re.compile(r"verlier|verpass|nicht aufgeben|lose|lost|miss|don't break|ห้ามขาด", re.I)
    for lg in ("de", "en", "th"):
        for k in ("learnGoalLine", "dueLine"):
            assert not bad.search(STR[lg][k]), (lg, k)


def test_controls_label_input_adjacent():
    for i in ("learnGoal", "learnDictate", "learnHardOnly", "learnDictIn"):
        assert re.search(r'<label><input [^>]*id="' + i + '"', HTML), i
    assert 'id="learnGoalProg"' in HTML and 'id="learnDictRow"' in HTML


def test_reduced_motion_and_space_key():
    rm = HTML.split("@media (prefers-reduced-motion: reduce)", 1)[1].split("}\n  @media", 1)[0]
    assert "animation-duration:.01ms" in rm and "transition-duration:.01ms" in rm
    assert "@keyframes learnIn" not in HTML
    assert "e.key === ' '" in SCRIPT and "$('learnShow').click()" in SCRIPT
    assert "'1': 1, '2': 2, '3': 3, '4': 4" in SCRIPT


@needs_node
def test_typed_match_ignores_case_space_punct():
    got = go(["learnTypedMatch('สวัสดีครับ', 'สวัสดี ครับ')", "learnTypedMatch('Hello, World!', 'hello world')", "learnTypedMatch('abc', 'abd')"])
    assert got == [True, True, False]


@needs_node
def test_goal_state():
    got = go(["learnGoalState({ [localDay(Date.UTC(2026,5,15,12))]: { ok: 3, bad: 2 } }, Date.UTC(2026,5,15,12), 5)",
              "learnGoalState({}, Date.UTC(2026,5,15,12), 'x')", "learnGoalState({}, 0, 9999).goal"])
    assert got[0] == {"done": 5, "goal": 5}
    assert got[1] == {"done": 0, "goal": 20} and got[2] == 500


@needs_node
def test_hard_cards():
    cards = json.dumps([{"k": 1, "box": 1, "reps": 2, "due": 5}, {"k": 2, "box": 2, "reps": 1, "due": 1, "deck": "x"}, {"k": 3, "box": 3, "reps": 4, "due": 0},
                        {"k": 4, "box": 1, "due": 0}])
    got = go([f"learnHardCards({cards}, '').map(c => c.k)", f"learnHardCards({cards}, 'x').map(c => c.k)"])
    assert got == [[1, 2], [2]]

