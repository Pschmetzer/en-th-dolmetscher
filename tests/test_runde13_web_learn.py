# ruff: noqa: E501
"""Runde 13 Web: Lernmodus (Planungsfunktion, Tageslimit, Decks, Sicherung, Tasten, Texte)."""
import json
import re

import pytest
from _webhelpers import HAVE_NODE, HTML, SCRIPT, func, line, prelude, run

DAY = 864e5
FUNCS = ("learnSide", "learnParse", "learnKey", "learnDay", "leitnerGrade", "learnIsNew", "learnDue", "learnQueue", "learnBoxes",
         "statsClean", "statsMerge", "learnPack", "learnUnpack", "localDay", "statsAdd", "learnMerge", "learnAdd")
PRE = prelude(FUNCS, ("const LEARN_KEY", "const RETRY_MS", "const LEARN_DAYS")) if HAVE_NODE else ""
PRE = PRE.replace("const LEARN_KEY", "const LEARN_KEY")
CARD = {"a": {"t": "Hallo", "l": "de"}, "b": {"t": "สวัสดี", "l": "th"}, "box": 2, "due": 0, "fav": True, "rec": False, "add": 0}
NOW = "Date.UTC(2026, 5, 15, 12)"
needs_node = pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")


def go(exprs):
    def iife(e):
        if not e.startswith("const "):
            return e
        stmts, last = e.rsplit("; ", 1)
        return f"(() => {{ {stmts}; return {last}; }})()"
    return run(_pre(), [iife(e) for e in exprs])


def _pre():
    consts = "const LEARN_MAX = 200, LEARN_TXT = 500, DAY = 864e5, RETRY_MS = 10 * 60000, LEARN_DAYS = [0, 1, 3, 7, 14];\n" + line("const LEARN_FORMAT") + "\n" + line("const STATS_DAY_RX")
    return prelude(FUNCS) + "\n" + consts


@needs_node
def test_grades_plan_the_boxes():
    c = json.dumps(CARD)
    got = go([
        f"const n = {NOW}; const x = leitnerGrade({c}, 1, n); [x.box, x.due - n, x.reps]",
        f"const n = {NOW}; const x = leitnerGrade({c}, 2, n); [x.box, (x.due - learnDay(n, 0)) / {DAY}, x.reps]",
        f"const n = {NOW}; const x = leitnerGrade({c}, 3, n); [x.box, (x.due - learnDay(n, 0)) / {DAY}]",
        f"const n = {NOW}; const x = leitnerGrade({c}, 4, n); [x.box, (x.due - learnDay(n, 0)) / {DAY}]",
        f"leitnerGrade({{...{c}, box: 5}}, 4, 0).box",
        f"const n = {NOW}; const x = leitnerGrade({{...{c}, box: 5}}, 2, n); [x.box, Math.round((x.due - learnDay(n, 0)) / {DAY})]",
        f"const n = {NOW}; const x = leitnerGrade({{...{c}, box: 1}}, 2, n); [x.box, Math.round((x.due - learnDay(n, 0)) / {DAY})]",
        f"leitnerGrade({c}, 9, 1) === undefined",
    ])
    assert got[0] == [1, 600000, 1]
    assert got[1] == [2, 1, 1]          # schwer: Fach bleibt, Abstand halb (min. 1 Tag)
    assert got[2] == [3, 3]
    assert got[3] == [4, 7]             # leicht: zwei Fächer weiter
    assert got[4] == 5
    assert got[5] == [5, 7]
    assert got[6] == [1, 1]
    assert got[7] is False


@needs_node
def test_daily_limit_for_new_cards():
    new = lambda i, deck="": {**CARD, "box": 1, "due": i, "a": {"t": f"n{i}", "l": "de"}, **({"deck": deck} if deck else {})}  # noqa: E731
    seen = {**CARD, "box": 3, "due": 1, "reps": 2, "a": {"t": "alt", "l": "de"}}
    cards = json.dumps([new(5), new(6), new(7), seen])
    got = go([
        f"learnQueue({cards}, 100, '', 2, 0).map(c => c.a.t)",
        f"learnQueue({cards}, 100, '', 2, 2).map(c => c.a.t)",
        f"learnQueue({cards}, 100, '', 99, 0).length",
        f"learnQueue({json.dumps([new(1, 'taxi'), new(2, 'hotel')])}, 100, 'hotel', 9, 0).map(c => c.a.t)",
        f"learnBoxes({cards}, '')",
        "learnIsNew({box: 1}) && !learnIsNew({box: 1, reps: 1}) && !learnIsNew({box: 2})",
        "const s = statsAdd({}, true, 5000, true); [s[localDay(5000)].nw, statsAdd({}, true, 5000).nw === undefined]",
    ])
    assert len(got[0]) == 3 and "n7" not in got[0]   # 2 neue + die gelernte Karte
    assert got[1] == ["alt"]                         # Limit schon erreicht
    assert got[2] == 4
    assert got[3] == ["n2"]
    assert got[4] == [3, 0, 1, 0, 0]
    assert got[5] is True
    assert got[6] == [1, True]


@needs_node
def test_backup_is_validated_not_executed():
    evil = json.dumps({"format": "dolmetscher-learn", "v": 1, "stats": {"__proto__": {"ok": 1}, "2026-06-15": {"ok": 2, "bad": "x", "nw": -3}, "evil": {"ok": 1}},
                       "cards": [{**CARD, "deck": "../x", "a": {"t": "<img src=x onerror=alert(1)>\x00", "l": "de"}, "__proto__": {"polluted": 1}, "constructor": 1}, 7, None]})
    got = go([
        f"const p = learnUnpack({json.dumps(evil)}); [p.cards.length, p.cards[0].deck === undefined, p.cards[0].a.t, Object.keys(p.stats), p.stats['2026-06-15'], ({{}}).polluted, ({{}}).ok]",
        "learnUnpack('{kaputt')", "learnUnpack('{\"format\":\"x\",\"v\":1,\"cards\":[]}')", "learnUnpack('42')", "learnUnpack('null')",
        f"learnUnpack(learnPack([{json.dumps(CARD)}], {{'2026-06-15': {{ok: 1, bad: 0}}}})).cards.length",
        f"learnUnpack(JSON.stringify([{json.dumps(CARD)}])).stats",
        "JSON.stringify(statsMerge({'2026-06-15': {ok: 3, bad: 1}}, {'2026-06-15': {ok: 2, bad: 4, nw: 1}}))",
        f"learnParse(JSON.stringify([{{...{json.dumps(CARD)}, deck: 'taxi', reps: 3, r: 'sa-wat-dee'}}]))[0]",
    ])
    assert got[0][0] == 1 and got[0][1] is True
    assert "\x00" not in got[0][2] and got[0][2].startswith("<img")   # nur Text, wird per textContent gezeigt
    assert got[0][3] == ["2026-06-15"] and got[0][4] == {"ok": 2, "bad": 0}
    assert got[0][5] is None and got[0][6] is None
    assert got[1] is None and got[2] is None and got[3] is None and got[4] is None
    assert got[5] == 1 and got[6] == {}
    assert json.loads(got[7]) == {"2026-06-15": {"ok": 3, "bad": 4, "nw": 1}}
    assert got[8]["deck"] == "taxi" and got[8]["reps"] == 3 and got[8]["r"] == "sa-wat-dee"


@needs_node
def test_preset_cards_carry_deck_and_romanization():
    item = {"a": {"t": "Taxi", "l": "de"}, "b": {"t": "แท็กซี่", "l": "th"}, "deck": "taxi", "r": "tæk-sîi"}
    got = go([f"learnAdd([], {json.dumps(item)}, 5, 'fav')[0]"])
    assert got[0]["deck"] == "taxi" and got[0]["r"] == "tæk-sîi" and got[0]["box"] == 1


def test_ui_wiring():
    for i in ("learnDeck", "learnReset", "learnHard", "learnEasy", "learnRom", "learnBoxStats", "learnNew", "learnExport", "learnImport", "learnFile"):
        assert f'id="{i}"' in HTML, i
    assert re.search(r'<label><input type="number" id="learnNew"', HTML)
    assert "window.confirm(t('learnResetConfirm'" in SCRIPT
    assert "'1': 1, '2': 2, '3': 3, '4': 4" in SCRIPT
    assert "learnUnpack(r.result)" in SCRIPT and "learnPack(learnList, learnStats)" in SCRIPT
    assert "learnQueueNow(now)" in func("learnRender")
    assert "learnRom" in func("learnReveal")
    assert "textContent = learnCur.r" in func("learnRender")


def test_texts_in_all_languages():
    m = re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M)
    strs = json.loads(m.group(1))
    for k in ("learnDeck", "learnDeckAll", "learnHard", "learnEasy", "learnReset", "learnResetConfirm", "learnResetDone", "learnLimitDone", "learnBoxes", "learnImportBad", "learnKeys"):
        assert all(strs[lg][k].strip() for lg in ("de", "en", "th")), k
    assert all("{n}" in strs[lg]["learnResetConfirm"] for lg in strs)
    assert "{e}" in strs["th"]["learnBoxes"]


def test_service_worker_cache_bumped():
    sw = (__import__("pathlib").Path(__file__).resolve().parent.parent / "sw.js").read_text(encoding="utf-8")
    import re
    assert int(re.search(r"dolmetscher-web-v(\d+)", sw).group(1)) >= 13   # nur hochzählen, nie zurück
