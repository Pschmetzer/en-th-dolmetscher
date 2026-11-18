# ruff: noqa: E501
"""Runde 16 Web: eigene Saetze (bearbeiten, Uebersetzung, Gruppen), Reihenfolge per Auf/Ab, Export/Import, Speicher voll."""
import json
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, line, prelude, run

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
STR = json.loads(re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M).group(1))
KEYS = ("mcMax", "mcGroup", "mcText", "mcTr", "mcTranslate", "mcCancel", "mcExport", "mcImport", "mcFilter", "mcFavOrder", "mcFavEmpty",
        "mcAllGroups", "mcEmpty", "mcShowTr", "mcEdit", "mcUp", "mcDown", "mcMoved", "mcEditing", "mcTranslating", "mcTranslated",
        "mcTranslateFail", "mcNoneExport", "mcExported", "mcFileBad", "mcImported", "mcStorageFull")
PRE = ""
if HAVE_NODE:
    PRE = prelude(funcs=("myCardsParse", "myClean", "myMove", "myExport", "myImport", "myGroups", "favMove", "learnKey"),
                  lines=("const MY_KEY =",))


def test_texts_in_three_languages():
    for lg in ("de", "en", "th"):
        for k in KEYS:
            assert STR[lg][k].strip(), (lg, k)
    for k in ("mcUp", "mcDown"):
        assert all("{n}" in STR[lg][k] for lg in STR), k
    assert all("{n}" in STR[lg]["mcMax"] and "{p}" in STR[lg]["mcMoved"] for lg in STR)


def test_controls_labelled_and_wired():
    for i in ("myGrp", "myTr", "myTranslate", "myCancel", "myExport", "myImport", "myGrpSel", "favOrder"):
        assert f'id="{i}"' in HTML, i
    for i in ("myGrp", "myFile"):
        assert re.search(r"<label><input\b[^>]*id=\"" + i + '"', HTML), i
    assert re.search(r'<label><select id="myGrpSel"', HTML)
    body = func("renderMine") + func("moveBtn") + func("focusMove")
    assert "aria-label" in body and "mcUp" in body and "mcDown" in body and "focus()" in body and "mcMoved" in body
    assert "renderFavOrder()" in func("learnStore") and "mcStorageFull" in func("learnStore")


def test_translation_uses_existing_chain_and_storage_full_is_handled():
    assert "await translate(" in SCRIPT.split("$('myTranslate').onclick", 1)[1].split("};", 1)[0]
    body = func("mySave")
    assert body.index("localStorage.setItem") < body.index("myCards = next") and "mcStorageFull" in body and "return false" in body


def test_no_shadowed_t_and_sw_bumped():
    for name in ("renderMine", "renderFavOrder", "mySave", "moveBtn", "focusMove", "myEditStart", "myImport", "favMove"):
        head = func(name)
        assert not re.search(r"\b(?:const|let|var) t\b|\(t[,)]|, t\)|\bt =>", head), name
    assert int(re.search(r"dolmetscher-web-v(\d+)'", SW).group(1)) >= 15
    assert line("const MY_KEY =")


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_clean_limits_and_control_chars():
    long = "x" * 500
    c, none1, none2, none3, tr = run(PRE, [
        "myClean({label:'A\\u0000B\\n', text:'hi\\u0007 there', lang:'en', grp:'" + long + "', extra:1})",
        "myClean({label:'', text:'x', lang:'en'})", "myClean({label:'a', text:'x', lang:'zz'})", "myClean([1])",
        "myClean({label:'a', text:'x', lang:'en', tr:'y', trl:'qq'})"])
    assert c == {"label": "A B", "text": "hi there", "lang": "en", "grp": "x" * 24}
    assert [int(x) for x in re.search(r"MY_MAX = (\d+), MY_RAW = (\d+), MY_TXT = 200", SCRIPT).groups()] == [30, 200000]
    assert "MAX = 30, RAW = 200000" in func("myCardsParse")
    assert none1 is None and none2 is None and none3 is None and tr == {"label": "a", "text": "x", "lang": "en"}


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_move_swaps_and_ignores_bad_indexes():
    a, b, c, d = run(PRE, ["myMove([1,2,3],0,1)", "myMove([1,2,3],0,-1)", "myMove([1,2,3],2,3)", "myMove([1,2,3],1,1)"])
    assert a == [2, 1, 3] and b == [1, 2, 3] and c == [1, 2, 3] and d == [1, 2, 3]


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_favourite_move_skips_non_favourites():
    pre = PRE + "\nconst L = [{fav:true,a:{l:'en',t:'1'},b:{l:'th',t:'1'}},{fav:false,a:{l:'en',t:'x'},b:{l:'th',t:'x'}},{fav:true,a:{l:'en',t:'2'},b:{l:'th',t:'2'}}];"
    up, edge = run(pre, ["favMove(L, learnKey(L[2]), -1).map(c => c.a.t)", "favMove(L, learnKey(L[0]), -1).map(c => c.a.t)"])
    assert up == ["2", "x", "1"] and edge == ["1", "x", "2"]


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_export_import_roundtrip_and_validation():
    pre = PRE + "\nconst CUR = [{label:'Hotel', text:'Hello', lang:'en'}];"
    rt, dup, bad_json, bad_kind, proto, big, polluted = run(pre, [
        "myImport(myExport([{label:'Taxi', text:'Stop', lang:'en', grp:'Reise', tr:'Halt', trl:'de'}]), CUR)",
        "myImport(myExport(CUR), CUR)",
        "myImport('{nope', CUR)", "myImport('{\"kind\":\"other\",\"v\":1,\"cards\":[]}', CUR)",
        "myImport('[{\"label\":\"a\",\"text\":\"b\",\"lang\":\"en\",\"__proto__\":{\"x\":1},\"constructor\":{}}]', CUR)",
        "myImport('[' + ' '.repeat(300000) + ']', CUR)",
        "({}).x === undefined && !Object.prototype.hasOwnProperty.call(myCardsParse('[{\"__proto__\":{\"x\":1}}]'), 'x')"])
    assert rt["added"] == 1 and rt["list"][1] == {"label": "Taxi", "text": "Stop", "lang": "en", "tr": "Halt", "trl": "de", "grp": "Reise"}
    assert dup["added"] == 0 and dup["skipped"] == 1 and len(dup["list"]) == 1
    assert bad_json is None and bad_kind is None and big is None
    assert proto["added"] == 1 and set(proto["list"][1]) == {"label", "text", "lang"}
    assert polluted is True


@pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")
def test_import_respects_card_limit_and_groups():
    pre = PRE + "\nconst MANY = JSON.stringify(Array.from({length: 150}, (_, i) => ({label: 'L' + i, text: 'T' + i, lang: 'en', grp: i % 2 ? 'b' : 'a'})));"
    res, groups, parsed = run(pre, ["myImport(MANY, [])", "myGroups(myImport(MANY, []).list)", "myCardsParse(MANY).length"])
    assert len(res["list"]) == 30 and res["added"] == 30 and res["skipped"] == 120
    assert groups == ["a", "b"] and parsed == 30
