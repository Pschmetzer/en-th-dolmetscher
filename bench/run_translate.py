#!/usr/bin/env python3
"""Übersetzungs-Vergleich: Google vs. Claude (Haiku/Sonnet/Opus) auf bench/idioms.json.

    python3 bench/run_translate.py [--models claude-haiku-5-5,claude-sonnet-5-5] [--style casual]
    python3 bench/run_translate.py --repeat 3 --json-out bench/results/translate.json

Claude braucht einen API-Schlüssel (Umgebung oder Datei) und kostet wenige Cent. Neben der Tabelle zum
Selbst-Bewerten gibt es eine automatische Bewertung (Nr. 164), je Anbieter gemittelt:

- `rt_chrf`: chrF (0–100) zwischen Original und Rückübersetzung (Google, Ziel -> Quelle). Ein Näherungswert:
  Redewendungen werden sinngemäß übersetzt und kommen nie wörtlich zurück; Vergleiche nur zwischen Anbietern
  auf denselben Sätzen sind aussagekräftig.
- `num_ok`: Anteil der Sätze, deren Zahlen/Uhrzeiten erhalten bleiben (`numbers_differ` der Engine).
- `names_ok`: Anteil, in dem Eigennamen/lateinische Wörter (Großschreibung im Original) wörtlich vorkommen.
- Zeit je Satz (Median über --repeat).
"""
import argparse, json, os, re, statistics, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import dolmetscher as d  # noqa: E402


# ---------------------------------------------------------------- Metriken (ohne Netz, getestet)

def _char_ngrams(s, n):
    s = re.sub(r"\s+", " ", s.strip().lower())
    return [s[i:i + n] for i in range(len(s) - n + 1)]


def chrf(ref, hyp, n_max=6, beta=2.0):
    """chrF (Popović 2015) auf Zeichen-n-Grammen 1..n_max, 0–100. Für Thai (ohne Leerzeichen) geeignet."""
    if not ref or not hyp:
        return 0.0
    precs, recs = [], []
    for n in range(1, n_max + 1):
        r, h = _char_ngrams(ref, n), _char_ngrams(hyp, n)
        if not r or not h:
            continue
        rc = {}
        for g in r:
            rc[g] = rc.get(g, 0) + 1
        hit = 0
        for g in h:
            if rc.get(g, 0) > 0:
                rc[g] -= 1
                hit += 1
        precs.append(hit / len(h))
        recs.append(hit / len(r))
    if not precs:
        return 0.0
    p, r = statistics.mean(precs), statistics.mean(recs)
    if p + r == 0:
        return 0.0
    b2 = beta * beta
    return round(100 * (1 + b2) * p * r / (b2 * p + r), 1)


_NAME = re.compile(r"(?<![.!?]\s)(?<!^)\b[A-Z][a-z]+\b")


def names_kept(src, out):
    """Eigennamen (großgeschrieben mitten im Satz) aus `src` stehen wörtlich in `out`? None ohne Namen."""
    names = [m.group(0) for m in _NAME.finditer(src or "") if m.group(0) not in ("I",)]
    if not names:
        return None
    return all(n.lower() in (out or "").lower() for n in names)


def score(src_text, src, out, back):
    """Bewertung eines Satzes (dict) – `back` = Rückübersetzung von `out` in die Quellsprache (oder None)."""
    return {"rt_chrf": chrf(src_text, back) if back else None,
            "num_ok": not d.numbers_differ(src_text, out),
            "names_ok": names_kept(src_text, out)}


def aggregate(rows):
    """Mittelwerte je Anbieter aus den Zeilen von score() (+ `secs`)."""
    def mean(k, as_bool=False):
        v = [r[k] for r in rows if r.get(k) is not None]
        if not v:
            return None
        return round(sum(bool(x) for x in v) / len(v), 3) if as_bool else round(statistics.mean(v), 1)
    secs = [r["secs"] for r in rows if r.get("secs") is not None]
    return {"n": len(rows), "rt_chrf": mean("rt_chrf"), "num_ok": mean("num_ok", True),
            "names_ok": mean("names_ok", True), "secs_median": round(statistics.median(secs), 2) if secs else None}


# ---------------------------------------------------------------- Lauf

def back_translate(out, dst, src):
    try:
        return d._mt_chain(out, dst, src, {}, time.monotonic() + 8)
    except Exception:
        return None


def timed(fn, repeat):
    times, out = [], None
    for _ in range(repeat):
        t = time.time()
        out = fn()
        times.append(time.time() - t)
    return out, statistics.median(times)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="claude-haiku-5-5,claude-sonnet-5-5")
    ap.add_argument("--style", default="casual", choices=list(d.STYLES))
    ap.add_argument("--repeat", type=int, default=1, help="jede Anfrage N-mal (Zeit als Median)")
    ap.add_argument("--no-back", action="store_true", help="ohne Rückübersetzung (spart Google-Anfragen)")
    ap.add_argument("--json-out", default=None, help="Ergebnis (Zeilen + Mittelwerte) als JSON speichern")
    a = ap.parse_args()
    if a.repeat < 1:
        ap.error("--repeat muss >= 1 sein")
    cases = json.load(open(os.path.join(os.path.dirname(__file__), "idioms.json"), encoding="utf-8"))
    models = [m for m in a.models.split(",") if m] if d.llm_available() else []
    if not models:
        print("(kein Claude-Schlüssel – nur Google)", file=sys.stderr)
    d.LLM["style"] = a.style
    rows = {}
    for c in cases:
        dst = d.TARGET[c["src"]]
        print(f"\n[{c['src']}] {c['text']}   (Sinn: {c['gist']})")
        runs = [("google", lambda: d.google_translate(c["text"], c["src"], dst))]
        for m in models:
            def claude(m=m):
                d.LLM["model"], d.LLM["client"] = m, None
                return d.claude_translate(c["text"], c["src"], dst)
            runs.append((m.replace("claude-", ""), claude))
        for name, fn in runs:
            try:
                out, secs = timed(fn, a.repeat)
            except Exception as e:
                print(f"  {name:7} Fehler: {e!r}"[:160])
                continue
            back = None if a.no_back else back_translate(out, dst, c["src"])
            sc = score(c["text"], c["src"], out, back)
            rows.setdefault(name, []).append({"text": c["text"], "out": out, "back": back, "secs": round(secs, 2),
                                              **sc})
            flags = "" if sc["num_ok"] else "  ⚠ Zahlen"
            print(f"  {name:7} {secs:4.1f}s  {out}{flags}")
            if back:
                print(f"  {'':7}  ↩︎ {back}  (chrF {sc['rt_chrf']})")
    summary = {k: aggregate(v) for k, v in rows.items()}
    print("\nAnbieter | n | Rück-chrF Ø | Zahlen ok | Namen ok | Zeit Median")
    for k, s in summary.items():
        print(f"{k:8} | {s['n']} | {s['rt_chrf']} | {s['num_ok']} | {s['names_ok']} | {s['secs_median']} s")
    if models:
        print(f"\nGeschätzte Kosten: ≈ ${d.LLM['usd']:.4f}")
    if a.json_out:
        with open(a.json_out, "w", encoding="utf-8") as f:
            json.dump({"style": a.style, "summary": summary, "rows": rows}, f, ensure_ascii=False, indent=1)
        print(f"Gespeichert: {a.json_out}")


if __name__ == "__main__":
    main()
