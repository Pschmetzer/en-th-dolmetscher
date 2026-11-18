# ruff: noqa: E501
"""Runde 19 Web: Satzbuch-Suche mit Tippfehler-Toleranz und Filter Nur wichtige Saetze."""
import json
import re

import pytest
from _webhelpers import HAVE_NODE, HTML, SCRIPT, prelude, run

STR = json.loads(re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M).group(1))
needs_node = pytest.mark.skipif(not HAVE_NODE, reason="node fehlt")


def test_crit_text_and_button():
    for lg in ("de", "en", "th"):
        assert STR[lg]["critOnly"].strip(), lg
    assert 'id="pbCrit"' in HTML and 'aria-pressed="false" data-i18n="critOnly"' in HTML
    assert "$('pbCrit').onclick" in SCRIPT and "w.querySelector('.crit')" in SCRIPT


@needs_node
def test_fuzzy_match():
    pre = prelude(("pbNorm", "pbNear", "pbMatch"))
    got = run(pre, ["pbMatch('Where is the hospital', 'hospitl')", "pbMatch('Where is the hospital', 'hosptial')", "pbMatch('Where is the hospital', 'hostel')",
                    "pbMatch('Where is the hospital', 'whre hospital')", "pbMatch('Krankenhaus', 'krankenhauss')", "pbMatch('ab cd', 'abc')", "pbMatch('x', '')",
                    "pbNear('hospital', 'hosptial')", "pbNear('abcd', 'abde')"])
    assert got == [True, False, False, True, True, False, True, False, False]
