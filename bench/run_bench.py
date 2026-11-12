#!/usr/bin/env python3
"""Misst Erkennung (STT) und Übersetzung der Engine auf bench/cases.json.

    python bench/run_bench.py                              # medium, alle Fälle
    python bench/run_bench.py --model small --device cpu --only th
    python bench/run_bench.py --cases th01,th02 --compare bench/results/baseline_main.json

Audio: bench/audio/real/<id>.* (eigene Aufnahmen, bevorzugt), sonst --audio-dir
(Standard bench/audio/clean, erzeugt von make_audio.py).
"""
import argparse, datetime, json, os, platform, re, statistics, subprocess, shutil, sys, time, unicodedata
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SR = 16000
AUDIO_EXT = (".wav", ".m4a", ".mp3", ".aiff", ".flac", ".ogg", ".caf")
FFMPEG = os.environ.get("DOLMETSCHER_FFMPEG") or shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"

# ---------------------------------------------------------------- Normalisierung / Metriken

THAI_DIGITS = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")
EN_NUM = {w: str(i) for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
    "fifteen sixteen seventeen eighteen nineteen twenty".split())}


def _strip_punct(s):
    return "".join(ch if not unicodedata.category(ch)[0] in "PS" else " " for ch in s)


# gleichwertige Schreibweisen, die keine Erkennungsfehler sind
TH_VARIANTS = [("มั้ย", "ไหม"), ("เท่าไหร่", "เท่าไร")]


TH_DIG = {"ศูนย์": 0, "หนึ่ง": 1, "เอ็ด": 1, "สอง": 2, "ยี่": 2, "สาม": 3, "สี่": 4, "ห้า": 5,
          "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9}
TH_UNIT = {"สิบ": 10, "ร้อย": 100, "พัน": 1000, "หมื่น": 10000, "แสน": 100000, "ล้าน": 1000000}
_TH_NUM_RE = re.compile("(?:" + "|".join(sorted(list(TH_DIG) + list(TH_UNIT), key=len, reverse=True)) + ")+")


def _th_words_to_int(w):
    total, cur, digit = 0, 0, None
    for tok in re.findall("|".join(sorted(list(TH_DIG) + list(TH_UNIT), key=len, reverse=True)), w):
        if tok in TH_DIG:
            digit = TH_DIG[tok]
        elif tok == "ล้าน":
            total = (total + cur + (digit or 0)) * 1000000; cur, digit = 0, None
        else:
            cur += (1 if digit is None else digit) * TH_UNIT[tok]; digit = None
    return total + cur + (digit or 0)


def th_numbers_to_digits(s):
    """Zahlwörter -> Ziffern (สามร้อย -> 300, หนึ่งพันสองร้อยห้า -> 1205), auf Referenz UND Erkennung.
    Whisper-Thai schreibt Zahlen mal als Ziffern, mal als Wörter; das ist kein Erkennungsfehler."""
    return _TH_NUM_RE.sub(lambda m: str(_th_words_to_int(m.group(0))), s)


def norm_th(s):
    """Thai: nur Zeichen, ohne Leerzeichen und Satzzeichen; Thai-Ziffern -> 0-9, Zahlwörter -> Ziffern."""
    s = unicodedata.normalize("NFC", s or "").translate(THAI_DIGITS).lower()
    s = re.sub(r"(?<=\d),(?=\d{3})", "", s)
    s = th_numbers_to_digits(re.sub(r"\s+", "", s))
    for a, b in TH_VARIANTS:
        s = s.replace(a, b)
    return re.sub(r"\s+", "", _strip_punct(s))


def words_en(s):
    """Englisch: Kleinbuchstaben, ohne Satzzeichen/Apostrophe, Zahlwörter 0-20 -> Ziffern."""
    s = (s or "").lower().replace("'", "").replace("’", "")
    return [EN_NUM.get(w, w) for w in _strip_punct(s).split()]


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def error_rate(ref, hyp, lang):
    """CER (Thai) bzw. WER (Englisch); 1.0 wenn nichts erkannt wurde."""
    r, h = (list(norm_th(ref)), list(norm_th(hyp))) if lang == "th" else (words_en(ref), words_en(hyp))
    if not r:
        return 0.0 if not h else 1.0
    return edit_distance(r, h) / len(r)


def _f1(a, b):
    if not a or not b:
        return 0.0
    common = sum(min(a.count(t), b.count(t)) for t in set(a))
    if not common:
        return 0.0
    p, r = common / len(b), common / len(a)
    return round(2 * p * r / (p + r), 3)


def overlap(ref, out, lang):
    """Grober Übersetzungs-Wert: Wort-F1 (Englisch) bzw. Zeichen-Bigramm-F1 (Thai) gegen die Soll-Bedeutung."""
    if not ref or not out:
        return None
    if lang == "en":
        return _f1(words_en(ref), words_en(out))
    a, b = norm_th(ref), norm_th(out)
    return _f1([a[i:i + 2] for i in range(len(a) - 1)], [b[i:i + 2] for i in range(len(b) - 1)])


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return None
    k = (len(xs) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


# ---------------------------------------------------------------- Audio

def find_audio(cid, audio_dir):
    for d, src in ((HERE / "audio" / "real", "real"), (Path(audio_dir), "synth")):
        for ext in AUDIO_EXT:
            p = d / f"{cid}{ext}"
            if p.exists():
                return p, src
    return None, None


def load_audio(path):
    raw = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path),
                          "-ar", str(SR), "-ac", "1", "-f", "s16le", "-"],
                         check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768


# ---------------------------------------------------------------- Engine-Anbindung

class Capture:
    """Fängt emit()-Ereignisse und log()-Dicts der Engine ab (stabiler als der Rückgabewert)."""

    def __init__(self):
        self.events, self.logs = [], []

    def emit(self, event, **kw):
        self.events.append((event, dict(kw)))

    def log(self, d, *a, **kw):
        if isinstance(d, dict):
            self.logs.append(dict(d))

    def reset(self):
        self.events, self.logs = [], []


def load_engine_module(cap):
    os.environ.setdefault("DOLMETSCHER_LOG", str(HERE / "audio" / "engine-bench.log"))
    sys.path.insert(0, str(ROOT))
    import dolmetscher as d
    for name in ("emit", "_emit"):
        if hasattr(d, name):
            setattr(d, name, cap.emit)
    if hasattr(d, "log"):
        d.log = cap.log                  # nichts ins echte engine.log schreiben, Infos mitlesen
    return d


RESET = {"paused": False, "awake_until": 0.0, "lock": "auto", "rate": 0, "volume": 1.0, "mute": False}


def reset_state(eng, keep_profiles):
    for k, v in RESET.items():
        if hasattr(eng, k):
            try:
                setattr(eng, k, v)
            except Exception:
                pass
    if hasattr(eng, "translate_dir"):
        eng.translate_dir = {"en": True, "th": True}
    if not keep_profiles and hasattr(eng, "spk"):
        eng.spk = None


def call_process(eng, audio):
    try:
        return eng.process(audio, speak=False)
    except TypeError:
        return eng.process(audio)


def run_case(d, eng, cap, case, audio, keep_profiles, retries=1):
    for attempt in range(retries + 1):
        reset_state(eng, keep_profiles)
        cap.reset()
        t0 = time.time()
        err = None
        try:
            ret = call_process(eng, audio)
        except Exception as e:                         # Engine-Fehler nicht den Lauf abbrechen lassen
            ret, err = None, repr(e)[:300]
        total = time.time() - t0
        utts = [kw for ev, kw in cap.events if ev == "utt"]
        errors = [kw.get("msg", "") for ev, kw in cap.events if ev == "error"]
        if err:
            errors.append(err)
        if utts or not errors or attempt == retries:
            break
        time.sleep(1.0)                                # z. B. Übersetzung kurz weg -> einmal neu
    info = next((l for l in reversed(cap.logs) if "lang" in l or "text" in l or "drop" in l), {})
    utt = utts[-1] if utts else {}
    if not utt and isinstance(ret, (tuple, list)) and len(ret) >= 3:
        utt = {"lang": ret[0], "text": ret[1], "out": ret[2]}
    dropped = [kw.get("reason") for ev, kw in cap.events if ev == "dropped"]

    lang = utt.get("lang") or info.get("lang")
    text = utt.get("text") if utt.get("text") is not None else info.get("text", "")
    out = utt.get("out", "")
    ref_tr = case.get("en_ref") if case["lang"] == "th" else case.get("th_ref")
    r = {
        "id": case["id"], "lang": case["lang"], "tags": case.get("tags", []),
        "ref": case["text"], "hyp": text or "", "hyp_lang": lang,
        "lang_ok": lang == case["lang"],
        "err": round(error_rate(case["text"], text or "", case["lang"]), 4),
        "metric": "cer" if case["lang"] == "th" else "wer",
        "out": out, "tr_ref": ref_tr,
        "overlap": overlap(ref_tr, out, "en" if case["lang"] == "th" else "th"),
        "total_s": round(total, 3),
        "stt_s": round(utt["stt"], 3) if isinstance(utt.get("stt"), (int, float)) else None,
        "tr_s": round(utt["tr"], 3) if isinstance(utt.get("tr"), (int, float)) else None,
        "dropped": dropped[-1] if dropped else None,
        "errors": errors or None,
        "attempts": attempt + 1,
        "p_en": info.get("p_en"), "p_th": info.get("p_th"), "lp": info.get("lp"),
        "alt_text": info.get("alt_text"),
    }
    if case.get("expect_command"):
        cmd = info.get("command")
        parsed = None
        if cmd and hasattr(d, "parse_command"):
            try:
                parsed = d.parse_command(cmd.strip(" .,!?"))
            except Exception:
                parsed = None
        r.update(command=cmd, command_parsed=parsed,
                 command_ok=bool(cmd) and (parsed == case["expect_command"] or case["expect_command"] in cmd.lower()))
    return r


# ---------------------------------------------------------------- Auswertung

def summarize(results):
    out = {}
    for lang in ("th", "en"):
        rs = [r for r in results if r["lang"] == lang]
        if not rs:
            continue
        tot = [r["total_s"] for r in rs]
        stt = [r["stt_s"] for r in rs if r["stt_s"] is not None]
        tr = [r["tr_s"] for r in rs if r["tr_s"] is not None]
        ov = [r["overlap"] for r in rs if r["overlap"] is not None]
        cmd = [r for r in rs if "command_ok" in r]
        out[lang] = {
            "n": len(rs),
            "lang_acc": round(sum(r["lang_ok"] for r in rs) / len(rs), 3),
            "err_mean": round(statistics.mean(r["err"] for r in rs), 4),
            "err_mean_capped": round(statistics.mean(min(r["err"], 1.0) for r in rs), 4),   # Halluzinationen max. 100 %
            "err_median": round(statistics.median(r["err"] for r in rs), 4),
            "exact": sum(r["err"] == 0 for r in rs),
            "dropped": sum(bool(r["dropped"]) for r in rs),
            "total_median_s": round(pct(tot, 0.5), 2),
            "total_p90_s": round(pct(tot, 0.9), 2),
            "stt_mean_s": round(statistics.mean(stt), 2) if stt else None,
            "tr_mean_s": round(statistics.mean(tr), 2) if tr else None,
            "overlap_mean": round(statistics.mean(ov), 3) if ov else None,
        }
        if cmd:
            out[lang]["commands_ok"] = f"{sum(r['command_ok'] for r in cmd)}/{len(cmd)}"
    return out


def fmt(v, nd=3):
    return "–" if v is None else (f"{v:.{nd}f}" if isinstance(v, float) else str(v))


def print_summary(summ, meta):
    print(f"\n=== Ergebnis  model={meta['model']} device={meta['device']} ({meta['date']}) ===")
    head = ["Sprache", "n", "Sprache ok", "CER/WER Ø", "Ø (≤100%)", "Median", "exakt", "verworfen",
            "Zeit Med.", "Zeit p90", "STT Ø", "Übers. Ø", "Überlapp Ø"]
    print(" | ".join(head))
    for lang, s in summ.items():
        print(" | ".join([
            f"{lang} ({'CER' if lang == 'th' else 'WER'})", str(s["n"]), f"{s['lang_acc'] * 100:.0f} %",
            f"{s['err_mean'] * 100:.1f} %", f"{s.get('err_mean_capped', s['err_mean']) * 100:.1f} %",
            f"{s['err_median'] * 100:.1f} %", str(s["exact"]),
            str(s["dropped"]), f"{s['total_median_s']:.2f} s", f"{s['total_p90_s']:.2f} s",
            fmt(s["stt_mean_s"], 2), fmt(s["tr_mean_s"], 2), fmt(s["overlap_mean"])]))
        if "commands_ok" in s:
            print(f"   Befehle erkannt: {s['commands_ok']}")


def print_worst(results, n=10):
    for lang in ("th", "en"):
        rs = sorted((r for r in results if r["lang"] == lang),
                    key=lambda r: (-r["err"], r["lang_ok"], r["overlap"] or 0))[:n]
        if not rs:
            continue
        print(f"\n--- {len(rs)} schlechteste Fälle ({lang}) ---")
        for r in rs:
            flags = []
            if not r["lang_ok"]:
                flags.append(f"Sprache={r['hyp_lang']}")
            if r["dropped"]:
                flags.append(f"verworfen: {r['dropped']}")
            if r["errors"]:
                flags.append("Fehler: " + "; ".join(r["errors"])[:80])
            print(f"{r['id']}  {r['metric'].upper()} {r['err'] * 100:5.1f} %  "
                  f"Überlapp {fmt(r['overlap'])}  {r['total_s']:.1f} s  {' '.join(flags)}")
            print(f"   Referenz:   {r['ref']}")
            print(f"   Erkannt:    {r['hyp']}")
            print(f"   Übersetzt:  {r['out']}")
            print(f"   Soll:       {r['tr_ref'] or '–'}")


def print_compare(cur, old_path):
    old = json.loads(Path(old_path).read_text())
    print(f"\n=== Vergleich mit {old_path} (model={old['meta'].get('model')}, {old['meta'].get('date')}) ===")
    keys = [("lang_acc", "Sprache ok", True), ("err_mean", "CER/WER Ø", False),
            ("err_mean_capped", "Ø (≤100%)", False),
            ("exact", "exakt", True), ("dropped", "verworfen", False),
            ("total_median_s", "Zeit Med.", False), ("total_p90_s", "Zeit p90", False),
            ("stt_mean_s", "STT Ø", False), ("tr_mean_s", "Übers. Ø", False),
            ("overlap_mean", "Überlapp Ø", True)]
    for lang in ("th", "en"):
        a, b = old["summary"].get(lang), cur["summary"].get(lang)
        if not a or not b:
            continue
        print(f"[{lang}]")
        for k, label, higher_better in keys:
            va, vb = a.get(k), b.get(k)
            if not isinstance(va, (int, float)) or not isinstance(vb, (int, float)):
                continue
            dlt = vb - va
            mark = "" if abs(dlt) < 1e-9 else ("besser" if (dlt > 0) == higher_better else "schlechter")
            print(f"   {label:12s} {va:8.3f} -> {vb:8.3f}  ({dlt:+.3f}) {mark}")
    oldr = {r["id"]: r for r in old["results"]}
    ch = [(r["id"], oldr[r["id"]]["err"], r["err"]) for r in cur["results"] if r["id"] in oldr
          and abs(r["err"] - oldr[r["id"]]["err"]) > 1e-9]
    if ch:
        print("Fälle mit geänderter Fehlerrate:")
        for cid, ea, eb in sorted(ch, key=lambda x: x[2] - x[1]):
            print(f"   {cid}  {ea * 100:5.1f} % -> {eb * 100:5.1f} %  ({'besser' if eb < ea else 'schlechter'})")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="medium", choices=["tiny", "base", "small", "medium", "best"])
    ap.add_argument("--device", default="auto", choices=["auto", "cpu", "mps"])
    ap.add_argument("--only", choices=["th", "en"])
    ap.add_argument("--cases", default="", help="nur diese IDs, kommagetrennt")
    ap.add_argument("--audio-dir", default=str(HERE / "audio" / "clean"),
                    help="Ordner mit <id>.wav (z. B. bench/audio/noise)")
    ap.add_argument("--json-out", default=None, help="Standard: bench/results/<datum>_<model>.json")
    ap.add_argument("--compare", default=None, help="ältere Ergebnis-JSON zum Vergleich")
    ap.add_argument("--profiles", action="store_true", help="Stimmprofile des Nutzers aktiv lassen")
    ap.add_argument("--worst", type=int, default=10)
    ap.add_argument("--rescore", default=None,
                    help="vorhandene Ergebnis-JSON nur neu bewerten (ohne Engine), z. B. nach Metrik-Änderung")
    a = ap.parse_args()

    if a.rescore:
        doc = json.loads(Path(a.rescore).read_text())
        for r in doc["results"]:
            r["err"] = round(error_rate(r["ref"], r["hyp"], r["lang"]), 4)
            r["overlap"] = overlap(r.get("tr_ref"), r.get("out"), "en" if r["lang"] == "th" else "th")
        doc["summary"] = summarize(doc["results"])
        doc["meta"]["rescored"] = datetime.datetime.now().isoformat(timespec="seconds")
        out = Path(a.json_out or a.rescore)
        out.write_text(json.dumps(doc, ensure_ascii=False, indent=1))
        print_summary(doc["summary"], doc["meta"])
        print_worst(doc["results"], a.worst)
        if a.compare:
            print_compare(doc, a.compare)
        print(f"\nGespeichert: {out}")
        return

    cases = json.loads((HERE / "cases.json").read_text())
    if a.only:
        cases = [c for c in cases if c["lang"] == a.only]
    if a.cases:
        want = a.cases.split(",")
        cases = [c for c in cases if c["id"] in want]
    todo = []
    for c in cases:
        p, src = find_audio(c["id"], a.audio_dir)
        if p is None:
            print(f"! {c['id']}: keine Audiodatei (erst bench/make_audio.py ausführen)")
            continue
        todo.append((c, p, src))
    if not todo:
        sys.exit("Keine Fälle mit Audio gefunden.")

    cap = Capture()
    d = load_engine_module(cap)
    t = time.time()
    eng = d.Engine(a.model, "krub", "auto", "say", a.device)
    load_s = time.time() - t
    reset_state(eng, a.profiles)
    try:                                               # Aufwärmen (nicht gemessen)
        call_process(eng, np.zeros(SR, dtype=np.float32))
    except Exception:
        pass
    device = getattr(eng, "device", a.device)
    print(f"Engine geladen: model={a.model} device={device} in {load_s:.1f} s, {len(todo)} Fälle")

    results = []
    for i, (c, p, src) in enumerate(todo, 1):
        r = run_case(d, eng, cap, c, load_audio(p), a.profiles)
        r["audio"] = str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)
        r["audio_src"] = src
        results.append(r)
        print(f"[{i:2d}/{len(todo)}] {c['id']} {r['metric']}={r['err'] * 100:5.1f} %  "
              f"lang={r['hyp_lang']}  {r['total_s']:.1f} s  | {r['hyp'][:50]}  ->  {r['out'][:50]}", flush=True)

    now = datetime.datetime.now()
    meta = {"date": now.isoformat(timespec="seconds"), "model": a.model, "device": device,
            "requested_device": a.device, "load_s": round(load_s, 1),
            "audio_dir": os.path.relpath(a.audio_dir, ROOT) if Path(a.audio_dir).resolve().is_relative_to(ROOT) else a.audio_dir,
            "profiles": a.profiles, "only": a.only, "cases": a.cases or None,
            "python": platform.python_version(), "machine": platform.machine()}
    try:
        meta["git"] = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                                     capture_output=True, text=True).stdout.strip()
    except Exception:
        pass
    doc = {"meta": meta, "summary": summarize(results), "results": results}
    out = Path(a.json_out) if a.json_out else HERE / "results" / f"{now:%Y-%m-%d_%H%M}_{a.model}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=1))

    print_summary(doc["summary"], meta)
    print_worst(results, a.worst)
    if a.compare:
        print_compare(doc, a.compare)
    print(f"\nGespeichert: {out}")


if __name__ == "__main__":
    main()
