"""Benchmark-Werkzeuge ohne Modelle/Netz (Nr. 163, 164, 210, 211, 212, 216): Metriken, Regressionsprüfung,
Negativfälle, Zustand zwischen Fällen."""
import importlib.util
import json
import pathlib
import types

import numpy as np
import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BENCH = ROOT / "bench"


def _load(name):
    spec = importlib.util.spec_from_file_location(f"bench_{name}", BENCH / f"{name}.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


rb = _load("run_bench")
rt = _load("run_translate")
ma = _load("make_audio")


# --- 216: Metriken -----------------------------------------------------------------------------------

@pytest.mark.parametrize("words,digits", [("สามร้อย", "300"), ("สองพันห้าร้อย", "2500"), ("ยี่สิบเอ็ด", "21"),
                                          ("หนึ่งหมื่น", "10000")])
def test_thai_zahlwoerter(words, digits):
    assert rb.th_numbers_to_digits(words) == digits


def test_fehlerraten():
    assert rb.error_rate("Where is the station?", "where is the station", "en") == 0
    assert rb.error_rate("I have two cats", "I have 2 cats", "en") == 0            # Zahlwort = Ziffer
    assert rb.error_rate("a b c d", "a b x d", "en") == 0.25
    assert rb.error_rate("ราคาสามร้อยบาท", "ราคา 300 บาท", "th") == 0
    assert rb.error_rate("ไปไหม", "ไปมั้ย", "th") == 0


def test_pct():
    assert rb.pct([1, 2, 3, 4], 0.5) == 2.5 and rb.pct([5], 0.9) == 5


# --- 211/212: Regression ------------------------------------------------------------------------------

def _doc(**en):
    base = {"n": 14, "lang_acc": 1.0, "exact": 10, "err_mean": 0.05, "stt_mean_s": 1.0, "dropped": 0,
            "total_median_s": 2.0}
    base.update(en)
    return {"summary": {"en": base}}


def test_regression_ignoriert_netzzeit():
    assert rb.regressions(_doc(total_median_s=5.0), _doc(), 10) == []          # nur Netz langsamer
    bad = rb.regressions(_doc(stt_mean_s=1.5), _doc(), 10)
    assert bad and bad[0].startswith("en.stt_mean_s")


def test_regression_basis_null_kein_unendlich():
    assert rb.regressions(_doc(dropped=1), _doc(dropped=0), 10) == []         # eine Kleinigkeit
    bad = rb.regressions(_doc(dropped=3), _doc(dropped=0), 10)
    assert bad == ["en.dropped: 0 -> 3 (vorher 0, n=14)"]


def test_regression_mindestabweichung():
    assert rb.regressions(_doc(err_mean=0.055), _doc(err_mean=0.05), 5) == []   # +0,5 Punkte: Rauschen
    assert rb.regressions(_doc(err_mean=0.08), _doc(err_mean=0.05), 5)


def test_regression_negativfaelle():
    cur = {"summary": {"neg": {"n": 9, "false_accept": 2, "dropped": 7}}}
    old = {"summary": {"neg": {"n": 9, "false_accept": 0, "dropped": 9}}}
    assert any(b.startswith("neg.false_accept") for b in rb.regressions(cur, old, 10))


# --- 163: Negativfälle -------------------------------------------------------------------------------

def test_negativfaelle_definiert_und_erzeugbar():
    cases = json.loads((BENCH / "negatives.json").read_text(encoding="utf-8"))
    kinds = {c["kind"] for c in cases}
    assert {"silence", "pink", "music", "cough", "foreign"} <= kinds
    assert len({c["id"] for c in cases}) == len(cases)
    for c in cases:
        if c["kind"] == "foreign":
            assert c["text"] and c["voice"]
            continue
        x = ma.negative_signal(c)
        assert x.dtype == np.float32 and x.size == int(c["dur"] * ma.SR) and np.max(np.abs(x)) <= 1.0
        assert np.array_equal(x, ma.negative_signal(c))                          # reproduzierbar


def test_negativ_auswertung():
    rows = [{"accepted": False, "dropped_code": "other_language"}, {"accepted": True, "dropped_code": None},
            {"accepted": False, "dropped_code": "too_short"}]
    s = rb.summarize_negatives(rows)
    assert s == {"n": 3, "false_accept": 1, "dropped": 2, "codes": {"other_language": 1, "too_short": 1}}
    assert rb.summarize_negatives([]) is None


def test_run_negative_zaehlt_utt_als_fehlalarm():
    cap = rb.Capture()

    class Eng:
        def process(self, audio, speak=False):
            cap.emit("utt", text="Thank you.", lang="en")
    r = rb.run_negative(Eng(), cap, {"id": "neg_x", "kind": "pink"}, np.zeros(10, np.float32), True)
    assert r["accepted"] and r["hyp"] == "Thank you."


# --- 210: Zustand zwischen Fällen ----------------------------------------------------------------------

def test_reset_state_vollstaendig():
    eng = types.SimpleNamespace(history=[("en", "a", "b")], _hist_ids={"u1": 1}, texts={"u1": 1}, last=("x",),
                                last_role=("me", 1.0), paused=True, translate_dir={})
    cleared = []
    d = types.SimpleNamespace(_cache_clear=lambda: cleared.append(1),
                              PRESET=types.SimpleNamespace(active="taxi"),
                              set_preset=lambda e, p, quiet=False: cleared.append(p))
    rb.reset_state(eng, False, d)
    assert eng.history == [] and eng._hist_ids == {} and eng.texts == {} and eng.last is None
    assert eng.last_role is None and eng.paused is False and cleared == [1, None]


# --- 164: Übersetzung automatisch bewerten -----------------------------------------------------------

def test_chrf():
    assert rt.chrf("hello world", "hello world") == 100.0
    assert rt.chrf("hello world", "") == 0.0
    a = rt.chrf("I'm very sleepy", "I am very sleepy")
    b = rt.chrf("I'm very sleepy", "the train is late")
    assert 50 < a < 100 and b < 30
    assert rt.chrf("ฉันง่วงนอน", "ฉันง่วงนอนมาก") > 60                             # Thai ohne Leerzeichen


def test_namen_und_bewertung():
    assert rt.names_kept("Meet Somchai at the Hilton", "พบ Somchai ที่ Hilton") is True
    assert rt.names_kept("Meet Somchai at the Hilton", "พบสมชายที่ฮิลตัน") is False
    assert rt.names_kept("see you later", "แล้วเจอกัน") is None
    s = rt.score("That costs 350 baht", "en", "ราคา 530 บาท", "That costs 530 baht")
    assert s["num_ok"] is False and s["rt_chrf"] > 50
    agg = rt.aggregate([dict(s, secs=1.0), dict(rt.score("ok", "en", "โอเค", None), secs=3.0)])
    assert agg["n"] == 2 and agg["num_ok"] == 0.5 and agg["secs_median"] == 2.0 and agg["rt_chrf"] == s["rt_chrf"]
