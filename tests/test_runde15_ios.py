"""Round 15 (iPhone app): conversation mode as source checks. The Swift tests run via xcodebuild test."""
import pathlib

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _read(*p):
    return IOS.joinpath(*p).read_text(encoding="utf-8")


def test_logic_file_is_pure_and_tested():
    src = _read("Dolmetscher", "ConversationLogic.swift")
    assert "import SwiftUI" not in src and "import UIKit" not in src
    assert "ConversationLogic" in _read("DolmetscherTests", "Round15Tests.swift")


def test_texts_in_all_ten_languages():
    src = _read("Dolmetscher", "L10n+R15.swift")
    keys = ("conv_state_idle", "conv_state_listening", "conv_state_translating", "conv_state_speaking",
            "conv_language", "conv_font_smaller", "conv_font_larger", "conv_repeat", "conv_slow")
    for k in keys:
        block = src.split(f'"{k}": [', 1)[1].split("],", 1)[0]
        for lang in LANGS:
            assert f'"{lang}":' in block, (k, lang)
    assert "round15" in _read("Dolmetscher", "L10n.swift")


def test_view_uses_features():
    v = _read("Dolmetscher", "ConversationView.swift")
    for needle in ("sideBySide", "isIdleTimerDisabled = true", "conv_repeat", "conv_slow", "setLang",
                   "convFontStep", "highlighted", "turnLocked"):
        assert needle in v, needle
    assert "isEcho" in _read("Dolmetscher", "Model.swift")


def test_state_is_not_only_color():
    v = _read("Dolmetscher", "ConversationView.swift")
    assert "ConversationLogic.icon(st)" in v and "ConversationLogic.textKey(st)" in v
