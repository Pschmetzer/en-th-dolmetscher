"""Round 11 (iPhone app): widget checks that run without Xcode. The Swift tests run via xcodebuild test."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def test_widget_texts_complete_in_all_languages():
    src = _src("Shared", "WidgetTexts.swift")
    rows = re.findall(r'"(w_[a-z0-9_]+)": \[(.*?)\],\n', src, re.S)
    keys = {k for k, _ in rows}
    assert {"w_pair_a11y", "w_empty", "w_say_hint"} <= keys
    for key, body in rows:
        assert len(re.findall(r'"(?:de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "[^"]+"', body)) == len(LANGS), key


def test_widget_supports_all_sizes_and_lock_screen():
    src = _src("DolmetscherWidget", "QuickPhrases.swift")
    families = (".systemSmall", ".systemMedium", ".systemLarge")
    for fam in (*families, ".accessoryRectangular", ".accessoryInline", ".accessoryCircular"):
        assert fam in src, fam


def test_widget_never_reads_conversation_data():
    for name in ("QuickPhrases.swift", "WidgetViews.swift"):
        src = _src("DolmetscherWidget", name) if name == "QuickPhrases.swift" else _src("Shared", name)
        assert "m.favorites" not in src and "history" not in src.lower().replace("verlauf", "")
        assert "UserDefaults" not in src and "FileManager" not in src
    assert "group." not in _src("Dolmetscher.entitlements")


def test_widget_timeline_rotates_and_view_scales_with_dynamic_type():
    views = _src("Shared", "WidgetViews.swift")
    assert "policy: .atEnd" in views and "policy: .never" in views
    assert "isAccessibilitySize" in views and "accessibilityHint" in views
    assert "PairHeader()" in views
