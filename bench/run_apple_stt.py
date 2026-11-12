#!/usr/bin/env python3
"""Bewertet Ergebnisse von tools/apple-stt (JSON-Array) mit den Metriken aus bench/run_bench.py
und stellt sie dem Whisper-Ergebnis (bench/results/feat_medium_cpu.json, Feld hyp) gegenüber.

    python bench/run_apple_stt.py tools/apple-stt/results/en_realtime.json [th_realtime.json …]
"""
import json, statistics, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_bench import error_rate  # noqa: E402  (gleiche Normalisierung wie der Benchmark)

cases = {c["id"]: c for c in json.loads((HERE / "cases.json").read_text())}
whisper = {r["id"]: r for r in json.loads((HERE / "results/feat_medium_cpu.json").read_text())["results"]}

rows = []
for f in sys.argv[1:]:
    for r in json.loads(Path(f).read_text()):
        cid = Path(r["file"]).stem
        c = cases[cid]
        hyp = r.get("text") or ""
        w = whisper.get(cid, {})
        rows.append({
            "id": cid, "lang": c["lang"], "ref": c["text"], "apple": hyp, "whisper": w.get("hyp") or "",
            "err_apple": error_rate(c["text"], hyp, c["lang"]),
            "err_whisper": error_rate(c["text"], w.get("hyp") or "", c["lang"]),
            "ms_after": r.get("ms_after_audio_end"), "ms_first": r.get("ms_first_result"),
            "ms_total": r.get("ms_total"), "audio_s": r.get("audio_s"), "error": r.get("error"),
        })

for lang in ("th", "en"):
    rs = [r for r in rows if r["lang"] == lang]
    if not rs:
        continue
    m = "CER" if lang == "th" else "WER"
    after = [r["ms_after"] for r in rs if r["ms_after"] is not None]
    print(f"\n== {lang}: n={len(rs)}  {m} Apple Ø {statistics.mean(r['err_apple'] for r in rs):.2%}"
          f"  Whisper Ø {statistics.mean(r['err_whisper'] for r in rs):.2%}"
          f"  | ms nach Audio-Ende Median {statistics.median(after) if after else '-'}"
          f"  max {max(after) if after else '-'}"
          f"  | erstes Ergebnis Median {statistics.median([r['ms_first'] for r in rs if r['ms_first'] is not None])}")
    for r in sorted(rs, key=lambda r: -r["err_apple"])[:10]:
        print(f"{r['id']}  A {r['err_apple']:.2f}  W {r['err_whisper']:.2f}  {r['ms_after']} ms"
              f"\n   ref: {r['ref']}\n   app: {r['apple']}\n   whi: {r['whisper']}")
