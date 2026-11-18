"""Runde 16: Pruefbogen-Werkzeuge (review_export, review_import, review_status) inkl. Round-Trip und Fehlerfaelle."""
import csv
import io
import json
import pathlib
import shutil
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import make_presets_index  # noqa: E402
import review_export  # noqa: E402
import review_import  # noqa: E402
import review_status  # noqa: E402
from _reviewlib import COLUMNS, protect, read_sheet, unprotect  # noqa: E402

TOOLS = ("review_export", "review_import", "review_status")


def _pack(pid, phrases):
    return {"id": pid, "names": {"de": pid, "en": pid, "th": "ทดสอบ"}, "style": "polite", "phrases": phrases}


def _ph(en, th, critical=False):
    d = {"en": en, "th": th}
    if critical:
        d["critical"] = True
    return d


@pytest.fixture
def repo(tmp_path):
    """Kleines Repo: zwei Pakete mit gleichem englischen Satz, ein kritischer Satz, plus Index."""
    (tmp_path / "presets").mkdir()
    packs = {
        "alpha": _pack("alpha", [_ph("Hello.", "สวัสดี"), _ph("Help me!", "ช่วยด้วย", True),
                                 _ph("Water, please.", "ขอน้ำหน่อย")]),
        "beta": _pack("beta", [_ph("Water, please.", "ขอน้ำหน่อย"), _ph("Thank you.", "ขอบคุณ")]),
    }
    for pid, d in packs.items():
        (tmp_path / "presets" / (pid + ".json")).write_text(review_import.dump_pack(d), encoding="utf-8")
    idx = make_presets_index.build(tmp_path)
    (tmp_path / "presets-index.json").write_text(json.dumps(idx, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return tmp_path


def _dir(repo):
    return str(repo / "presets")


def _snapshot(repo):
    return {p.name: p.read_text(encoding="utf-8") for p in sorted(repo.glob("**/*.json"))}


def _export(repo, tmp_path, fmt="csv", *extra):
    out = tmp_path / ("sheet." + fmt)
    assert review_export.main(["--dir", _dir(repo), "--format", fmt, "--out", str(out), *extra]) == 0
    return out


def _fill(path, edits, fmt="csv"):
    """edits: id -> (Status, Korrektur, Kommentar). Schreibt den Bogen mit den Eintraegen neu."""
    rows = read_sheet(path)
    known = {r["id"] for r in rows}
    for rid in sorted(set(edits) - known):  # unbekannte ids als zusaetzliche Zeilen (Fehlerfaelle)
        rows.append({"id": rid, "en": "Hello.", "de": "", "th": "สวัสดี", "Status": "", "Korrektur": "",
                     "Kommentar": ""})
    for r in rows:
        if r["id"] in edits:
            r["Status"], r["Korrektur"], r["Kommentar"] = edits[r["id"]]
    if fmt == "csv":
        buf = io.StringIO(newline="")
        w = csv.writer(buf, lineterminator="\r\n")
        w.writerow(COLUMNS)
        for r in rows:
            w.writerow([r[c] for c in COLUMNS])
        pathlib.Path(path).write_bytes(("﻿" + buf.getvalue()).encode("utf-8"))
    else:
        text = review_export.render_md([[r[c] for c in COLUMNS] for r in rows])
        pathlib.Path(path).write_text(text, encoding="utf-8")


def _run_import(repo, sheet, *extra):
    return review_import.main([str(sheet), "--dir", _dir(repo), *extra])


@pytest.mark.parametrize("tool", TOOLS)
def test_help_laeuft(tool):
    r = subprocess.run([sys.executable, str(ROOT / "tools" / (tool + ".py")), "--help"],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0 and "usage" in r.stdout.lower()


def test_export_csv_bom_spalten_und_kritisch_zuerst(repo, tmp_path):
    out = _export(repo, tmp_path)
    raw = out.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    rows = read_sheet(out)
    assert list(rows[0])[:7] == COLUMNS
    assert [r["id"] for r in rows] == ["alpha:02", "alpha:01", "alpha:03", "beta:01", "beta:02"]
    assert all(r["Status"] == "" and r["Korrektur"] == "" for r in rows)


def test_export_filter_und_deterministisch(repo, tmp_path):
    a = _export(repo, tmp_path, "csv", "--critical")
    assert [r["id"] for r in read_sheet(a)] == ["alpha:02"]
    b = _export(repo, tmp_path, "md", "--pack", "beta")
    assert [r["id"] for r in read_sheet(b)] == ["beta:01", "beta:02"]
    assert _export(repo, tmp_path, "csv").read_bytes() == _export(repo, tmp_path, "csv").read_bytes()
    with pytest.raises(SystemExit):
        review_export.main(["--dir", _dir(repo), "--pack", "gibtsnicht"])


def test_formel_schutz():
    assert protect("=1+1") == "'=1+1" and protect("-x") == "'-x" and protect("normal") == "normal"
    assert unprotect("'=1+1") == "=1+1" and unprotect("'normal") == "'normal"
    rows = review_export.render_csv([["a:01", "=HYPERLINK(1)", "", "ไทย", "", "", "@x"]])
    assert "'=HYPERLINK(1)" in rows and "'@x" in rows


def test_roundtrip_ohne_aenderung_ist_trockenlauf(repo, tmp_path, capsys):
    before = _snapshot(repo)
    sheet = _export(repo, tmp_path)
    assert _run_import(repo, sheet) == 0
    assert "Trockenlauf" in capsys.readouterr().out
    assert _snapshot(repo) == before


@pytest.mark.parametrize("fmt", ["csv", "md"])
def test_roundtrip_korrektur_zieht_gleichen_satz_mit(repo, tmp_path, capsys, fmt):
    sheet = _export(repo, tmp_path, fmt)
    _fill(sheet, {"alpha:03": ("korrigiert", "ขอน้ำเปล่า", "klingt besser"), "alpha:01": ("ok", "", "")}, fmt)
    before = _snapshot(repo)
    assert _run_import(repo, sheet) == 0
    out = capsys.readouterr().out
    assert "mitgezogen aus alpha:03" in out and "+ ขอน้ำเปล่า" in out
    assert _snapshot(repo) == before  # Trockenlauf
    assert _run_import(repo, sheet, "--apply") == 0
    alpha = json.loads((repo / "presets" / "alpha.json").read_text(encoding="utf-8"))
    beta = json.loads((repo / "presets" / "beta.json").read_text(encoding="utf-8"))
    assert alpha["phrases"][2]["th"] == beta["phrases"][0]["th"] == "ขอน้ำเปล่า"
    assert alpha["phrases"][0]["th"] == "สวัสดี"
    assert review_import.dump_pack(alpha) == (repo / "presets" / "alpha.json").read_text(encoding="utf-8")
    # nicht alle Saetze bestaetigt -> kein reviewed
    idx = json.loads((repo / "presets-index.json").read_text(encoding="utf-8"))
    assert [p["reviewed"] for p in idx["packs"]] == [False, False]
    assert review_status.main(["--dir", _dir(repo)]) == 0


def test_reviewed_nur_wenn_alle_saetze_bestaetigt(repo, tmp_path, capsys):
    sheet = _export(repo, tmp_path)
    ids = {r["id"]: ("ok", "", "") for r in read_sheet(sheet) if r["id"].startswith("beta")}
    ids["alpha:01"] = ("ok", "", "")
    ids["alpha:02"] = ("ok", "", "")
    ids["alpha:03"] = ("unklar", "", "bitte pruefen")
    _fill(sheet, ids)
    assert _run_import(repo, sheet, "--apply") == 0
    idx = json.loads((repo / "presets-index.json").read_text(encoding="utf-8"))
    assert {p["id"]: p["reviewed"] for p in idx["packs"]} == {"alpha": False, "beta": True}
    assert idx == make_presets_index.build(repo)  # Index stimmt mit Neuerzeugung ueberein
    capsys.readouterr()
    assert review_status.main(["--dir", _dir(repo), "--sheet", str(sheet), "--format", "json"]) == 0
    st = json.loads(capsys.readouterr().out)
    assert (st["reviewed"], st["open"]) == (1, 1)
    assert [p["confirmed"] for p in st["packs"]] == [2, 2]


def test_reviewed_true_wird_nie_zurueckgenommen(repo, tmp_path):
    idx = json.loads((repo / "presets-index.json").read_text(encoding="utf-8"))
    idx["packs"][1]["reviewed"] = True
    (repo / "presets-index.json").write_text(json.dumps(idx, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    sheet = _export(repo, tmp_path)
    _fill(sheet, {"alpha:01": ("ok", "", "")})
    assert _run_import(repo, sheet, "--apply") == 0
    new = json.loads((repo / "presets-index.json").read_text(encoding="utf-8"))
    assert [p["reviewed"] for p in new["packs"]] == [False, True]


def test_status_text_deterministisch(repo, capsys):
    assert review_status.main(["--dir", _dir(repo)]) == 0
    a = capsys.readouterr().out
    assert review_status.main(["--dir", _dir(repo)]) == 0
    assert capsys.readouterr().out == a
    assert "alpha" in a and "Pakete: 0 geprueft, 2 offen" in a


@pytest.mark.parametrize("edits,needle", [
    ({"alpha:99": ("ok", "", "")}, "ausserhalb"),
    ({"nope:01": ("ok", "", "")}, "unbekannt"),
    ({"alpha:03": ("korrigiert", "", "")}, "ohne Korrektur"),
    ({"alpha:03": ("ok", "ขอน้ำ", "")}, "Korrektur ohne Status"),
    ({"alpha:03": ("vielleicht", "", "")}, "Status 'vielleicht'"),
    ({"alpha:03": ("korrigiert", "ขอน้ำ\x07", "")}, "Steuerzeichen"),
    ({"alpha:03": ("korrigiert", "ขอน้ำ", "a\nb")}, "Steuerzeichen"),
    ({"alpha:03": ("korrigiert", "ขอน้ำ​", "")}, "Steuerzeichen"),
    ({"alpha:03": ("korrigiert", "=ขอน้ำ", "")}, "Formelzeichen"),
    ({"alpha:03": ("korrigiert", "water", "")}, "Pruefung"),
    ({"alpha:03": ("korrigiert", "ขอน้ำครับ", "")}, "Pruefung"),
])
def test_fehlerfaelle_schreiben_nichts(repo, tmp_path, capsys, edits, needle):
    sheet = _export(repo, tmp_path)
    _fill(sheet, edits)
    before = _snapshot(repo)
    assert _run_import(repo, sheet, "--apply") == 1
    assert needle in capsys.readouterr().out
    assert _snapshot(repo) == before


def test_verschobener_index_und_veralteter_bogen(repo, tmp_path, capsys):
    sheet = _export(repo, tmp_path)
    p = repo / "presets" / "alpha.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d["phrases"].insert(0, _ph("New first.", "ใหม่ก่อน"))
    p.write_text(review_import.dump_pack(d), encoding="utf-8")
    _fill(sheet, {"alpha:01": ("ok", "", "")})
    before = _snapshot(repo)
    assert _run_import(repo, sheet, "--apply") == 1
    assert "Position verschoben" in capsys.readouterr().out
    d["phrases"].pop(0)
    d["phrases"][0]["th"] = "หวัดดี"  # th geaendert, en gleich
    p.write_text(review_import.dump_pack(d), encoding="utf-8")
    assert _run_import(repo, sheet) == 1
    assert "weicht vom aktuellen Stand ab" in capsys.readouterr().out
    assert _snapshot(repo) != before


def test_doppelte_id_und_widerspruch_im_bogen(repo, tmp_path, capsys):
    sheet = _export(repo, tmp_path)
    _fill(sheet, {"alpha:03": ("korrigiert", "ขอน้ำเปล่า", ""), "beta:01": ("korrigiert", "ขอน้ำแข็ง", "")})
    assert _run_import(repo, sheet) == 1
    assert "Widerspruch im Bogen" in capsys.readouterr().out
    rows = read_sheet(sheet)
    extra = ",".join([rows[0]["id"], rows[0]["en"], "", rows[0]["th"], "", "", ""])
    text = sheet.read_text(encoding="utf-8-sig") + "\r\n" + extra + "\r\n"
    sheet.write_text(text, encoding="utf-8")
    assert _run_import(repo, sheet) == 1
    assert "doppelt" in capsys.readouterr().out


def test_kaputter_bogen(repo, tmp_path, capsys):
    bad = tmp_path / "bad.csv"
    bad.write_bytes(b"id,en\r\na,b\r\n")
    assert _run_import(repo, bad) == 1
    assert "Spalten fehlen" in capsys.readouterr().out
    bad.write_bytes("id;en\n\xe4".encode("latin-1"))
    assert _run_import(repo, bad) == 1
    assert "UTF-8" in capsys.readouterr().out


def test_echte_pakete_unveraendert_im_trockenlauf(tmp_path):
    work = tmp_path / "repo"
    shutil.copytree(ROOT / "presets", work / "presets")
    shutil.copy(ROOT / "presets-index.json", work / "presets-index.json")
    out = tmp_path / "all.csv"
    assert review_export.main(["--dir", str(work / "presets"), "--out", str(out)]) == 0
    rows = read_sheet(out)
    index = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
    assert len(rows) == sum(p["phrases"] for p in index["packs"])
    before = _snapshot(work)
    assert review_import.main([str(out), "--dir", str(work / "presets")]) == 0
    assert _snapshot(work) == before
