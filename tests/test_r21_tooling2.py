"""Runde 21, Teil 2: Profilspeicher (Sperre, Aufraeumen, Download), Korrekturvorschlaege, Allergene, Build-Skripte."""
import json
import os
import pathlib
import subprocess
import time

import pytest

import correction_learning as cl
import profiles

ROOT = pathlib.Path(__file__).resolve().parent.parent


@pytest.fixture
def pdir(tmp_path, monkeypatch):
    d = tmp_path / "profiles"
    d.mkdir()
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(d))
    monkeypatch.setattr(profiles, "_CLEANED", [True])
    return d


def _age(path, days):
    t = time.time() - days * 86400
    os.utime(path, (t, t))


def test_cleanup_removes_old_bad_and_stale_tmp(pdir):
    old_bad = pdir / "a.json.20200101.bad"
    new_bad = pdir / "b.json.20991231.bad"
    old_tmp = pdir / "a.json.1.2.tmp"
    new_tmp = pdir / "b.json.1.3.tmp"
    keep = pdir / "a.json"
    for f in (old_bad, new_bad, old_tmp, new_tmp, keep):
        f.write_text("x")
    _age(old_bad, 30)
    _age(old_tmp, 1)
    n = profiles.cleanup_stale()
    assert n == 2 and not old_bad.exists() and not old_tmp.exists()
    assert new_bad.exists() and new_tmp.exists() and keep.exists()


def test_cleanup_caps_number_of_bad_files(pdir):
    for i in range(profiles.BAD_KEEP_MAX + 3):
        f = pdir / ("p%d.json.x.bad" % i)
        f.write_text("x")
        _age(f, 0.001 * (i + 1))                             # i = 0 ist die neueste
    profiles.cleanup_stale()
    left = sorted(p.name for p in pdir.glob("*.bad"))
    assert len(left) == profiles.BAD_KEEP_MAX and "p0.json.x.bad" in left


def test_cleanup_missing_dir_is_zero(tmp_path, monkeypatch):
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(tmp_path / "nein"))
    assert profiles.cleanup_stale() == 0


def test_flock_times_out_with_clear_error(tmp_path):
    import fcntl
    p = tmp_path / "l"
    a = os.open(p, os.O_RDWR | os.O_CREAT)
    b = os.open(p, os.O_RDWR)
    fcntl.flock(a, fcntl.LOCK_EX)
    t0 = time.monotonic()
    with pytest.raises(TimeoutError, match="locked"):
        profiles._flock(b, timeout=0.2)
    assert time.monotonic() - t0 < 2
    fcntl.flock(a, fcntl.LOCK_UN)
    profiles._flock(b, timeout=0.2)                          # jetzt frei
    os.close(a)
    os.close(b)


def test_second_process_cannot_hold_lock_forever(pdir, monkeypatch):
    monkeypatch.setattr(profiles, "LOCK_TIMEOUT_S", 0.3)
    code = ("import fcntl,os,sys,time;fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600);"
            "fcntl.flock(fd,fcntl.LOCK_EX);print('x',flush=True);time.sleep(3)")
    p = subprocess.Popen(["python3", "-I", "-c", code, str(pdir / ".lock")], stdout=subprocess.PIPE)
    try:
        p.stdout.readline()
        with pytest.raises(TimeoutError):
            with profiles._locked():
                pass
    finally:
        p.kill()


@pytest.mark.parametrize("url", ["http://example.com/m.onnx", "ftp://x/m", "gopher://x", ""])
def test_download_rejects_non_https(url, tmp_path):
    with pytest.raises(ValueError, match="https"):
        profiles._download(url, str(tmp_path / "x"))


def test_download_size_cap(tmp_path, monkeypatch):
    src = tmp_path / "big.bin"
    src.write_bytes(b"0" * 5000)
    monkeypatch.setattr(profiles, "MODEL_MAX_BYTES", 1000)
    monkeypatch.setattr(profiles, "DOWNLOAD_CHUNK", 100)
    with pytest.raises(RuntimeError, match="larger"):
        profiles._download(src.as_uri(), str(tmp_path / "out"))


def test_model_ok_stamp_written_after_download(tmp_path, monkeypatch):
    import hashlib
    data = b"model-bytes"
    src = tmp_path / "ok.onnx"
    src.write_bytes(data)
    monkeypatch.setattr(profiles, "BASE", str(tmp_path))
    monkeypatch.setattr(profiles, "MODEL_PATH", str(tmp_path / "m" / "model.onnx"))
    monkeypatch.setattr(profiles, "MODEL_SHA256", hashlib.sha256(data).hexdigest())
    monkeypatch.setattr(profiles, "MODEL_URL", src.as_uri())
    monkeypatch.delenv(profiles.ENV_MODEL_FILE, raising=False)
    monkeypatch.delenv(profiles.ENV_MODEL_URL, raising=False)
    assert profiles.ensure_model() == profiles.MODEL_PATH
    assert os.path.exists(profiles.MODEL_PATH + ".ok")


# ---- correction_learning ----------------------------------------------------------------------------------------

def test_stop_words_and_particles_not_suggested(monkeypatch):
    assert cl.suggest_vocab("send it", "send the and you invoice", "en") == ["invoice"]
    monkeypatch.setattr(cl, "_thai_tokens", lambda t: t.split())
    assert cl.suggest_vocab("ไป ตลาด", "ไป ตลาดน้ำ ครับ นะ", "th") == ["ตลาดน้ำ"]


def test_thai_fallback_ignores_long_runs(monkeypatch):
    import builtins
    real = builtins.__import__

    def no_pythainlp(name, *a, **k):
        if name.startswith("pythainlp"):
            raise ImportError
        return real(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", no_pythainlp)
    toks = cl._thai_tokens("ตลาด" + "ก" * 40 + " ตลาดน้ำ")
    assert "ตลาดน้ำ" in toks and not any(len(t) > cl.MAX_FALLBACK_RUN for t in toks)


def test_skip_signature_has_no_dead_parameter():
    import inspect
    assert list(inspect.signature(cl._skip).parameters) == ["tok"]


# ---- allergens.json -----------------------------------------------------------------------------------------------

def test_allergens_schema_and_thailand_relevant_entries():
    d = json.loads((ROOT / "allergens.json").read_text(encoding="utf-8"))
    assert set(d) >= {"version", "note", "allergies", "conditions"}
    for key in ("allergies", "conditions"):
        ids = [x["id"] for x in d[key]]
        assert len(ids) == len(set(ids)), key
        for x in d[key]:
            assert set(x) == {"id", "en", "de", "th"}, x
            assert all(isinstance(x[k], str) and x[k].strip() for k in x)
            assert any("฀" <= c <= "๿" for c in x["th"]), x["id"]        # Thai-Schrift
            assert x["id"].isidentifier() or x["id"].isalnum(), x["id"]
    ids = {x["id"] for x in d["allergies"]}
    assert {"mustard", "lupin", "sulfite", "msg", "fishsauce", "shrimppaste", "coconut", "mollusc"} <= ids
    cond = {x["id"] for x in d["conditions"]}
    assert {"nopork", "halal", "vegetarian", "jay", "noalcohol"} <= cond
    assert not ids & cond


# ---- build scripts -----------------------------------------------------------------------------------------------

def test_make_stamp_takes_python_and_arch():
    f = ROOT / "build-support" / "make-stamp.sh"
    base = subprocess.run(["bash", str(f), str(ROOT / "requirements.txt")], capture_output=True, text=True).stdout
    assert "python=3.12\n" in base and "arch=arm64\n" in base
    out = subprocess.run(["bash", str(f), str(ROOT / "requirements.txt"), "3.13", "x86_64"],
                         capture_output=True, text=True).stdout
    assert "python=3.13\n" in out and "arch=x86_64\n" in out


def test_build_install_copies_before_removing_old_app():
    s = (ROOT / "build.sh").read_text(encoding="utf-8")
    inst = s[s.index('if [ "$INSTALL" = 1 ]'):]
    assert inst.index('cp -R "$APP" "$NEWINSTALL"') < inst.index('rm -rf "$HOME/Applications/Dolmetscher.app"')
    assert 'mv "$NEWINSTALL"' in inst


def test_setup_env_verifies_all_runtime_packages():
    s = (ROOT / "build-support" / "setup-env.sh").read_text(encoding="utf-8")
    line = next(ln for ln in s.splitlines() if "import sys, faster_whisper" in ln)
    reqs = (ROOT / "requirements.in").read_text(encoding="utf-8")
    for pkg, mod in (("onnxruntime", "onnxruntime"), ("tokenizers", "tokenizers"), ("sherpa-onnx", "sherpa_onnx"),
                     ("edge-tts", "edge_tts")):
        assert pkg + "==" in reqs and mod in line, pkg


def test_new_wave2_packs_valid():
    import presets as P
    ids = ["motorcycle-taxi", "promptpay-qr-payment", "water-park-zoo", "home-repair", "volunteering",
           "birthday-celebration", "funeral-condolence", "skin-clinic", "fishing-trip", "badminton-tennis"]
    allp = P.load_all()
    pend = (ROOT / "tools" / "web_pending_presets.txt").read_text(encoding="utf-8").split()
    for i in ids:
        assert i in allp and not P.validate(allp[i]) and i in pend
