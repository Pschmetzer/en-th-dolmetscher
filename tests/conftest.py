"""Gemeinsame Test-Einstellungen: kein Test darf ins echte ~/Library/Logs/Dolmetscher/engine.log schreiben."""
import pytest

import dolmetscher as d


class _NullLogger:
    def info(self, *a, **kw):
        pass

    warning = error = debug = exception = info


@pytest.fixture(autouse=True)
def _no_real_log(monkeypatch):
    """Ersetzt den Datei-Logger der Engine durch einen Null-Logger (wie zuvor in test_pipeline.py)."""
    monkeypatch.setattr(d, "_logger", lambda: _NullLogger())
