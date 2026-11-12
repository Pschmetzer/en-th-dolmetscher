#!/usr/bin/env python3
"""Übersetzungs-Vergleich: Google vs. Claude (Haiku/Sonnet/Opus) auf bench/idioms.json.

    python3 bench/run_translate.py [--models claude-haiku-5-5,claude-sonnet-5-5] [--style casual]

Claude braucht einen API-Schlüssel (Umgebung oder Datei) und kostet wenige Cent. Ausgabe: Tabelle zum
Selbst-Bewerten (kein automatischer Score, Redewendungen lassen sich nicht sinnvoll per Skript benoten)."""
import argparse, json, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import dolmetscher as d  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="claude-haiku-5-5,claude-sonnet-5-5")
    ap.add_argument("--style", default="casual", choices=list(d.STYLES))
    a = ap.parse_args()
    cases = json.load(open(os.path.join(os.path.dirname(__file__), "idioms.json"), encoding="utf-8"))
    models = [m for m in a.models.split(",") if m] if d.llm_available() else []
    if not models:
        print("(kein Claude-Schlüssel – nur Google)", file=sys.stderr)
    d.LLM["style"] = a.style
    for c in cases:
        dst = d.TARGET[c["src"]]
        print(f"\n[{c['src']}] {c['text']}   (Sinn: {c['gist']})")
        t = time.time()
        try:
            print(f"  google  {time.time() - t:4.1f}s  {d.google_translate(c['text'], c['src'], dst)}")
        except Exception as e:
            print(f"  google  Fehler: {e}")
        for m in models:
            d.LLM["model"], d.LLM["client"] = m, None
            t = time.time()
            try:
                out = d.claude_translate(c["text"], c["src"], dst)
                print(f"  {m.replace('claude-', ''):7} {time.time() - t:4.1f}s  {out}")
            except Exception as e:
                print(f"  {m:7} Fehler: {e!r}"[:160])
    if models:
        print(f"\nGeschätzte Kosten: ≈ ${d.LLM['usd']:.4f}")


if __name__ == "__main__":
    main()
