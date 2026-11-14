"""Gemeinsame Test-Einstellungen: kein echtes Log, kein Backoff-Zustand zwischen Tests."""
import pytest

import dolmetscher as d


class _NullLogger:
    def info(self, *a, **kw):
        pass

    warning = error = debug = exception = info


@pytest.fixture(autouse=True)
def _no_real_log(monkeypatch):
    """Ersetzt den Datei-Logger der Engine durch einen Null-Logger."""
    monkeypatch.setattr(d, "_logger", lambda: _NullLogger())


@pytest.fixture(autouse=True)
def _reset_net_backoff():
    """Anbieter-Backoff/Offline-Schalter (Modulzustand) darf nicht zwischen Tests lecken."""
    d.reset_net_backoff()
    yield
    d.reset_net_backoff()
