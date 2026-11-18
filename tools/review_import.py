#!/usr/bin/env python3
"""Liest einen ausgefuellten Pruefbogen (CSV oder Markdown) ein und uebernimmt die Korrekturen in presets/*.json.

Aufruf:  python3 tools/review_import.py BOGEN [--dir ORDNER] [--apply]
Standard ist ein Trockenlauf (--dry-run): Pruefung und Diff, es wird nichts geschrieben. Mit --apply werden die
Pakete und presets-index.json neu geschrieben. Bei jedem Fehler (Exitcode 1) wird gar nichts geschrieben.
Regeln:
- Status je Zeile: ok (th stimmt), korrigiert (Spalte Korrektur Pflicht), unklar (bleibt offen), leer (offen).
- id und en muessen zur Datei passen (Schutz gegen verschobene Positionen); th muss dem aktuellen Stand entsprechen.
- Korrekturen duerfen keine Steuerzeichen oder Formelanfaenge enthalten und muessen die Paketpruefung
  (tools/check_presets.py) bestehen.
- Gleicher englischer Satz = gleiches Thai: eine Korrektur wird in alle Pakete mit demselben englischen Satz
  uebernommen; widerspruechliche Eintraege im Bogen sind ein Fehler.
- `reviewed` je Paket wird nur true, wenn der Bogen ALLE Saetze des Pakets mit ok oder korrigiert bestaetigt;
  ein vorhandenes true wird nie zurueckgenommen.
"""
import argparse
import copy
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_presets  # noqa: E402
import make_presets_index  # noqa: E402
from _presetlib import norm  # noqa: E402
from _reviewlib import (MAX_COMMENT, MAX_TEXT, STATUS_FIXED, STATUS_OK, STATUS_UNCLEAR, STATUSES,  # noqa: E402
                        FORMULA_START, dump_pack, has_control, index_path, load_packs, read_sheet, row_id,
                        split_id, unprotect)
import json  # noqa: E402


def plan(packs, rows):
    """Prueft den Bogen gegen die Pakete. Gibt dict mit errors, changes, new (Paketdaten), reviewed, counts."""
    errors = []
    by_pack = {d.get("id", n[:-5]): (n, d) for n, d in packs}
    seen, decided = {}, []
    counts = {STATUS_OK: 0, STATUS_FIXED: 0, STATUS_UNCLEAR: 0, "offen": 0}
    for r in rows:
        where = "Zeile %d" % r["_line"]
        rid = r["id"].strip()
        loc = split_id(rid)
        if loc is None or loc[0] not in by_pack:
            errors.append("%s: id '%s' unbekannt" % (where, rid))
            continue
        pid, idx = loc
        phrases = by_pack[pid][1].get("phrases", [])
        if not 0 <= idx < len(phrases) or not isinstance(phrases[idx], dict):
            errors.append("%s: id '%s' ausserhalb des Pakets (%d Saetze)" % (where, rid, len(phrases)))
            continue
        if rid in seen:
            errors.append("%s: id '%s' doppelt (auch Zeile %d)" % (where, rid, seen[rid]))
            continue
        seen[rid] = r["_line"]
        cur = phrases[idx]
        en, th = unprotect(r["en"]), unprotect(r["th"])
        if norm(en) != norm(cur.get("en", "")):
            errors.append("%s: %s passt nicht zum englischen Satz (Position verschoben? Bogen neu erzeugen)"
                          % (where, rid))
            continue
        if norm(th) != norm(cur.get("th", "")):
            errors.append("%s: %s th weicht vom aktuellen Stand ab (Bogen veraltet; Aenderungen gehoeren in "
                          "die Spalte Korrektur)" % (where, rid))
            continue
        status = r["Status"].strip().casefold()
        fix = unprotect(r["Korrektur"]).strip()
        comment = r["Kommentar"].strip()
        bad = False
        for label, v, limit in (("Korrektur", fix, MAX_TEXT), ("Kommentar", comment, MAX_COMMENT)):
            if has_control(v):
                errors.append("%s: %s enthaelt Steuerzeichen" % (where, label))
                bad = True
            elif len(v) > limit:
                errors.append("%s: %s zu lang (%d > %d)" % (where, label, len(v), limit))
                bad = True
        if fix.startswith(FORMULA_START[:4]):
            errors.append("%s: Korrektur beginnt mit Formelzeichen" % where)
            bad = True
        if status and status not in STATUSES:
            errors.append("%s: Status '%s' unbekannt (erlaubt: %s)" % (where, r["Status"].strip(), ", ".join(STATUSES)))
            bad = True
        elif status == STATUS_FIXED and not fix:
            errors.append("%s: Status korrigiert ohne Korrektur" % where)
            bad = True
        elif status != STATUS_FIXED and fix:
            errors.append("%s: Korrektur ohne Status korrigiert" % where)
            bad = True
        if bad:
            continue
        counts[status or "offen"] += 1
        if status in (STATUS_OK, STATUS_FIXED):
            final = fix if status == STATUS_FIXED else cur["th"]
            decided.append((pid, idx, rid, status, final))
    # Konsistenz im Bogen: gleicher englischer Satz muss gleiche endgueltige Thai-Fassung haben
    finals = {}
    for pid, idx, rid, _s, final in decided:
        en = norm(by_pack[pid][1]["phrases"][idx]["en"])
        finals.setdefault(en, []).append((rid, final))
    for en in sorted(finals):
        if len({norm(f) for _r, f in finals[en]}) > 1:
            errors.append("Widerspruch im Bogen: gleicher englischer Satz '%s' mit verschiedenem Thai (%s)"
                          % (en, ", ".join(r for r, _f in finals[en])))
    new = {pid: copy.deepcopy(d) for pid, (_n, d) in by_pack.items()}
    changes = []
    if not errors:
        order = {pid: i for i, (pid, _) in enumerate(sorted(by_pack.items(), key=lambda kv: kv[1][0]))}
        fixes = sorted((x for x in decided if x[3] == STATUS_FIXED), key=lambda x: (order[x[0]], x[1]))
        targets = {}
        for pid, idx, rid, _s, final in fixes:
            targets.setdefault(norm(by_pack[pid][1]["phrases"][idx]["en"]), (rid, final))
        done = {(x[0], x[1]) for x in fixes}
        for pid in sorted(new, key=lambda p: order[p]):
            for i, p in enumerate(new[pid].get("phrases", [])):
                if not isinstance(p, dict) or not isinstance(p.get("en"), str):
                    continue
                hit = targets.get(norm(p["en"]))
                if hit and norm(p.get("th", "")) != norm(hit[1]):
                    changes.append({"id": row_id(pid, i), "pack": pid, "en": p["en"], "old": p.get("th", ""),
                                    "new": hit[1], "via": None if (pid, i) in done else hit[0]})
                    p["th"] = hit[1]
        # Paketpruefung: nur neue Fehler zaehlen
        touched = sorted({c["pack"] for c in changes}, key=lambda p: order[p])
        for pid in touched:
            fname = by_pack[pid][0]
            before, after = [], []
            check_presets.check_phrases(fname, by_pack[pid][1], before)
            check_presets.check_phrases(fname, new[pid], after)
            old_msgs = {(w, m) for lv, w, m in before if lv == "E"}
            for lv, w, m in after:
                if lv == "E" and (w, m) not in old_msgs:
                    errors.append("Pruefung %s: %s" % (w, m))
    reviewed = []
    if not errors:
        ok_idx = {}
        for pid, idx, _rid, _s, _f in decided:
            ok_idx.setdefault(pid, set()).add(idx)
        for pid in sorted(ok_idx):
            if ok_idx[pid] == set(range(len(new[pid].get("phrases", [])))) and new[pid].get("phrases"):
                reviewed.append(pid)
    return {"errors": errors, "changes": changes, "new": new, "by_pack": by_pack, "reviewed": reviewed,
            "counts": counts, "rows": len(rows)}


def report(res, applied):
    c = res["counts"]
    lines = ["Bogen: %d Zeilen (ok %d, korrigiert %d, unklar %d, offen %d)"
             % (res["rows"], c[STATUS_OK], c[STATUS_FIXED], c[STATUS_UNCLEAR], c["offen"])]
    for ch in res["changes"]:
        lines.append("~ %s%s" % (ch["id"], "  (mitgezogen aus %s)" % ch["via"] if ch["via"] else ""))
        lines.append("    en: %s" % ch["en"])
        lines.append("    - %s" % ch["old"])
        lines.append("    + %s" % ch["new"])
    lines.append("%d Aenderungen, Pakete mit reviewed:true durch diesen Bogen: %s"
                 % (len(res["changes"]), ", ".join(res["reviewed"]) or "keine"))
    lines.append("geschrieben" if applied else "Trockenlauf: nichts geschrieben (--apply zum Schreiben)")
    return lines


def apply(res, directory):
    """Schreibt geaenderte Pakete und erzeugt presets-index.json neu (reviewed aus Bestand plus neue)."""
    for ch_pack in sorted({c["pack"] for c in res["changes"]}):
        fname = res["by_pack"][ch_pack][0]
        (pathlib.Path(directory) / fname).write_text(dump_pack(res["new"][ch_pack]), encoding="utf-8")
    root = pathlib.Path(directory).resolve().parent
    idx = make_presets_index.build(root)
    for p in idx["packs"]:
        if p["id"] in res["reviewed"]:
            p["reviewed"] = True
    index_path(directory).write_text(json.dumps(idx, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ausgefuellten Pruefbogen pruefen und Korrekturen in presets/*.json "
                                             "uebernehmen (Standard: Trockenlauf).")
    ap.add_argument("sheet", help="ausgefuellter Bogen (.csv oder .md) aus tools/review_export.py")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--dry-run", action="store_true", help="nur pruefen und Diff zeigen (Standard)")
    g.add_argument("--apply", action="store_true", help="Aenderungen schreiben")
    a = ap.parse_args(argv)
    directory = pathlib.Path(a.dir) if a.dir else make_presets_index.ROOT / "presets"
    packs = load_packs(directory)
    try:
        rows = read_sheet(a.sheet)
    except ValueError as e:
        print("Fehler: %s" % e)
        return 1
    res = plan(packs, rows)
    if res["errors"]:
        for e in res["errors"]:
            print("E %s" % e)
        print("%d Fehler, nichts geschrieben" % len(res["errors"]))
        return 1
    if a.apply:
        apply(res, directory)
    print("\n".join(report(res, a.apply)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
