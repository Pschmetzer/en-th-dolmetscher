"""Runde 28, Mac-App: neue reine Logik (R28Logic.swift) ist Foundation-only und in swift-tests verlinkt;
die Tests decken jeden Typ ab; kein Typname kollidiert mit anderen App-Dateien."""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
LINK = ROOT / "swift-tests" / "Sources" / "DolmetscherLogic" / "R28Logic.swift"
TESTS = ROOT / "swift-tests" / "Tests" / "DolmetscherLogicTests" / "R28Tests.swift"


def test_r28_logic_is_foundation_only_and_linked():
    text = (APP / "R28Logic.swift").read_text(encoding="utf-8")
    assert re.findall(r"^import (\w+)", text, re.M) == ["Foundation"]
    assert LINK.is_symlink() and LINK.resolve() == (APP / "R28Logic.swift").resolve()


def test_every_r28_type_is_tested_and_unique():
    text = (APP / "R28Logic.swift").read_text(encoding="utf-8")
    types = re.findall(r"^enum (\w+)", text, re.M)
    assert len(types) >= 15
    tests = TESTS.read_text(encoding="utf-8")
    others = "\n".join(f.read_text(encoding="utf-8") for f in APP.glob("*.swift") if f.name != "R28Logic.swift")
    for t in types:
        assert re.search(r"\b%s\." % t, tests), f"kein Test fuer {t}"
        assert not re.search(r"\b(enum|struct|class) %s\b" % t, others), f"Namenskollision {t}"
