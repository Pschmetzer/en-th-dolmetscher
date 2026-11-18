"""Tests für satzbuch.py: Export (CSV/JSON/Anki) und Prüfung der Phrasenpakete – ohne Netz oder Modell."""
import csv
import io
import json
import pathlib

import pytest

import satzbuch as S

ROOT = pathlib.Path(__file__).resolve().parent.parent


def pack(pid="demo", **kw):
    d = {"id": pid, "names": {"de": "Demo", "en": "Demo", "th": "เดโม"}, "style": "polite",
         "glossary": [{"en": "room", "th": "ห้อง"}],
         "phrases": [{"en": "Help!", "th": "ช่วยด้วย", "critical": True},
                     {"en": "Where is the ___?", "th": "___ อยู่ที่ไหน"}]}
    d.update(kw)
    return d


def write(folder, *packs, raw=None):
    folder.mkdir(exist_ok=True)
    for d in packs:
        (folder / f"{d['id']}.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    for name, text in (raw or {}).items():
        (folder / name).write_text(text, encoding="utf-8")
    return folder


def codes(findings, severity=None):
    return {f["code"] for f in findings if severity in (None, f["severity"])}


# ------------------------------------------------------------------------------------------- mitgelieferte Pakete

def test_shipped_packs_have_no_errors():
    errors = [f for f in S.check() if f["severity"] == S.ERROR]
    assert not errors, S.format_findings(errors)


def test_shipped_export_covers_all_phrases():
    packs, errs = S.load_dir()
    assert not errs
    rows = S.entries(packs)
    total = sum(len(d.get("phrases", [])) + len(d.get("glossary", [])) for d in packs.values())
    assert len(rows) == total
    index = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
    crit = sum(p["critical"] for p in index["packs"])
    assert len(S.entries(packs, critical_only=True)) == crit


# ------------------------------------------------------------------------------------------------------ Prüfung

def test_clean_pack_has_no_findings(tmp_path):
    assert S.check(write(tmp_path / "p", pack())) == []


def test_invalid_json_and_id_mismatch(tmp_path):
    d = pack()
    folder = write(tmp_path / "p", raw={"kaputt.json": "{nicht json", "anders.json": json.dumps(d)})
    f = S.check(folder)
    assert {"json", "id"} <= codes(f, S.ERROR)
    assert any(x["pack"] == "kaputt" and x["code"] == "json" for x in f)


def test_schema_errors_from_presets_validate(tmp_path):
    f = S.check(write(tmp_path / "p", pack(style="frech", extra=1)))
    msgs = " ".join(x["message"] for x in f if x["code"] == "schema")
    assert "style" in msgs and "unbekannte Felder" in msgs


@pytest.mark.parametrize("item,lang", [({"en": "Hello", "th": ""}, "th"), ({"en": "  ", "th": "สวัสดี"}, "en"),
                                       ({"th": "สวัสดี"}, "en")])
def test_missing_translation(tmp_path, item, lang):
    f = S.check(write(tmp_path / "p", pack(phrases=[item])))
    assert any(x["code"] == "missing" and f"Übersetzung {lang}" in x["message"] and x["where"] == "phrases[0]"
               for x in f)


def test_missing_names_and_note(tmp_path):
    d = pack(names={"de": "Demo", "en": "", "th": "เดโม"}, note={"de": "Hinweis", "en": ""})
    f = [x for x in S.check(write(tmp_path / "p", d)) if x["code"] == "missing"]
    assert {x["where"] for x in f} == {"names", "note"}


def test_duplicates_ignore_case_and_final_punctuation(tmp_path):
    d = pack(phrases=[{"en": "Thank you.", "th": "ขอบคุณ"}, {"en": "thank you", "th": "ขอบคุณมาก"},
                      {"en": "Sorry", "th": "ขอบคุณ"}])
    dup = [x for x in S.check(write(tmp_path / "p", d)) if x["code"] == "duplicate"]
    assert [(x["where"], x["message"][:2]) for x in dup] == [("phrases[1]", "en"), ("phrases[2]", "th")]


def test_same_text_in_glossary_and_phrases_is_no_duplicate(tmp_path):
    d = pack(glossary=[{"en": "Help!", "th": "ช่วยด้วย"}])
    assert "duplicate" not in codes(S.check(write(tmp_path / "p", d)))


@pytest.mark.parametrize("item,part", [
    ({"en": " Hello", "th": "สวัสดี"}, "Anfang oder Ende"),
    ({"en": "Hello", "th": "hello"}, "keine Thai-Schrift"),
    ({"en": "Hello สวัสดี", "th": "สวัสดี"}, "vertauscht"),
    ({"en": "Room ___ please", "th": "ห้อง"}, "Lücken"),
    ({"en": "Room {p}", "th": "ห้อง {p}"}, "Platzhalter"),
])
def test_format_errors(tmp_path, item, part):
    f = S.check(write(tmp_path / "p", pack(phrases=[item])))
    assert any(x["code"] == "format" and x["severity"] == S.ERROR and part in x["message"] for x in f), f


@pytest.mark.parametrize("item,part", [
    ({"en": "Hello  there", "th": "สวัสดี"}, "doppeltes"),
    ({"en": "Hello (friend", "th": "สวัสดี"}, "Klammern"),
    ({"en": "Thank you", "th": "ขอบคุณครับ"}, "Höflichkeitspartikel"),
])
def test_format_warnings(tmp_path, item, part):
    f = S.check(write(tmp_path / "p", pack(phrases=[item])))
    assert any(x["code"] == "format" and x["severity"] == S.WARNING and part in x["message"] for x in f), f


def test_critical_order_warning(tmp_path):
    d = pack(phrases=[{"en": "Hi", "th": "สวัสดี"}, {"en": "Help!", "th": "ช่วยด้วย", "critical": True}])
    assert "order" in codes(S.check(write(tmp_path / "p", d)), S.WARNING)


def test_cross_pack_inconsistency(tmp_path):
    a = pack("aa", glossary=[{"en": "Passport", "th": "พาสปอร์ต"}])
    b = pack("bb", glossary=[{"en": "passport", "th": "หนังสือเดินทาง"}])
    c = pack("cc", glossary=[{"en": "passport", "th": "พาสปอร์ต"}])
    inc = [x for x in S.check(write(tmp_path / "p", a, b, c)) if x["code"] == "inconsistent"]
    assert len(inc) == 1 and inc[0]["severity"] == S.WARNING
    assert inc[0]["where"] == "aa:glossary[0], bb:glossary[0], cc:glossary[0]"
    # gleiche Übersetzung in mehreren Paketen ist in Ordnung (die Phrasen von pack() stehen in allen dreien)
    assert "Help" not in inc[0]["message"]


def test_non_object_pack_and_items(tmp_path):
    folder = write(tmp_path / "p", pack("ok", phrases=["nur Text"]), raw={"liste.json": "[1, 2]"})
    f = S.check(folder)
    assert any(x["pack"] == "liste" and x["code"] == "schema" for x in f)
    assert any(x["pack"] == "ok" and x["where"] == "phrases[0]" for x in f)


# ------------------------------------------------------------------------------------------------------- Export

@pytest.fixture
def two(tmp_path):
    return write(tmp_path / "p", pack("bbb"), pack("aaa", glossary=[], note={"de": "x", "en": "y"}))


def test_entries_order_and_filters(two):
    packs, _ = S.load_dir(two)
    rows = S.entries(packs)
    assert [(r["pack"], r["kind"], r["index"]) for r in rows] == [
        ("aaa", "phrases", 0), ("aaa", "phrases", 1), ("bbb", "phrases", 0), ("bbb", "phrases", 1),
        ("bbb", "glossary", 0)]
    assert [r["pack"] for r in S.entries(packs, {"bbb"}, glossary=False)] == ["bbb", "bbb"]
    assert [r["en"] for r in S.entries(packs, critical_only=True)] == ["Help!", "Help!"]


def test_csv_roundtrip(two):
    packs, _ = S.load_dir(two)
    text = S.to_csv(S.entries(packs))
    rows = list(csv.DictReader(io.StringIO(text)))
    assert tuple(rows[0]) == S.CSV_FIELDS
    assert rows[0]["critical"] == "1" and rows[1]["critical"] == "0"
    assert rows[1]["th"] == "___ อยู่ที่ไหน" and rows[-1]["kind"] == "glossary"


def test_csv_quotes_commas_and_quotes(tmp_path):
    d = pack(phrases=[{"en": 'Say "yes", please', "th": "พูดว่า ใช่"}], glossary=[])
    packs, _ = S.load_dir(write(tmp_path / "p", d))
    rows = list(csv.DictReader(io.StringIO(S.to_csv(S.entries(packs)))))
    assert rows[0]["en"] == 'Say "yes", please'


def test_json_export_groups_by_pack_and_validates(two):
    packs, _ = S.load_dir(two)
    data = json.loads(S.to_json(S.entries(packs)))
    assert data["version"] == 1 and [p["id"] for p in data["packs"]] == ["aaa", "bbb"]
    bbb = data["packs"][1]
    assert bbb["phrases"][0] == {"en": "Help!", "th": "ช่วยด้วย", "critical": True}
    assert bbb["glossary"] == [{"en": "room", "th": "ห้อง"}]
    assert bbb["names"]["th"] == "เดโม"


def test_anki_export(two):
    packs, _ = S.load_dir(two)
    lines = S.to_anki(S.entries(packs)).splitlines()
    assert lines[:4] == ["#separator:tab", "#html:false", "#columns:English\tThai\tTags", "#tags column:3"]
    body = [ln.split("\t") for ln in lines[4:]]
    assert all(len(cols) == 3 for cols in body)
    assert body[0] == ["Help!", "ช่วยด้วย", "dolmetscher::aaa satz kritisch"]
    assert body[-1] == ["room", "ห้อง", "dolmetscher::bbb glossar"]


def test_anki_strips_tabs_and_newlines(tmp_path):
    d = pack(phrases=[{"en": "a\tb\nc", "th": "ก\tข"}], glossary=[])
    packs, _ = S.load_dir(write(tmp_path / "p", d))
    assert S.to_anki(S.entries(packs)).splitlines()[4] == "a b c\tก ข\tdolmetscher::demo satz"


# ---------------------------------------------------------------------------------------------------------- CLI

def run(*argv):
    out = io.StringIO()
    return S.main(list(argv), stdout=out), out.getvalue()


def test_cli_check_ok_and_strict(tmp_path):
    folder = write(tmp_path / "p", pack(phrases=[{"en": "Hi  there", "th": "สวัสดี"}]))
    rc, text = run("check", "--dir", str(folder))
    assert rc == 0 and "0 Fehler, 1 Warnungen" in text
    assert run("check", "--dir", str(folder), "--strict")[0] == 1


def test_cli_check_errors_and_json(tmp_path):
    folder = write(tmp_path / "p", pack(phrases=[{"en": "Hi", "th": ""}]))
    rc, text = run("check", "--dir", str(folder), "--json")
    data = json.loads(text)
    assert rc == 1 and data["summary"]["error"] >= 1
    assert all(set(f) == {"severity", "pack", "code", "where", "message"} for f in data["findings"])


@pytest.mark.parametrize("fmt", ["csv", "json", "anki"])
def test_cli_export_to_file(tmp_path, fmt):
    folder = write(tmp_path / "p", pack())
    out = tmp_path / f"out.{fmt}"
    rc, text = run("export", fmt, "--dir", str(folder), "-o", str(out))
    assert rc == 0 and text == "" and "ช่วยด้วย" in out.read_text(encoding="utf-8")


def test_cli_export_stdout_options_and_unknown_pack(tmp_path, capsys):
    folder = write(tmp_path / "p", pack("aaa"), pack("bbb"), raw={"kaputt.json": "{"})
    rc, text = run("export", "csv", "--dir", str(folder), "--pack", "bbb", "--critical-only")
    assert rc == 0 and text.splitlines()[1].startswith("bbb,phrases,0,Help!")
    assert len(text.splitlines()) == 2
    assert "übersprungen: kaputt" in capsys.readouterr().err
    assert run("export", "csv", "--dir", str(folder), "--pack", "zzz")[0] == 2
    rc, text = run("export", "anki", "--dir", str(folder), "--no-glossary")
    assert "glossar" not in text


def test_shipped_cli_check_passes():
    assert run("check")[0] == 0
