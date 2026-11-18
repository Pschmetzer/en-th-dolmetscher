"""Round 17 (iPhone app): shortcut and control checks that run without Xcode (Swift tests: xcodebuild test)."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def _rows(file, pattern):
    src = _src(*file)
    return {k: dict(re.findall(r'"(de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "((?:[^"\\]|\\.)*)"', body))
            for k, body in re.findall(pattern, src, re.S)}


def test_app_texts_complete_with_same_placeholders():
    rows = _rows(("Dolmetscher", "L10n+R17.swift"), r'"(sc_[a-z_]+)": \[(.*?)\],\n')
    assert set(rows) == {"sc_swapped", "sc_said", "sc_no_phrase", "sc_no_last"}
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(v.strip() for v in row.values()), key
        assert all(v.count("%@") == row["en"].count("%@") for v in row.values()), key
    assert "round17" in _src("Dolmetscher", "L10n.swift")


def test_widget_texts_complete():
    rows = _rows(("Shared", "WidgetTexts.swift"), r'"(w_(?:swap|swap_d|speak_last|speak_last_d))": \[(.*?)\],\n')
    assert len(rows) == 4
    for key, row in rows.items():
        assert set(row) == set(LANGS) and all(v.strip() for v in row.values()), key


def test_intents_have_siri_phrases_and_controls_exist():
    intents = _src("Dolmetscher", "Intents.swift")
    for name in ("SpeakLastTranslationIntent", "SwapLanguagePairIntent", "SayPhrasebookPhraseIntent"):
        assert f"AppShortcut(intent: {name}()" in intents, name
    assert intents.count("\\(.applicationName)") >= 15
    bundle = _src("DolmetscherWidget", "WidgetBundle.swift")
    assert "SwapPairControl()" in bundle and "SpeakLastControl()" in bundle
    assert "SwapLanguagePairIntent" in _src("Shared", "SharedIntents.swift")


def test_logic_is_pure_tested_and_no_new_target():
    logic = _src("Dolmetscher", "ShortcutLogic.swift")
    assert "import SwiftUI" not in logic and "import AVFoundation" not in logic
    tests = _src("DolmetscherTests", "Round17Tests.swift")
    for name in ("PairSwitch", "LastSpeech", "PhraseMatcher"):
        assert name in tests, name
    assert "StatusColor" not in logic and not re.search(r"Color\(red:|\.red\b|\.green\b|\.orange\b", logic)
