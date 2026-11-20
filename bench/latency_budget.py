#!/usr/bin/env python3
"""Latenz-Regression mit Zeitbudget (Runde 24): prüft ein Ergebnis von run_bench.py gegen bench/latency_budget.json
und optional gegen eine Baseline. Kein Modell, kein Netz: liest nur JSON.

    python3 bench/latency_budget.py bench/results/ci_small.json
    python3 bench/latency_budget.py neu.json --baseline bench/results/baseline_main.json --scale 1.5

Prüft (1) die Kennzahlen je Sprache in `summary` gegen das Budget (mal --scale), (2) jeden Fall: mehr als
`case_regression_pct` Prozent UND mehr als `case_min_delta_s` Sekunden langsamer als in der Baseline.
Exit 0 = ok, 2 = Budget oder Regression verletzt, 1 = Datei unlesbar.
"""
import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_BUDGET = HERE / "latency_budget.json"


def _num(x):
    return float(x) if isinstance(x, (int, float)) and not isinstance(x, bool) and x == x else None


def check_budget(result, budget, scale=1.0):
    """[(lang, key, wert, grenze)] für verletzte Kennzahlen. Fehlende Kennzahlen zählen nicht als Verstoß."""
    out = []
    summ = result.get("summary") or {}
    for lang, limits in (budget.get("budget") or {}).items():
        got = summ.get(lang) or {}
        for key, lim in limits.items():
            v, lim = _num(got.get(key)), _num(lim)
            if v is not None and lim is not None and v > lim * scale:
                out.append((lang, key, v, round(lim * scale, 3)))
    return out


def check_cases(result, baseline, pct=40.0, min_delta=1.0, scale=1.0):
    """[(id, alt, neu)] für Fälle, die gegenüber der Baseline deutlich langsamer wurden. Verworfene Fälle
    (kein Zeitwert) und Fälle ohne Gegenstück werden übersprungen."""
    base = {r.get("id"): _num(r.get("total_s")) for r in (baseline.get("results") or [])}
    out = []
    for r in result.get("results") or []:
        new, old = _num(r.get("total_s")), base.get(r.get("id"))
        if new is None or not old or old <= 0:
            continue
        old *= scale
        if new - old > min_delta and (new - old) / old * 100.0 > pct:
            out.append((r.get("id"), round(old, 3), new))
    return out


def main(argv=None, stdout=None):
    stdout = stdout or sys.stdout
    ap = argparse.ArgumentParser(description="Latenz gegen Zeitbudget prüfen")
    ap.add_argument("result", help="JSON aus run_bench.py")
    ap.add_argument("--budget", default=str(DEFAULT_BUDGET))
    ap.add_argument("--baseline", help="Baseline-JSON für die Prüfung je Fall")
    ap.add_argument("--scale", type=float, default=1.0, help="Budget und Baseline-Zeiten mit Faktor (langsamer Runner)")
    a = ap.parse_args(argv)
    if not 0.1 <= a.scale <= 20:
        ap.error("--scale muss zwischen 0.1 und 20 liegen")
    try:
        result = json.loads(pathlib.Path(a.result).read_text(encoding="utf-8"))
        budget = json.loads(pathlib.Path(a.budget).read_text(encoding="utf-8"))
        baseline = json.loads(pathlib.Path(a.baseline).read_text(encoding="utf-8")) if a.baseline else None
    except (OSError, ValueError) as e:
        sys.stderr.write(f"nicht lesbar: {e}\n")
        return 1
    bad = check_budget(result, budget, a.scale)
    for lang, key, v, lim in bad:
        stdout.write(f"BUDGET  {lang} {key}: {v} > {lim}\n")
    slow = []
    if baseline is not None:
        slow = check_cases(result, baseline, float(budget.get("case_regression_pct", 40)),
                           float(budget.get("case_min_delta_s", 1.0)), a.scale)
        for cid, old, new in slow:
            stdout.write(f"LANGSAMER  {cid}: {old} s -> {new} s\n")
    stdout.write(f"{len(bad)} Budgetverstöße, {len(slow)} langsamere Fälle\n")
    return 2 if bad or slow else 0


if __name__ == "__main__":
    sys.exit(main())
