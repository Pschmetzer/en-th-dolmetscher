"""build-support/setup-env.sh: Einrichtung der Python-Umgebung (Stempel, Fehlerarten, Abbrechen) und
ein Ende-zu-Ende-Lauf mit echtem uv unter `env -i` (ohne Homebrew im PATH).

Der Ende-zu-Ende-Test lädt Python + ~350 MB Pakete und läuft nur mit DOLMETSCHER_E2E_SETUP=1
(lokal; in CI übersprungen). Modelle lädt er nie neu: für den ready-Handshake verlinkt er das
small-Modell aus dem vorhandenen Hugging-Face-Cache, fehlt es, prüft er nur den Mikrofon-Handshake.
"""
import json
import os
import pathlib
import platform
import shutil
import signal
import subprocess
import sys
import time

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUP = ROOT / "build-support" / "setup-env.sh"
STAMP = ROOT / "build-support" / "make-stamp.sh"
LOCK = ROOT / "requirements.txt"
CLEAN_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"

pytestmark = [pytest.mark.macos,
              pytest.mark.skipif(sys.platform != "darwin" or platform.machine() != "arm64",
                                 reason="setup-env.sh: nur macOS auf Apple Silicon")]

FAKE_UV = r"""#!/bin/bash
# Fake-uv: protokolliert Aufrufe und Umgebung, verhält sich je nach $FAKE_MODE
echo "uv $* | pref=$UV_PYTHON_PREFERENCE noconf=$UV_NO_CONFIG pyinst=$UV_PYTHON_INSTALL_DIR" >> "$FAKE_CALLS"
case "$1" in
  venv)
    [ "$FAKE_MODE" = offline-venv ] && { echo "error: Failed to download https://x: dns error" >&2; exit 1; }
    dir="${@: -1}"; mkdir -p "$dir/bin"
    printf '#!/bin/bash\n[ "$FAKE_MODE" = badpy ] && { echo "No module named av" >&2; exit 1; }\nexit 0\n' \
      > "$dir/bin/python"
    chmod +x "$dir/bin/python" ;;
  pip)
    [ "$FAKE_MODE" = offline ] && { echo "error: Request failed after 3 retries: connection refused" >&2; exit 1; }
    [ "$FAKE_MODE" = disk ] && { echo "error: No space left on device (os error 28)" >&2; exit 1; }
    [ "$FAKE_MODE" = slow ] && sleep 30
    exit 0 ;;
esac
"""


def _env(tmp, mode="ok"):
    return {"PATH": CLEAN_PATH, "HOME": str(tmp / "home"), "FAKE_MODE": mode, "FAKE_CALLS": str(tmp / "calls")}


@pytest.fixture
def fake(tmp_path):
    uv = tmp_path / "uv"
    uv.write_text(FAKE_UV)
    uv.chmod(0o755)
    stamp = tmp_path / "env-stamp"
    stamp.write_text(subprocess.run([str(STAMP), str(LOCK)], capture_output=True, text=True, check=True).stdout)
    return uv, stamp, tmp_path / "support"


def _run(fake, tmp_path, mode="ok"):
    uv, stamp, sup = fake
    return subprocess.run(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in _env(tmp_path, mode).items()],
                           "/bin/bash", str(SETUP), str(uv), str(LOCK), str(stamp), str(sup)],
                          capture_output=True, text=True, timeout=60)


def test_stempel_aus_lock_python_arch():
    out = subprocess.run([str(STAMP), str(LOCK)], capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()
    assert lines[0].startswith("lock=") and len(lines[0]) == 5 + 64
    assert lines[1:] == ["python=3.12", "arch=arm64"]


def test_einrichtung_schritte_und_stempel_zuletzt(fake, tmp_path):
    r = _run(fake, tmp_path)
    assert r.returncode == 0, r.stderr
    assert r.stdout.split("\n")[:-1] == ["step python", "step packages", "step verify", "done"]
    sup = fake[2]
    assert (sup / "venv" / ".dolmetscher-stamp").read_text() == fake[1].read_text()
    calls = (tmp_path / "calls").read_text().splitlines()
    assert calls[0].startswith("uv venv --clear --quiet --python 3.12 ")
    assert "pip sync --quiet --require-hashes --no-build" in calls[1] and str(LOCK) in calls[1]
    assert all("pref=only-managed noconf=1" in c and f"pyinst={sup}/python" in c for c in calls)
    assert not (sup / "uv-cache").exists()


@pytest.mark.parametrize("mode,kind", [("offline", "offline"), ("offline-venv", "offline"), ("disk", "disk"),
                                       ("badpy", "failed")])
def test_fehlerart_und_teilumgebung_entfernt(fake, tmp_path, mode, kind):
    r = _run(fake, tmp_path, mode)
    assert r.returncode == 1 and r.stdout.strip().splitlines()[-1] == f"fail {kind}"
    assert not (fake[2] / "venv").exists()               # nie eine halbe Umgebung mit Stempel
    assert (fake[2] / "setup.log").read_text()


def test_alter_stempel_wird_vor_dem_neuaufbau_entfernt(fake, tmp_path):
    venv = fake[2] / "venv"
    venv.mkdir(parents=True)
    (venv / ".dolmetscher-stamp").write_text("lock=alt\n")
    r = _run(fake, tmp_path, "disk")
    assert "fail disk" in r.stdout and not (venv / ".dolmetscher-stamp").exists()


def test_fremde_venv_wird_beiseitegelegt_nie_geloescht(fake, tmp_path):
    """Eine venv mit fremdem Python (z. B. von build.sh mit conda angelegt) überlebt jede Einrichtung."""
    venv = fake[2] / "venv"
    (venv / "lib").mkdir(parents=True)
    (venv / "pyvenv.cfg").write_text("home = /opt/miniconda3/bin\nversion_info = 3.12\n")
    (venv / "lib" / "eigenes_paket.py").write_text("x = 1\n")
    r = _run(fake, tmp_path, "disk")                      # auch wenn die Einrichtung danach scheitert
    assert "fail disk" in r.stdout
    kept = [d for d in fake[2].iterdir() if d.name.startswith("venv.vorher-")]
    assert len(kept) == 1 and (kept[0] / "lib" / "eigenes_paket.py").exists()


def test_eigene_venv_wird_neu_aufgebaut(fake, tmp_path):
    sup = fake[2]
    venv = sup / "venv"
    venv.mkdir(parents=True)
    (venv / "pyvenv.cfg").write_text(f"home = {sup}/python/cpython-3.12-macos-aarch64-none/bin\n")
    r = _run(fake, tmp_path)
    assert r.stdout.strip().endswith("done")
    assert not [d for d in sup.iterdir() if d.name.startswith("venv.vorher-")]


def test_abbrechen_beendet_sofort(fake, tmp_path):
    uv, stamp, sup = fake
    p = subprocess.Popen(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in _env(tmp_path, "slow").items()],
                          "/bin/bash", str(SETUP), str(uv), str(LOCK), str(stamp), str(sup)],
                         stdout=subprocess.PIPE, text=True)
    t = time.monotonic()
    calls = tmp_path / "calls"
    while not (calls.exists() and "pip sync" in calls.read_text()):
        assert time.monotonic() - t < 10
        time.sleep(0.05)
    time.sleep(0.2)
    p.send_signal(signal.SIGTERM)
    out, _ = p.communicate(timeout=10)
    assert time.monotonic() - t < 10
    assert out.strip().splitlines()[-1] == "fail cancelled" and not (sup / "venv").exists()


def test_falsche_architektur_bricht_ab(fake, tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    (bindir / "uname").write_text("#!/bin/bash\necho x86_64\n")
    (bindir / "uname").chmod(0o755)
    uv, stamp, sup = fake
    env = _env(tmp_path)
    env["PATH"] = f"{bindir}:{CLEAN_PATH}"
    r = subprocess.run(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in env.items()],
                        "/bin/bash", str(SETUP), str(uv), str(LOCK), str(stamp), str(sup)],
                       capture_output=True, text=True, timeout=30)
    assert r.stdout.strip() == "fail arch"


# ---------------------------------------------------------------- Ende-zu-Ende (echtes uv, Netz) ----------

def _real_uv():
    for c in (os.environ.get("DOLMETSCHER_UV"), shutil.which("uv"), "/opt/homebrew/bin/uv"):
        if c and os.access(c, os.X_OK):
            return c
    return None


def _engine_events(cmd, env, until, timeout):
    p = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True)
    seen, end = [], time.monotonic() + timeout
    try:
        for line in p.stdout:
            if line.startswith("{"):
                o = json.loads(line)
                seen.append(o)
                if o.get("event") in until:
                    break
            if time.monotonic() > end:
                break
    finally:
        p.kill()
        p.communicate(timeout=10)
    return seen


@pytest.mark.skipif(os.environ.get("DOLMETSCHER_E2E_SETUP") != "1", reason="schwer: DOLMETSCHER_E2E_SETUP=1")
@pytest.mark.timeout(2400)                                     # Einrichtung bis 1800 s + Engine-Start 240 s
def test_e2e_einrichtung_unter_env_i_und_engine_handshake(tmp_path):
    uv = _real_uv()
    if not uv:
        pytest.skip("uv nicht gefunden")
    helpers = tmp_path / "Helpers"                    # wie im Bundle: uv außerhalb jedes PATH
    helpers.mkdir()
    shutil.copy2(uv, helpers / "uv")
    stamp = tmp_path / "env-stamp"
    stamp.write_text(subprocess.run([str(STAMP), str(LOCK)], capture_output=True, text=True, check=True).stdout)
    sup, home = tmp_path / "support", tmp_path / "home"
    home.mkdir()
    base = {"PATH": CLEAN_PATH, "HOME": str(home)}
    r = subprocess.run(["/usr/bin/env", "-i", *[f"{k}={v}" for k, v in base.items()], "/bin/bash", str(SETUP),
                        str(helpers / "uv"), str(LOCK), str(stamp), str(sup)],
                       capture_output=True, text=True, timeout=1800)
    assert r.stdout.strip().splitlines()[-1] == "done", (sup / "setup.log").read_text()[-2000:]
    py = sup / "venv" / "bin" / "python"
    real = os.path.realpath(py)
    assert real.startswith(str(sup / "python")), real          # uv-verwaltetes Python der App, kein Homebrew/conda
    # Engine: nur mit der neuen Umgebung, ohne Homebrew/ffmpeg, mit eigenem Log/Cache
    hf = tmp_path / "hf"
    (hf / "hub").mkdir(parents=True)
    env = {**base, "DOLMETSCHER_HOME": str(tmp_path / "dh"), "DOLMETSCHER_LOG": str(tmp_path / "engine.log"),
           "HF_HOME": str(hf), "XDG_CACHE_HOME": str(tmp_path / "xdg"), "HF_HUB_OFFLINE": "1",
           "PYTHONPYCACHEPREFIX": str(tmp_path / "pycache"), "DOLMETSCHER_NULL_AUDIO": "1"}
    ev = _engine_events([str(py), "-B", str(ROOT / "dolmetscher.py"), "--json", "--list-mics"], env, {"mics"}, 60)
    assert ev and ev[-1]["event"] == "mics" and not any(e.get("code") in ("audio_missing", "ffmpeg_missing")
                                                      for e in ev), ev
    src = pathlib.Path.home() / ".cache" / "huggingface" / "hub" / "models--Systran--faster-whisper-small"
    if not src.exists():
        pytest.skip("small-Modell nicht im Cache: ready-Handshake übersprungen (kein Neu-Download)")
    (hf / "hub" / src.name).symlink_to(src)
    ev = _engine_events([str(py), "-B", str(ROOT / "dolmetscher.py"), "--json", "--idle", "--model", "small",
                         "--tts", "say", "--langs", "en,th"], env, {"ready"}, 240)
    ready = [e for e in ev if e["event"] == "ready"]
    assert ready and ready[0]["protocol"] == 1, ev[-5:]
