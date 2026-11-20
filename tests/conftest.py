"""Gemeinsame Test-Einstellungen: kein echtes Log, kein Backoff-Zustand zwischen Tests."""
import pathlib

import pytest

import dolmetscher as d


# Runde 26: app/Views.swift wurde aufgeteilt (ViewsToolbar.swift, ViewsBanners.swift). Die älteren Quelltext-Tests lesen
# "app/Views.swift" als Ganzes; sie bekommen weiter die drei Teile zusammen (ohne Verhaltensänderung der App).
_orig_read_text = pathlib.Path.read_text


def _read_text(self, *a, **kw):
    text = _orig_read_text(self, *a, **kw)
    if self.name == "Views.swift" and self.parent.name == "app":
        parts = ("ViewsToolbar.swift", "ViewsBanners.swift")
        text += "".join(_orig_read_text(self.parent / n, *a, **kw) for n in parts)
    return text


pathlib.Path.read_text = _read_text


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


@pytest.fixture(autouse=True)
def _glossary_tmp(monkeypatch, tmp_path):
    """Glossar-Lernen (Standard an) schreibt die Glossar-Datei: nie die echte im Nutzerordner."""
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "glossary.txt"))
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", None)           # gehört zu GLOSSARY (steckt im Cache-Schlüssel, _cache_sig)
    monkeypatch.setattr(d.PRESET, "hint", None, raising=False)


@pytest.fixture(autouse=True)
def _llm_spend_tmp(monkeypatch, tmp_path):
    """Claude-Monatskosten nie in die echte Datei schreiben; Zustand je Test frisch."""
    monkeypatch.setattr(d, "LLM_SPEND_FILE", str(tmp_path / "llm_spend.json"))
    monkeypatch.setattr(d, "_SPEND", {"month": None, "usd": 0.0, "warned": None})
    monkeypatch.setitem(d.LLM, "budget", 0.0)


@pytest.fixture(autouse=True)
def _pseud_salt_fixed(monkeypatch):
    """Das Log-Pseudonym nutzt ein Salz aus dem Datenordner: Tests legen nie die echte Datei an."""
    monkeypatch.setattr(d, "_PSEUD_SALT", {"v": "test-salt-0123456789"})
