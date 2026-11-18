"""Runde 8 (Cloud): Presets (presets.py), Korrektur-Lernen (correction_learning.py), Hardware-Wahl (hwprofile.py).
Kein Netz, kein Modell, keine echte Hardware (sysctl/pmset sind Attrappen)."""
import json
import os
import types

import pytest

import correction_learning as cl
import hwprofile as hw
import presets as P


def _ok(**kw):
    return {"id": "test", "names": {"de": "Test", "en": "Test", "th": "ทดสอบ"}, "style": "neutral", **kw}


# ---- validate ------------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("bad", [None, [], "x", 5, True, [{}]])
def test_validate_non_dict(bad):
    assert P.validate(bad) == ["kein Objekt"]


def test_validate_minimal_is_valid():
    assert P.validate(_ok()) == []


def test_validate_empty_dict_lists_the_three_required_problems():
    assert len(P.validate({})) == 3


@pytest.mark.parametrize("pid,valid", [("a", True), ("a" * 32, True), ("a" * 33, False), ("-a", False), ("_a", False),
                                       ("A", False), ("a b", False), ("", False), (None, False), (5, False),
                                       ("a-b_c9", True), ("ä", False), ("../x", False)])
def test_validate_id(pid, valid):
    assert (P.validate(_ok(id=pid)) == []) is valid


@pytest.mark.xfail(strict=True, reason="ID_RE endet mit $: eine id mit angehängtem Zeilenumbruch ('a\\n') gilt als "
                                       "gültig (re.match + $ trifft vor dem letzten \\n); fullmatch/\\Z nötig")
def test_validate_id_with_trailing_newline_is_invalid():
    assert P.validate(_ok(id="a\n")) != []


@pytest.mark.parametrize("names", [
    {"de": "a", "en": "b"}, {"de": "a", "en": "b", "th": ""}, {"de": "a", "en": "b", "th": "  "},
    {"de": "a" * 41, "en": "b", "th": "c"}, {"de": 1, "en": "b", "th": "c"}, [], None, "x"])
def test_validate_names_invalid(names):
    assert any("names" in e for e in P.validate(_ok(names=names)))


def test_validate_names_extra_language_is_tolerated():
    assert P.validate(_ok(names={"de": "a", "en": "b", "th": "c", "fr": "d"})) == []


@pytest.mark.parametrize("style,valid", [("casual", True), ("neutral", True), ("polite", True), ("formal", False),
                                         (None, False), ("", False), (1, False)])
def test_validate_style(style, valid):
    assert (P.validate(_ok(style=style)) == []) is valid


@pytest.mark.parametrize("polite,valid", [("krub", True), ("ka", True), ("KRUB", False), ("", False), (None, False)])
def test_validate_polite(polite, valid):
    assert (P.validate(_ok(polite=polite)) == []) is valid


@pytest.mark.parametrize("voice,valid", [({"en": "Aria"}, True), ({"en": "A", "th": "B"}, True), ({}, True),
                                         ({"de": "x"}, False), ({"en": ""}, False), ({"en": 5}, False), ("x", False),
                                         ({"en": "x" * 65}, False)])
def test_validate_voice(voice, valid):
    assert (P.validate(_ok(voice=voice)) == []) is valid


def test_validate_glossary_and_phrase_limits():
    pair = {"en": "a", "th": "ก"}
    assert P.validate(_ok(glossary=[pair] * P.MAX_GLOSSARY)) == []
    assert P.validate(_ok(glossary=[pair] * (P.MAX_GLOSSARY + 1)))
    assert P.validate(_ok(phrases=[pair] * P.MAX_PHRASES)) == []
    assert P.validate(_ok(phrases=[pair] * (P.MAX_PHRASES + 1)))


@pytest.mark.parametrize("item", [{"en": "a"}, {"th": "ก"}, {"en": "", "th": "ก"}, {"en": "a" * 61, "th": "ก"},
                                  "text", None, 5, {"en": 1, "th": 2}])
def test_validate_glossary_item_invalid(item):
    assert P.validate(_ok(glossary=[item]))


@pytest.mark.parametrize("crit,valid", [(True, True), (False, True), ("yes", False), (1, False), (None, False)])
def test_validate_phrase_critical_must_be_bool(crit, valid):
    assert (P.validate(_ok(phrases=[{"en": "a", "th": "ก", "critical": crit}])) == []) is valid


def test_validate_phrase_allows_longer_text_than_glossary():
    assert P.validate(_ok(phrases=[{"en": "a" * 200, "th": "ก" * 200}])) == []
    assert P.validate(_ok(phrases=[{"en": "a" * 201, "th": "ก"}]))


@pytest.mark.parametrize("note,valid", [({"de": "a", "en": "b"}, True), ({"de": "a", "en": "b", "th": "ก"}, True),
                                        ({"de": "a"}, False), ({"de": "a", "en": ""}, False),
                                        ({"de": "a", "en": "b", "fr": "c"}, False), ("x", False), (None, False),
                                        ({"de": "a" * 501, "en": "b"}, False)])
def test_validate_note(note, valid):
    assert (P.validate(_ok(note=note)) == []) is valid


def test_validate_hotwords_and_hint_limits():
    assert P.validate(_ok(hotwords=["a"] * P.MAX_HOTWORDS)) == []
    assert P.validate(_ok(hotwords=["a"] * (P.MAX_HOTWORDS + 1)))
    assert P.validate(_ok(hotwords=["a" * 61]))
    assert P.validate(_ok(hotwords=[1]))
    assert P.validate(_ok(llm_hint="x" * P.MAX_HINT)) == []
    assert P.validate(_ok(llm_hint="x" * (P.MAX_HINT + 1)))
    assert P.validate(_ok(llm_hint="   "))


@pytest.mark.parametrize("tun,valid", [
    ({"rate": 50}, True), ({"rate": -50.0}, True), ({"rate": 51}, False), ({"rate": True}, False),
    ({"rate": "5"}, False), ({"silence": 0.4}, True), ({"silence": 0.39}, False), ({"silence": 2.01}, False),
    ({"let_finish": 0}, True), ({"let_finish": 5.1}, False),
    ({"sensitivity": "high"}, True), ({"sensitivity": "max"}, False), ({"sensitivity": 1}, False),
    ({"catch_up": "skip"}, True), ({"catch_up": "x"}, False),
    ({}, True), ({"unbekannt": 1}, False), ("x", False), (None, False), ([], False),
])
def test_validate_tuning(tun, valid):
    assert (P.validate(_ok(tuning=tun)) == []) is valid


def test_validate_unknown_fields_are_listed_sorted():
    err = P.validate(_ok(zzz=1, aaa=2))
    assert err == ["unbekannte Felder: aaa, zzz"]


def test_validate_never_raises_on_weird_nested_values():
    for key in ("names", "voice", "glossary", "phrases", "note", "hotwords", "llm_hint", "tuning", "style", "polite"):
        for v in (None, 0, [], {}, [[]], [{}], {"a": {}}, float("nan"), "\x00"):
            assert isinstance(P.validate(_ok(**{key: v})), list)


# ---- Laden: App- und Nutzerordner ----------------------------------------------------------------------------------

@pytest.fixture
def dirs(tmp_path, monkeypatch):
    app, home = tmp_path / "app", tmp_path / "home"
    (app).mkdir()
    (home / "presets").mkdir(parents=True)
    monkeypatch.setattr(P, "app_dir", lambda: str(app))
    monkeypatch.setenv("DOLMETSCHER_HOME", str(home))
    monkeypatch.setitem(P._LOAD_CACHE, "sig", None)
    monkeypatch.setitem(P._LOAD_CACHE, "val", None)
    return app, home / "presets"


def _w(folder, name, obj):
    (folder / name).write_text(obj if isinstance(obj, str) else json.dumps(obj), encoding="utf-8")


def test_user_preset_overrides_shipped_one_and_is_listed(dirs):
    app, user = dirs
    _w(app, "hotel.json", _ok(id="hotel", style="polite"))
    _w(user, "hotel.json", _ok(id="hotel", style="casual"))
    got = P.load_all()
    assert got["hotel"]["style"] == "casual" and P.overridden == ["hotel"]


def test_broken_and_invalid_files_are_skipped_with_reason(dirs):
    app, user = dirs
    _w(app, "ok.json", _ok(id="ok"))
    _w(app, "kaputt.json", "{nicht json")
    _w(app, "falsch.json", {"id": "BAD"})
    _w(user, "liste.json", "[1]")
    got = P.load_all()
    assert list(got) == ["ok"]
    assert len(P.last_errors) == 3
    assert any("lesen" in v for v in P.last_errors.values())


def test_missing_folders_give_empty_result(tmp_path, monkeypatch):
    monkeypatch.setattr(P, "app_dir", lambda: str(tmp_path / "nein"))
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path / "auch-nicht"))
    monkeypatch.setitem(P._LOAD_CACHE, "sig", None)
    assert P.load_all() == {}


def test_non_json_files_and_subfolders_are_ignored(dirs):
    app, _ = dirs
    _w(app, "notiz.txt", "x")
    (app / "ordner.json").mkdir()
    _w(app, "ok.json", _ok(id="ok"))
    assert list(P.load_all()) == ["ok"]


def test_cache_picks_up_new_and_changed_files(dirs):
    app, user = dirs
    _w(app, "a.json", _ok(id="a"))
    assert list(P.load_all()) == ["a"]
    _w(user, "b.json", _ok(id="b"))
    assert sorted(P.load_all()) == ["a", "b"]
    _w(user, "b.json", _ok(id="b", style="polite", glossary=[{"en": "x", "th": "ก"}]))   # andere Größe
    assert P.load_all()["b"]["style"] == "polite"


def test_load_all_returns_a_copy_of_the_cache(dirs):
    app, _ = dirs
    _w(app, "a.json", _ok(id="a"))
    first = P.load_all()
    first.clear()
    assert list(P.load_all()) == ["a"]


def test_bom_json_is_reported_not_crashing(dirs):
    app, _ = dirs
    (app / "bom.json").write_bytes(b"\xef\xbb\xbf" + json.dumps(_ok(id="bom")).encode())
    P.load_all()
    assert len(P.last_errors) == 1


def test_shipped_presets_are_all_valid_and_ids_match_filenames():
    app = P.app_dir()
    for fn in os.listdir(app):
        if fn.endswith(".json"):
            d = json.load(open(os.path.join(app, fn), encoding="utf-8"))
            assert P.validate(d) == [], fn
            assert d["id"] == fn[:-5], fn


# ---- find / parse_spoken -------------------------------------------------------------------------------------------

PRES = {"hotel": {"names": {"de": "Hotel", "en": "Hotel (stay)", "th": "โรงแรม"}},
        "taxi": {"names": {"de": "Taxi", "en": "Taxi", "th": "แท็กซี่"}}}


@pytest.mark.parametrize("spoken,want", [("hotel", "hotel"), ("HOTEL", "hotel"), ("  Hotel!  ", "hotel"),
                                         ("โรงแรม", "hotel"), ("taxi", "taxi"), ("hotel stay", None),
                                         ("", None), (None, None), ("   ", None), ("!!!", None), ("nope", None)])
def test_find(spoken, want):
    assert P.find(spoken, PRES) == want


@pytest.mark.parametrize("cmd,want", [
    ("hotel mode", "preset:hotel"), ("preset taxi", "preset:taxi"), ("Preset Hotel.", "preset:hotel"),
    ("preset off", "preset:none"), ("preset none", "preset:none"), ("preset clear", "preset:none"),
    ("preset reset", "preset:none"),
    ("mode", None), ("preset", None), ("", None), (None, None), ("taxi", None), ("hotel", None),
    ("preset gibt es nicht", None), ("this is a long sentence about hotel mode", None),
    ("hotel mode please", None), ("off mode", None),
])
def test_parse_spoken(cmd, want):
    assert P.parse_spoken(cmd, PRES) == want


# ---- app_fields / glossary_entries ---------------------------------------------------------------------------------

def test_app_fields_without_preset():
    assert P.app_fields(None) == {"note": None, "phrases": []} and P.app_fields({}) == {"note": None, "phrases": []}


def test_app_fields_phrases_get_critical_flag_and_note_is_copied():
    note = {"de": "a", "en": "b"}
    out = P.app_fields({"note": note, "phrases": [{"en": "a", "th": "ก", "critical": True}, {"en": "b", "th": "ข"}]})
    assert [p["critical"] for p in out["phrases"]] == [True, False]
    out["note"]["de"] = "geändert"
    assert note["de"] == "a"


def test_app_fields_non_dict_note_becomes_none():
    assert P.app_fields({"note": "text"})["note"] is None


def test_glossary_entries_both_directions():
    assert P.glossary_entries({"glossary": [{"en": "a", "th": "ก"}]}) == [("a", "ก"), ("ก", "a")]
    assert P.glossary_entries({}) == []


# ---- PresetState ---------------------------------------------------------------------------------------------------

def _env():
    llm = {"style": "neutral"}
    eng = types.SimpleNamespace(polite="krub", voices={"en": "Aria", "th": "Premwadee"})
    return llm, eng, [("eigen", "own")]


def _preset(**kw):
    return _ok(id="p", style="polite", polite="ka", glossary=[{"en": "hotel", "th": "โรงแรม"}],
               hotwords=["  Amari  "], llm_hint="  sei höflich  ", **kw)


def test_activate_applies_and_deactivate_restores_everything():
    llm, eng, gl = _env()
    st = P.PresetState()
    p = st.activate("p", {"p": _preset(voice={"en": "Jenny"})}, gl, llm, eng, voices={"en": ["Jenny", "Aria"]})
    assert p["id"] == "p" and llm["style"] == "polite" and eng.polite == "ka" and eng.voices["en"] == "Jenny"
    assert ("eigen", "own") in gl and ("hotel", "โรงแรม") in gl and ("โรงแรม", "hotel") in gl
    assert st.hotwords == ["Amari"] and st.hint == "sei höflich" and st.active == "p"
    assert st.activate("none", {}, gl, llm, eng) is None
    assert llm["style"] == "neutral" and eng.polite == "krub" and eng.voices["en"] == "Aria"
    assert gl == [("eigen", "own")] and st.active is None and st.hotwords == [] and st.hint is None


@pytest.mark.parametrize("off", [None, "", "none"])
def test_activate_off_values_without_active_preset_change_nothing(off):
    llm, eng, gl = _env()
    assert P.PresetState().activate(off, {}, gl, llm, eng) is None
    assert llm["style"] == "neutral" and gl == [("eigen", "own")]


def test_activate_unknown_id_raises_and_leaves_state_alone():
    llm, eng, gl = _env()
    st = P.PresetState()
    st.activate("p", {"p": _preset()}, gl, llm, eng)
    with pytest.raises(KeyError):
        st.activate("gibtsnicht", {"p": _preset()}, gl, llm, eng)
    assert st.active == "p" and llm["style"] == "polite"


def test_user_change_during_preset_survives_deactivation():
    llm, eng, gl = _env()
    st = P.PresetState()
    st.activate("p", {"p": _preset()}, gl, llm, eng)
    llm["style"] = "casual"                              # Nutzer ändert währenddessen
    eng.polite = "krub"
    st.activate(None, {}, gl, llm, eng)
    assert llm["style"] == "casual" and eng.polite == "krub"


def test_switching_presets_restores_original_not_previous_preset():
    llm, eng, gl = _env()
    st = P.PresetState()
    presets = {"p": _preset(), "q": _ok(id="q", style="casual")}
    st.activate("p", presets, gl, llm, eng)
    st.activate("q", presets, gl, llm, eng)
    assert llm["style"] == "casual" and eng.polite == "krub" and ("hotel", "โรงแรม") not in gl
    st.activate(None, presets, gl, llm, eng)
    assert llm["style"] == "neutral"


def test_unknown_preset_voice_is_ignored():
    llm, eng, gl = _env()
    P.PresetState().activate("p", {"p": _preset(voice={"en": "Tippfehler"})}, gl, llm, eng, voices={"en": ["Aria"]})
    assert eng.voices["en"] == "Aria"


def test_own_glossary_entries_win_and_limit_applies():
    llm, eng, gl = _env()
    gl[:] = [("HOTEL", "mein hotel")]
    P.PresetState().activate("p", {"p": _preset()}, gl, llm, eng)
    assert ("hotel", "โรงแรม") not in gl and gl[0] == ("HOTEL", "mein hotel")
    gl2 = [(f"w{i}", f"v{i}") for i in range(10)]
    P.PresetState().activate("p", {"p": _preset()}, gl2, llm, eng, glossary_limit=11)
    assert len(gl2) == 11


# ---- correction_learning -------------------------------------------------------------------------------------------

@pytest.mark.parametrize("old,new,lang,want", [
    ("go to the temple", "go to Wat Pho temple", "en", ["Wat", "Pho"]),
    ("", "hello Bangkok", "en", ["hello", "Bangkok"]),
    ("hello", "hello", "en", []),
    ("meet Anna", "meet anna", "en", []),
    ("a b", "c d", "en", []),                                       # zu kurz
    ("pay 50 baht kg", "pay 50 baht Thonglor kg", "en", ["Thonglor"]),   # Zahlen und Einheiten nie
    ("x", "Привет Москва", "ru", ["Привет", "Москва"]),
    ("ราคา", "ราคา สีลม", "th", ["สีลม"]),
    ("我要去", "我要去曼谷", "zh", ["曼谷"]),
    ("", "", "en", []), (None, None, "en", []), ("", None, "th", []),
])
def test_suggest_vocab(old, new, lang, want):
    assert cl.suggest_vocab(old, new, lang) == want


def test_suggest_vocab_limit_and_duplicates():
    new = " ".join(f"wort{chr(97 + i)}x" for i in range(20))
    assert len(cl.suggest_vocab("", new)) == cl.MAX_SUGGEST
    assert len(cl.suggest_vocab("", new, limit=3)) == 3
    assert cl.suggest_vocab("", "Siam siam SIAM") == ["Siam"]


def test_suggest_vocab_does_not_suggest_digits_dates_or_units():
    assert cl.suggest_vocab("", "500 baht 3.5kg 12:30 usd") == []


def test_suggest_vocab_pure_deletion_gives_nothing():
    assert cl.suggest_vocab("go to the big temple", "go to temple") == []


def test_suggest_vocab_never_raises_on_odd_text():
    for t in ("\x00", "🙂🙂🙂", "   ", "ก" * 5000, "a" * 5000 + " " + "b" * 5000, "​​", "'", "-", "..."):
        assert isinstance(cl.suggest_vocab("", t), list)
        assert isinstance(cl.suggest_vocab(t, ""), list)


@pytest.mark.parametrize("old,new,want", [
    ("take me to the beach", "take me to Chiang Mai beach", ["Chiang Mai"]),
    ("a", "One. Two Bangkok. Three Siam Paragon", ["Bangkok", "Siam Paragon"]),
    ("a", "go to NASA now", []),                                   # nur Großbuchstaben: Abkürzung
    ("a", "see you on Monday in May", []),                         # Wochentage/Monate
    ("a", "I'm Okay Dr Smith", ["Smith"]),
    ("meet Phuket", "meet Phuket", []),                            # schon im Original
    ("a", "Bangkok is big", []),                                   # Satzanfang: nicht unterscheidbar
    ("a", "", []), (None, None, []),
])
def test_proper_names(old, new, want):
    assert cl.proper_names(old, new, "en") == want


@pytest.mark.parametrize("lang,new", [("th", "ฉันไป Siam"), ("de", "ich gehe nach Berlin"), ("lb", "ech ginn Berlin"),
                                      ("zh", "我去 Bangkok"), ("en", "ไป Bangkok เมื่อวาน")])
def test_proper_names_empty_for_languages_without_capital_rule(lang, new):
    assert cl.proper_names("", new, lang) == []


def test_proper_names_limit():
    assert len(cl.proper_names("a", "go Anna Bert Carl Dora Emil", "en", limit=2)) <= 2


def test_tokenize_by_script():
    assert cl.tokenize("don't stop-it 3.5kg", "en") == ["don't", "stop-it", "3.5kg"]
    assert cl.tokenize("你好, 世界!", "zh") == ["你", "好", "世", "界"]
    assert cl.tokenize("", "en") == [] and cl.tokenize(None, "th") == []
    assert cl.tokenize("สวัสดีครับ", "th")


def test_thai_tokens_fall_back_when_pythainlp_fails(monkeypatch):
    import sys
    monkeypatch.setitem(sys.modules, "pythainlp", None)
    monkeypatch.setitem(sys.modules, "pythainlp.tokenize", None)
    assert cl._thai_tokens("ไป Siam 2024 วันนี้") == ["ไป", "Siam", "2024", "วันนี้"]


# ---- hwprofile -----------------------------------------------------------------------------------------------------

def _runner(table):
    def run(cmd, **kw):
        key = cmd[-1] if cmd[0] == "sysctl" else " ".join(cmd)
        v = table.get(key)
        if isinstance(v, Exception):
            raise v
        return types.SimpleNamespace(returncode=0 if v is not None else 1, stdout=v or "")
    return run


@pytest.mark.parametrize("info,model,beam", [
    ({}, "small", 1),
    ({"arm64": False, "ram_gb": 64, "chip": "Intel"}, "small", 1),
    ({"arm64": True, "ram_gb": 7.9, "chip": "Apple M1"}, "small", 1),
    ({"arm64": True, "ram_gb": 8, "chip": "Apple M1"}, "medium", 1),
    ({"arm64": True, "ram_gb": 15.9, "chip": "Apple M1"}, "medium", 1),
    ({"arm64": True, "ram_gb": 16, "chip": "Apple M2"}, "medium", 3),
    ({"arm64": True, "ram_gb": 24, "chip": "Apple M2"}, "medium", 3),
    ({"arm64": True, "ram_gb": 24, "chip": "Apple M2 Pro"}, "best", 5),
    ({"arm64": True, "ram_gb": 23.9, "chip": "Apple M2 Max"}, "medium", 3),
    ({"arm64": True, "ram_gb": 64, "chip": "APPLE M3 ULTRA"}, "best", 5),
    ({"arm64": True, "ram_gb": None, "chip": None}, "small", 1),
])
def test_recommend(info, model, beam):
    rec = hw.recommend(info)
    assert rec["model"] == model and rec["beam"] == beam and rec["model"] in hw.TIERS and rec["reason"]


def test_detect_reads_sysctl():
    run = _runner({"hw.memsize": str(16 * 2 ** 30), "machdep.cpu.brand_string": "Apple M2", "hw.optional.arm64": "1"})
    assert hw.detect(run, machine="arm64") == {"chip": "Apple M2", "ram_gb": 16.0, "arm64": True}


def test_detect_rosetta_asks_sysctl():
    run = _runner({"hw.memsize": str(8 * 2 ** 30), "hw.optional.arm64": "1"})
    assert hw.detect(run, machine="x86_64")["arm64"] is True
    assert hw.detect(_runner({"hw.memsize": str(8 * 2 ** 30)}), machine="x86_64")["arm64"] is False


@pytest.mark.parametrize("table", [{}, {"hw.memsize": "kein Zahl"}, {"hw.memsize": ""},
                                   {"hw.memsize": FileNotFoundError("sysctl")}, {"hw.memsize": OSError("x")}])
def test_detect_survives_missing_or_garbage_sysctl(table):
    info = hw.detect(_runner(table), machine="arm64")
    assert info["ram_gb"] == 0.0 and info["arm64"] is True


def test_detect_timeout_is_swallowed():
    import subprocess
    run = _runner({"hw.memsize": subprocess.TimeoutExpired("sysctl", 3)})
    assert hw.detect(run, machine="arm64")["ram_gb"] == 0.0


def test_auto_choice_merges_info_and_recommendation():
    run = _runner({"hw.memsize": str(32 * 2 ** 30), "machdep.cpu.brand_string": "Apple M3 Max",
                   "hw.optional.arm64": "1"})
    out = hw.auto_choice(run, machine="arm64")
    assert out["model"] == "best" and out["ram_gb"] == 32.0 and out["chip"] == "Apple M3 Max"


@pytest.mark.parametrize("table,want", [
    ({"hw.perflevel0.physicalcpu": "8", "hw.physicalcpu": "10"}, 8),
    ({"hw.physicalcpu": "4"}, 4),
    ({"hw.perflevel0.physicalcpu": "0", "hw.physicalcpu": "6"}, 6),
    ({"hw.perflevel0.physicalcpu": "abc", "hw.physicalcpu": "6"}, 6),
    ({}, 0),
])
def test_perf_cores(table, want):
    assert hw.perf_cores(_runner(table)) == want


@pytest.mark.parametrize("out,want", [
    ("Now drawing from 'Battery Power'\n -InternalBattery-0", True),
    ("Now drawing from 'AC Power'\n", False),
    ("now drawing from 'battery power'", True),
    ("", False),
])
def test_on_battery(out, want):
    assert hw.on_battery(_runner({"pmset -g batt": out})) is want


def test_on_battery_unknown_or_error_is_false():
    assert hw.on_battery(_runner({"pmset -g batt": FileNotFoundError("pmset")})) is False
    assert hw.on_battery(_runner({})) is False


def test_adjust_for_power_on_ac_is_identity():
    rec = {"model": "best", "beam": 5, "reason": "x"}
    assert hw.adjust_for_power(rec, False) is rec


def test_adjust_for_power_on_battery_saves_but_does_not_mutate():
    rec = {"model": "best", "beam": 5, "reason": "x"}
    out = hw.adjust_for_power(rec, True)
    assert out["model"] == "medium" and out["beam"] == 1 and "Akku" in out["reason"]
    assert rec == {"model": "best", "beam": 5, "reason": "x"}
    assert hw.adjust_for_power({"model": "small", "beam": 3, "reason": "y"}, True)["model"] == "small"
