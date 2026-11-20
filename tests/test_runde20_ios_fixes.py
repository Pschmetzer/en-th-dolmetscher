"""Round 20 (iPhone): Bugfixes ohne Xcode pruefbar (Swift-Tests: xcodebuild test)."""
import pathlib

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def test_live_activity_cleanup_reads_list_synchronously():
    src = _src("Dolmetscher", "LiveActivity.swift")
    init = src[src.index("private init()"):src.index("static let staleMinutes")]
    assert "let leftovers = Activity<ListeningActivityAttributes>.activities" in init
    # die Liste darf nicht erst im Task gelesen werden
    task = init[init.index("Task {"):]
    assert ".activities" not in task


def test_background_tasks_have_expiration_handler():
    for f in ("Model.swift", "WhisperEngine.swift"):
        assert "beginBackgroundTask" not in _src("Dolmetscher", f), f
        assert "BackgroundGrace(name:" in _src("Dolmetscher", f), f
    grace = _src("Dolmetscher", "BackgroundGrace.swift")
    assert "beginBackgroundTask(withName: name) {" in grace
    assert "endBackgroundTask" in grace
