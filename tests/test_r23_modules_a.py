"""Runde 23: profiles, hwprofile, avhelper, correction_learning."""
import os
import sys
import time

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import avhelper  # noqa: E402
import correction_learning as CL  # noqa: E402
import hwprofile  # noqa: E402
import profiles as P  # noqa: E402


@pytest.fixture
def home(tmp_path, monkeypatch):
    monkeypatch.setattr(P, "PROFILE_DIR", str(tmp_path / "profiles"))
    monkeypatch.setattr(P, "_CLEANED", [True])
    return tmp_path


def unit(*xs):
    v = np.array(xs, dtype=np.float32)
    return v / np.linalg.norm(v)


def make_spk(profs):
    spk = P.SpeakerID.__new__(P.SpeakerID)
    spk.reload()
    for p in profs:
        P.save_profile(p)
    spk.reload()
    return spk


def prof(name, lang, emb, created="2026-01-01T00:00:00Z", **kw):
    return {"name": name, "lang": lang, "created": created, "embedding": [float(x) for x in emb],
            "embedding_model": P.EMBED_MODEL_ID, **kw}


# ---------------- profiles
def test_pair_from_langs_validates():
    assert P.pair_from_langs("DE", " th ") == ("de", "th")
    for bad in (("en", "en"), ("", "th"), ("e", "th"), (None, "th"), ("en", "t h")):
        with pytest.raises(ValueError):
            P.pair_from_langs(*bad)


def test_me_partner_follow_language_pair(home):
    spk = make_spk([prof("A", "de", unit(1, 0, 0, 0)), prof("B", "fr", unit(0, 1, 0, 0)),
                    prof("C", "en", unit(0, 0, 1, 0))])
    assert spk.me()["name"] == "C"           # Standard en/th
    assert spk.partner() is None
    assert spk.set_pair("de", "fr") == ("de", "fr")
    assert spk.me()["name"] == "A" and spk.partner()["name"] == "B"
    spk2 = make_spk([])
    assert spk2.pair == ("en", "th")          # Klassenstandard bleibt unberührt


def test_kmeans_two_clusters():
    a = [unit(1, 0.1 * i, 0) for i in range(4)]
    b = [unit(0, 1, 0.1 * i) for i in range(3)]
    cents = P.kmeans_centroids(a + b, 2)
    assert [n for _, n in cents] == [4, 3]
    assert float(cents[0][0] @ unit(1, 0.15, 0)) > 0.99


def test_kmeans_identical_embeddings_single_centroid():
    cents = P.kmeans_centroids([unit(1, 2, 3)] * 5, 2)
    assert len(cents) == 1 and cents[0][1] == 5


def test_extra_centroids_only_for_distinct_clusters():
    same = [unit(1, 0.01 * i, 0) for i in range(8)]
    assert P.extra_centroids(same) == []
    assert P.extra_centroids(same[:3]) == []                       # zu wenige
    two = [unit(1, 0.05 * i, 0) for i in range(4)] + [unit(0, 1, 0.05 * i) for i in range(4)]
    ex = P.extra_centroids(two)
    assert len(ex) == 2 and len(ex[0]) == 3
    lopsided = [unit(1, 0.05 * i, 0) for i in range(7)] + [unit(0, 1, 0)]
    assert P.extra_centroids(lopsided) == []                       # Gruppe mit nur 1 Satz zählt nicht


def test_extra_centroid_improves_match_and_main_unchanged(home):
    main = unit(1, 0, 0, 0)
    other = unit(0, 1, 0, 0)
    p = prof("Anna", "en", main, embedding_extra=[[float(x) for x in other]])
    spk = make_spk([p])
    assert spk._sim(spk.profiles[0], other) == pytest.approx(1.0, abs=1e-5)
    p2 = {k: v for k, v in p.items() if k != "embedding_extra"}
    assert spk._sim(p2, other) == pytest.approx(0.0, abs=1e-5)


def test_extra_ignores_wrong_shape(home):
    spk = make_spk([prof("Anna", "en", unit(1, 0, 0, 0), embedding_extra=[[1.0, 2.0], "x", None])])
    assert spk._sim(spk.profiles[0], unit(1, 0, 0, 0)) == pytest.approx(1.0, abs=1e-5)


def test_identify_uses_extra_centroid(home):
    a = prof("A", "en", unit(1, 0, 0, 0), embedding_extra=[[0.0, 1.0, 0.0, 0.0]])
    b = prof("B", "th", unit(0, 0, 1, 0))
    spk = make_spk([a, b])
    audio = np.zeros(int(P.SR * 2), dtype=np.float32)
    got, sim, _ = spk.identify(audio, emb=lambda: unit(0, 1, 0, 0))
    assert got["name"] == "A" and sim > 0.99


def test_learn_async_runs_in_background_and_flushes(home):
    e = unit(1, 0.05, 0, 0)
    spk = make_spk([prof("Anna", "en", unit(1, 0, 0, 0))])
    results = []
    assert spk.learn_async("Anna", e, 0.1, done=results.append) is True
    assert spk.flush_learning(5.0)
    assert results == [True]
    assert P.get_profile("Anna")["adapted"] == 1


def test_learn_async_swallows_errors(home):
    spk = make_spk([prof("Anna", "en", unit(1, 0, 0, 0))])
    got = []
    spk.learn_async("Unbekannt", unit(1, 0, 0, 0), 0.1, done=got.append)
    assert spk.flush_learning(5.0) and got == [False]


def test_learn_async_does_not_block_caller(home, monkeypatch):
    spk = make_spk([prof("Anna", "en", unit(1, 0, 0, 0))])
    monkeypatch.setattr(spk, "learn", lambda *a: time.sleep(0.3) or True)
    t0 = time.monotonic()
    spk.learn_async("Anna", unit(1, 0, 0, 0), 0.1)
    assert time.monotonic() - t0 < 0.15
    assert spk.flush_learning(5.0)


def test_speaker_delete_removes_and_reloads(home):
    spk = make_spk([prof("Anna", "en", unit(1, 0, 0, 0)), prof("Ben", "th", unit(0, 1, 0, 0))])
    assert spk.delete("Anna") is True
    assert [p["name"] for p in spk.profiles] == ["Ben"]
    assert spk.delete("Anna") is False


def test_rename_profile(home):
    P.save_profile(prof("Anna", "en", unit(1, 0, 0, 0), vocab=["Chiang Mai"]))
    p = P.rename_profile("Anna", "Annika")
    assert p["name"] == "Annika"
    assert P.get_profile("Anna") is None and P.get_profile("Annika")["vocab"] == ["Chiang Mai"]
    P.save_profile(prof("Ben", "en", unit(0, 1, 0, 0)))
    with pytest.raises(FileExistsError):
        P.rename_profile("Ben", "Annika")
    with pytest.raises(KeyError):
        P.rename_profile("Nope", "X")
    with pytest.raises(P.ProfileNameError):
        P.rename_profile("Ben", "!!!")
    assert P.rename_profile("Ben", "Ben")["name"] == "Ben"


def test_extras_not_public():
    p = prof("A", "en", unit(1, 0), embedding_extra=[[1.0, 0.0]])
    assert "embedding_extra" not in P.public(p)


# ---------------- hwprofile
def test_quick_benchmark_counts_blocks_with_fake_clock():
    t = [0.0]

    def clock():
        t[0] += 0.01
        return t[0]
    score = hwprofile.quick_benchmark(budget_s=0.1, clock=clock, work=lambda: None)
    assert score > 0


def test_quick_benchmark_never_raises():
    def boom():
        raise RuntimeError("x")
    assert hwprofile.quick_benchmark(work=boom) == 1.0


def test_quick_benchmark_real_run_is_short_and_positive():
    t0 = time.monotonic()
    s = hwprofile.quick_benchmark(0.05)
    assert 0 < s < 1000 and time.monotonic() - t0 < 1.0


def test_bench_tier_boundaries():
    assert hwprofile.bench_tier(0.1) == "slow"
    assert hwprofile.bench_tier(1.0) == "normal"
    assert hwprofile.bench_tier(2.5) == "fast"


def test_refine_with_benchmark_downgrades_only_when_slow():
    rec = {"model": "best", "beam": 5, "reason": "x"}
    assert hwprofile.refine_with_benchmark(rec, 1.0) == rec
    slow = hwprofile.refine_with_benchmark(rec, 0.1)
    assert slow["model"] == "medium" and slow["beam"] == 1 and rec["model"] == "best"
    assert hwprofile.refine_with_benchmark({"model": "small", "beam": 1, "reason": ""}, 0.1)["model"] == "small"


# ---------------- avhelper
def test_explain_error_variants():
    assert "permission" in avhelper.explain_error(PermissionError())
    assert avhelper.explain_error(FileNotFoundError()) == "file not found"
    assert "busy" in avhelper.explain_error(OSError("Device or resource busy"))
    assert avhelper.explain_error(ValueError()) == "ValueError"


def test_check_file(tmp_path):
    assert avhelper.check_file("") == "no file given"
    assert avhelper.check_file(str(tmp_path / "x.wav")) == "file not found"
    assert "directory" in avhelper.check_file(str(tmp_path))
    f = tmp_path / "a.wav"
    f.write_bytes(b"")
    assert avhelper.check_file(str(f)) == "file is empty"
    f.write_bytes(b"RIFF")
    assert avhelper.check_file(str(f)) is None


def test_validate_af():
    assert avhelper.validate_af("highpass=f=80,volume=6dB") == []
    assert avhelper.validate_af("") == []
    assert avhelper.validate_af("high pass=1") == ["high pass"]
    assert avhelper.validate_af("volume@v=2, ;rm=x") == [";rm"]
    assert avhelper.validate_af("=5") == ["=5"]


def test_main_rejects_bad_filter_chain(capsys):
    with pytest.raises(SystemExit) as e:
        avhelper.main(["capture", "--af", "bad name=1"])
    assert e.value.code == 2
    assert "--af" in capsys.readouterr().err


def test_main_turns_unexpected_exception_into_one_line(monkeypatch):
    monkeypatch.setattr(avhelper, "list_devices", lambda a: (_ for _ in ()).throw(PermissionError()))
    with pytest.raises(SystemExit) as e:
        avhelper.main(["list"])
    assert "permission denied" in str(e.value.code)


def test_capture_missing_file_message(tmp_path, monkeypatch):
    import types
    monkeypatch.setattr(avhelper, "_av", lambda: types.SimpleNamespace(AudioResampler=lambda **k: None))
    a = type("A", (), {"af": "", "rate": 16000, "file": str(tmp_path / "none.wav"), "loop": False,
                       "realtime": False, "device": None})()
    with pytest.raises(SystemExit) as e:
        avhelper.capture(a)
    assert "cannot open file: file not found" in str(e.value.code)


def test_av_missing_is_clean_exit(monkeypatch):
    import builtins
    real = builtins.__import__

    def fake(name, *a, **k):
        if name == "av":
            raise ImportError("no av")
        return real(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", fake)
    with pytest.raises(SystemExit) as e:
        avhelper._av()
    assert "not installed" in str(e.value.code)


# ---------------- correction_learning
def test_confusion_pairs_one_to_one():
    assert CL.confusion_pairs("go to chang my tomorrow", "go to Chiang Mai tomorrow") == \
        [("chang", "Chiang"), ("my", "Mai")]


def test_confusion_pairs_span_and_skips_numbers_and_case():
    assert CL.confusion_pairs("the new hotel", "the Nuvo Hotel") == [("new", "Nuvo")]
    assert CL.confusion_pairs("pay 5 baht", "pay 6 baht") == []
    assert CL.confusion_pairs("Hello there", "hello there") == []
    assert CL.confusion_pairs("a b c d e f g h", "x y z") == []          # Strecke zu lang


def test_confusion_map_counts_and_threshold():
    m = CL.ConfusionMap()
    m.add("see you at phuket", "see you at Phuket!")
    assert m.top() == []                                                  # einmal reicht nicht
    m.add("to phuquet", "to Phuket")
    m.add("fly to phuquet today", "fly to Phuket today")
    assert m.top() == [("phuquet", "Phuket", 2)]
    assert m.best("PHUQUET") == "Phuket" and m.best("phuquet", min_count=3) is None


def test_confusion_map_apply_whole_words_only():
    m = CL.ConfusionMap()
    for _ in range(2):
        m.add("send the cat now", "send the cut now")
    assert m.apply("Cat catalog CAT") == "cut catalog cut"


def test_confusion_map_roundtrip_and_bad_input():
    m = CL.ConfusionMap()
    for _ in range(2):
        m.add("a chang b", "a Chiang b")
    m2 = CL.ConfusionMap.from_dict(m.to_dict())
    assert m2.counts == m.counts
    assert CL.ConfusionMap.from_dict({"pairs": [["a"], [1, 2, 3], ["x", "y", -1], ["x", "y", 2]]}).counts == \
        {("x", "y"): 2}
    assert CL.ConfusionMap.from_dict(None).counts == {}


def test_confusion_map_is_capped():
    m = CL.ConfusionMap()
    for i in range(CL.MAX_CONFUSIONS + 20):
        m.counts[("w%d" % i, "r")] = 1
    m.counts[("keep", "me")] = 9
    m.add("aaa bbb", "ccc ddd")
    assert len(m.counts) <= CL.MAX_CONFUSIONS and ("keep", "me") in m.counts


def test_name_alignment_multiword_and_single():
    assert CL.name_alignment("we go to chang my soon", "we go to Chiang Mai soon") == [("chang my", "Chiang Mai")]
    assert CL.name_alignment("ask somchai please", "ask Somchai please") == []     # nur Schreibweise: nichts zu lernen
    assert CL.name_alignment("meet sam chi tomorrow", "meet Somchai tomorrow") == [("sam chi", "Somchai")]


def test_name_alignment_thai_and_no_name():
    assert CL.name_alignment("ไปเชียงใหม่", "ไปภูเก็ต", "th") == []
    assert CL.name_alignment("we like it", "we love it") == []
