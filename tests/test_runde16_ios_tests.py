"""Round 16 (iPhone app): static checks for Round16Tests.swift; the tests themselves run via xcodebuild test."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
TESTS = IOS / "DolmetscherTests" / "Round16Tests.swift"


def _methods():
    return re.findall(r"^\s*func (test\w+)\(\)", TESTS.read_text(encoding="utf-8"), re.M)


def test_round16_tests_exist_and_are_unique():
    names = _methods()
    assert len(names) >= 40
    assert len(names) == len(set(names))
    assert "final class Round16Tests: XCTestCase" in TESTS.read_text(encoding="utf-8")


def test_test_target_picks_the_file_up():
    # The tests folder is a file-system-synchronised group of the DolmetscherTests target: no per-file entry needed.
    pbx = (IOS / "Dolmetscher.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    assert "path = DolmetscherTests; sourceTree" in pbx and "PBXFileSystemSynchronizedRootGroup" in pbx
    assert TESTS.parent.name == "DolmetscherTests"


def test_every_area_is_covered():
    src = TESTS.read_text(encoding="utf-8")
    for symbol in ("TranscriptCSV", "CSVSafe", "PhraseSearch", "SpeechRate", "Retention", "UndoBuffer", "SecureCopy",
                   "ShieldPolicy", "ErrorAdvice", "LeitnerDeck", "LangPair", "RecentPairs", "QuickPhrasesEntry",
                   "ThaiNumber", "NumberCard", "BackCheck", "ReviewGate", "LanguagePick"):
        assert symbol in src, symbol


def test_no_test_is_silently_skipped():
    src = TESTS.read_text(encoding="utf-8")
    assert "XCTSkip" not in src
    assert not re.search(r"^\s*//\s*func test", src, re.M)
