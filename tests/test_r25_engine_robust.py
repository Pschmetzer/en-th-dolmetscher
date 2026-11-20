"""Runde 25: Randfälle aus der Code-Durchsicht (Clustering, Textteilung) und die festgehaltenen Schalter-Standards."""
import json
import os
import subprocess
import sys

import numpy as np
import pytest

import dolmetscher as d
import profiles as P

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_cluster_speakers_marks_nan_inf_zero_as_minus_one_and_keeps_rest():
    good = np.ones(4)
    labels = P.cluster_speakers([np.full(4, np.nan), good, np.full(4, np.inf), np.zeros(4), good * 2])
    assert labels == [-1, 0, -1, -1, 0]


def test_cluster_speakers_mixed_dimensions_keep_majority_model():
    labels = P.cluster_speakers([np.ones(4), np.ones(5), np.ones(4) * 3])
    assert labels == [0, -1, 0]


@pytest.mark.parametrize("bad", ["abc", None, [[1, 2], [3]], object()])
def test_cluster_speakers_non_numeric_entries_do_not_raise(bad):
    out = P.cluster_speakers([np.ones(4), bad])
    assert out[0] == 0 and out[1] == -1 and len(out) == 2


def test_cluster_speakers_all_invalid():
    assert P.cluster_speakers([np.zeros(3), np.zeros(3)]) == [-1, -1]


def test_kmeans_centroids_empty_input_is_empty_list():
    assert P.kmeans_centroids([]) == []


def test_extra_centroids_empty_and_short_input():
    assert P.extra_centroids([]) == []


@pytest.mark.parametrize("limit", [1, 2, 3, 0, -5])
def test_chunk_long_tiny_limits_terminate_and_lose_nothing(limit):
    text = "สวัสดีครับ" * 3 + " ok," + "x" * 20
    out = d.chunk_long([text], "th", limit)
    assert "".join(out).replace(" ", "").replace(",", "") == text.replace(" ", "").replace(",", "")
    assert all(out)


def test_chunk_long_default_limit_unchanged_for_normal_text():
    t = "word " * 200
    out = d.chunk_long([t.strip()], "en")
    assert all(len(x) <= d.MAX_SPEAK_CHARS for x in out) and " ".join(out).split() == t.split()


# ---- Schalter-Standards (Runde 25: nach Prüfung bewusst alle aus) ----------------------------------------------------

def _fresh_defaults():
    env = {k: v for k, v in os.environ.items() if k != "DOLMETSCHER_FEATURES"}
    env["PYTHONNOUSERSITE"] = "1"
    code = ("import json, dolmetscher as d; print(json.dumps({'llm_stream': d.LLM['stream'], "
            "'llm_router': d.LLM['router'], 'defer': d.DEFER['on'], 'parallel_alt': d.PARALLEL_ALT['on'], "
            "'stt_prompt': d.STT_PROMPT['on'], 'speak_numbers': d.SPEAK_NUMBER_WORDS['on'], "
            "'group': d.Engine.group_speakers, 'source': d.SOURCE['kind']}))")
    r = subprocess.run([sys.executable, "-c", code], cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr[-300:]
    return json.loads(r.stdout.strip().splitlines()[-1])


def test_runde24_switches_and_runde25_opt_ins_are_off_by_default():
    """Ohne Messung (Benchmarks unter bench/ messen nur Erkennung, nicht Router/Stream/Prompt) bleiben alle Schalter
    aus: Router, stt_prompt und speak_numbers ändern Text oder Ton, parallel_alt konkurriert auf CPU-Macs um
    Rechenzeit, llm_stream/defer ändern Reihenfolge und Fehlerpfade. Ein Schalter wird erst mit Messwert und Test
    umgestellt – dieser Test fällt dann bewusst auf."""
    assert _fresh_defaults() == {"llm_stream": False, "llm_router": False, "defer": False, "parallel_alt": False,
                                 "stt_prompt": False, "speak_numbers": False, "group": False, "source": "mic"}


def test_features_env_still_turns_each_switch_on_and_only_that_switch():
    saved = {"stream": d.LLM["stream"], "router": d.LLM["router"], "defer": d.DEFER["on"]}
    try:
        assert d.apply_features("defer") == ["defer"]
        assert d.DEFER["on"] is True and d.LLM["stream"] is saved["stream"] and d.LLM["router"] is saved["router"]
    finally:
        d.DEFER["on"] = saved["defer"]


def test_bench_has_no_measurement_for_router_stream_or_prompt():
    """Grundlage der Entscheidung: bench/cases.json und run_bench.py kennen die Schalter nicht."""
    with open(os.path.join(ROOT, "bench", "run_bench.py"), encoding="utf-8") as f:
        src = f.read()
    for name in ("llm_router", "llm_stream", "stt_prompt", "speak_numbers", "parallel_alt"):
        assert name not in src


def test_clock_and_number_helpers_share_the_reexported_objects():
    import numwords
    assert d.speak_numbers_th is numwords.speak_numbers_th
