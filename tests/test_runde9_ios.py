"""Round 9 (iPhone app): static checks that run without Xcode. The Swift tests themselves run via xcodebuild test."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return (IOS.joinpath(*parts)).read_text(encoding="utf-8")


def _table(name, var):
    src = _src("Dolmetscher", name)
    rows = {}
    for key, body in re.findall(r'"([a-z0-9_]+)": \[\s*((?:"[^"]+": "(?:\\.|[^"\\])*",?\s*)+)\]', src):
        rows[key] = dict(re.findall(r'"([A-Za-z-]+)": "((?:\\.|[^"\\])*)"', body))
    return rows


def test_round9_texts_complete_and_registered():
    rows = _table("L10n+R9.swift", "round9")
    assert {"interrupt_paused", "route_lost"} <= set(rows)
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(t.strip() for t in row.values()), key
    l10n = _src("Dolmetscher", "L10n.swift")
    assert "round9[key]" in l10n and "round9.keys" in l10n


def test_round9_keys_are_new():
    mine = set(_table("L10n+R9.swift", "round9"))
    for name in ("L10n.swift", "L10n+R4.swift", "L10n+R5.swift", "L10n+R6.swift", "L10n+R7.swift", "L10n+R8.swift",
                 "L10n+Extra.swift"):
        others = set(re.findall(r'"([a-z0-9_]+)":\s*\[', _src("Dolmetscher", name)))
        assert not mine & others, name


def test_round9_used_keys_exist():
    mine = set(_table("L10n+R9.swift", "round9"))
    used = set()
    for f in (IOS / "Dolmetscher").glob("*.swift"):
        used |= set(re.findall(r'T\("([a-z0-9_]+)"\)', f.read_text(encoding="utf-8")))
    assert {"interrupt_paused", "route_lost"} <= used & mine


def test_widget_stale_text_in_all_languages():
    src = _src("Shared", "WidgetTexts.swift")
    block = re.search(r'"w_stale": \[(.*?)\],\n', src, re.S).group(1)
    assert set(re.findall(r'"([A-Za-z-]+)": "', block)) == set(LANGS)


def test_csv_formula_guard_and_search_wired():
    assert "CSVSafe.cell(s)" in _src("Dolmetscher", "Round7.swift")
    assert "PhraseSearch.matches" in _src("Dolmetscher", "Phrasebook.swift")
    r9 = _src("Dolmetscher", "Round9.swift")
    assert 'dangerous: Set<Character> = ["=", "+", "-", "@"' in r9


def test_interruption_and_route_events_wired():
    assert "case routeLost" in _src("Dolmetscher", "SpeechEngine.swift")
    assert "emit(.routeLost)" in _src("Dolmetscher", "AudioCapture.swift")
    model = _src("Dolmetscher", "Model.swift")
    assert "case .routeLost" in model and "interrupt_paused" in model and "interrupted ? .interrupted" in model


def test_live_activity_states_privacy_and_stale():
    la = _src("Dolmetscher", "LiveActivity.swift")
    assert "staleDate: Self.staleDate()" in la and "staleDate: nil" not in la
    views = _src("Shared", "WidgetViews.swift")
    assert "w_stale" in views and "dynamicTypeSize" in views and ".privacySensitive()" in views
    assert "stale: context.isStale" in _src("DolmetscherWidget", "LiveActivityViews.swift")
