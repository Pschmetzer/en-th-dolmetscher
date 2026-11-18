"""Round 8 (iPhone app): static checks that run without Xcode. The Swift tests themselves run via xcodebuild test."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")
PLACEHOLDER = re.compile(r"%(?:\.\d+)?[@dfs]")


def _round8_table():
    src = (IOS / "Dolmetscher" / "L10n+R8.swift").read_text(encoding="utf-8")
    rows = {}
    for key, body in re.findall(r'"([a-z0-9_]+)": \[\s*((?:"[^"]+": "(?:\\.|[^"\\])*",?\s*)+)\]', src):
        rows[key] = dict(re.findall(r'"([A-Za-z-]+)": "((?:\\.|[^"\\])*)"', body))
    return rows


def test_round8_texts_complete_in_all_languages():
    rows = _round8_table()
    assert len(rows) >= 6
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(t.strip() for t in row.values()), key
        for lang, text in row.items():
            assert PLACEHOLDER.findall(text) == PLACEHOLDER.findall(row["en"]), (key, lang)


def test_round8_keys_are_new_and_registered():
    mine = set(_round8_table())
    others = set()
    for name in ("L10n.swift", "L10n+R4.swift", "L10n+R5.swift", "L10n+R6.swift", "L10n+R7.swift"):
        f = IOS / "Dolmetscher" / name
        if f.exists():
            others |= set(re.findall(r'"([a-z0-9_]+)":\s*\[', f.read_text(encoding="utf-8")))
    assert not mine & others
    l10n = (IOS / "Dolmetscher" / "L10n.swift").read_text(encoding="utf-8")
    registered = l10n[l10n.index("static func text("):]
    assert re.search(r"\bround8\b", registered)   # Nachschlag und allKeys kennen die Tabelle, egal in welcher Schreibweise


def test_round8_used_keys_exist():
    mine = set(_round8_table())
    used = set()
    for f in (IOS / "Dolmetscher").glob("*.swift"):
        used |= set(re.findall(r'T\("([a-z0-9_]+)"\)', f.read_text(encoding="utf-8")))
    for key in ("learn_today", "learn_streak", "learn_box_a11y", "cat_recent", "recent_empty", "net_back"):
        assert key in mine and key in used, key


def test_round8_wiring():
    model = (IOS / "Dolmetscher" / "Model.swift").read_text(encoding="utf-8")
    assert "NetStatus.shared.onReconnect" in model and "retryFailedTranslations" in model
    views = (IOS / "Dolmetscher" / "Views.swift").read_text(encoding="utf-8")
    assert ".accessibilityAction(.magicTap)" in views
    learn = (IOS / "Dolmetscher" / "Learn.swift").read_text(encoding="utf-8")
    assert "font(.system(size: 48))" not in learn   # Dynamic Type: skalierbar statt fest
    assert (IOS / "DolmetscherTests" / "Round8Tests.swift").exists()
