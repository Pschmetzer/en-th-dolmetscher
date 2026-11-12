"""Every event the engine emits must be documented in docs/PROTOKOLL.md."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_all_emitted_events_documented():
    src = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    docs = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
    events = set(re.findall(r'\bemit\(\s*"([a-z_]+)"', src))
    assert events, "no emit() calls found"
    missing = sorted(e for e in events if f"`{e}`" not in docs)
    assert not missing, f"Events missing in docs/PROTOKOLL.md: {missing}"
