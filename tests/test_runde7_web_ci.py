"""CI-Dateien: Aktionen auf Commit-SHA festgelegt, jeder Job mit Zeitlimit (wie CONTRIBUTING.md verspricht)."""
import pathlib
import re

WORKFLOWS = sorted((pathlib.Path(__file__).resolve().parent.parent / ".github" / "workflows").glob("*.yml"))


def test_workflows_exist():
    assert WORKFLOWS


def test_all_actions_pinned_to_sha():
    for wf in WORKFLOWS:
        for n, line in enumerate(wf.read_text(encoding="utf-8").splitlines(), 1):
            m = re.match(r"\s*-?\s*uses:\s*(\S+)", line)
            if m and not m.group(1).startswith("./"):
                assert re.search(r"@[0-9a-f]{40}$", m.group(1)), f"{wf.name}:{n} nicht auf SHA festgelegt: {m.group(1)}"


def test_every_job_has_timeout():
    for wf in WORKFLOWS:
        text = wf.read_text(encoding="utf-8")
        jobs = text.split("\njobs:\n", 1)[1]
        # Jobs beginnen mit zwei Leerzeichen Einrückung und Namen
        blocks = re.split(r"(?m)^  (?=[A-Za-z0-9_-]+:\s*$)", jobs)[1:]
        assert blocks, wf.name
        for b in blocks:
            ok = re.search(r"(?m)^    timeout-minutes:\s*\d+", b)
            assert ok, f"{wf.name}: Job ohne timeout-minutes: {b.splitlines()[0]}"
