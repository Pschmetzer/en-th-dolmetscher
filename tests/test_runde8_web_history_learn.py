# ruff: noqa: E501
"""Runde 8 Web: Verlauf (CSV, Suche, Leeren), Lernfortschritt/-plan, Favoriten-Filter, Fehlerzustaende, t()-Verdeckung."""
import re

import pytest

from _webhelpers import HAVE_NODE, HTML, SCRIPT, func, prelude, run, web_str

DAY = 86_400_000
PRE = prelude(funcs=("pbNorm", "pbMatch", "logCsv", "learnProgress", "learnPlan", "titleFor"), lines=("const LEARN_KEY",))
node = pytest.mark.skipif(not HAVE_NODE, reason="node nicht installiert")


@node
def test_log_csv_quotes_and_blocks_formulas():
    got = run(PRE, ["logCsv([{orig:'a \"b\"', trans:'x,y'}, {orig:'=1+1', trans:'line1\\nline2'}, {orig:'ไทย', trans:''}])", "logCsv([])"])
    assert got[0] == '"original","translation"\r\n"a ""b""","x,y"\r\n"\'=1+1","line1 line2"\r\n"ไทย",""\r\n'
    assert got[1] == '"original","translation"\r\n'


@node
def test_learn_progress_and_plan():
    now = 1_700_000_000_000
    lst = "[{box:1,due:%d},{box:4,due:%d},{box:5,due:%d},{box:2,due:%d},{box:3,due:%d}]" % (
        now - 5 * DAY, now, now + DAY, now + 3 * DAY, now + 30 * DAY)
    got = run(PRE, [f"learnProgress({lst})", "learnProgress([])", f"learnPlan({lst}, {now})", "titleFor('a','Dolmetscher','Hört zu')", "titleFor(null,'Dolmetscher','x')"])
    assert got[0] == {"total": 5, "done": 2, "pct": 40}
    assert got[1] == {"total": 0, "done": 0, "pct": 0}
    plan = got[2]
    assert plan["today"] >= 2 and plan["today"] + plan["tomorrow"] + plan["week"] == 4   # der Fach-3-Eintrag in 30 Tagen zaehlt nicht
    assert got[3] == "🎙 Hört zu – Dolmetscher" and got[4] == "Dolmetscher"


def test_no_function_shadows_translation_function():
    """t() darf nicht durch Parameter/lokale Variablen namens t verdeckt werden (war ein Laufzeitfehler in deliver/addActions/renderCards)."""
    bad = []
    for m in re.finditer(r"^(?:async )?function (\w+)\(([^)]*)\) \{(.*?)^\}", SCRIPT, re.S | re.M):
        name, params, body = m.groups()
        uses_t = re.search(r"(?<![.\w$])t\(", body)
        shadow = "t" in [x.strip() for x in params.split(",")] or re.search(r"\b(?:const|let|var) t\b", body)
        if uses_t and shadow:
            bad.append(name)
    assert not bad, bad


def test_history_controls_and_strings():
    for i in ("btnCsv", "btnShareLog", "btnClearLog", "logQ", "logCount", "pbFav", "learnProg", "learnPlan", "wipeLocal"):
        assert f'id="{i}"' in HTML, i
    assert "setTimeout(applyLogFilter, 300)" in SCRIPT
    assert "window.confirm(t('logClearConfirm'))" in SCRIPT and "window.confirm(t('wipeConfirm'))" in SCRIPT
    assert "'\\ufeff' + logCsv(rows)" in SCRIPT   # BOM fuer Excel
    for k in ("logQ", "logCount", "logNone", "logClear", "logClearConfirm", "logCleared", "logShare", "saveCsv", "favOnly", "favNone", "learnProgress",
              "learnPlan", "learnKeys", "micDeniedPre", "micDeniedAct", "netBack", "netOffNow", "noSw", "wipeLocal", "wipeConfirm", "wipeDone", "helpKey", "titleListen"):
        assert all(k in S for S in web_str().values()), k


def test_error_states_and_platform_quirks():
    assert "navigator.permissions.query({ name: 'microphone' })" in SCRIPT and "data-act=\"phrasebook\"" in SCRIPT
    assert ".catch(() => {})" in SCRIPT.split("navigator.permissions.query", 1)[1][:600]   # Safari kennt die Abfrage nicht
    assert "t('netOffNow')" in func("updateOnline") and "t('netBack')" in func("updateOnline")
    assert "t('noSw')" in SCRIPT
    assert "window.addEventListener('pagehide'" in SCRIPT
    for css in ("-webkit-text-size-adjust", "touch-action:manipulation", "font-size:max(16px, 1em)", "content-visibility:auto"):
        assert css in HTML, css


def test_keyboard_and_aria():
    assert "e.key === '?'" in SCRIPT and "ArrowLeft" in SCRIPT.split("$('learnCard').addEventListener('keydown'", 1)[1][:400]
    assert 'aria-keyshortcuts="E 1"' in HTML and 'aria-keyshortcuts="T 2"' in HTML
    assert "$('skipLink').addEventListener('click'" in SCRIPT
