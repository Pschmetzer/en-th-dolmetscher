import hashlib, json, os, stat
import numpy as np
import pytest
import profiles


@pytest.fixture
def pdir(tmp_path, monkeypatch):
    d = tmp_path / "profiles"
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(d))
    return d


def _p(name, **kw):
    return {"name": name, "lang": "en", "embedding": [1.0, 0.0], **kw}


def test_permissions_and_utf8(pdir):
    profiles.save_profile(_p("Nok ไทย"))
    assert stat.S_IMODE(os.stat(pdir).st_mode) == 0o700
    f = next(pdir.glob("*.json"))
    assert stat.S_IMODE(os.stat(f).st_mode) == 0o600
    assert "ไทย" in f.read_text(encoding="utf-8")
    assert not list(pdir.glob("*.tmp"))
    assert profiles.list_profiles()[0]["schema_version"] == profiles.SCHEMA_VERSION


def test_legacy_without_schema_version_loads(pdir):
    pdir.mkdir()
    (pdir / "Old.json").write_text(json.dumps(_p("Old")), encoding="utf-8")
    p = profiles.list_profiles()[0]
    assert p["name"] == "Old" and p["schema_version"] == 1


def test_name_collisions_keep_both(pdir):
    profiles.save_profile(_p("Anna", vocab=["a"]))
    profiles.save_profile(_p("Anna!", vocab=["b"]))
    profiles.save_profile(_p("ANNA", vocab=["c"]))
    names = sorted(p["name"] for p in profiles.list_profiles())
    assert names == ["ANNA", "Anna", "Anna!"]
    assert (pdir / "Anna.json").exists()                  # bestehende Datei behält ihren Namen
    profiles.save_profile(_p("Anna", vocab=["a2"]))       # Update trifft dieselbe Datei
    assert profiles.get_profile("Anna")["vocab"] == ["a2"]
    assert profiles.get_profile("Anna!")["vocab"] == ["b"]
    assert profiles.delete_profile("Anna!") and profiles.get_profile("Anna") is not None


@pytest.mark.parametrize("bad", ["", "!!!", "   ", None, 5, "x" * 200])
def test_invalid_name_raises_cleanly(pdir, bad):
    with pytest.raises(profiles.ProfileNameError):
        profiles.save_profile({"name": bad})
    assert isinstance(profiles.ProfileNameError("x"), ValueError)


def test_corrupt_profile_quarantined(pdir, capsys):
    profiles.save_profile(_p("Good"))
    (pdir / "Bad.json").write_text("{not json", encoding="utf-8")
    (pdir / "Nolist.json").write_text("[1]", encoding="utf-8")
    assert [p["name"] for p in profiles.list_profiles()] == ["Good"]
    assert len(list(pdir.glob("*.bad"))) == 2
    assert not (pdir / "Bad.json").exists()
    assert "profile_corrupt" in capsys.readouterr().err
    assert profiles.CORRUPT


def test_timestamps_iso_utc_and_public_allowlist(pdir):
    assert profiles._utcnow().endswith("Z") and "T" in profiles._utcnow()
    p = _p("N", secret="x", embedding_orig=[1, 0], vocab=[], created="2026-01-01T00:00:00Z")
    pub = profiles.public(p)
    assert set(pub) == {"name", "lang", "created", "vocab"}


def test_set_vocab_clean(pdir):
    profiles.save_profile(_p("V"))
    words = ["Siam, siam;  Wat  Pho\nSiam", "é", "é", "  "] + [f"w{i}" for i in range(50)]
    p = profiles.set_vocab("V", words)
    assert p["vocab"][:3] == ["Siam", "Wat Pho", "é"]       # Dedup (case), NFC
    assert len(p["vocab"]) == profiles.MAX_VOCAB
    assert profiles.set_vocab("V", "a, b;c\nd")["vocab"] == ["a", "b", "c", "d"]
    with pytest.raises(KeyError):
        profiles.set_vocab("nope", ["x"])


def test_home_env(monkeypatch, tmp_path):
    import importlib
    monkeypatch.setenv("DOLMETSCHER_HOME", str(tmp_path))
    try:
        m = importlib.reload(profiles)
        assert m.BASE == str(tmp_path) and m.PROFILE_DIR.startswith(str(tmp_path))
    finally:
        monkeypatch.delenv("DOLMETSCHER_HOME")
        importlib.reload(profiles)


# ---- model download ----
@pytest.fixture
def model(tmp_path, monkeypatch):
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    data = b"modelbytes" * 1000
    monkeypatch.setattr(profiles, "MODEL_SHA256", hashlib.sha256(data).hexdigest())
    return data


def test_model_local_import_and_cleanup(model, tmp_path, monkeypatch):
    src = tmp_path / "src.onnx"
    src.write_bytes(model)
    mdir = tmp_path / "m"
    mdir.mkdir()
    (mdir / "model.onnx.old.part").write_bytes(b"junk")
    monkeypatch.setattr(profiles, "MODEL_URL", "http://127.0.0.1:1/x")
    monkeypatch.setenv(profiles.ENV_MODEL_FILE, str(src))
    assert profiles.ensure_model() == profiles.MODEL_PATH
    assert open(profiles.MODEL_PATH, "rb").read() == model
    assert not list(mdir.glob("*.part"))


def test_model_second_url_after_first_fails(model, tmp_path, monkeypatch):
    src = tmp_path / "ok.onnx"
    src.write_bytes(model)
    monkeypatch.setattr(profiles, "MODEL_URL", "http://127.0.0.1:1/x")      # Verbindung abgelehnt
    monkeypatch.setenv(profiles.ENV_MODEL_URL, src.as_uri())
    assert profiles.ensure_model() == profiles.MODEL_PATH


def test_model_bad_checksum_raises_and_cleans(model, tmp_path, monkeypatch):
    src = tmp_path / "bad.onnx"
    src.write_bytes(b"wrong")
    monkeypatch.setattr(profiles, "MODEL_URL", src.as_uri())
    with pytest.raises(RuntimeError, match="checksum"):
        profiles.ensure_model()
    assert not list((tmp_path / "m").glob("*.part")) and not os.path.exists(profiles.MODEL_PATH)


# ---- recognition ----
def _spk(profs, embed=None):
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    s.profiles = profs
    s.mat = np.stack([np.array(p["embedding"], dtype=np.float32) for p in profs]) if profs else None
    if embed:
        s.embed = embed
    return s


def test_reload_skips_dimension_and_model_mismatch(pdir):
    profiles.save_profile(_p("A", embedding=[1.0, 0.0, 0.0]))
    profiles.save_profile(_p("B", embedding=[0.0, 1.0, 0.0]))
    profiles.save_profile(_p("C", embedding=[0.0, 1.0]))
    profiles.save_profile(_p("D", embedding=[0.0, 1.0, 0.0], embedding_model="other"))
    profiles.save_profile(_p("E", embedding=[float("nan"), 1.0, 0.0]))
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    s.reload()
    assert sorted(p["name"] for p in s.profiles) == ["A", "B"]
    assert {n for n, _ in s.skipped} == {"C", "D", "E"}
    assert s.mat.shape == (2, 3)


class _FakeEx:
    def __init__(self, out):
        self.out = out
    def create_stream(self):
        class S:
            def accept_waveform(self, *a): pass
            def input_finished(self): pass
        return S()
    def compute(self, s):
        return self.out


def test_embed_rejects_silence_nan_short_zero():
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    s.ex = _FakeEx([3.0, 4.0])
    voice = (np.random.RandomState(0).randn(profiles.SR) * 0.1).astype(np.float32)
    assert np.allclose(s.embed(voice), [0.6, 0.8])
    assert s.embed(np.zeros(profiles.SR, np.float32)) is None
    nan = voice.copy(); nan[5] = np.nan
    assert s.embed(nan) is None
    assert s.embed(voice[:1000]) is None
    s.ex = _FakeEx([0.0, 0.0])
    assert s.embed(voice) is None
    s.ex = _FakeEx([float("nan"), 1.0])
    assert s.embed(voice) is None


def test_identify_single_profile_stricter():
    s = _spk([{"name": "A", "lang": "en"}] if False else [{"name": "A", "lang": "en", "embedding": [1.0, 0.0]}])
    audio = np.zeros(profiles.SR * 2, np.float32)
    s.embed = lambda a: np.array([0.70, np.sqrt(1 - 0.49)], np.float32)     # 0.70: ok mit 2 Profilen, hier zu wenig
    assert s.identify(audio)[0] is None
    s.embed = lambda a: np.array([0.80, 0.6], np.float32)
    assert s.identify(audio)[0]["name"] == "A"
    s.embed = lambda a: None
    assert s.identify(audio)[0] is None


def test_me_partner_deterministic():
    ps = [{"name": "B", "lang": "en", "created": "2026-02-01T00:00:00Z"},
          {"name": "A", "lang": "en", "created": "2026-01-01 10:00"},
          {"name": "T", "lang": "th"}]
    s = _spk([dict(p, embedding=[1.0, 0.0]) for p in ps])
    assert s.me()["name"] == "B" and s.partner()["name"] == "T"
    s.profiles.reverse()
    assert s.me()["name"] == "B"


def test_learn_keeps_original_limits_drift_and_resets(pdir):
    profiles.save_profile(_p("L", vocab=["keep"]))
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    s.reload()
    assert s.learn("L", np.array([0.8, 0.6], np.float32), 0.2)
    p = profiles.get_profile("L")
    assert p["embedding_orig"] == [1.0, 0.0] and p["adapted"] == 1 and p["vocab"] == ["keep"]
    orth = np.array([0.0, 1.0], np.float32)
    for _ in range(20):                                  # darf nie weit vom Original wegdriften
        s.learn("L", orth, 0.5)
    q = np.array(profiles.get_profile("L")["embedding"], np.float32)
    assert float(q @ np.array([1.0, 0.0])) >= profiles.MAX_DRIFT_COS - 1e-3
    assert not s.learn("L", None, 0.1) and not s.learn("L", np.array([np.nan, 1]), 0.1)
    assert s.reset_learning("L")
    r = profiles.get_profile("L")
    assert r["embedding"] == [1.0, 0.0] and r["adapted"] == 0


# ---- enroll ----
def _voice(rng, base, n=profiles.SR * 2):
    return (rng.randn(n) * 0.1).astype(np.float32)


class _EnrollSpk:
    """Embedding pro Aufnahme aus dem Marker im ersten Sample."""
    def embed(self, a):
        if a.size < profiles.SR * 0.5:
            return None
        v = np.array([1.0, a[0] * 10, 0.0], np.float32)
        return v / np.linalg.norm(v)


def _run_enroll(markers, tmp_dur=2.0, name="N", lang="en"):
    it = iter(markers)
    def rec():
        m = next(it)
        if m is None:
            return None
        a = np.full(int(profiles.SR * tmp_dur), 0.01, np.float32)
        a[0] = m
        return a
    sents = profiles.ENROLL[lang]
    cur = {"i": 0}
    def emit(ev, **k):
        if ev == "enroll_prompt":
            cur["i"] = k["i"]
    events = []
    return profiles.enroll(name, lang, rec, lambda a, lg: sents[cur["i"] - 1],
                           lambda ev, **k: (emit(ev, **k), events.append(ev)), _EnrollSpk()), events


def test_enroll_drops_outlier_and_backs_up(pdir):
    p, _ = _run_enroll([0.001] * 7 + [0.09])           # 8. Satz klingt völlig anders
    assert p["enroll_results"] and len(p["enroll_results"]) == 8
    assert p["embedding_model"] == profiles.EMBED_MODEL_ID and p["created"].endswith("Z")
    assert profiles.set_vocab("N", ["x"])["vocab"] == ["x"]
    p2, _ = _run_enroll([0.001] * 8)
    assert p2["vocab"] == ["x"]                         # Vokabular bleibt
    assert len(list(pdir.glob("*.bak"))) == 1           # altes Profil gesichert
    assert len(profiles.list_profiles()) == 1


def test_enroll_needs_five_usable(pdir):
    p, ev = _run_enroll([0.001] * 4 + [None] * 12)      # 4 Sätze, Rest scheitert (3 Versuche je Satz)
    assert p is None and "enroll_failed" in ev and not list(pdir.glob("*.json"))
    p, ev = _run_enroll([0.001] * 5 + [None] * 9)
    assert p is not None


def test_enroll_short_audio_rejected_consistently(pdir):
    p, ev = _run_enroll([0.001] * 40, tmp_dur=1.0)      # 1,0 s < 1,5 s: weder akzeptiert noch Embedding
    assert p is None and "enroll_failed" in ev


def test_enroll_invalid_name_before_recording(pdir):
    with pytest.raises(profiles.ProfileNameError):
        profiles.enroll("!!", "en", lambda: None, lambda a, lg: "", lambda *a, **k: None, _EnrollSpk())


# ---- error_rate ----
def test_error_rate_thai_marks_nfc():
    ref = "ยินดีที่ได้รู้จัก"
    assert profiles.error_rate(ref, ref, "th") == 0
    assert profiles.error_rate(ref, "ยินดีทีได้รูจัก", "th") > 0          # fehlende Tonmarken/Vokalzeichen zählen
    assert profiles.error_rate("ที่", "ทื่", "th") == 1.0                # ein Cluster falsch
    assert profiles.error_rate("é", "é", "en") == 0                # NFC
    assert profiles.error_rate("ขอบคุณ ครับ!", "ขอบคุณครับ", "th") == 0
    assert profiles.error_rate("Let's go, now.", "lets go now", "en") == 0
