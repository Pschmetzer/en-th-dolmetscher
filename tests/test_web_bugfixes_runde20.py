"""Runde 20 (Web): t() darf in loadLangTable nicht überdeckt werden."""
import pathlib
import re

HTML = (pathlib.Path(__file__).resolve().parent.parent / "index.html").read_text(encoding="utf-8")


def test_loadlangtable_does_not_shadow_t():
    body = re.search(r"function loadLangTable\(\).*?^\}", HTML, re.S | re.M).group(0)
    assert not re.search(r"\.then\(\s*t\s*=>", body), "Parameter t überdeckt die Übersetzungsfunktion t()"
    assert "t('langTableFail')" in body
