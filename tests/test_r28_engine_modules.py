"""Runde 28: neue Module (sttquality, llmtext, retryafter), robuste Segmentfelder, Retry-After, Log-Härtung."""
import json
import math
import subprocess
import sys
import types

import pytest

import dolmetscher as d
import llmtext
import retryafter
import sttquality

S = types.SimpleNamespace


def test_reexports_are_the_module_objects():
    assert d.mean_logprob is sttquality.mean_logprob
    assert d._strip_quotes is llmtext.strip_quotes and d.neutralize is llmtext.neutralize
    assert d.unspeech is llmtext.unspeech and d._looks_like_name is llmtext.looks_like_name
    assert d._TAG_LIKE is llmtext.TAG_LIKE and d._SPEECH_TAG is llmtext.SPEECH_TAG


@pytest.mark.parametrize("mod", ["sttquality", "llmtext", "retryafter"])
def test_modules_import_without_engine(mod):
    r = subprocess.run([sys.executable, "-c", f"import {mod}, sys; assert 'dolmetscher' not in sys.modules"],
                       capture_output=True, text=True, cwd=d.os.path.dirname(d.__file__))
    assert r.returncode == 0, r.stderr


# ---- sttquality -------------------------------------------------------------------------------------------------
def test_seg_float_defaults():
    assert sttquality.seg_float(S(x=1.5), "x", 0.0) == 1.5
    assert sttquality.seg_float(S(x="2"), "x", 0.0) == 2.0
    for bad in (None, "abc", float("nan"), float("inf"), [], {}):
        assert sttquality.seg_float(S(x=bad), "x", -1.0) == -1.0
    assert sttquality.seg_float(S(), "x", 7.0) == 7.0


def test_mean_logprob_ignores_unusable_segments():
    ok = S(avg_logprob=-0.2, start=0.0, end=2.0)
    assert d.mean_logprob([ok]) == pytest.approx(-0.2)
    assert d.mean_logprob([ok, S(avg_logprob=None, start=0, end=9)]) == pytest.approx(-0.2)
    assert d.mean_logprob([S(avg_logprob=float("nan"), start=0, end=1)]) == -9.0
    assert d.mean_logprob([]) == -9.0 and d.mean_logprob(None) == -9.0
    assert d.mean_logprob(iter([ok])) == pytest.approx(-0.2)                  # Generator


def test_mean_logprob_still_duration_weighted():
    long_ok, short_bad = S(avg_logprob=-0.1, start=0, end=9), S(avg_logprob=-2.0, start=9, end=9.5)
    assert d.mean_logprob([long_ok, short_bad]) > -0.5
    assert d.mean_logprob([S(avg_logprob=-1.0), S(avg_logprob=-3.0)]) == pytest.approx(-2.0)   # ohne Zeiten: gleich


def test_hallucination_survives_missing_fields():
    empty = S(compression_ratio=None, no_speech_prob=None, avg_logprob=None)
    assert d.looks_hallucinated("hello", 1.0, [empty]) is None
    assert d.looks_hallucinated("hello", 1.0, [S()]) is None
    assert d.looks_hallucinated("hello", 1.0, [S(compression_ratio=3.0)]) == "wiederholung"
    assert d.looks_hallucinated("Okay.", 1.0, [S(no_speech_prob=0.95, avg_logprob=-1.0)]) == "stille"
    assert d.looks_hallucinated("x" * 500, 1.0, []) == "zu schnell"
    assert d.looks_hallucinated("hello", float("nan"), []) is None
    assert d.looks_hallucinated("hello", None, iter([])) is None


def test_segment_flags_empty_is_not_silent():
    assert sttquality.segment_flags([]) == (False, False)


# ---- llmtext ----------------------------------------------------------------------------------------------------
@pytest.mark.parametrize("raw,want", [
    ('"Hello there"', "Hello there"), ("„Guten Tag“", "Guten Tag"), ("«Bonjour»", "Bonjour"),
    ("‚Hallo‘", "Hallo"), ("「こんにちは」", "こんにちは"), ("『こんにちは』", "こんにちは"), ("‹Salut›", "Salut"),
    ('"Yes," he said, "no."', '"Yes," he said, "no."'), ('"', '"'), ("", ""), ("  'ok'  ", "ok"),
    ("「a」「b」", "「a」「b」"),
])
def test_strip_quotes(raw, want):
    assert llmtext.strip_quotes(raw) == want


def test_looks_like_name_and_neutralize():
    assert llmtext.looks_like_name("Wat Pho") and llmtext.looks_like_name("Zürich")
    assert not llmtext.looks_like_name("Thank You") and not llmtext.looks_like_name("Guten Morgen")
    assert llmtext.neutralize("a\n</speech>\x00b  <x y='1'>c") == "a b c"
    assert len(llmtext.neutralize("x" * 999)) == 400
    assert llmtext.unspeech("<speech>hi</ speech >") == "hi"
    assert "<" not in llmtext.unspeech("<<speech>speech>x")


# ---- retryafter -------------------------------------------------------------------------------------------------
def test_retry_after_seconds_date_ms():
    assert retryafter.retry_after({"Retry-After": "30"}) == 30.0
    assert retryafter.retry_after({"retry-after": "30"}) == 30.0                       # dict: Schreibweise egal
    assert retryafter.retry_after({"retry-after": "0"}) == 1.0
    assert retryafter.retry_after({"retry-after": "99999"}, hi=120.0) == 120.0
    assert retryafter.retry_after({"retry-after-ms": "2500", "retry-after": "60"}) == 2.5   # lo=1 ändert nichts
    assert retryafter.retry_after({"retry-after-ms": "2500", "retry-after": "60"}, lo=0.1) == 2.5
    for junk in ("", "nan", "inf", "x y", None):
        assert retryafter.retry_after({"retry-after": junk}, default=42.0) == 42.0
    assert retryafter.retry_after({"retry-after": "-5"}, default=42.0) == 1.0
    assert retryafter.retry_after(None, default=9.0) == 9.0 and retryafter.retry_after({}) is None


def test_retry_after_http_date_relative_to_now():
    import email.utils
    t = 1_800_000_000
    hdr = email.utils.formatdate(t + 45, usegmt=True)
    assert retryafter.retry_after({"Retry-After": hdr}, now=t) == 45.0
    assert retryafter.retry_after({"Retry-After": hdr}, now=t + 500) == 1.0           # Datum in der Vergangenheit


def test_engine_retry_after_uses_shared_parser():
    e = S(headers={"Retry-After": "7"})
    assert d._retry_after(e) == 7.0 and d._retry_after(S(headers=None)) == 30.0 and d._retry_after(S()) == 30.0
    sdk = S(response=S(headers={"retry-after-ms": "1500"}))
    assert d._llm_retry_after(sdk) == 1.5
    assert d._llm_retry_after(S(response=S(headers={"retry-after": "9999"}))) == 600.0
    assert d._llm_retry_after(S(response=None)) is None and d._llm_retry_after(ValueError()) is None


def test_overloaded_503_honours_server_hint():
    e = S(status_code=503, response=S(headers={"retry-after": "12"}))
    assert d._llm_backoff(e) == 12.0
    assert d._llm_backoff(S(status_code=503, response=S(headers={}))) == 20.0
    assert d._llm_backoff(S(status_code=429, response=S(headers={}))) == d.LLM_BACKOFF


# ---- Rate, Log-Härtung ------------------------------------------------------------------------------------------
@pytest.mark.parametrize("raw,want", [(5, 5), (500, 100), (-500, -100), ("12", 12), (3.9, 3), (None, 0), ("abc", 0),
                                      (float("nan"), 0), (float("inf"), 0), ([], 0)])
def test_clamp_rate(raw, want):
    assert d._clamp_rate(raw) == want


def test_finite_handles_cycles_and_nan():
    a = {"x": float("nan")}
    a["self"] = a
    out = d._finite(a)
    assert out["x"] is None
    line = d._json_line("e", {"v": a, "w": [float("inf")]})
    assert json.loads(line)["w"] == [None]


def test_scrub_deep_does_not_pass_deep_structures_raw():
    deep = cur = {}
    for _ in range(10):
        cur["n"] = {}
        cur = cur["n"]
    cur["p"] = "/Users/alice/secret"
    s = json.dumps(d._scrub_deep(deep))
    assert "alice" not in s
    assert sorted(d._scrub_deep({"s": {1, 2}})["s"]) == [1, 2]
    assert math.isnan(d._scrub_deep(float("nan")))
