"""Hardware-Erkennung (Chip, RAM) und Empfehlung für Whisper-Modell und Beam-Breite.

Wird nur mit `--model auto` benutzt; der Standard bleibt `medium`."""
import platform
import subprocess
import time

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


def low_power_mode(run=None):
    """Energiesparmodus an (`pmset -g`: "lowpowermode 1")? Unbekannt/Fehler: False."""
    run = run or subprocess.run
    try:
        r = run(["pmset", "-g"], capture_output=True, text=True, timeout=3)
        for line in (r.stdout or "").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0].lower() in ("lowpowermode", "powermode") and parts[1] == "1":
                return True
    except Exception:
        pass
    return False


def thermal_throttled(run=None):
    """Drosselt macOS die CPU wegen Hitze (`pmset -g therm`: "CPU_Speed_Limit = 70")? Unbekannt/Fehler: False."""
    run = run or subprocess.run
    try:
        r = run(["pmset", "-g", "therm"], capture_output=True, text=True, timeout=3)
        for line in (r.stdout or "").splitlines():
            key, _, val = line.partition("=")
            if key.strip().lower() == "cpu_speed_limit":
                return int(val.strip()) < 100
    except Exception:
        pass
    return False


def power_saving(run=None):
    """Akkubetrieb, Energiesparmodus oder Hitzedrosselung: dann lieber sparsam rechnen (für adjust_for_power)."""
    return on_battery(run) or low_power_mode(run) or thermal_throttled(run)


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


# ---------------------------------------------------------------- Kurz-Benchmark (Runde 23)
BENCH_BUDGET_S = 0.15          # so lange läuft der Test höchstens (der Start soll nicht spürbar warten)
BENCH_SLOW = 0.5               # Punktzahl darunter: eine Stufe sparsamer
BENCH_FAST = 2.0               # Punktzahl ab hier: "fast"
_BENCH_REF_PER_S = 1500.0      # Rechenblöcke je Sekunde auf dem Maßstab-Rechner (Punktzahl 1,0)


def _bench_block():
    x = 0
    for i in range(2000):
        x = (x * 31 + i) & 0xFFFF
    return x


def quick_benchmark(budget_s=BENCH_BUDGET_S, clock=None, work=None):
    """Kurzer CPU-Test (reines Python, kein numpy/Netz): zählt die Rechenblöcke, die in `budget_s` Sekunden fertig
    werden. -> Punktzahl relativ zum Maßstab (1,0 = typischer Rechner). `clock`/`work` sind für Tests austauschbar.
    Wirft nie: bei Fehler 1.0."""
    clock = clock or time.perf_counter
    work = work or _bench_block
    try:
        budget = max(0.01, float(budget_s))
        t0 = clock()
        n = 0
        while clock() - t0 < budget:
            work()
            n += 1
        elapsed = max(1e-6, clock() - t0)
        return round((n / elapsed) / _BENCH_REF_PER_S, 3)
    except Exception:
        return 1.0


def bench_tier(score):
    """Punktzahl -> "slow" | "normal" | "fast"."""
    if score < BENCH_SLOW:
        return "slow"
    return "fast" if score >= BENCH_FAST else "normal"


def refine_with_benchmark(rec, score):
    """Empfehlung anhand des Kurz-Benchmarks anpassen: langsam -> eine Stufe kleiner und Beam 1, sonst unverändert.
    Gibt eine Kopie zurück."""
    out = dict(rec)
    if bench_tier(score) != "slow":
        return out
    i = TIERS.index(out["model"]) if out.get("model") in TIERS else 1
    out["model"] = TIERS[max(0, i - 1)]
    out["beam"] = 1
    out["reason"] = str(out.get("reason", "")) + " (Benchmark langsam: sparsamer)"
    return out
