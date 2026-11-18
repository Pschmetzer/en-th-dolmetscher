"""Runde 8: neue Phrasenpakete, Wartelisten-Datei fuer die Web-Listen, Paketzahl in den Dokus, Skripte."""
import json
import pathlib
import re
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (ROOT / "presets").glob("*.json")}
R8 = ["emergency", "work", "school", "visa", "sport", "nomad", "diving", "market", "kids"]
SAFETY_FIRST = ["emergency", "work", "school", "sport", "diving", "kids", "market"]   # brauchen kritische Saetze
PENDING_FILE = ROOT / "tools" / "web_pending_presets.txt"


def _pending():
    return [x.strip() for x in PENDING_FILE.read_text(encoding="utf-8").splitlines()
            if x.strip() and not x.startswith("#")]


def _web_ids(path):
    src = (ROOT / path).read_text(encoding="utf-8")
    return re.findall(r"'(\w+)'", re.search(r"const PRESET_IDS = \[(.*?)\]", src, re.S).group(1))


@pytest.mark.parametrize("pid", R8)
def test_new_pack_shape(pid):
    d = PACKS[pid]
    assert d["style"] == "polite"
    assert 15 <= len(d["phrases"]) <= 25
    assert len(d["glossary"]) >= 5
    assert "maschinell" in d["note"]["de"] and "machine" in d["note"]["en"]       # Thai ungeprueft gekennzeichnet
    for ph in d["phrases"]:
        assert ph["en"].rstrip()[-1] in ".?!", ph["en"]                             # ganze Saetze
        assert not re.search(r"[A-Za-z]{3,}", ph["th"]), ph["th"]


@pytest.mark.parametrize("pid", SAFETY_FIRST)
def test_safety_packs_lead_with_critical(pid):
    ph = PACKS[pid]["phrases"]
    assert ph[0].get("critical") is True
    assert sum(1 for p in ph if p.get("critical")) >= 2


def test_emergency_names_the_thai_emergency_numbers():
    note = PACKS["emergency"]["note"]["de"] + PACKS["emergency"]["note"]["en"]
    for number in ("191", "199", "1669", "1155"):
        assert number in note


def test_pending_file_is_exact():
    pend = _pending()
    assert len(pend) == len(set(pend))
    in_web = set(_web_ids("index.html"))
    assert in_web == set(_web_ids("sw.js"))
    for pid in pend:
        assert pid in PACKS, f"{pid} steht in web_pending_presets.txt, hat aber keine Datei"
        assert pid not in in_web, f"{pid} ist schon in PRESET_IDS: aus tools/web_pending_presets.txt loeschen"
    assert set(PACKS) - set(pend) == in_web, "neues Paket: id in PRESET_IDS (index.html, sw.js) oder in die Warteliste"


def test_docs_and_readme_count_matches_pack_count():
    n = len(PACKS)
    assert f"{n} Phrasenpakete" in (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert f"{n} phrase packs" in readme and f"({n} packs" in readme


@pytest.mark.skipif(shutil.which("shellcheck") is None, reason="shellcheck fehlt")
def test_shell_scripts_pass_shellcheck():
    scripts = [str(ROOT / "build.sh")] + sorted(str(p) for p in (ROOT / "build-support").glob("*.sh"))
    r = subprocess.run(["shellcheck", *scripts], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout


def test_ci_shellcheck_covers_all_scripts_without_severity_filter():
    ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert "shellcheck build-support/*.sh" in ci and "--severity=warning" not in ci
