"""Runde 24 (Module): satzbuch-Bericht und Ordnerprüfung, Sprecher-Clustering, Loopback-Erkennung, verschlüsselter
Verlaufsexport, Latenzbudget, Pages-Smoke-Drift, ConfusionMap.apply in einem Durchlauf."""
import importlib.util
import io
import json
import pathlib

import numpy as np
import pytest

import avhelper
import correction_learning as cl
import history_store as hs
import profiles as P
import satzbuch

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load(rel, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


lb = _load("bench/latency_budget.py", "latency_budget")
smoke = _load("tools/pages_smoke.py", "pages_smoke_r24")


# ---- satzbuch ----------------------------------------------------------------------------------------------------
def _pack(folder, pid, phrases):
    (folder / f"{pid}.json").write_text(json.dumps({
        "id": pid, "names": {"de": "D", "en": "E", "th": "ท"}, "style": "neutral",
        "phrases": phrases, "glossary": []}, ensure_ascii=False), encoding="utf-8")


def test_satzbuch_fehlender_ordner_ist_fehler(tmp_path):
    f = satzbuch.check(tmp_path / "gibtsnicht")
    assert [x["code"] for x in f] == ["dir"] and satzbuch.summary(f)["error"] == 1
    assert satzbuch.main(["check", "--dir", str(tmp_path / "gibtsnicht")], io.StringIO()) == 1


def test_satzbuch_leerer_ordner_ist_fehler(tmp_path):
    assert [x["code"] for x in satzbuch.check(tmp_path)] == ["empty"]
    assert satzbuch.main(["export", "csv", "--dir", str(tmp_path)], io.StringIO()) == 2


def test_satzbuch_report_zaehlt_nach_code_und_paket(tmp_path):
    _pack(tmp_path, "aa", [{"en": "Hello", "th": "สวัสดี"}, {"en": "hello", "th": "สวัสดีครับ"}])
    _pack(tmp_path, "bb", [{"en": "Thanks", "th": "ขอบคุณ", "critical": True}])
    rep = satzbuch.report(tmp_path)
    assert rep["packs"] == 2 and rep["size"]["bb"] == {"phrases": 1, "critical": 1, "glossary": 0}
    assert rep["by_pack"]["aa"]["warning"] + rep["by_pack"]["aa"]["error"] >= 1
    md = satzbuch.format_report(rep)
    assert md.startswith("# Satzbuch-Prüfbericht") and "## Umfang" in md and "3 Sätze (1 kritisch)" in md


def test_satzbuch_report_cli_json_und_datei(tmp_path):
    _pack(tmp_path, "aa", [{"en": "Hello", "th": "สวัสดี"}])
    out = io.StringIO()
    assert satzbuch.main(["report", "--dir", str(tmp_path), "--json"], out) == 0
    assert json.loads(out.getvalue())["packs"] == 1
    target = tmp_path / "bericht.md"
    assert satzbuch.main(["report", "--dir", str(tmp_path), "-o", str(target)], io.StringIO()) == 0
    assert "Satzbuch-Prüfbericht" in target.read_text(encoding="utf-8")


def test_satzbuch_filter_ignore_und_pack():
    fs = [{"severity": "warning", "pack": "a", "code": "x", "message": "", "where": None},
          {"severity": "warning", "pack": "b", "code": "y", "message": "", "where": None}]
    assert [f["code"] for f in satzbuch.filter_findings(fs, ignore=["x"])] == ["y"]
    assert [f["pack"] for f in satzbuch.filter_findings(fs, packs=["a"])] == ["a"]
    assert satzbuch.filter_findings(fs) == fs


# ---- Sprecher-Clustering --------------------------------------------------------------------------------------
def _groups(sizes, seed=3, noise=0.08, dim=64):
    rng = np.random.default_rng(seed)
    cents = [rng.normal(size=dim) for _ in sizes]
    embs, truth = [], []
    for k, n in enumerate(sizes):
        for _ in range(n):
            embs.append(cents[k] + noise * rng.normal(size=dim))
            truth.append(k)
    order = rng.permutation(len(embs))
    return [embs[i] for i in order], [truth[i] for i in order]


def _same_partition(a, b):
    pairs = {(x, y) for x, y in zip(a, b)}
    return len({x for x, _ in pairs}) == len(pairs) == len({y for _, y in pairs})


@pytest.mark.parametrize("sizes", [[6, 4], [6, 4, 3], [7, 5, 4, 3]])
def test_cluster_speakers_trennt_zwei_bis_vier(sizes):
    embs, truth = _groups(sizes)
    labels = P.cluster_speakers(embs)
    assert _same_partition(labels, truth)
    assert labels.count(0) == max(sizes)               # größte Gruppe hat Label 0


def test_cluster_speakers_randfaelle():
    assert P.cluster_speakers([]) == []
    e, _ = _groups([1])
    assert P.cluster_speakers(e) == [0]
    same = [np.ones(16)] * 5
    assert P.cluster_speakers(same) == [0] * 5


def test_cluster_speakers_einzelner_ausreisser_wird_zugeschlagen():
    embs, _ = _groups([6, 5])
    rng = np.random.default_rng(9)
    embs.append(rng.normal(size=64))                   # ein Satz, der keiner Gruppe gleicht
    labels = P.cluster_speakers(embs)
    assert len(set(labels)) == 2


def test_cluster_speakers_max_k_begrenzt():
    embs, _ = _groups([3, 3, 3, 3, 3])
    assert len(set(P.cluster_speakers(embs, max_k=3))) <= 3


# ---- avhelper: Systemaudio-Vorbereitung -----------------------------------------------------------------------
def test_find_loopback_erkennt_virtuelle_geraete():
    mics = [{"index": "0", "name": "MacBook Pro-Mikrofon"}, {"index": "1", "name": "BlackHole 2ch"},
            {"index": "2", "name": "Loopback Audio"}, {"index": "3", "name": "AirPods Pro"}]
    assert [m["index"] for m in avhelper.find_loopback(mics)] == ["1", "2"]
    assert avhelper.find_loopback([]) == []


def test_capture_prep_bericht():
    ok = avhelper.capture_prep([{"index": "1", "name": "BLACKHOLE 16ch"}])
    assert ok["ready"] is True and ok["hint"] == "" and ok["loopback"][0]["index"] == "1"
    no = avhelper.capture_prep([{"index": "0", "name": "Mikrofon"}])
    assert no["ready"] is False and "BlackHole" in no["hint"]


def test_avhelper_prep_ist_subcommand():
    with pytest.raises(SystemExit):
        avhelper.main(["prep", "--bogus"])


# ---- history_store: verschlüsselter Export -------------------------------------------------------------------
def test_encrypt_roundtrip_und_falsches_passwort():
    blob = hs.encrypt_bytes("Grüße ทดสอบ".encode("utf-8") * 50, "geheim")
    assert blob.startswith(hs.ENC_MAGIC) and b"Gr" not in blob[:40]
    assert hs.decrypt_bytes(blob, "geheim") == "Grüße ทดสอบ".encode("utf-8") * 50
    with pytest.raises(ValueError):
        hs.decrypt_bytes(blob, "falsch")


def test_encrypt_manipulation_und_eingaben():
    blob = bytearray(hs.encrypt_bytes(b"abc", "pw"))
    blob[len(hs.ENC_MAGIC) + 40] ^= 1                  # ein Bit im Chiffretext
    with pytest.raises(ValueError):
        hs.decrypt_bytes(bytes(blob), "pw")
    for bad in ("", None, 5):
        with pytest.raises(ValueError):
            hs.encrypt_bytes(b"x", bad)
    with pytest.raises(ValueError):
        hs.decrypt_bytes(b"kein Export", "pw")
    assert hs.decrypt_bytes(hs.encrypt_bytes(b"", "pw"), "pw") == b""


def test_encrypt_zwei_mal_verschieden():
    assert hs.encrypt_bytes(b"x", "pw") != hs.encrypt_bytes(b"x", "pw")      # Salz und Nonce zufällig


def test_store_export_encrypted_import(tmp_path):
    a = hs.Store(str(tmp_path / "a" / "h.sqlite"))
    a.add("hello there", "สวัสดี", lang="en", session="s1", ts=1700000000.0)
    blob = a.export_encrypted("pw")
    assert b"hello" not in blob
    a.close()
    b = hs.Store(str(tmp_path / "b" / "h.sqlite"))
    assert b.import_encrypted(blob, "pw") == (1, 0, 0)
    assert b.import_encrypted(blob, "pw") == (0, 1, 0)                        # zweiter Import: nur übersprungen
    with pytest.raises(ValueError):
        b.import_encrypted(blob, "x")
    assert b.rows()[0]["text"] == "hello there"
    b.close()


# ---- bench/latency_budget -----------------------------------------------------------------------------------
BUDGET = {"budget": {"th": {"total_median_s": 8.0, "tr_mean_s": 1.0}},
          "case_regression_pct": 40, "case_min_delta_s": 1.0}


def test_latency_budget_verstoss_und_scale():
    res = {"summary": {"th": {"total_median_s": 9.0, "tr_mean_s": 0.5}}}
    assert lb.check_budget(res, BUDGET) == [("th", "total_median_s", 9.0, 8.0)]
    assert lb.check_budget(res, BUDGET, scale=1.5) == []
    assert lb.check_budget({"summary": {}}, BUDGET) == []                      # fehlende Werte sind kein Verstoß


def test_latency_budget_faelle_gegen_baseline():
    base = {"results": [{"id": "a", "total_s": 5.0}, {"id": "b", "total_s": 1.0}, {"id": "c", "total_s": None}]}
    new = {"results": [{"id": "a", "total_s": 8.0}, {"id": "b", "total_s": 1.9}, {"id": "c", "total_s": 3.0},
                       {"id": "neu", "total_s": 50.0}, {"id": "a2", "total_s": None}]}
    # a: +60 % und +3 s -> langsamer; b: +90 %, aber nur 0,9 s -> Rauschen; c/neu: kein Vergleich
    assert lb.check_cases(new, base) == [("a", 5.0, 8.0)]
    assert lb.check_cases(new, base, scale=2.0) == []


def test_latency_budget_cli(tmp_path):
    good, bad = tmp_path / "g.json", tmp_path / "b.json"
    good.write_text(json.dumps({"summary": {"th": {"total_median_s": 1.0}}}))
    bad.write_text(json.dumps({"summary": {"th": {"total_median_s": 99.0}}}))
    budget = tmp_path / "budget.json"
    budget.write_text(json.dumps(BUDGET))
    assert lb.main([str(good), "--budget", str(budget)], io.StringIO()) == 0
    out = io.StringIO()
    assert lb.main([str(bad), "--budget", str(budget)], out) == 2 and "BUDGET" in out.getvalue()
    assert lb.main([str(tmp_path / "fehlt.json")], io.StringIO()) == 1
    with pytest.raises(SystemExit):
        lb.main([str(good), "--scale", "0"])


def test_latency_budget_datei_ist_gueltig_und_baseline_besteht():
    budget = json.loads((ROOT / "bench" / "latency_budget.json").read_text(encoding="utf-8"))
    base = json.loads((ROOT / "bench" / "results" / "baseline_main.json").read_text(encoding="utf-8"))
    assert lb.check_budget(base, budget) == []           # die eingecheckte Baseline hält das eigene Budget ein


# ---- tools/pages_smoke: sw.js gegen Paketindex ------------------------------------------------------------
def test_sw_preset_drift():
    sw = "const PRESET_IDS = ['a', 'b'];\n"
    assert smoke.sw_preset_drift(sw, ["a", "b"]) == []
    err = smoke.sw_preset_drift(sw, ["a", "c"])
    assert any("unbekanntes Paket b" in e for e in err) and any("Paket c fehlt" in e for e in err)
    assert smoke.sw_preset_drift("nichts", ["a"]) == ["sw.js: keine PRESET_IDS-Liste"]


def test_sw_preset_ids_decken_index_im_repo():
    ids = [p["id"] for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]]
    assert smoke.sw_preset_drift((ROOT / "sw.js").read_text(encoding="utf-8"), ids) == []


# ---- correction_learning ----------------------------------------------------------------------------------
def test_confusion_apply_ersetzt_nicht_doppelt():
    m = cl.ConfusionMap()
    m.counts = {("a", "b"): 3, ("b", "c"): 3, ("chang my", "Chiang Mai"): 2}
    assert m.apply("a b Chang my") == "b c Chiang Mai"


def test_confusion_apply_haeufigste_korrektur_gewinnt():
    m = cl.ConfusionMap()
    m.counts = {("sam", "Sam"): 2, ("sam", "Somchai"): 5}
    assert m.apply("hi sam") == "hi Somchai"


def test_confusion_from_dict_ohne_bool_und_mit_grenze():
    m = cl.ConfusionMap.from_dict({"pairs": [["a", "b", True], ["c", "d", 2]]})
    assert m.counts == {("c", "d"): 2}
    big = {"pairs": [["w%d" % i, "r", 1] for i in range(cl.MAX_CONFUSIONS + 50)]}
    assert len(cl.ConfusionMap.from_dict(big).counts) == cl.MAX_CONFUSIONS
