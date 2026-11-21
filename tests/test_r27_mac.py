"""Runde 27, Mac-App: Abbruch von Schlüsseltest/Selbsttest, Cmd-A der Auswahlleiste, Modifier an Section,
Diagramm-Labels, Aufteilung von Engine.swift, Ausgabegerät je Richtung (nur senden, wenn die Engine es kennt)."""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
SWIFT_TESTS = ROOT / "swift-tests" / "Sources" / "DolmetscherLogic"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_key_tester_is_cancellable():
    s = src("R23SetViews.swift")
    body = s.split("final class KeyTester", 1)[1].split("struct KeyTestRow", 1)[0]
    assert "dataTask" not in body, "Schlüsseltest: Task statt nicht abbrechbarem dataTask"
    assert "func cancel()" in body and "StaleGuard" in body and "task?.cancel()" in body
    assert "isCurrent(token)" in body
    row = s.split("struct KeyTestRow", 1)[1].split("// MARK:", 1)[0]
    assert ".onDisappear { t.cancel() }" in row


def test_self_test_is_cancellable():
    s = src("DiagnosticsView.swift")
    model = s.split("final class SelfTestModel", 1)[1].split("struct SelfTestSheet", 1)[0]
    assert "func cancel()" in model and model.count("isCurrent(token)") >= 2
    assert "monitor?.cancel()" in model
    assert ".onDisappear { model.cancel() }" in s


def test_select_all_does_not_steal_text_field_shortcut():
    for f in APP.glob("*.swift"):
        assert 'keyboardShortcut("a"' not in f.read_text(encoding="utf-8"), f.name
    s = src("R23Views.swift")
    assert "SelectAllKeyMonitor" in s and "NSText" in s
    assert "SelectAllShortcut.shouldSelectBubbles" in s
    assert "removeMonitor" in s and ".onDisappear { keys.stop() }" in s


def test_no_modifiers_on_section():
    """.onAppear/.onReceive/.onDisappear an einer Section greifen je nach Container mehrfach oder nicht:
    an die erste Zeile hängen."""
    bad = []
    for f in sorted(APP.glob("*.swift")):
        lines = f.read_text(encoding="utf-8").splitlines()
        stack = []
        for i, line in enumerate(lines):
            m = re.match(r"^(\s*)Section\b.*\{\s*$", line)
            if m:
                stack.append(len(m.group(1)))
                continue
            for ind in list(stack):
                if re.match(r"^\s{%d}\}( header:.*| footer:.*)?$" % ind, line):
                    stack.remove(ind)
                    nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                    if re.match(r"\.(onAppear|onDisappear|onReceive|task|onChange)\b", nxt):
                        bad.append(f"{f.name}:{i + 2}")
    assert not bad, f"Modifier direkt an Section: {bad}"


def test_every_chart_has_accessibility_label():
    for f in APP.glob("*.swift"):
        lines = f.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if re.search(r"\bChart\(", line):
                window = "\n".join(lines[i : i + 14])
                assert "accessibilityElement(children: .ignore)" in window or "accessibilityLabel" in window \
                    or "chartBlock" in "\n".join(lines[max(0, i - 4) : i + 1]), f"{f.name}:{i + 1}"
    s = src("R23SetViews.swift")
    assert s.count("ChartA11y.values(") >= 2


def test_engine_split_is_wired():
    e = src("Engine.swift")
    assert len(e.splitlines()) < 1990
    for needle in ("EngineProtocolTexts", "EngineLineFramer()", "BubbleTrimLogic.indicesToDrop", "LogTailLogic.tail"):
        assert needle in e, needle
    assert 'static let errorKeys: [String: String] = [' not in e
    assert "discardingLine" not in e and "private var buffer = Data()" not in e


def test_new_logic_files_are_foundation_only_and_linked_in_swift_tests():
    for name in ("EngineProtocolTexts", "EngineLineFramer", "BubbleTrimLogic", "LogTailLogic", "R27Logic"):
        text = src(name + ".swift")
        imports = re.findall(r"^import (\w+)", text, re.M)
        assert imports == ["Foundation"], (name, imports)
        link = SWIFT_TESTS / (name + ".swift")
        assert link.is_symlink() and link.resolve() == (APP / (name + ".swift")).resolve(), name


def test_output_device_per_direction_only_when_engine_knows_it():
    """Solange docs/PROTOKOLL.md `output_device_me` nicht kennt, sendet die App nichts; danach muss sie es senden."""
    doc = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
    all_src = "\n".join(f.read_text(encoding="utf-8") for f in APP.glob("*.swift"))
    if "output_device_me" in doc:
        assert "AudioRouteLogic.protocolFields" in all_src.replace("static func protocolFields", ""), \
            "Engine kennt output_device_me/_other: AudioRouteLogic.protocolFields muss gesendet werden"
    else:
        assert "AudioRouteLogic.protocolFields" not in all_src
