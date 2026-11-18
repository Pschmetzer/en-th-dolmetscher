"""CLI-Werkzeuge fuer Phrasenpakete: export_phrasebook, check_presets, preset_stats (reine Dateipruefung)."""
import csv
import io
import json
import pathlib
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"


def run(tool, *args):
    return subprocess.run([sys.executable, str(TOOLS / tool), *args], capture_output=True, text=True, encoding="utf-8")


def pack(pid, phrases, **extra):
    d = {"id": pid, "names": {"de": "T", "en": "T", "th": "ที"}, "style": "polite", "phrases": phrases}
    d.update(extra)
    return d


@pytest.fixture
def folder(tmp_path):
    def make(*packs):
        for d in packs:
            (tmp_path / (d["id"] + ".json")).write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
        return str(tmp_path)
    return make


GOOD = [{"en": "Help", "th": "ช่วยด้วย", "critical": True}, {"en": "Water, please", "th": "ขอน้ำหน่อย"}]


@pytest.mark.parametrize("tool", ["export_phrasebook.py", "check_presets.py", "preset_stats.py"])
def test_help(tool):
    r = run(tool, "--help")
    assert r.returncode == 0 and "usage" in r.stdout.lower()


def test_real_presets_have_no_errors():
    r = run("check_presets.py")
    assert r.returncode == 0, r.stdout


@pytest.mark.parametrize("fmt", ["csv", "md", "html", "anki"])
def test_export_is_deterministic(fmt):
    a, b = run("export_phrasebook.py", fmt), run("export_phrasebook.py", fmt)
    assert a.returncode == 0 and a.stdout == b.stdout and a.stdout


def test_export_formats(folder):
    d = folder(pack("one", list(reversed(GOOD))))
    c = list(csv.reader(io.StringIO(run("export_phrasebook.py", "csv", "--dir", d).stdout)))
    assert c[0] == ["pack", "critical", "en", "th"] and c[1] == ["one", "1", "Help", "ช่วยด้วย"]
    anki = run("export_phrasebook.py", "anki", "--dir", d).stdout.splitlines()
    assert anki[0].split("\t") == ["Help", "ช่วยด้วย", "one critical"] and len(anki) == 2
    md = run("export_phrasebook.py", "md", "--dir", d, "--critical-only").stdout
    assert "Help" in md and "Water" not in md
    h = run("export_phrasebook.py", "html", "--dir", d, "--size", "a5").stdout
    assert "148mm" in h and 'class="card"' in h and "Water, please" in h


def test_export_html_escapes_and_splits_cards(folder):
    many = [{"en": "a<b %d" % i, "th": "ไทย %d" % i} for i in range(9)]
    h = run("export_phrasebook.py", "html", "--dir", folder(pack("many", many)), "--size", "a6").stdout
    assert h.count('<section class="card">') == 3 and "a&lt;b 0" in h


def test_export_unknown_pack_fails(folder):
    r = run("export_phrasebook.py", "csv", "--dir", folder(pack("one", GOOD)), "--pack", "nope")
    assert r.returncode != 0


def test_check_clean_pack(folder):
    r = run("check_presets.py", "--dir", folder(pack("one", GOOD)))
    assert r.returncode == 0 and "0 Fehler" in r.stdout


@pytest.mark.parametrize("phrases,needle", [
    ([{"en": "A", "th": "ก"}, {"en": "a ", "th": "ข"}], "Dublette"),
    ([{"en": "A", "th": ""}], "Thai-Uebersetzung fehlt"),
    ([{"en": "Hello", "th": "Hello"}], "gleich en"),
    ([{"en": "Hello", "th": "สวัสดีครับ"}], "Hoeflichkeitspartikel"),
    ([{"en": "I", "th": "ผมไม่ไหว"}], "Pronomen"),
    ([{"en": "Go", "th": "ไปนะ"}], "นะ"),
    ([{"en": "Go", "th": "ก" * 201}], "max 200"),
    ([{"en": "Go", "th": "123"}], "keine Thai-Schrift"),
    ([{"en": "Go ___", "th": "ไป"}], "Luecke"),
])
def test_check_errors(folder, phrases, needle):
    r = run("check_presets.py", "--dir", folder(pack("one", phrases)))
    assert r.returncode == 1 and needle in r.stdout


def test_check_schema_errors(folder):
    bad = pack("one", GOOD, style="rude", extra=1)
    r = run("check_presets.py", "--dir", folder(bad))
    assert r.returncode == 1 and "style" in r.stdout and "unbekanntes Feld" in r.stdout


def test_check_consistency_and_strict(folder):
    d = folder(pack("one", [{"en": "Stop", "th": "หยุด"}]), pack("two", [{"en": "stop", "th": "หยุดเลย"}]))
    assert run("check_presets.py", "--dir", d).returncode == 0
    r = run("check_presets.py", "--dir", d, "--strict")
    assert r.returncode == 1 and "unterschiedlicher" in r.stdout


def test_check_json_output(folder):
    r = run("check_presets.py", "--dir", folder(pack("one", GOOD)), "--json")
    out = json.loads(r.stdout)
    assert out["errors"] == 0 and out["packs"] == 1


def test_stats(folder):
    d = folder(pack("one", GOOD, glossary=[{"en": "x", "th": "ก"}]))
    out = json.loads(run("preset_stats.py", "--dir", d, "--format", "json").stdout)
    row = out["packs"][0]
    assert row["phrases"] == 2 and row["critical"] == 1 and row["critical_pct"] == 50.0 and row["glossary"] == 1
    assert out["total"]["phrases"] == 2
    t1, t2 = run("preset_stats.py"), run("preset_stats.py")
    assert t1.returncode == 0 and t1.stdout == t2.stdout and "Gesamt" in t1.stdout
    assert "|---|" in run("preset_stats.py", "--format", "md").stdout
