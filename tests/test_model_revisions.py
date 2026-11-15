"""Modelle werden mit fester Hugging-Face-Revision geladen (Supply-Chain-Schutz) – ohne Download."""
import re

import pytest

import dolmetscher


def test_every_engine_model_has_a_pinned_revision():
    for name in ("small", "medium", "large-v3-turbo", dolmetscher.THAI_MODEL):
        assert re.fullmatch(r"[0-9a-f]{40}", dolmetscher.MODEL_REVISIONS[name]), name


@pytest.mark.parametrize("name", ["small", "medium", "large-v3-turbo", dolmetscher.THAI_MODEL])
def test_wm_passes_revision(monkeypatch, name):
    calls = []
    monkeypatch.setattr(dolmetscher, "WhisperModel", lambda model, **kw: calls.append((model, kw)) or object())
    dolmetscher._wm(name, device="cpu", compute_type="int8")
    assert calls == [(name, {"local_files_only": True, "device": "cpu", "compute_type": "int8",
                             "revision": dolmetscher.MODEL_REVISIONS[name]})]


def test_wm_download_fallback_keeps_revision(monkeypatch):
    calls = []

    def fake(model, **kw):
        calls.append(kw)
        if kw.get("local_files_only"):
            raise RuntimeError("nicht im Cache")
        return object()
    monkeypatch.setattr(dolmetscher, "WhisperModel", fake)
    dolmetscher._wm("medium", device="cpu")
    assert [c["revision"] for c in calls] == [dolmetscher.MODEL_REVISIONS["medium"]] * 2


def test_unknown_model_has_no_revision(monkeypatch):
    calls = []
    monkeypatch.setattr(dolmetscher, "WhisperModel", lambda model, **kw: calls.append(kw) or object())
    dolmetscher._wm("/eigener/pfad", device="cpu")
    assert calls[0]["revision"] is None


def test_build_script_uses_shared_revisions():
    src = open("build.sh", encoding="utf-8").read()
    assert "MODEL_REVISIONS" in src and "biodatlab" not in src
