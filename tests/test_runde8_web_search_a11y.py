# ruff: noqa: E501
"""Runde 8 Web: Satzbuch-Suche, Kopieren, Zugaenglichkeits-CSS, behobener t()-Konflikt in addActions."""
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, func, prelude, run, web_str

SW = (ROOT / "sw.js").read_text(encoding="utf-8")
PRE = prelude(funcs=("pbNorm", "pbMatch"))


@pytest.mark.skipif(not HAVE_NODE, reason="node nicht installiert")
def test_pb_match():
    got = run(PRE, ["pbMatch('Where is the Toilet?', '')", "pbMatch('Where is the Toilet?', ' toilet WHERE ')",
                    "pbMatch('Café au lait', 'cafe')", "pbMatch('ห้องน้ำอยู่ไหน', 'ห้องน้ำ')", "pbMatch('Hello', 'bye')",
                    "pbMatch(undefined, 'x')", "pbMatch(null, '')"])
    assert got == [True, True, True, True, False, False, True]


def test_add_actions_does_not_shadow_t():
    body = func("addActions")
    sig = re.match(r"function addActions\(([^)]*)\)", body).group(1).split(",")
    assert "t" not in [x.strip() for x in sig], "Parameter t verdeckt die Uebersetzungsfunktion t()"
    assert "t('showBigBtn')" in body and "t('copyBtn')" in body


def test_search_field_and_wiring():
    assert 'id="pbQ" type="search"' in HTML and 'id="pbCount" role="status"' in HTML
    assert "setTimeout(applyPbFilter, 300)" in SCRIPT                     # entprellt (CLAUDE: ~300 ms)
    assert "applyPbFilter();\n}" in func("renderCards") + "\n}" or "applyPbFilter();" in func("renderCards")
    assert "e.key === '/'" in SCRIPT and "$('pbQ').focus()" in SCRIPT


def test_new_strings_in_all_ui_languages():
    for k in ("skipLink", "pbSearch", "pbNoMatch", "pbCount", "copyBtn", "copied", "copyFail", "pbSearchHint"):
        assert all(k in S for S in web_str().values()), k


def test_a11y_css():
    for needle in ("prefers-contrast: more", "forced-colors: active", ".skip:focus", "scroll-behavior:auto !important"):
        assert needle in HTML, needle
    assert 'href="#pbBox"' in HTML


def test_sw_cache_bumped_r8():
    assert int(re.search(r"dolmetscher-web-v(\d+)'", SW).group(1)) >= 11
