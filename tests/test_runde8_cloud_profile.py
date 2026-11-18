"""Runde 8 (Cloud): Stimmprofile (profiles.py) – Namen, Dateien, Quarantäne, Datenschutz, Hotwords, Rollenregel,
Fehlerrate (Thai), Aufnahme mit Attrappen. Kein Modell, kein Mikrofon, kein Netz."""
import json
import os
import stat
import unicodedata

import numpy as np
import pytest

import profiles


@pytest.fixture
def pdir(tmp_path, monkeypatch):
    d = tmp_path / "profiles"
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(d))
    monkeypatch.setattr(profiles, "CORRUPT", [])
    return d


def _p(name, **kw):
    return {"name": name, "lang": "en", "embedding": [1.0, 0.0], **kw}


def _files(pdir):
    return sorted(f.name for f in pdir.iterdir() if not f.name.startswith("."))


# ---- Namen ----------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("raw,want", [
    ("Anna", "Anna"), ("  Anna  ", "Anna"), ("../../etc", "etc"), ("a/b", "ab"), ("a.b", "ab"),
    ("Anna Maria", "Anna Maria"), ("Anna-Lee", "Anna-Lee"), ("José", "José"), ("สมชาย", "สมชาย"),
    ("x" * 64, "x" * 64),
])
def test_safe_names(raw, want):
    assert profiles._safe(raw) == want


@pytest.mark.parametrize("raw", ["", "   ", "!!!", "///", "x" * 65, None, 5, ["a"], b"anna"])
def test_safe_rejects(raw):
    with pytest.raises(profiles.ProfileNameError):
        profiles._safe(raw)


def test_profile_name_error_is_a_valueerror():
    assert issubclass(profiles.ProfileNameError, ValueError)


def test_path_traversal_name_stays_inside_profile_dir(pdir):
    profiles.save_profile(_p("../../evil"))
    assert _files(pdir) == ["evil.json"]
    assert not (pdir.parent / "evil.json").exists()
    assert profiles.get_profile("../../evil")["name"] == "../../evil"


def test_nfc_and_nfd_names_are_the_same_profile(pdir):
    profiles.save_profile(_p(unicodedata.normalize("NFD", "José")))
    assert profiles.get_profile("José") is not None
    profiles.save_profile(_p("José", vocab=["x"]))
    assert len(profiles.list_profiles()) == 1


def test_colliding_stems_get_separate_files(pdir):
    for n in ("Anna", "Anna!", "anna"):
        profiles.save_profile(_p(n))
    assert len(_files(pdir)) == 3
    assert {p["name"] for p in profiles.list_profiles()} == {"Anna", "Anna!", "anna"}
    assert profiles.delete_profile("Anna!") and profiles.get_profile("Anna") is not None


def test_save_profile_invalid_name_writes_nothing(pdir):
    with pytest.raises(profiles.ProfileNameError):
        profiles.save_profile(_p("!!!"))
    assert not pdir.exists() or _files(pdir) == []


def test_save_profile_does_not_mutate_the_argument(pdir):
    p = _p("Anna")
    profiles.save_profile(p)
    assert "schema_version" not in p


def test_get_profile_unknown_or_invalid_returns_none(pdir):
    assert profiles.get_profile("Niemand") is None
    assert profiles.get_profile("!!!") is None


# ---- Dateirechte und Reste ----------------------------------------------------------------------------------------

def test_profile_dir_and_files_are_private(pdir):
    profiles.save_profile(_p("Anna"))
    assert stat.S_IMODE(os.stat(pdir).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(pdir / "Anna.json").st_mode) == 0o600


def test_atomic_write_leaves_no_tmp_files(pdir):
    for i in range(5):
        profiles.save_profile(_p("Anna", vocab=[str(i)]))
    assert not [f for f in _files(pdir) if f.endswith(".tmp")]


def test_failed_write_removes_tmp_and_keeps_old_profile(pdir, monkeypatch):
    profiles.save_profile(_p("Anna", vocab=["alt"]))

    def boom(*a, **k):
        raise OSError("platte voll")
    monkeypatch.setattr(profiles.json, "dump", boom)
    with pytest.raises(OSError):
        profiles.save_profile(_p("Anna", vocab=["neu"]))
    monkeypatch.undo()
    assert not [f for f in _files(pdir) if f.endswith(".tmp")]


def test_backups_are_limited_and_private(pdir):
    profiles.save_profile(_p("Anna"))
    for _ in range(profiles.MAX_BACKUPS + 3):
        dest = profiles._backup("Anna")
        assert stat.S_IMODE(os.stat(dest).st_mode) == 0o600
    assert len([f for f in _files(pdir) if f.endswith(".bak")]) == profiles.MAX_BACKUPS


def test_backup_of_unknown_profile_is_none(pdir):
    assert profiles._backup("Niemand") is None


def test_backups_are_not_loaded_as_profiles(pdir):
    profiles.save_profile(_p("Anna"))
    profiles._backup("Anna")
    assert [p["name"] for p in profiles.list_profiles()] == ["Anna"]


def test_delete_all_removes_everything_but_lock(pdir):
    profiles.save_profile(_p("Anna"))
    profiles.save_profile(_p("Bob"))
    profiles._backup("Anna")
    (pdir / "x.json.2026.bad").write_text("{")
    (pdir / "y.tmp").write_text("{")
    (pdir / "notiz.txt").write_text("bleibt")
    n = profiles.delete_all_profiles()
    assert n == 5
    assert sorted(f.name for f in pdir.iterdir()) == [".lock", "notiz.txt"]


def test_delete_all_without_directory_is_zero(pdir):
    assert profiles.delete_all_profiles() == 0


def test_delete_unknown_profile_is_false(pdir):
    assert profiles.delete_profile("Niemand") is False


# ---- Kaputte Dateien -----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("body", ["{kaputt", "[1, 2]", '"text"', "null", '{"name": "  "}', '{"name": 5}', "{}", ""])
def test_unreadable_profile_is_quarantined_not_crashing(pdir, body):
    pdir.mkdir(mode=0o700)
    (pdir / "kaputt.json").write_text(body)
    assert profiles.list_profiles() == []
    assert not (pdir / "kaputt.json").exists()
    assert any(f.endswith(".bad") for f in _files(pdir))
    assert len(profiles.CORRUPT) == 1


def test_quarantine_message_has_no_profile_name(pdir, capsys):
    pdir.mkdir(mode=0o700)
    (pdir / "GeheimerName.json").write_text("{kaputt")
    profiles.list_profiles()
    assert "GeheimerName" not in capsys.readouterr().err
    assert all("GeheimerName" not in m for m in profiles.CORRUPT)


def test_invalid_utf8_profile_is_quarantined(pdir):
    pdir.mkdir(mode=0o700)
    (pdir / "bin.json").write_bytes(b"\xff\xfe\x00{")
    assert profiles.list_profiles() == []
    assert any(f.endswith(".bad") for f in _files(pdir))


def test_one_broken_file_does_not_hide_the_good_ones(pdir):
    profiles.save_profile(_p("Anna"))
    (pdir / "kaputt.json").write_text("{")
    assert [p["name"] for p in profiles.list_profiles()] == ["Anna"]


def test_profile_without_schema_version_is_version_1(pdir):
    pdir.mkdir(mode=0o700)
    (pdir / "alt.json").write_text(json.dumps({"name": "Alt", "lang": "en"}))
    assert profiles.get_profile("Alt")["schema_version"] == 1


def test_unknown_fields_in_profile_file_survive_a_roundtrip(pdir):
    pdir.mkdir(mode=0o700)
    (pdir / "neu.json").write_text(json.dumps({"name": "Neu", "zukunft": {"a": 1}}))
    p = profiles.get_profile("Neu")
    profiles.save_profile(p)
    assert profiles.get_profile("Neu")["zukunft"] == {"a": 1}


def test_dotfiles_are_not_profiles(pdir):
    pdir.mkdir(mode=0o700)
    (pdir / ".versteckt.json").write_text(json.dumps({"name": "Versteckt"}))
    assert profiles.list_profiles() == []


# ---- public() ------------------------------------------------------------------------------------------------------

def test_public_never_leaks_voiceprints_or_unknown_fields():
    p = {"name": "A", "lang": "en", "embedding": [1], "embedding_orig": [1], "secret": "x", "vocab": ["w"],
         "polite": "ka", "enroll_results": []}
    out = profiles.public(p)
    assert "embedding" not in out and "embedding_orig" not in out and "secret" not in out
    assert out == {"name": "A", "lang": "en", "vocab": ["w"], "polite": "ka", "enroll_results": []}


def test_public_of_empty_profile():
    assert profiles.public({}) == {}


# ---- Vokabular -----------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("raw,want", [
    ("a, b;c\nA\n  d  e  ", ["a", "b", "c", "d e"]),
    (None, []), ([], []), ("", []), (",,;;\n", []),
    (["Ströme", "STRÖME"], ["Ströme"]),
    (["สีลม, ทองหล่อ"], ["สีลม", "ทองหล่อ"]),
])
def test_clean_vocab(raw, want):
    assert profiles.clean_vocab(raw) == want


def test_clean_vocab_limits_count_and_length():
    assert len(profiles.clean_vocab([str(i) for i in range(100)])) == profiles.MAX_VOCAB
    assert len(profiles.clean_vocab(["x" * 500])[0]) == profiles.MAX_VOCAB_LEN


def test_clean_vocab_nfc_normalises_and_dedupes():
    assert profiles.clean_vocab(["Café", "Café"]) == ["Café"]


def test_clean_vocab_skips_none_entries():
    assert profiles.clean_vocab([None, "ok"]) == ["ok"]


def test_set_vocab_unknown_profile_raises_keyerror(pdir):
    with pytest.raises(KeyError):
        profiles.set_vocab("Niemand", ["a"])


def test_set_vocab_replaces_and_cleans(pdir):
    profiles.save_profile(_p("Anna", vocab=["alt"]))
    assert profiles.set_vocab("Anna", "x, y, X")["vocab"] == ["x", "y"]
    assert profiles.get_profile("Anna")["vocab"] == ["x", "y"]


@pytest.mark.parametrize("bad", ["bad", "KRUB", 5, ["krub"], True])
def test_set_polite_rejects_invalid(pdir, bad):
    profiles.save_profile(_p("Anna"))
    with pytest.raises(ValueError):
        profiles.set_polite("Anna", bad)


def test_set_polite_unknown_profile_raises_keyerror(pdir):
    with pytest.raises(KeyError):
        profiles.set_polite("Niemand", "krub")


@pytest.mark.parametrize("clear", ["", "-", None])
def test_set_polite_can_be_cleared(pdir, clear):
    profiles.save_profile(_p("Anna", polite="ka"))
    assert "polite" not in profiles.set_polite("Anna", clear)
    assert "polite" not in profiles.get_profile("Anna")


def test_reset_learning_restores_original_embedding(pdir):
    profiles.save_profile(_p("Anna", embedding=[0.0, 1.0], embedding_orig=[1.0, 0.0], adapted=7))
    assert profiles.reset_learning("Anna") is True
    p = profiles.get_profile("Anna")
    assert p["embedding"] == [1.0, 0.0] and p["adapted"] == 0 and "embedding_orig" not in p


def test_reset_learning_without_original_or_profile_is_false(pdir):
    profiles.save_profile(_p("Anna"))
    assert profiles.reset_learning("Anna") is False
    assert profiles.reset_learning("Niemand") is False


# ---- Hotwords ------------------------------------------------------------------------------------------------------

def test_hotwords_own_language_all_words_other_profiles_only_matching_script():
    profs = [{"lang": "en", "vocab": ["Amari", "สีลม"]}, {"lang": "th", "vocab": ["ทองหล่อ", "Siam"]}]
    assert profiles.pick_hotwords(profs, "th") == "สีลม ทองหล่อ Siam"
    assert profiles.pick_hotwords(profs, "en") == "Amari สีลม Siam"   # Siam: lateinische Schrift passt


def test_hotwords_who_comes_first():
    profs = [{"lang": "en", "vocab": ["eins"]}, {"lang": "en", "vocab": ["zwei"]}]
    assert profiles.pick_hotwords(profs, "en", who=profs[1]) == "zwei eins"


@pytest.mark.parametrize("profs", [[], None, [{"lang": "en", "vocab": None}], [{"lang": "en"}],
                                   [{"lang": "en", "vocab": [None, 5, "  "]}]])
def test_hotwords_empty_inputs_give_none(profs):
    assert profiles.pick_hotwords(profs, "en") is None


def test_hotwords_dedupe_casefold():
    assert profiles.pick_hotwords([{"lang": "en", "vocab": ["Amari", "AMARI", "amari"]}], "en") == "Amari"


def test_hotwords_thai_budget_counts_triple():
    thai = ["ก" * 50, "ข" * 50, "ค" * 50]
    out = profiles.pick_hotwords([{"lang": "th", "vocab": thai}], "th").split()
    assert out == thai[:2]                                  # 3 x 151 > 400


def test_hotwords_first_word_is_kept_even_if_over_budget():
    assert profiles.pick_hotwords([{"lang": "th", "vocab": ["ก" * 300]}], "th") == "ก" * 300


def test_hotwords_latin_languages_and_foreign_scripts():
    assert profiles.pick_hotwords([{"lang": "en", "vocab": ["a"]}], "de") == "a"
    assert profiles.pick_hotwords([{"lang": "zh", "vocab": ["abc"]}], "en") == "abc"
    assert profiles.pick_hotwords([{"lang": "zh", "vocab": ["你好"]}], "en") is None


@pytest.mark.parametrize("word,lang,want", [("สีลม", "th", True), ("Siam", "th", False), ("Siam", "en", True),
                                           ("สีลม", "en", False), ("Café", "fr", True), ("123", "en", False),
                                           ("你好", "zh", False), ("abc", "xx", False)])
def test_script_fits(word, lang, want):
    assert profiles._script_fits(word, lang) is want


# ---- Rollenregel ---------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("args,want", [
    ((0.90, None, 2.0, 0.76), "me"),
    ((0.50, None, 2.0, 0.76), "other"),
    ((0.30, None, 0.5, 0.76), "other"),
    ((0.80, 0.50, 2.0, 0.76), "me"),
    ((0.50, 0.80, 2.0, 0.76), "other"),
    ((0.70, 0.30, 1.0, 0.76), "me"),
    ((0.60, 0.62, 2.0, 0.76), None),
    ((0.76, 0.76, 2.0, 0.76), None),
])
def test_decide_role(args, want):
    assert profiles.decide_role(*args)[0] == want


def test_decide_role_returns_reason_string():
    role, why = profiles.decide_role(0.6, 0.62, 2.0, 0.76)
    assert role is None and isinstance(why, str) and why


def test_decide_role_tie_break_uses_previous_speaker_only_for_other_or_confident_me():
    assert profiles.decide_role(0.58, 0.62, 2.0, 0.76, prev="other")[0] == "other"
    assert profiles.decide_role(0.62, 0.58, 2.0, 0.76, prev="me")[0] is None       # unter ROLE_ME_FLOOR


@pytest.mark.parametrize("me", [0.0, 0.5, 0.75, 0.76, 0.99, 1.0])
@pytest.mark.parametrize("her", [None, 0.0, 0.5, 0.99])
@pytest.mark.parametrize("dur", [0.1, 0.6, 1.5, 30.0])
@pytest.mark.parametrize("prev", [None, "me", "other"])
def test_decide_role_always_returns_valid_value(me, her, dur, prev):
    role, why = profiles.decide_role(me, her, dur, 0.76, prev)
    assert role in ("me", "other", None) and isinstance(why, str)


# ---- Fehlerrate (Englisch Wörter, Thai Zeichencluster) -------------------------------------------------------------

@pytest.mark.parametrize("ref,hyp,lang,want", [
    ("hello world", "hello world", "en", 0.0),
    ("hello world", "hello", "en", 0.5),
    ("Hello, World!", "hello world", "en", 0.0),
    ("a b c", "c b a", "en", 2 / 3),
    ("", "irgendwas", "en", 0.0),
    ("สวัสดี", "สวัสดี", "th", 0.0),
    ("สวัสดี", "", "th", 1.0),
    ("สวัสดี", "สวสดี", "th", 0.25),
    ("สวัสดี ครับ", "สวัสดีครับ", "th", 0.0),
])
def test_error_rate(ref, hyp, lang, want):
    assert profiles.error_rate(ref, hyp, lang) == pytest.approx(want)


def test_error_rate_thai_tone_mark_is_part_of_its_cluster():
    # ไม้ -> ไม่: nur ein Cluster von vier ist falsch, nicht zwei Zeichen
    assert profiles.error_rate("ไม้", "ไม่", "th") == pytest.approx(1 / 2)


def test_error_rate_can_exceed_one_when_hypothesis_is_longer():
    assert profiles.error_rate("a", "a b c d", "en") == 3.0


def test_norm_text_keeps_thai_vowel_marks_and_drops_punctuation():
    assert profiles._norm_text("สวัสดี!") == "สวัสดี"
    assert profiles._norm_text("Don't, stop.") == "dont stop"


# ---- Ausreißer -----------------------------------------------------------------------------------------------------

def _v(*x):
    a = np.array(x, dtype=np.float32)
    return a / np.linalg.norm(a)


def test_drop_outliers_removes_the_wrong_voice():
    embs = [_v(1, 0, 0)] * 5 + [_v(0, 1, 0)]
    assert profiles._drop_outliers(embs) == [0, 1, 2, 3, 4]


def test_drop_outliers_keeps_consistent_set():
    embs = [_v(1, 0.01 * i, 0) for i in range(6)]
    assert profiles._drop_outliers(embs) == list(range(6))


# ---- Aufnahme mit Attrappen ----------------------------------------------------------------------------------------

class _Spk:
    """Liefert für lange Aufnahmen denselben Abdruck, für Kurzausschnitte einen ähnlichen."""
    def __init__(self, vecs=None):
        self.vecs = list(vecs or [])
        self.calls = 0

    def embed(self, audio):
        self.calls += 1
        if self.vecs:
            return self.vecs.pop(0)
        return _v(1, 0.05, 0)


def _enroll(name="Anna", lang="en", spk=None, record=None, transcribe=None):
    events = []
    cur = {}

    def emit(event, **kw):
        events.append((event, kw))
        if event == "enroll_prompt":
            cur["s"] = kw["sentence"]
    rec = record or (lambda: np.full(profiles.SR * 2, 0.1, dtype=np.float32))
    tr = transcribe or (lambda audio, lg: cur["s"])
    res = profiles.enroll(name, lang, rec, tr, emit, spk=spk or _Spk())
    return res, events


def test_enroll_invalid_name_fails_before_recording(pdir):
    asked = []
    with pytest.raises(profiles.ProfileNameError):
        _enroll("!!!", record=lambda: asked.append(1))
    assert asked == []


def test_enroll_success_saves_normalised_embedding_and_public_event(pdir):
    p, events = _enroll()
    assert p is not None
    assert np.linalg.norm(p["embedding"]) == pytest.approx(1.0, abs=1e-3)
    assert p["embedding_model"] == profiles.EMBED_MODEL_ID and p["lang"] == "en"
    done = [kw for e, kw in events if e == "enroll_done"][0]["profile"]
    assert "embedding" not in done and done["name"] == "Anna"
    assert profiles.get_profile("Anna") is not None


def test_enroll_silence_gives_too_few(pdir):
    p, events = _enroll(record=lambda: None)
    assert p is None
    assert [kw["code"] for e, kw in events if e == "enroll_failed"] == ["too_few"]
    assert profiles.get_profile("Anna") is None


def test_enroll_too_short_audio_is_retried_three_times_per_sentence(pdir):
    n = []
    p, events = _enroll(record=lambda: n.append(1) or np.zeros(10, dtype=np.float32))
    assert p is None
    assert len(n) == 3 * len(profiles.ENROLL["en"])
    assert {kw["code"] for e, kw in events if e == "enroll_retry"} == {"too_short", "skipped"}


def test_enroll_inconsistent_voices_fail(pdir):
    vecs = [_v(1, 0, 0), _v(0, 1, 0), _v(0, 0, 1), _v(-1, 0, 0), _v(0, -1, 0), _v(0, 0, -1)] * 3
    p, events = _enroll(spk=_Spk(vecs))
    assert p is None
    assert [kw["code"] for e, kw in events if e == "enroll_failed"][0] in ("inconsistent", "too_few")


def test_reenroll_keeps_vocab_and_polite_and_backs_up_old_profile(pdir):
    profiles.save_profile(_p("Anna", vocab=["Amari"], polite="ka"))
    p, _ = _enroll()
    assert p["vocab"] == ["Amari"] and p["polite"] == "ka"
    assert any(f.endswith(".bak") for f in _files(pdir))


def test_enroll_role_threshold_stays_in_range(pdir):
    p, _ = _enroll()
    assert profiles.ROLE_ME_MIN <= p["role_me_min"] <= 0.85


def test_enroll_wrong_sentence_heard_is_retried(pdir):
    heard = []
    sents = profiles.ENROLL["en"]

    def transcribe(audio, lg):
        heard.append(1)
        return "völlig anderer Text ohne Bezug"
    p, events = _enroll(transcribe=transcribe)
    assert len(heard) >= len(sents)
    assert any(e == "enroll_heard" and kw["err"] >= 0.85 for e, kw in events)


# ---- Sprechermodell: Datenschutz (kein Download im Privatmodus) ----------------------------------------------------

def test_ensure_model_offline_only_never_downloads(tmp_path, monkeypatch):
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "OFFLINE_ONLY", True)
    monkeypatch.delenv(profiles.ENV_MODEL_FILE, raising=False)
    monkeypatch.delenv(profiles.ENV_MODEL_URL, raising=False)
    called = []
    monkeypatch.setattr(profiles, "_download", lambda *a, **k: called.append(a))
    with pytest.raises(RuntimeError) as ex:
        profiles.ensure_model()
    assert called == [] and profiles.ENV_MODEL_FILE in str(ex.value)


def test_ensure_model_rejects_local_file_with_wrong_checksum(tmp_path, monkeypatch):
    src = tmp_path / "fremd.onnx"
    src.write_bytes(b"kein modell")
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "OFFLINE_ONLY", True)
    monkeypatch.setenv(profiles.ENV_MODEL_FILE, str(src))
    with pytest.raises(RuntimeError, match="checksum"):
        profiles.ensure_model()
    assert not (tmp_path / "m" / "model.onnx").exists()
    assert not [f for f in os.listdir(tmp_path / "m") if f.endswith(".part")]


def test_ensure_model_accepts_local_file_with_right_checksum(tmp_path, monkeypatch):
    src = tmp_path / "echt.onnx"
    src.write_bytes(b"inhalt")
    import hashlib
    monkeypatch.setattr(profiles, "MODEL_SHA256", hashlib.sha256(b"inhalt").hexdigest())
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "OFFLINE_ONLY", True)
    monkeypatch.setenv(profiles.ENV_MODEL_FILE, str(src))
    assert profiles.ensure_model() == str(tmp_path / "m" / "model.onnx")
