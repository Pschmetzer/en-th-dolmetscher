"""Round 18 (iPhone app): history list checks that run without Xcode (Swift tests: xcodebuild test)."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def _rows():
    src = _src("Dolmetscher", "L10n+R18.swift")
    return {k: dict(re.findall(r'"(de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "((?:[^"\\]|\\.)*)"', body))
            for k, body in re.findall(r'"(hs_[a-z0-9_]+)": \[(.*?)\],\n', src, re.S)}


def test_history_texts_complete_with_same_placeholders():
    rows = _rows()
    assert len(rows) >= 25
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(v.strip() for v in row.values()), key
        assert all(v.count("%@") == row["en"].count("%@") for v in row.values()), key
    assert "round18" in _src("Dolmetscher", "L10n.swift")


def test_every_text_key_used_in_the_view_or_logic_exists():
    rows = _rows()
    code = _src("Dolmetscher", "HistoryView.swift") + _src("Dolmetscher", "HistoryLogic.swift")
    used = set(re.findall(r'"(hs_[a-z0-9_]+)"', code)) - {"hs_range_"}
    assert used <= set(rows), used - set(rows)
    for r in ("all", "today", "week", "month"):
        assert f"hs_range_{r}" in rows


def test_view_uses_status_colors_and_touch_targets_only():
    view = _src("Dolmetscher", "HistoryView.swift")
    assert "StatusColor." in view and "minTapTarget()" in view
    assert not re.search(r"\.(red|green|orange|yellow|blue)\b", view)
    assert "m.sheet = .history" in _src("Dolmetscher", "Views.swift")
