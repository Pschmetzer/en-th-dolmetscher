#!/usr/bin/env python3
"""Mikro-Benchmark der Pipeline-Hot-Paths (Runde 27): Übersetzungs-Cache, Cache-Schlüssel (`_norm`),
Satzteilung (`split_sentences`) und Zahlen-Vorlesen. Misst nur reine CPU-Zeit, keine Modelle, kein Netz.

    python bench/micro_bench.py [--n 20000] [--out bench/results/micro_r27.json]

Ausgabe: Medianzeit je Aufruf in Mikrosekunden (beste von 5 Läufen, gegen Ausreißer). Die Zahlen hängen vom Rechner ab;
verglichen wird vor/nach einer Änderung auf demselben Gerät."""
import argparse
import json
import os
import platform
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

EN = ["Could you tell me where the nearest pharmacy is, please? I have a headache. It started this morning.",
      "Hello!", "How much is the room per night, and is breakfast included? We arrive at 10:30 a.m. on Friday.",
      "Mr. Smith said the meeting costs 3.5 million baht. Dr. Lee agreed, e.g. for the first year."]
TH = ["สวัสดีครับ วันนี้อากาศดีมาก ผมอยากไปเที่ยวทะเลกับครอบครัว ไม่ทราบว่าคุณมีแนะนำที่ไหนบ้างไหมครับ",
      "ราคา 1,500 บาท ต่อคืน รวมอาหารเช้าไหมคะ เวลา 10.30 น. ค่ะ", "ขอบคุณค่ะ", "ตีสามสิบห้านาที สี่โมงสิบห้านาที"]


def bench(fn, n, repeat=5):
    """Beste mittlere Zeit je Aufruf in µs über `repeat` Läufe zu je `n` Aufrufen."""
    best = None
    for _ in range(repeat):
        t0 = time.perf_counter()
        for i in range(n):
            fn(i)
        dt = (time.perf_counter() - t0) / n * 1e6
        best = dt if best is None or dt < best else best
    return round(best, 3)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--n", type=int, default=20000, help="Aufrufe je Lauf")
    ap.add_argument("--out", default="", help="Ergebnis als JSON schreiben")
    a = ap.parse_args()
    import dolmetscher as d
    n = max(100, a.n)
    res = {}
    res["norm_warm_us"] = bench(lambda i: d._norm(EN[i % len(EN)]), n)
    res["norm_cold_us"] = bench(lambda i: d._norm.__wrapped__(f"{EN[i % len(EN)]} {i}"), n)
    res["norm_thai_cold_us"] = bench(lambda i: d._norm.__wrapped__(f"{TH[i % len(TH)]} {i}"), n)
    res["split_en_us"] = bench(lambda i: d.split_sentences(EN[i % len(EN)], "en"), n)
    res["split_th_us"] = bench(lambda i: d.split_sentences(TH[i % len(TH)], "th"), n)
    res["cache_key_us"] = bench(lambda i: d._cache_key(EN[i % len(EN)], "en", "th", False, "krub"), n)
    d._cache_clear()
    keys = [d._cache_key(f"{EN[i % len(EN)]} {i % 500}", "en", "th", False, "krub") for i in range(512)]
    res["cache_put_us"] = bench(lambda i: d._cache_put(keys[i % 512], (f"übersetzt {i % 512}", "google")), n)
    res["cache_get_hit_us"] = bench(lambda i: d._cache_get(keys[i % 512]), n)
    res["cache_get_miss_us"] = bench(lambda i: d._cache_get(("x", "en", "th", "mt", str(i))), n)
    res["speak_numbers_th_us"] = bench(lambda i: d.speak_numbers_th(TH[i % len(TH)]), n)
    res["numbers_differ_us"] = bench(lambda i: d._numbers_differ(f"{EN[i % len(EN)]} {i}", TH[i % len(TH)]),
                                     max(100, n // 10))
    d._cache_clear()
    out = {"meta": {"python": platform.python_version(), "machine": platform.machine(), "n": n}, "us_per_call": res}
    print(json.dumps(out, indent=2))
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=2, ensure_ascii=False)
            f.write("\n")


if __name__ == "__main__":
    main()
