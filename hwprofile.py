"""Hardware-Erkennung (Chip, RAM) und Empfehlung für Whisper-Modell und Beam-Breite.

Wird nur mit `--model auto` benutzt; der Standard bleibt `medium`."""
import platform
import subprocess

TIERS = ("small", "medium", "best")


def _sysctl(key, run=None):
    run = run or subprocess.run
    try:
        r = run(["sysctl", "-n", key], capture_output=True, text=True, timeout=3)
        return (r.stdout or "").strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def detect(run=None, machine=None):
    """-> {"chip": str, "ram_gb": float, "arm64": bool}; unbekannte Werte werden 0 / ""."""
    machine = machine if machine is not None else platform.machine()
    try:
        ram = int(_sysctl("hw.memsize", run) or 0) / 2 ** 30
    except ValueError:
        ram = 0.0
    # Unter Rosetta meldet platform.machine() "x86_64", obwohl ein Apple-Chip läuft: sysctl fragen
    arm64 = machine == "arm64" or _sysctl("hw.optional.arm64", run) == "1"
    return {"chip": _sysctl("machdep.cpu.brand_string", run), "ram_gb": round(ram, 1), "arm64": arm64}


def perf_cores(run=None):
    """Performance-Kerne (Apple Silicon: hw.perflevel0.physicalcpu, sonst hw.physicalcpu); 0 = unbekannt."""
    for key in ("hw.perflevel0.physicalcpu", "hw.physicalcpu"):
        try:
            n = int(_sysctl(key, run) or 0)
        except ValueError:
            n = 0
        if n > 0:
            return n
    return 0


def recommend(info):
    """-> {"model": small|medium|best, "beam": int, "reason": str}."""
    ram, chip = info.get("ram_gb") or 0, (info.get("chip") or "").lower()
    if not info.get("arm64") or ram < 8:
        return {"model": "small", "beam": 1, "reason": "Intel/unbekannt oder unter 8 GB RAM"}
    strong = any(k in chip for k in ("pro", "max", "ultra"))
    if ram >= 24 and strong:
        return {"model": "best", "beam": 5, "reason": "Apple Silicon Pro/Max/Ultra, mindestens 24 GB"}
    if ram >= 16:
        return {"model": "medium", "beam": 3, "reason": "Apple Silicon, mindestens 16 GB"}
    return {"model": "medium", "beam": 1, "reason": "Apple Silicon, 8-15 GB"}


def auto_choice(run=None, machine=None):
    info = detect(run, machine)
    return {**info, **recommend(info)}


def on_battery(run=None):
    """Läuft der Mac im Akkubetrieb (pmset -g batt: "Battery Power")? Unbekannt/Fehler: False."""
    run = run or subprocess.run
    try:
        r = run(["pmset", "-g", "batt"], capture_output=True, text=True, timeout=3)
        return "battery power" in (r.stdout or "").lower()
    except Exception:
        return False


def adjust_for_power(rec, battery):
    """Im Akkubetrieb eine Stufe sparsamer: Beam 1, `best` -> `medium` (Wärme/Laufzeit)."""
    if not battery:
        return rec
    out = dict(rec)
    out["beam"] = 1
    if out["model"] == "best":
        out["model"] = "medium"
    out["reason"] += " (Akkubetrieb: sparsamer)"
    return out
