"""Runde 12: CI-Dateien ohne YAML-Parser pruefen (SHA-Pins, Zeitlimits, permissions) und Hilfsskript vorhanden."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = sorted((ROOT / ".github" / "workflows").glob("*.yml"))


def _jobs(text):
    jobs = text.split("\njobs:\n", 1)[1]
    return re.split(r"(?m)^  (?=[A-Za-z0-9_-]+:\s*$)", jobs)[1:]


def test_every_uses_is_a_40_char_sha():
    seen = 0
    for wf in WORKFLOWS:
        for n, line in enumerate(wf.read_text(encoding="utf-8").splitlines(), 1):
            m = re.match(r"\s*-?\s*uses:\s*(\S+)", line)
            if m and not m.group(1).startswith("./"):
                seen += 1
                assert re.fullmatch(r"[\w./-]+@[0-9a-f]{40}", m.group(1)), f"{wf.name}:{n} keine SHA: {m.group(1)}"
    assert seen


def test_every_job_has_timeout():
    for wf in WORKFLOWS:
        for b in _jobs(wf.read_text(encoding="utf-8")):
            ok = re.search(r"(?m)^    timeout-minutes:\s*\d+", b)
            assert ok, f"{wf.name}: {b.splitlines()[0]} ohne timeout-minutes"


def test_permissions_set_and_read_only_by_default():
    for wf in WORKFLOWS:
        text = wf.read_text(encoding="utf-8")
        top = re.search(r"(?m)^permissions:\s*\n((?:  .+\n)+)", text)
        assert top, f"{wf.name}: permissions auf Workflow-Ebene fehlen"
        assert "contents: read" in top.group(1), f"{wf.name}: contents nicht auf read"


def test_pull_request_workflows_cancel_superseded_runs():
    for name in ("ci.yml", "changelog.yml"):
        text = (ROOT / ".github" / "workflows" / name).read_text(encoding="utf-8")
        assert re.search(r"(?m)^concurrency:", text) and "cancel-in-progress: true" in text, name


def test_check_all_script():
    sh = ROOT / "tools" / "check_all.sh"
    text = sh.read_text(encoding="utf-8")
    assert text.startswith("#!/usr/bin/env bash") and "set -euo pipefail" in text
    assert "ruff check ./*.py bench/ tests/" in text and 'pytest -rs -m "not macos"' in text
    assert sh.stat().st_mode & 0o111


def test_makefile_targets():
    text = (ROOT / "Makefile").read_text(encoding="utf-8")
    for target in ("test", "test-web", "web-test", "lint", "check"):
        assert re.search(rf"(?m)^{target}:", text), target
