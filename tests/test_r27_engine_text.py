"""Runde 27: Auslagerung (textnorm, Satzteilung), Thai-Uhrzeiten mit Minuten, Pronomen und Partikel-Korpus."""
import json
import pathlib
import subprocess
import sys

import pytest

import dolmetscher as d
import textnorm
import textsplit
import thaiparticles
from thaiparticles import fit_thai_particles

ROOT = pathlib.Path(__file__).resolve().parent.parent


# ---- Auslagerung mit Re-Export -------------------------------------------------------------------------------------
def test_reexports_are_the_same_objects():
    assert d._norm is textnorm._norm and d.squash_repeats is textnorm.squash_repeats
    assert d._TH_RX is textnorm._TH_RX and d._NORM_QUOTES is textnorm._NORM_QUOTES and d._TH_GAP is textnorm._TH_GAP
    assert d._rejoin_abbrev is textsplit._rejoin_abbrev and d._ABBREV is textsplit._ABBREV
    assert d._ABBREV_NUM is textsplit._ABBREV_NUM


def test_textnorm_imports_without_engine():
    r = subprocess.run([sys.executable, "-c", "import textnorm, textsplit; print(textnorm._norm('A  B.'))"],
                       cwd=ROOT, capture_output=True, text=True, env={"PYTHONNOUSERSITE": "1", "PATH": ""})
    assert r.returncode == 0 and r.stdout.strip() == "a b"


@pytest.mark.parametrize("raw,want", [
    ("It’s  OK .", "it's ok"), ("Hello,  World。", "hello world"), ("1.5 ?!", "1.5?"), ("", ""),
    ("geht's ? !", "geht's?"), ("ครับ  ครับบบ", "ครับครับ"), ("สวัสดี ครับ", "สวัสดีครับ"), ("1,5 kg", "1,5 kg"),
    ("“Quote” – dash", '"quote" - dash'), ("A B", "a b"), ("What?", "what?"), ("what.", "what"),
])
def test_norm_cases(raw, want):
    assert textnorm._norm(raw) == want


def test_norm_question_differs_from_statement():
    assert d._norm("Is it ready?") != d._norm("Is it ready.")


@pytest.mark.parametrize("raw,want", [
    ("ha ha ha ha ha ha", "ha ha ha"), ("สติ๊กฮ่าาาาาาา", "สติ๊กฮ่าาา"), ("0808080808", "0808080808"),
    ("normal sentence", "normal sentence"), ("", ""),
])
def test_squash_repeats(raw, want):
    assert textnorm.squash_repeats(raw) == want


def test_rejoin_abbrev():
    assert textsplit._rejoin_abbrev(["Mr.", "Smith came."]) == ["Mr. Smith came."]
    assert textsplit._rejoin_abbrev(["Call no.", "5 now."]) == ["Call no. 5 now."]
    assert textsplit._rejoin_abbrev(["No.", "I don't."]) == ["No.", "I don't."]
    assert textsplit._rejoin_abbrev(["It ended.", "then more"]) == ["It ended. then more"]


def test_split_sentences_keeps_decimals_and_abbrev():
    out = d.split_sentences("Pay 3.5 baht. Then 10:30 a.m. Go now! ok", "en", 10)
    assert "".join(out).replace(" ", "") == "Pay3.5baht.Then10:30a.m.Gonow!ok"
    assert any("3.5" in p for p in out)


def test_build_and_pyproject_list_textnorm():
    assert "textnorm.py" in (ROOT / "build.sh").read_text(encoding="utf-8")
    assert '"textnorm"' in (ROOT / "pyproject.toml").read_text(encoding="utf-8")


# ---- Thai-Uhrzeit mit Minuten ---------------------------------------------------------------------------------------
@pytest.mark.parametrize("text,want", [
    ("นัด สี่โมงสิบห้านาที", ["4.15"]), ("สามทุ่มห้านาที", ["21.05"]), ("บ่ายสองโมงสี่สิบห้านาที", ["14.45"]),
    ("บ่ายสองโมง 5 นาที", ["14.05"]), ("เจ็ดโมงเช้าสามสิบนาที", ["7.30"]), ("สี่โมงเย็นครึ่ง", ["16.30"]),
    ("ตีสาม", ["3"]),
])
def test_numbers_thai_clock_with_minutes(text, want):
    assert d._numbers(text) == want


def test_no_false_number_warning_for_thai_minutes():
    assert d.numbers_differ("นัด สี่โมงสิบห้านาที", "The meeting is at 4:15") is False
    assert d.numbers_differ("นัด สามทุ่มห้านาที", "at 21:05") is False
    assert d.numbers_differ("นัด สามทุ่มห้านาที", "at 21:15") is True


@pytest.mark.parametrize("text,want", [
    ("สามทุ่มห้านาที", "21:05"), ("ตีหนึ่งยี่สิบเอ็ดนาที", "01:21"), ("บ่ายสองโมง 5 นาที", "14:05"),
    ("บ่ายสองโมงสี่สิบห้านาที", "14:45"), ("เจ็ดโมงเช้าสามสิบนาที", "07:30"), ("ตีสาม", "03:00"),
    ("สี่โมงเย็นครึ่ง", "16:30"), ("ตีสามหกสิบนาที", "03:00 หกสิบนาที"), ("สองโมง", "สองโมง"),
])
def test_th_times_for_mt_minutes(text, want):
    assert d.th_times_for_mt(text) == want


@pytest.mark.parametrize("tok,want", [
    ("สิบ", 10), ("สิบห้า", 15), ("ยี่สิบ", 20), ("ยี่สิบเอ็ด", 21), ("สามสิบ", 30), ("สี่สิบห้า", 45), ("ห้า", 5),
    ("5", 5), ("59", 59), ("60", None), ("", None), (None, None), ("หกสิบ", None), ("abc", None), ("สิบเอ็ด", 11),
])
def test_th_minutes(tok, want):
    assert d.th_minutes(tok) == want


def test_hmm_rejects_invalid():
    import re
    m = re.match(r".*", "x")
    assert d._hmm(10, "75", m) == "x"
    assert d._hmm(18 + 9, "5", m) == " 3:05 "


# ---- Partikel und Pronomen: Testkorpus -----------------------------------------------------------------------------
KORPUS = [
    # (Text, polite, erwartet)
    ("ขอบคุณค่ะ", "krub", "ขอบคุณครับ"), ("ขอบคุณครับ", "ka", "ขอบคุณค่ะ"), ("ไปไหนครับ", "ka", "ไปไหนคะ"),
    ("ได้ค่ะ ไม่เป็นไรนะคะ", "krub", "ได้ครับ ไม่เป็นไรนะครับ"), ("สวัสดีค่ะ", "ka", "สวัสดีค่ะ"),
    ("สวัสดีครับ", "krub", "สวัสดีครับ"), ("ได้คะแนนดี", "krub", "ได้คะแนนดี"), ("บังคับใช้กฎ", "ka", "บังคับใช้กฎ"),
    ("ผักคะน้าราคาเท่าไรคะ", "krub", "ผักคะน้าราคาเท่าไรครับ"), ("ดิฉันชื่อแอนค่ะ", "krub", "ผมชื่อแอนครับ"),
    ("กระผมชื่อสมชายครับ", "ka", "ดิฉันชื่อสมชายค่ะ"), ("ผมชื่อสมชายครับ", "ka", "ผมชื่อสมชายค่ะ"),
    ("ดิฉันชื่อแอนค่ะ", "ka", "ดิฉันชื่อแอนค่ะ"), ("ดิฉันเห็นว่า ผมครับ", "krub", "ดิฉันเห็นว่า ผมครับ"),
    ("เส้นผมดิฉันยาวค่ะ", "krub", "เส้นผมผมยาวครับ"), ("", "krub", ""), ("ดิฉันค่ะ", "", "ดิฉันค่ะ"),
    ("ดิฉันค่ะ", "xx", "ดิฉันค่ะ"), ("ครับผม", "ka", "ค่ะ"), ("ค่ะค่ะ", "krub", "ครับครับ"),
    ("hello ค่ะ world", "krub", "hello ครับ world"), ("ใช่ไหมครับ", "ka", "ใช่ไหมคะ"), ("ขอบคุณค่ะ ครับ", "ka", "ขอบคุณค่ะ ครับ"),
]


@pytest.mark.parametrize("text,polite,want", KORPUS)
def test_particle_corpus(text, polite, want):
    assert fit_thai_particles(text, polite) == want


def test_fit_is_idempotent():
    for text, polite, _ in KORPUS:
        once = fit_thai_particles(text, polite)
        assert fit_thai_particles(once, polite) == once


def test_pronoun_none_input():
    assert fit_thai_particles(None, "krub") is None


def test_dolmetscher_uses_new_fit():
    assert d.fit_thai_particles is thaiparticles.fit_thai_particles


# ---- Benchmark-Ergebnisse -----------------------------------------------------------------------------------------
def test_micro_bench_results_recorded():
    data = json.loads((ROOT / "bench" / "results" / "micro_r27.json").read_text(encoding="utf-8"))
    us = data["us_per_call"]
    for k in ("norm_warm_us", "norm_cold_us", "split_en_us", "split_th_us", "cache_put_us", "cache_get_hit_us"):
        assert us[k] > 0


def test_micro_bench_runs_small():
    r = subprocess.run([sys.executable, str(ROOT / "bench" / "micro_bench.py"), "--n", "100"], cwd=ROOT,
                       capture_output=True, text=True, timeout=120, env={"PYTHONNOUSERSITE": "1", "PATH": ""})
    assert r.returncode == 0, r.stderr[-300:]
    assert json.loads(r.stdout)["us_per_call"]["cache_get_hit_us"] > 0
