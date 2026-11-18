"""Runde 8 (Cloud): JSON-Protokoll der Engine – unbekannte Felder, kaputte Zeilen, ungültige Werte, Sprachtabelle.
Kein Netz, kein Modell, kein Mikrofon."""
import json
import threading
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _eng(**kw):
    base = dict(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False, paused=False,
                rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False, beam=1)
    base.update(kw)
    return types.SimpleNamespace(**base)


@pytest.fixture
def pair(monkeypatch):
    """Sprachpaar-Zustand je Test zurücksetzen (Modulzustand)."""
    old = (list(d.PAIR), dict(d.TARGET))
    yield
    d.PAIR[:], d.TARGET.clear()
    d.TARGET.update(old[1])
    d.PAIR[:] = old[0]


def _kinds(ev):
    return [e for e, _ in ev]


# ---- _json_line ---------------------------------------------------------------------------------------------

def test_json_line_nan_and_inf_become_null():
    row = json.loads(d._json_line("utt", {"lp": float("nan"), "x": float("inf"), "y": float("-inf")}))
    assert row == {"event": "utt", "lp": None, "x": None, "y": None}


def test_json_line_keeps_thai_unescaped():
    line = d._json_line("utt", {"text": "สวัสดีครับ"})
    assert "สวัสดีครับ" in line and "\\u" not in line


def test_json_line_nested_nan_in_lists():
    row = json.loads(d._json_line("x", {"a": [1.0, float("nan"), {"b": float("inf")}]}))
    assert row["a"] == [1.0, None, {"b": None}]


def test_json_line_is_single_line_even_with_newlines_in_text():
    line = d._json_line("utt", {"text": "a\nb\r\nc d"})
    assert "\n" not in line and "\r" not in line
    assert json.loads(line)["text"] == "a\nb\r\nc d"


def test_json_line_numpy_scalars():
    import numpy as np
    row = json.loads(d._json_line("x", {"a": np.float32(0.5), "b": np.int64(3), "c": np.float64("nan")}))
    assert row["a"] == 0.5 and row["b"] == 3 and row["c"] is None


def test_json_line_event_key_comes_first_and_is_not_overridable_by_unknown_fields():
    row = json.loads(d._json_line("pong", {"id": 1, "zzz_unbekannt": "x"}))
    assert row["event"] == "pong" and row["zzz_unbekannt"] == "x"


# ---- _as_bool / _flag / _choice / _clamp / _text_arg ---------------------------------------------------------

@pytest.mark.parametrize("v,want", [
    (True, True), (False, False), (1, True), (0, False), ("true", True), ("FALSE", False), (" 1 ", True),
    ("0", False), (2, None), (-1, None), ("yes", None), ("", None), (None, None), ([], None), ({}, None),
    (1.0, None), ("on", None),
])
def test_as_bool_is_strict(v, want):
    assert d._as_bool(v) is want


def test_flag_missing_key_and_invalid_value(monkeypatch):
    assert d._flag({}, "speak") == (False, None)
    assert d._flag({"speak": "maybe"}, "speak") == (False, None)
    assert d._flag({"speak": "false"}, "speak") == (True, False)


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), float("-inf"), True, False, "5", None, [1], {"a": 1}])
def test_clamp_rejects_non_numbers(bad):
    assert d._clamp(bad, 0, 10) is None


@pytest.mark.parametrize("v,want", [(-5, 0), (50, 10), (3, 3), (0.5, 0.5), (10, 10)])
def test_clamp_limits(v, want):
    assert d._clamp(v, 0, 10) == want


def test_choice_unhashable_value_is_reported_not_raised(ev):
    assert d._choice({"style": ["polite"]}, "style", ("polite", "neutral")) is None
    assert ev == [("control_invalid", {"key": "style", "reason": "value"})]


def test_choice_missing_key_is_silent(ev):
    assert d._choice({}, "style", ("polite",)) is None
    assert ev == []


def test_text_arg_trims_and_limits():
    assert d._text_arg("  hi  ") == "hi"
    assert d._text_arg("   ") is None
    assert d._text_arg("x" * 11, 10) is None
    assert d._text_arg(5) is None and d._text_arg(None) is None


# ---- apply_control: unbekannte Felder, ungültige Werte -------------------------------------------------------

def test_unknown_fields_are_reported_and_known_ones_still_applied(ev):
    e = _eng()
    d.apply_control(e, {"rate": 12, "zukunftsfeld": 1, "noch_eins": {"a": 1}})
    assert e.rate == 12
    ign = [kw for k, kw in ev if k == "control_ignored"]
    assert ign == [{"keys": ["noch_eins", "zukunftsfeld"]}]


def test_unknown_field_names_are_truncated_and_limited(ev):
    d.apply_control(_eng(), {("k" * 100) + str(i): 1 for i in range(30)})
    keys = [kw for k, kw in ev if k == "control_ignored"][0]["keys"]
    assert len(keys) == 10 and all(len(k) <= 40 for k in keys)


def test_empty_control_line_emits_nothing(ev):
    assert d.apply_control(_eng(), {}) is None
    assert ev == []


@pytest.mark.parametrize("bad", [None, "fast", 5, ["a"], {"a": 1}])
def test_invalid_sensitivity_is_reported_and_vad_unchanged(ev, bad):
    before = dict(d.VAD)
    d.apply_control(_eng(), {"sensitivity": bad})
    assert d.VAD == before
    assert ("control_invalid", {"key": "sensitivity", "reason": "value"}) in ev


@pytest.mark.parametrize("bad", [float("nan"), "5", True, None, [1]])
def test_invalid_rate_keeps_old_value(ev, bad):
    e = _eng(rate=7)
    d.apply_control(e, {"rate": bad})
    assert e.rate == 7


def test_rate_and_volume_are_clamped(ev):
    e = _eng()
    d.apply_control(e, {"rate": 9999, "volume": 99})
    assert e.rate == 50 and e.volume == 2.0
    d.apply_control(e, {"rate": -9999, "volume": -1})
    assert e.rate == -50 and e.volume == 0.2


def test_silence_is_clamped(ev, monkeypatch):
    monkeypatch.setattr(d, "SILENCE_END", 0.7)
    d.apply_control(_eng(), {"silence": 100})
    assert d.SILENCE_END == 2.0
    d.apply_control(_eng(), {"silence": 0})
    assert d.SILENCE_END == 0.4


def test_ping_echoes_only_short_scalar_ids(ev):
    d.apply_control(_eng(), {"ping": "abc"})
    d.apply_control(_eng(), {"ping": 7})
    d.apply_control(_eng(), {"ping": "x" * 65})
    d.apply_control(_eng(), {"ping": True})
    d.apply_control(_eng(), {"ping": {"a": 1}})
    pongs = [kw for k, kw in ev if k == "pong"]
    assert pongs == [{"id": "abc"}, {"id": 7}, {}, {}, {}]


def test_say_with_unknown_language_is_rejected(ev):
    jobs = d.apply_control(_eng(), {"say": {"text": "hello", "lang": "xx"}})
    assert not jobs
    assert ("error", {"code": "phrase_invalid"}) in [(k, {"code": kw.get("code")}) for k, kw in ev]


def test_say_with_empty_or_overlong_text_is_rejected(ev):
    d.apply_control(_eng(), {"say": {"text": "   ", "lang": "en"}})
    d.apply_control(_eng(), {"say": {"text": "x" * 5000, "lang": "en"}})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["phrase_invalid", "phrase_invalid"]


def test_say_not_a_dict_is_ignored_silently(ev):
    assert not d.apply_control(_eng(), {"say": "hello"})
    assert "error" not in _kinds(ev)


def test_reassign_with_bad_role_is_rejected(ev):
    d.apply_control(_eng(), {"reassign": {"id": "u1", "role": "admin"}})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["reassign_invalid"]


def test_retranslate_without_text_is_rejected(ev):
    d.apply_control(_eng(), {"retranslate": {"id": "u1"}})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["edit_invalid"]


def test_glossary_non_string_is_rejected(ev):
    d.apply_control(_eng(), {"glossary": ["a", "b"]})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["glossary_invalid"]


def test_glossary_too_long_is_rejected(ev):
    d.apply_control(_eng(), {"glossary": "x" * (d.GLOSSARY_MAX + 1)})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["glossary_invalid"]


@pytest.mark.parametrize("bad", [None, 5, ["x"], {"a": 1}])
def test_reset_learning_needs_a_string_name(ev, bad):
    d.apply_control(_eng(), {"reset_learning": bad})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["profile_name_invalid"]


def test_output_device_overlong_is_rejected(ev):
    d.apply_control(_eng(), {"output_device": "x" * 301})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["output_invalid"]


def test_unknown_voice_is_reported_and_kept(ev):
    e = _eng(voices={"en": "Aria", "th": None})
    d.apply_control(e, {"voice_en": "GibtEsNicht"})
    assert e.voices["en"] == "Aria"
    assert [kw["code"] for k, kw in ev if k == "error"] == ["voice_unknown"]


def test_voice_null_resets_to_default(ev):
    e = _eng(voices={"en": "Aria", "th": None})
    d.apply_control(e, {"voice_en": None})
    assert e.voices["en"] is None


def test_every_ctrl_key_is_a_string_and_language_keys_are_present():
    assert all(isinstance(k, str) for k in d.CTRL_KEYS)
    for code in d.LANGS:
        assert f"tr_{code}" in d.CTRL_KEYS and f"voice_{code}" in d.CTRL_KEYS


# ---- Sprachpaar -----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("a,b", [("en", "en"), ("en", "xx"), (None, "th"), ("en", None), ("en", ["th"]),
                                 (1, 2), ("", "th"), ("  ", "th")])
def test_parse_pair_rejects(a, b):
    assert d.parse_pair(a, b) is None


def test_parse_pair_normalizes_case_and_space():
    assert d.parse_pair(" EN ", "Th") == ("en", "th")


def test_invalid_langs_leaves_pair_unchanged_and_reports(ev, pair):
    before = list(d.PAIR)
    d.apply_control(_eng(), {"langs": {"mine": "en", "partner": "en"}})
    assert list(d.PAIR) == before
    assert [kw["code"] for k, kw in ev if k == "error"] == ["langs_invalid"]


@pytest.mark.parametrize("bad", ["en", ["en", "th"], None, 5, {"mine": "en"}])
def test_langs_wrong_shape_reports(ev, pair, bad):
    d.apply_control(_eng(), {"langs": bad})
    assert [kw["code"] for k, kw in ev if k == "error"] == ["langs_invalid"]


def test_set_pair_updates_target_both_ways(pair):
    assert d.set_pair("de", "th")
    assert d.target_of("de") == "th" and d.target_of("th") == "de"
    assert set(d.TARGET) == {"de", "th"}
    assert d.other_lang("de") == "th"


def test_target_of_third_language_goes_to_partner(pair):
    d.set_pair("en", "th")
    assert d.target_of("fr") == "th"


def test_set_langs_resets_foreign_lock_to_auto(ev, pair):
    e = _eng(lock="en")
    assert d.set_langs(e, "de", "th")
    assert e.lock == "auto"
    assert ("langs", {"mine": "de", "partner": "th"}) in ev


def test_set_langs_keeps_translate_flags_for_remaining_language(ev, pair):
    e = _eng(translate_dir={"en": False, "th": True})
    d.set_langs(e, "en", "de")
    assert e.translate_dir == {"en": False, "de": True}


# ---- control_loop: kaputte Zeilen ---------------------------------------------------------------------------

def _run_loop(monkeypatch, lines, eng=None):
    monkeypatch.setattr(d, "_stdin_lines", lambda: iter(lines))
    monkeypatch.setattr(d, "log", lambda *a, **k: None)
    d.STOP.clear()
    applied = []
    monkeypatch.setattr(d, "apply_control", lambda e, dd: applied.append(dd))
    t = d.control_loop(eng or _eng())
    th = t if isinstance(t, threading.Thread) else None
    if th:
        th.join(5)
    return applied


def _loop_thread(monkeypatch, lines):
    """control_loop startet einen Thread (oder läuft direkt): beides abwarten."""
    before = {t for t in threading.enumerate()}
    applied = _run_loop(monkeypatch, lines)
    for t in set(threading.enumerate()) - before:
        t.join(5)
    return applied


def test_control_loop_skips_broken_lines_and_continues(monkeypatch):
    lines = ['{"rate": 5}\n', "{kaputt\n", "\n", "[1, 2]\n", '"text"\n', "42\n", "null\n", '{"rate": 6}\n']
    applied = _loop_thread(monkeypatch, lines)
    assert applied == [{"rate": 5}, {"rate": 6}]
    assert d.STOP.is_set()                      # Ende von stdin = geordnetes Ende
    d.STOP.clear()


def test_control_loop_ignores_oversize_line(monkeypatch):
    big = '{"glossary": "' + "x" * (d.CTRL_LINE_MAX + 5) + '"}\n'
    applied = _loop_thread(monkeypatch, [big, '{"rate": 1}\n'])
    assert applied == [{"rate": 1}]
    d.STOP.clear()


def test_control_loop_survives_exception_in_apply_control(monkeypatch):
    monkeypatch.setattr(d, "_stdin_lines", lambda: iter(['{"a": 1}\n', '{"b": 2}\n']))
    monkeypatch.setattr(d, "log", lambda *a, **k: None)
    seen = []

    def boom(e, dd):
        seen.append(dd)
        if "a" in dd:
            raise RuntimeError("kaputt")
    monkeypatch.setattr(d, "apply_control", boom)
    d.STOP.clear()
    before = set(threading.enumerate())
    d.control_loop(_eng())
    for t in set(threading.enumerate()) - before:
        t.join(5)
    assert seen == [{"a": 1}, {"b": 2}]
    d.STOP.clear()


def test_bad_json_log_is_rate_limited(monkeypatch):
    logs = []
    monkeypatch.setattr(d, "_stdin_lines", lambda: iter(["{x\n"] * 20))
    monkeypatch.setattr(d, "log", lambda o, *a, **k: logs.append(o))
    monkeypatch.setattr(d, "apply_control", lambda e, dd: None)
    monkeypatch.setitem(d._BAD_JSON, "t", 0.0)
    monkeypatch.setitem(d._BAD_JSON, "n", 0)
    d.STOP.clear()
    before = set(threading.enumerate())
    d.control_loop(_eng())
    for t in set(threading.enumerate()) - before:
        t.join(5)
    bad = [x for x in logs if isinstance(x, dict) and x.get("control") == "ungültiges JSON"]
    assert 1 <= len(bad) <= 2
    d.STOP.clear()


# ---- Sprachtabelle ---------------------------------------------------------------------------------------------

def _table(tmp_path, mutate=None):
    raw = json.loads(open(d.LANGS_FILE, encoding="utf-8").read())
    if mutate:
        mutate(raw)
    p = tmp_path / "languages.json"
    p.write_text(json.dumps(raw), encoding="utf-8")
    return str(p)


def test_load_lang_table_reads_the_shipped_file():
    scripts, langs, default = d.load_lang_table()
    assert default == ("en", "th") and {"en", "th"} <= set(langs) and "thai" in scripts


def test_load_lang_table_missing_file_falls_back_to_builtin(tmp_path):
    scripts, langs, default = d.load_lang_table(str(tmp_path / "gibt-es-nicht.json"))
    assert default == ("en", "th") and "th" in langs and "latin" in scripts


def test_load_lang_table_broken_json_is_an_error_not_a_fallback(tmp_path):
    p = tmp_path / "languages.json"
    p.write_text("{kaputt", encoding="utf-8")
    with pytest.raises(ValueError):
        d.load_lang_table(str(p))


def test_load_lang_table_missing_field_raises_keyerror(tmp_path):
    path = _table(tmp_path, lambda r: r["languages"][0].pop("edge"))
    with pytest.raises(KeyError):
        d.load_lang_table(path)


def test_load_lang_table_custom_default_pair(tmp_path):
    path = _table(tmp_path, lambda r: r.update(default_pair=["de", "th"]))
    assert d.load_lang_table(path)[2] == ("de", "th")


def test_load_lang_table_ignores_unknown_top_level_and_language_fields(tmp_path):
    def mut(r):
        r["zukunft"] = {"a": 1}
        r["languages"][0]["neues_feld"] = [1, 2]
    scripts, langs, _ = d.load_lang_table(_table(tmp_path, mut))
    assert "en" in langs


def test_load_lang_table_error_is_converted_to_json_line_and_exit4(monkeypatch, capsys):
    def bad():
        raise KeyError("edge")
    monkeypatch.setattr(d, "load_lang_table", bad)
    with pytest.raises(SystemExit) as ex:
        d._load_lang_table_or_exit()
    assert ex.value.code == 4
    row = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert row["event"] == "error" and row["code"] == "languages_invalid" and "edge" in row["msg"]


def test_language_codes_are_lowercase_unique_and_have_voices():
    assert len(d.LANGS) == len(set(d.LANGS))
    for code, v in d.LANGS.items():
        assert code == code.lower()
        assert v["m"] in v["voices"] and v["f"] in v["voices"]
        assert v["min_lp"] < 0 and v["say"]


def test_lang_name_variants():
    assert d.lang_name("th") == "Thai"
    assert d.lang_name("de", de=True) == "Deutsch"
    assert d.lang_name("zz") == "zz" and d.lang_name(None) == "None"


def test_mt_code_special_cases():
    assert d.mt_code("zh") == "zh-CN"
    assert d.mt_code("th") == "th" and d.mt_code("unbekannt") == "unbekannt"


@pytest.mark.parametrize("a,b,want", [("en", "th", True), ("de", "ja", True), ("de", "es", False),
                                      ("zh", "ja", False), ("en", "zz", False), ("zz", "yy", False)])
def test_scripts_distinct(a, b, want):
    assert d.scripts_distinct(a, b) is want


@pytest.mark.parametrize("text,lang,lo,hi", [
    ("", "th", 0.0, 0.0), ("12345 !!!", "th", 0.0, 0.0), ("สวัสดี", "th", 1.0, 1.0), ("hello", "th", 0.0, 0.0),
    ("hello", "en", 1.0, 1.0), ("hello สวัสดี", "th", 0.3, 0.5), ("abc", "unbekannt", 0.0, 0.0),
    ("Привет", "ru", 1.0, 1.0), ("你好", "zh", 1.0, 1.0),
])
def test_script_share_ranges(text, lang, lo, hi):
    assert lo <= d.script_share(text, lang) <= hi


# ---- Sprachbefehle -----------------------------------------------------------------------------------------------

def test_parse_command_empty_is_wake_and_overlong_is_none():
    assert d.parse_command("") == "wake" and d.parse_command("  .! ") == "wake"
    assert d.parse_command(" ".join(["wort"] * 40)) is None


def test_parse_command_preset_spoken():
    assert d.parse_command("preset off") == "preset:none"
    assert d.parse_command("hotel mode") == "preset:hotel"
