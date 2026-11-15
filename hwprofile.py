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
    return {"chip": _sysctl("machdep.cpu.brand_string", run), "ram_gb": round(ram, 1),
            "arm64": machine == "arm64"}


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
