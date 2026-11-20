"""Runde 23: history_store, presets, satzbuch."""
import json
import os
import sys
import time

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import history_store as H  # noqa: E402
import presets as PR  # noqa: E402
import satzbuch as S  # noqa: E402

DAY = 86400.0


@pytest.fixture
def st(tmp_path):
    s = H.Store(str(tmp_path / "h.sqlite"))
    yield s
    s.close()


def fill(st, n=1200):
    base = 1_700_000_000.0
    for i in range(n):
        st.add("Hello %d there" % (i % 7), "Hallo %d" % i if i % 2 else None, lang="en",
               session="s%d" % (i // 400), ts=base + i * 60.0,
               role="me" if i % 3 == 0 else None, speaker="Anna" if i % 5 == 0 else None)
    return base


# ---------------- history_store
def test_stats_sql_matches_python_reference(st):
    fill(st, 300)
    r = st.stats(top=3, tz_offset_s=7 * 3600)
    rows = st.rows()
    ref_days = {}
    from datetime import datetime, timezone
    for x in rows:
        d = datetime.fromtimestamp(x["ts"] + 7 * 3600, timezone.utc).strftime("%Y-%m-%d")
        e = ref_days.setdefault(d, {"utterances": 0, "words": 0})
        e["utterances"] += 1
        e["words"] += len((x["text"] or "").split())
    assert r["per_day"] == ref_days
    assert r["total"] == 300 and r["sessions"] == 1
    assert r["first"] == rows[0]["ts"] and r["last"] == rows[-1]["ts"]
    assert len(r["top_sentences"]) == 3 and r["top_sentences"][0]["count"] >= r["top_sentences"][-1]["count"]
    assert st.stats(top=0)["top_sentences"] == []


def test_stats_top_sentence_casefold_and_keeps_first_spelling(st):
    st.add("Good Morning", ts=1000.0, session="a")
    st.add("good   morning", ts=1001.0, session="a")
    st.add("other", ts=1002.0, session="a")
    assert st.stats()["top_sentences"] == [{"text": "Good Morning", "count": 2}]


def test_stats_does_not_load_all_rows(st, monkeypatch):
    fill(st, 50)
    monkeypatch.setattr(st, "rows", lambda *a, **k: (_ for _ in ()).throw(AssertionError("rows() geladen")))
    assert st.stats()["total"] == 50


def test_iter_rows_chunks_equal_rows(st):
    fill(st, 130)
    assert list(st.iter_rows(chunk=17)) == st.rows()
    assert list(st.iter_rows("s0", chunk=50)) == st.rows("s0")
    assert list(st.iter_rows("none")) == []


def test_iter_rows_same_timestamp_not_skipped(st):
    for i in range(10):
        st.add("t%d" % i, ts=5.0, session="x")
    assert [r["text"] for r in st.iter_rows(chunk=3)] == ["t%d" % i for i in range(10)]


@pytest.mark.parametrize("fmt", ["json", "csv", "md", "anki", "txt", "srt", "vtt"])
def test_export_stream_equals_export(st, fmt):
    fill(st, 450)
    out = []
    n = H.export_stream(st, fmt, out.append)
    assert n == 450
    assert "".join(out) == H.export(st.rows(), fmt)


@pytest.mark.parametrize("fmt", ["json", "csv", "md", "anki", "txt", "srt"])
def test_export_stream_empty_and_session(st, fmt):
    out = []
    assert H.export_stream(st, fmt, out.append) == 0
    assert "".join(out) == H.export([], fmt)
    fill(st, 450)
    out = []
    H.export_stream(st, fmt, out.append, session="s1")
    assert "".join(out) == H.export(st.rows("s1"), fmt)


def test_export_stream_json_is_valid_json(st):
    fill(st, 30)
    out = []
    H.export_stream(st, "json", out.append)
    assert len(json.loads("".join(out))) == 30


def test_export_stream_unknown_format(st):
    with pytest.raises(ValueError):
        H.export_stream(st, "pdf", lambda s: None)


def test_export_stream_csv_columns_only_when_known(st):
    st.add("a", ts=1.0, session="x")
    out = []
    H.export_stream(st, "csv", out.append)
    assert out[0].strip().endswith("provider")
    st.add("b", ts=2.0, session="x", speaker="Anna")
    out = []
    H.export_stream(st, "csv", out.append)
    assert out[0].strip().endswith("provider,speaker")


def test_keep_days_persisted_and_applied_on_open(tmp_path):
    p = str(tmp_path / "k.sqlite")
    s = H.Store(p)
    now = time.time()
    s.add("old", ts=now - 40 * DAY, session="a")
    s.add("new", ts=now - 1 * DAY, session="a")
    assert s.get_keep_days() is None
    assert s.set_keep_days(30) == 1
    assert s.get_keep_days() == 30.0
    s.add("older", ts=now - 90 * DAY, session="a")
    s.close()
    s2 = H.Store(p)                                   # Frist wirkt beim Öffnen
    assert [r["text"] for r in s2.rows()] == ["new"]
    s2.set_keep_days(None)
    assert s2.get_keep_days() is None
    s2.close()


def test_set_keep_days_rejects_invalid(st):
    for bad in (0, -1, "abc", float("inf"), True):
        with pytest.raises(ValueError):
            st.set_keep_days(bad)
    assert st.get_keep_days() is None


def test_purge_session_and_count(st):
    fill(st, 10)
    st.add("zzz", session="other", ts=1.0)
    assert st.count() == 11 and st.count("other") == 1
    assert st.purge_session("other") == 1
    assert st.count() == 10 and st.search("zzz") == []
    assert st.purge_session("missing") == 0
    for bad in ("", None, 5):
        with pytest.raises(ValueError):
            st.purge_session(bad)


def test_db_size_positive(st):
    fill(st, 20)
    assert st.db_size() > 0


def test_reindex_repairs_search(st):
    fill(st, 20)
    assert st.index_status()["ok"]
    with st.lock, st.db:
        st.db.execute("DELETE FROM utt_fts")
    assert not st.index_status()["ok"] and st.search("Hello") == []
    assert st.reindex() == 20
    assert st.index_status()["ok"] and len(st.search("Hello", limit=5)) == 5


def test_index_auto_repaired_on_open(tmp_path):
    p = str(tmp_path / "i.sqlite")
    s = H.Store(p)
    s.add("Bangkok trip", ts=1.0, session="a")
    with s.lock, s.db:
        s.db.execute("DELETE FROM utt_fts")
    s.close()
    s2 = H.Store(p)
    assert len(s2.search("Bangkok")) == 1
    s2.close()


# ---------------- presets: texts-Schema
def pack(**kw):
    d = {"id": "t", "names": {"de": "T", "en": "T", "th": "ท"}, "style": "neutral"}
    d.update(kw)
    return d


def test_validate_accepts_texts_schema():
    d = pack(phrases=[{"texts": {"en": "Hello", "th": "สวัสดี", "de": "Hallo"}, "critical": True}],
             glossary=[{"texts": {"en": "bill", "th": "บิล"}}])
    assert PR.validate(d) == []


@pytest.mark.parametrize("item", [
    {"texts": {"en": "only one"}},
    {"texts": {"en": "a", "xx_yy": "b"}},
    {"texts": {"en": "a", "th": ""}},
    {"texts": "x"},
    {"texts": {"en": "a", "th": "b"}, "en": "different"},
    {"en": "a"},
])
def test_validate_rejects_bad_texts(item):
    assert PR.validate(pack(phrases=[item]))


def test_validate_legacy_still_works_and_message_kept():
    assert PR.validate(pack(phrases=[{"en": "a", "th": "ก"}])) == []
    assert "braucht en und th" in PR.validate(pack(phrases=[{"en": "a"}]))[0]


def test_migrate_roundtrip_and_no_mutation():
    d = pack(phrases=[{"en": "Hi", "th": "หวัดดี", "critical": True}], glossary=[{"en": "a", "th": "ก"}])
    m = PR.migrate(d)
    assert m["phrases"] == [{"texts": {"en": "Hi", "th": "หวัดดี"}, "critical": True}]
    assert PR.validate(m) == [] and d["phrases"][0]["en"] == "Hi"
    assert PR.migrate(m) == m                                   # idempotent
    back = PR.legacy_view(m)
    assert back["phrases"][0]["en"] == "Hi" and back["glossary"][0]["th"] == "ก"


def test_item_texts_and_helpers():
    it = {"texts": {"en": "a", "th": "ก", "de": "b"}}
    assert PR.item_texts(it) == {"en": "a", "th": "ก", "de": "b"}
    assert PR.item_texts({"en": "a", "th": "ก"}) == {"en": "a", "th": "ก"}
    assert PR.item_texts(None) == {}
    d = pack(phrases=[it, {"en": "x", "th": "ข"}], glossary=[it, {"texts": {"en": "q", "de": "r"}}])
    assert PR.texts_for(d, "de") == ["b"]
    assert PR.glossary_pairs(d, "en", "de") == [("a", "b"), ("q", "r")]
    assert PR.glossary_pairs(d, "th", "de") == [("ก", "b")]


def test_load_all_texts_preset_usable_by_app(tmp_path, monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    ud = tmp_path / "presets"
    ud.mkdir()
    d = pack(id="neu", phrases=[{"texts": {"en": "Hi", "th": "หวัดดี", "de": "Hallo"}, "critical": True}],
             glossary=[{"texts": {"en": "bill", "th": "บิล"}}, {"texts": {"en": "x", "de": "y"}}])
    (ud / "neu.json").write_text(json.dumps(d), encoding="utf-8")
    got = PR.load_all()["neu"]
    assert PR.app_fields(got)["phrases"] == [{"en": "Hi", "th": "หวัดดี", "critical": True}]
    assert PR.glossary_entries(got) == [("bill", "บิล"), ("บิล", "bill")]      # Eintrag ohne th/en fehlt


def test_shipped_presets_unchanged_by_loader():
    assert PR.load_all() and not PR.last_errors


# ---------------- satzbuch
def test_ascii_digits_and_numbers_of():
    assert S.ascii_digits("๓๐ นาที") == "30 นาที"
    assert S.numbers_of("1,500.50 THB") == ["150050"]
    assert S.numbers_of("๓๐ นาที, 2 คน") == ["2", "30"]
    assert S.numbers_of("no digits") == []


def numpack(en, th, kind="phrases"):
    return {kind: [{"en": en, "th": th}]}


def codes(f):
    return [x["message"] for x in f]


def test_check_numbers_clean_and_mismatch():
    assert S.check_numbers("p", numpack("Meet at 10:30", "เจอกันตอน 10:30")) == []
    assert S.check_numbers("p", numpack("It costs 500 baht", "ราคา 5000 บาท"))
    assert S.check_numbers("p", numpack("Two people", "สองคน")) == []          # Zahlwort: kein Befund
    assert S.check_numbers("p", numpack("Room 12", "ห้อง 12", "glossary")) == []


def test_check_numbers_thai_digits_style_and_mixed():
    f = S.check_numbers("p", numpack("Room 12", "ห้อง ๑๒"))
    assert len(f) == 1 and "Thai-Ziffern" in f[0]["message"]                    # gleiche Zahl, nur Stilhinweis
    f = S.check_numbers("p", numpack("Room 12", "ห้อง ๑2"))
    assert any("gemischt" in m for m in codes(f))


def test_check_numbers_german_format():
    f = S.check_numbers("p", numpack("It costs 1.000,50 baht", "ราคา 1,000.50 บาท"))
    assert any("deutschen Format" in m for m in codes(f))
    assert S.check_numbers("p", numpack("It costs 1,000.50 baht", "ราคา 1,000.50 บาท")) == []


def test_check_numbers_ignores_non_dict_items():
    assert S.check_numbers("p", {"phrases": ["x", {"en": 1, "th": 2}]}) == []


def test_check_default_unchanged_and_opt_in(tmp_path):
    d = {"id": "p", "names": {"de": "P", "en": "P", "th": "พ"}, "style": "neutral",
         "phrases": [{"en": "Room 12", "th": "ห้อง ๑๒"}]}
    (tmp_path / "p.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    assert S.check(str(tmp_path)) == []
    assert any(x["code"] == "numbers" for x in S.check(str(tmp_path), numbers=True))


def test_fuzzy_match_finds_typo_and_orders():
    packs = {"a": {"phrases": [{"en": "Where is the toilet?", "th": "ห้องน้ำอยู่ที่ไหน"},
                               {"en": "How much is this?", "th": "อันนี้เท่าไหร่", "critical": True}]},
             "b": {"phrases": [{"en": "Where is the toilet", "th": "ห้องน้ำอยู่ไหน"}]}}
    hits = S.fuzzy_match("where is the tolet", packs)
    assert [(h["pack"], h["index"]) for h in hits] == [("a", 0), ("b", 0)]
    assert hits[0]["score"] >= 0.8 and hits[0]["th"] == "ห้องน้ำอยู่ที่ไหน"
    assert S.fuzzy_match("completely different", packs) == []
    assert S.fuzzy_match("how much is this", packs, limit=1)[0]["critical"] is True


def test_fuzzy_match_thai_and_bad_input():
    packs = {"a": {"phrases": [{"en": "Thank you", "th": "ขอบคุณมาก"}]}}
    assert S.fuzzy_match("ขอบคุณมากๆ", packs, lang="th")[0]["en"] == "Thank you"
    assert S.fuzzy_match("", packs) == [] and S.fuzzy_match("x", packs, lang="de") == []
    assert S.fuzzy_match("thank you", {"a": {"phrases": "kaputt"}}) == []


def test_similarity_ignores_case_punctuation_space():
    assert S.similarity("Thank you!", "thank   you") == 1.0
    assert S.similarity("", "x") == 0.0


def test_near_duplicates_found_but_not_exact_or_distinct():
    d = {"phrases": [{"en": "Please call a doctor now", "th": "กรุณาเรียกหมอ"},
                     {"en": "Please call a doctor, now!!", "th": "กรุณาเรียกหมอ"},
                     {"en": "Please call a doctors now", "th": "กรุณาเรียกแท็กซี่"},
                     {"en": "Where is the bank", "th": "ธนาคารอยู่ไหน"}]}
    f = S.check_near_duplicates("p", d)
    assert {x["where"] for x in f} == {"phrases[1]", "phrases[2]"} and f[0]["code"] == "near_duplicate"


def test_shipped_presets_strict_checks_still_ok():
    assert [x for x in S.check() if x["severity"] == S.ERROR] == []


def test_cli_flags(tmp_path, capsys):
    d = {"id": "p", "names": {"de": "P", "en": "P", "th": "พ"}, "style": "neutral",
         "phrases": [{"en": "Room 12", "th": "ห้อง 13"}]}
    (tmp_path / "p.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    assert S.main(["check", "--dir", str(tmp_path)]) == 0
    assert S.main(["check", "--dir", str(tmp_path), "--numbers", "--strict"]) == 1
    assert "numbers" in capsys.readouterr().out
