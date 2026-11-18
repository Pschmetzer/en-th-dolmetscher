"""Round 10 (iPhone app): static checks without Xcode."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios" / "Dolmetscher"


def _read(n):
    return (IOS / n).read_text(encoding="utf-8")


def test_help_guide_keys_in_all_languages():
    src = _read("L10n+R9.swift")
    for key in ("help_title", *(f"help_s{i}_{x}" for i in range(1, 6) for x in "tb")):
        m = re.search(rf'"{key}": \[\s*(.*?)\n\s*\],', src, re.S)
        assert m, key
        assert len(re.findall(r'"(?:de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "', m.group(1))) == 10, key


def test_help_sheet_shows_guide_and_shortcut():
    views = _read("Views.swift")
    assert "HelpGuideCard()" in views and 'keyboardShortcut("/", modifiers: .command)' in views


def test_slow_repeat_uses_shared_rate_and_haptic():
    assert "SpeechRate.effective" in _read("Model.swift")
    assert "if slow { Haptics.slow() }" in _read("Model.swift")
    assert "static func slow()" in _read("Haptics.swift")


def test_ipad_tools_column_is_adaptive():
    assert "IPadLayout.toolsMaxWidth" in _read("Views.swift")
    assert "frame(width: 380)" not in _read("Views.swift")
