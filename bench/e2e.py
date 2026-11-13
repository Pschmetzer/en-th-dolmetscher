#!/usr/bin/env python3
"""Ende-zu-Ende-Test über den echten Mikrofon-Pfad, ohne Mikrofon und ohne Ton.

Startet dolmetscher.py wie die App (--json --idle …), speist eine Audiodatei in Echtzeit statt des
Mikrofons ein (DOLMETSCHER_MIC_FILE, für Dauerläufe in Schleife) und schickt die Ausgabe durch den
kompletten Wiedergabe-Pfad, nur ohne Ton (DOLMETSCHER_NULL_AUDIO). Steuert listen an/aus nach
Zeitplan, sammelt die Ereignisse und prüft Grundregeln.

    python bench/e2e.py gespraech.wav                 # listen an, Datei einmal abspielen
    python bench/e2e.py gespraech.wav --toggle        # Start/Stopp mehrfach umschalten
    python bench/e2e.py gespraech.wav --soak 600      # 10 Minuten Dauerlauf (Datei in Schleife)

Ausgabe: Zeit vom Äußerungsende bis Übersetzung bzw. erstem Ton (Median/p90), Rückstand,
Speicher/Threads. Rückgabewert 1, wenn eine Regel verletzt ist.
"""
import argparse, json, os, statistics, subprocess, sys, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = os.path.expanduser("~/Library/Application Support/Dolmetscher/venv/bin/python")


def p90(xs):
    xs = sorted(xs)
    return xs[int(0.9 * (len(xs) - 1))] if xs else None


def fmt(x):
    return "–" if x is None else f"{x:.2f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("--model", default="best")
    ap.add_argument("--toggle", action="store_true", help="listen mehrfach an/aus")
    ap.add_argument("--soak", type=float, default=0, help="Sekunden Dauerlauf (Datei in Schleife)")
    ap.add_argument("--args", default="", help="weitere Engine-Argumente")
    a = ap.parse_args()

    audio = os.path.abspath(a.audio)
    env = dict(os.environ, DOLMETSCHER_NULL_AUDIO="1", DOLMETSCHER_MIC_FILE=audio,
               DOLMETSCHER_LOG=os.path.join(os.path.dirname(audio), "e2e_engine.log"))
    if a.soak:
        env["DOLMETSCHER_MIC_LOOP"] = "1"
    cmd = [PY, "-u", os.path.join(ROOT, "dolmetscher.py"), "--json", "--idle", "--model", a.model,
           "--meter", "--no-log-text", *a.args.split()]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, env=env, cwd=ROOT)
    events, err, t0 = [], [], time.time()

    def rd():
        for line in p.stdout:
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    threading.Thread(target=rd, daemon=True).start()
    threading.Thread(target=lambda: err.extend(p.stderr), daemon=True).start()

    def send(d):
        if p.poll() is None:
            p.stdin.write(json.dumps(d) + "\n")
            p.stdin.flush()

    def wait_for(pred, timeout):
        t = time.time()
        while time.time() - t < timeout and p.poll() is None:
            if any(pred(e) for e in events):
                return True
            time.sleep(0.1)
        return False

    ok = wait_for(lambda e: e.get("event") == "ready", 300)
    print(f"ready nach {time.time() - t0:.1f}s: {ok}")
    stats = []

    def sample():
        out = subprocess.run(["ps", "-M", "-p", str(p.pid)], capture_output=True, text=True).stdout
        rss = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip()
        stats.append((rss, max(0, len(out.splitlines()) - 1)))

    n_listen = len(events)                  # nur mic-Ereignisse nach dem Start zählen (--idle meldet anfangs "aus")
    send({"listen": True})
    if a.toggle:
        state = True
        for dt in (12, 3, 15, 2, 10, 4):
            time.sleep(dt)
            state = not state
            send({"listen": state})
            sample()
        if not state:
            send({"listen": True})
        time.sleep(15)
    else:
        end = time.time() + (a.soak or 150)
        while time.time() < end and p.poll() is None:
            time.sleep(10)
            sample()
            if not a.soak and any(e.get("event") == "mic" and e.get("on") is False for e in events[n_listen:]):
                break
        time.sleep(6)
    alive = p.poll() is None
    send({"listen": False})
    time.sleep(1.5)
    p.terminate()
    try:
        p.wait(5)
    except subprocess.TimeoutExpired:
        p.kill()

    utts = [e for e in events if e.get("event") == "utt"]
    lat = [e["latency_s"] for e in events if e.get("event") == "speaking" and isinstance(e.get("latency_s"), (int, float))]
    ready = [e["ready_s"] for e in utts if isinstance(e.get("ready_s"), (int, float))]
    queues = [e.get("stt", 0) for e in events if e.get("event") == "queue"]
    errors = [e for e in events if e.get("event") == "error"]
    done = {}
    for e in events:
        if e.get("event") == "speak_done" and e.get("id") != "cmd":
            done[e["id"]] = done.get(e["id"], 0) + 1
    tb = [ln for ln in err if "Traceback" in ln or ("Error" in ln and "experimental" not in ln)]

    print(f"Prozess lebte bis zum Schluss: {alive}")
    print(f"Übersetzungen: {len(utts)}   verworfen: {sum(1 for e in events if e.get('event') == 'dropped')}"
          f"   Fehler-Ereignisse: {len(errors)}")
    print(f"Übersetzung fertig nach Äußerungsende: Median {fmt(statistics.median(ready) if ready else None)} s"
          f"   p90 {fmt(p90(ready))} s")
    print(f"Erster Ton nach Äußerungsende:        Median {fmt(statistics.median(lat) if lat else None)} s"
          f"   p90 {fmt(p90(lat))} s")
    print(f"größter Rückstand (wartende Äußerungen): {max(queues) if queues else 0}")
    print(f"mic-Ereignisse: {[e.get('on') for e in events if e.get('event') == 'mic']}")
    print(f"RSS kB / Threads: erste {stats[:1]}  letzte {stats[-1:]}")
    for e in utts[:14]:
        print(f"  {e.get('lang')}→{e.get('to')}  fertig {e.get('ready_s')} s  {e.get('text', '')[:38]!r} → {e.get('out', '')[:38]!r}")
    bad = []
    if not alive:
        bad.append("Engine-Prozess ist beendet")
    if any(n != 1 for n in done.values()):
        bad.append(f"speak_done nicht genau einmal: {done}")
    if tb:
        bad.append("Fehler in stderr: " + "".join(tb[-5:]))
    if errors:
        bad.append(f"Fehler-Ereignisse: {errors[:3]}")
    if not utts:
        bad.append("keine Übersetzung")
    for b in bad:
        print("FEHLER:", b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
