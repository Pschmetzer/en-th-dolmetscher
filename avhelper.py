"""avhelper.py – Audio-Ein/Ausgabe über PyAV (``av``), ersetzt das externe ffmpeg.

Die Engine startet das Skript als Kindprozess (wie früher ffmpeg), damit Stopp, Barge-in und
Wachhunde unverändert einen Prozess beenden können. PyAV bringt eigene LGPL-Bibliotheken von
FFmpeg mit (avfoundation-Eingang, audiotoolbox-Ausgang, Filter) – Homebrew ist nicht nötig.

  capture  (--device IDX|default|NAME | --file PFAD [--loop] [--realtime]) [--af KETTE] [--rate 16000]
           -> s16le mono auf stdout (wie ``ffmpeg … -f s16le -``)
  play     [--volume 1.0]   mp3 von stdin sofort über AudioToolbox abspielen
  list     -> eine JSON-Zeile {"mics": [{"index", "name"}]} auf stdout

Fehler gehen als Klartext nach stderr (die Engine klassifiziert sie wie früher ffmpeg-Meldungen).
"""
import argparse, json, os, re, signal, sys, time

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # Leser weg (Stopp): still beenden statt Traceback


def _av():
    import av, av.logging
    av.logging.set_level(av.logging.ERROR)       # Fehler von libav nach stderr (für Mic._explain)
    return av


def parse_af(chain):
    """"highpass=f=80,volume=6dB" -> [("highpass", "f=80"), ("volume", "6dB")]."""
    out = []
    for part in (chain or "").split(","):
        part = part.strip()
        if part:
            name, _, args = part.partition("=")
            out.append((name.strip(), args.strip()))
    return out


class Chain:
    """Filterkette (libavfilter) + Umwandlung nach s16 mono in der Zielrate."""

    def __init__(self, av, af, rate):
        self.av, self.filters, self.rate = av, parse_af(af), rate
        self.graph, self.key = None, None
        self.rs = av.AudioResampler(format="s16", layout="mono", rate=rate)

    def _build(self, fr):
        av = self.av
        g = av.filter.Graph()
        node = src = g.add_abuffer(format=fr.format.name, sample_rate=fr.sample_rate,
                                   layout=fr.layout.name, time_base=fr.time_base)
        for name, args in self.filters:
            nxt = g.add(name, args) if args else g.add(name)
            node.link_to(nxt)
            node = nxt
        sink = g.add("abuffersink")
        node.link_to(sink)
        g.configure()
        self.graph, self.src = g, src
        self.key = (fr.format.name, fr.sample_rate, fr.layout.name)

    def push(self, fr):
        """-> bytes (s16le mono) für einen Eingangs-Frame."""
        if not self.filters:
            return b"".join(bytes(o.planes[0])[:o.samples * 2] for o in self.rs.resample(fr))
        if self.key != (fr.format.name, fr.sample_rate, fr.layout.name):
            self._build(fr)
        self.graph.push(fr)
        out = []
        while True:
            try:
                f = self.graph.pull()
            except (self.av.error.BlockingIOError, self.av.error.EOFError):
                break
            f.pts = None
            out += [bytes(o.planes[0])[:o.samples * 2] for o in self.rs.resample(f)]
        return b"".join(out)


def _write(b):
    if b:
        sys.stdout.buffer.write(b)
        sys.stdout.buffer.flush()


def _frames(av, container, stream):
    """Dekodierte Frames; Geräte liefern zwischendurch EAGAIN (noch keine Daten) – dann kurz warten."""
    while True:
        try:
            for pkt in container.demux(stream):  # am Ende kommt ein Flush-Paket (leert den Decoder)
                for fr in pkt.decode():
                    yield fr
            return
        except av.error.BlockingIOError:        # beendet den demux-Generator: neu ansetzen
            time.sleep(0.005)


def capture(a):
    av = _av()
    chain = Chain(av, a.af, a.rate)
    if a.file:
        while True:
            try:
                c = av.open(a.file)
            except Exception as e:
                sys.exit(f"cannot open file: {e}")
            st = c.streams.audio[0]
            t0, n = time.monotonic(), 0
            for fr in _frames(av, c, st):
                fr.pts = None
                b = chain.push(fr)
                _write(b)
                n += len(b) // 2
                if a.realtime:                  # wie ffmpeg -re: nicht schneller als Echtzeit
                    ahead = n / a.rate - (time.monotonic() - t0)
                    if ahead > 0:
                        time.sleep(ahead)
            c.close()
            if not a.loop:
                return
    dev = a.device or "default"
    try:
        c = av.open(f":{dev}", format="avfoundation")
        st = c.streams.audio[0]
    except Exception as e:
        sys.exit(f"cannot open audio device :{dev}: {e}")
    for fr in _frames(av, c, st):
        fr.pts = None
        _write(chain.push(fr))
    sys.exit("audio device ended")


class _Stdin:
    """Dateiartiges stdin, das liefert, was da ist (kein Warten auf volle Blöcke wie bei BufferedReader)."""

    def __init__(self, head=b""):
        self.head = head

    def read(self, n):
        if self.head:
            b, self.head = self.head[:n], self.head[n:]
            return b
        return os.read(0, n)


def play(a):
    av = _av()                                  # vorab laden: als Bereitschaftsprozess wartet er erst hier
    head = os.read(0, 65536)
    if not head:                                # sofort geschlossen (verworfen/abgebrochen): still beenden
        return
    try:
        inp = av.open(_Stdin(head), format="mp3",
                      options={"probesize": "32", "analyzeduration": "0", "fflags": "nobuffer"})
    except Exception as e:
        sys.exit(f"cannot decode mp3: {e}")
    ist = inp.streams.audio[0]
    out, ost, rs = None, None, None
    vol = max(0.0, min(2.0, a.volume))
    import numpy as np
    for fr in _frames(av, inp, ist):
        if out is None:
            rate = fr.sample_rate or 24000
            out = av.open("", "w", format="audiotoolbox")
            ost = out.add_stream("pcm_f32le", rate=rate, layout="mono")
            rs = av.AudioResampler(format="flt", layout="mono", rate=rate)
        fr.pts = None
        for r in rs.resample(fr):
            x = r.to_ndarray().astype(np.float32)
            if vol != 1.0:
                x = np.clip(x * vol, -1.0, 1.0)
            o = av.AudioFrame.from_ndarray(x.reshape(1, -1), format="flt", layout="mono")
            o.sample_rate = rate
            for p in ost.encode(o):
                out.mux(p)
    if out is not None:
        for p in ost.encode(None):
            out.mux(p)
        out.close()                             # wartet, bis der Ton zu Ende gespielt ist


_DEV_RX = re.compile(r"\[(\d+)\]\s+(.+)$")


def parse_devices(lines):
    """avfoundation-Gerätezeilen (Log von list_devices) -> Audio-Eingänge [{index, name}]."""
    mics, audio = [], False
    for line in lines:
        low = line.lower()
        if "audio devices" in low:
            audio = True
            continue
        if "video devices" in low:
            audio = False
            continue
        m = _DEV_RX.search(line.strip())
        if audio and m:
            mics.append({"index": m.group(1), "name": m.group(2).strip()})
    return mics


def list_devices(_a):
    av = _av()
    av.logging.set_level(av.logging.INFO)
    with av.logging.Capture(local=False) as logs:
        try:
            av.open("", format="avfoundation", options={"list_devices": "true"})
        except Exception:
            pass                                # list_devices „scheitert“ immer, die Liste steht im Log
    av.logging.set_level(av.logging.ERROR)
    print(json.dumps({"mics": parse_devices(str(m) for _lvl, _name, m in logs)}), flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="avhelper")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture")
    c.add_argument("--device")
    c.add_argument("--file")
    c.add_argument("--loop", action="store_true")
    c.add_argument("--realtime", action="store_true")
    c.add_argument("--af", default="")
    c.add_argument("--rate", type=int, default=16000)
    p = sub.add_parser("play")
    p.add_argument("--volume", type=float, default=1.0)
    sub.add_parser("list")
    a = ap.parse_args(argv)
    try:
        {"capture": capture, "play": play, "list": list_devices}[a.cmd](a)
    except (BrokenPipeError, KeyboardInterrupt):
        pass


if __name__ == "__main__":
    main()
