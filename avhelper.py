"""avhelper.py – Audio-Ein/Ausgabe über PyAV (``av``), ersetzt das externe ffmpeg.

Die Engine startet das Skript als Kindprozess (wie früher ffmpeg), damit Stopp, Barge-in und
Wachhunde unverändert einen Prozess beenden können. PyAV bringt eigene LGPL-Bibliotheken von
FFmpeg mit (avfoundation-Eingang, audiotoolbox-Ausgang, Filter) – Homebrew ist nicht nötig.

  capture  (--device IDX|default|NAME | --file PFAD [--loop] [--realtime]) [--af KETTE] [--rate 16000]
           -> s16le mono auf stdout (wie ``ffmpeg … -f s16le -``)
  play     [--volume 1.0] [--device UID|NAME|IDX] [--file PFAD]
           mp3 von stdin (oder eine Audiodatei, z. B. aiff von `say`) sofort über AudioToolbox abspielen;
           --device wählt das Ausgabegerät (CoreAudio-UID, Name oder Index), unbekannt -> Systemstandard
  list     -> eine JSON-Zeile {"mics": [{"index", "name"}], "outputs": [{"index", "name", "uid"}]} auf stdout

Fehler gehen als Klartext nach stderr (die Engine klassifiziert sie wie früher ffmpeg-Meldungen).
"""
import argparse, json, math, os, re, signal, sys, time



def _av():
    try:
        import av, av.logging
    except ImportError:
        sys.exit("PyAV (av) is not installed")      # klare Meldung statt Traceback
    av.logging.set_level(av.logging.ERROR)       # Fehler von libav nach stderr (für Mic._explain)
    return av


def explain_error(exc):
    """Kurze, klare Fehlermeldung (englisch, wie die übrigen Meldungen) statt Python-Repr; die Engine sucht darin nach
    Stichwörtern ("permission", "busy", "not found")."""
    if isinstance(exc, PermissionError):
        return "permission denied (microphone or file access not allowed)"
    if isinstance(exc, FileNotFoundError):
        return "file not found"
    if isinstance(exc, IsADirectoryError):
        return "path is a directory, not an audio file"
    msg = str(exc).strip() or type(exc).__name__
    low = msg.lower()
    if "not permitted" in low or "permission" in low:
        return "permission denied: " + msg
    if "busy" in low:
        return "audio device busy: " + msg
    return msg


def check_file(path):
    """Eingabedatei vorab prüfen -> None oder Fehlertext (nicht gefunden, Ordner, nicht lesbar, leer)."""
    if not path:
        return "no file given"
    if not os.path.exists(path):
        return "file not found"
    if os.path.isdir(path):
        return "path is a directory, not an audio file"
    if not os.access(path, os.R_OK):
        return "permission denied (file not readable)"
    if os.path.getsize(path) == 0:
        return "file is empty"
    return None


_FILTER_NAME = re.compile(r"[A-Za-z0-9_]+(@[\w-]+)?")


def validate_af(chain):
    """Filterkette prüfen -> Liste von Problemen (leer = gültig): jeder Eintrag braucht einen Filternamen."""
    bad = []
    for part in (chain or "").split(","):
        if not part.strip():
            continue
        name = part.partition("=")[0].strip()
        if not _FILTER_NAME.fullmatch(name):
            bad.append(name or part.strip())
    return bad


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


    def flush(self):
        """Reste von Filter und Resampler am Dateiende (sonst fehlen die letzten Millisekunden)."""
        out = []
        try:
            if self.filters and self.graph is not None:
                self.graph.push(None)
                while True:
                    try:
                        f = self.graph.pull()
                    except (self.av.error.BlockingIOError, self.av.error.EOFError):
                        break
                    f.pts = None
                    out += [bytes(o.planes[0])[:o.samples * 2] for o in self.rs.resample(f)]
            out += [bytes(o.planes[0])[:o.samples * 2] for o in self.rs.resample(None)]
        except Exception:                           # noqa: BLE001 – Flush ist best effort
            pass
        return b"".join(out)


def _write(b):
    if b:
        try:
            sys.stdout.buffer.write(b)
            sys.stdout.buffer.flush()
        except (BrokenPipeError, ValueError):   # Runde 22: Pipe/stdout zu: leise beenden, kein Traceback
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())   # Python-Exit-Flush nicht erneut scheitern lassen  # noqa: E501
            except OSError:
                pass
            sys.exit(0)


def _frames(av, container, stream):
    """Dekodierte Frames; Geräte liefern zwischendurch EAGAIN (noch keine Daten) – dann kurz warten."""
    idle = 0.0
    while True:
        try:
            for pkt in container.demux(stream):  # am Ende kommt ein Flush-Paket (leert den Decoder)
                for fr in pkt.decode():
                    idle = 0.0                  # Daten da: wieder kurz schlafen, sobald es stockt
                    yield fr
            return
        except av.error.BlockingIOError:        # beendet den demux-Generator: neu ansetzen
            idle = min(0.02, idle * 1.5) if idle else 0.005    # adaptiv: 5 -> 20 ms, weniger Aufwachen im Leerlauf
            time.sleep(idle)


def capture(a):
    av = _av()
    chain = Chain(av, a.af, a.rate)
    if a.file:
        problem = check_file(a.file)
        if problem:
            sys.exit(f"cannot open file: {problem}")
        while True:
            try:
                c = av.open(a.file)
            except Exception as e:
                sys.exit(f"cannot open file: {explain_error(e)}")
            if not c.streams.audio:
                sys.exit("no audio stream")             # sonst IndexError-Traceback als Fehlermeldung
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
            _write(chain.flush())
            c.close()
            if not a.loop:
                return
            if n == 0:                          # leere Datei: sonst Endlosschleife ohne Schlaf
                sys.exit("no audio data in file")
    dev = a.device or "default"
    try:
        c = av.open(f":{dev}", format="avfoundation")
        st = c.streams.audio[0]
    except Exception as e:
        sys.exit(f"cannot open audio device :{dev}: {explain_error(e)}")
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


_OUT_RX = re.compile(r"^\[(\d+)\]\s+(.*)$")


def parse_outputs(lines):
    """audiotoolbox-Geräteliste ("[1]   MacBook Pro-Lautsprecher, BuiltInSpeakerDevice") -> [{index, name, uid}].
    Die Liste enthält alle CoreAudio-Geräte (auch reine Eingänge); der Index ist der für audio_device_index."""
    out = []
    for line in lines:
        m = _OUT_RX.match(str(line).strip())
        if m:
            name, sep, uid = m.group(2).rpartition(", ")
            if not sep:
                name, uid = m.group(2), ""
            out.append({"index": m.group(1), "name": name.strip(), "uid": uid.strip()})
    return out


def list_outputs(av):
    """CoreAudio-Geräte über audiotoolbox (list_devices). Schreibt nur den Kopf, spielt nichts ab."""
    av.logging.set_level(av.logging.INFO)
    try:
        with av.logging.Capture(local=False) as logs:
            try:
                o = av.open("", "w", format="audiotoolbox", options={"list_devices": "true"})
                o.add_stream("pcm_f32le", rate=24000, layout="mono")
                o.start_encoding()
                o.close()
            except Exception:
                pass
    finally:
        av.logging.set_level(av.logging.ERROR)
    return parse_outputs(m for _lvl, _name, m in logs)


def match_output(outputs, want):
    """UID (genau), dann Name (genau, dann ohne Groß/klein), dann reiner Index -> Index als str, sonst None."""
    w = (want or "").strip()
    if not w or w.lower() == "default":
        return None
    for key in ("uid", "name"):
        for o in outputs:
            if o[key] and o[key] == w:
                return o["index"]
    for o in outputs:
        if o["name"].lower() == w.lower():
            return o["index"]
    if w.isdigit() and any(o["index"] == w for o in outputs):
        return w
    return None


def resolve_output(av, want):
    """Gewünschtes Ausgabegerät -> audio_device_index; unbekannt: Hinweis auf stderr, Systemstandard."""
    if not (want or "").strip() or want.strip().lower() == "default":
        return None
    idx = match_output(list_outputs(av), want)
    if idx is None:
        print(f"output device not found: {want}", file=sys.stderr, flush=True)
    return idx


OUT_STALE_S = 30.0                              # so lange gilt die vorab ermittelte Geräte-Nummer (Hot-Plug)


def _soft_limit(x, vol):
    """Lautstärke anwenden; über 1,0 ein weicher Begrenzer (tanh) statt hartem Abschneiden (Verzerrung)."""
    if vol == 1.0:
        return x
    y = x * vol
    peak = float(abs(y).max()) if y.size else 0.0
    if peak <= 1.0:
        return y
    knee = 0.8                                      # bis dahin unverändert, darüber tanh-Rundung bis 1,0
    import numpy as np
    out = y.copy()
    big = abs(y) > knee
    out[big] = np.sign(y[big]) * (knee + (1 - knee) * np.tanh((abs(y[big]) - knee) / (1 - knee)))
    return out


def _mux_frame(av, np, r, vol, rate, ost, out):
    x = _soft_limit(r.to_ndarray().astype(np.float32), vol)
    o = av.AudioFrame.from_ndarray(x.reshape(1, -1), format="flt", layout="mono")
    o.sample_rate = rate
    for p in ost.encode(o):
        out.mux(p)


def play(a):
    av = _av()                                  # vorab laden: als Bereitschaftsprozess wartet er erst hier
    dev = getattr(a, "device", None)
    idx, t_idx = resolve_output(av, dev), time.monotonic()   # vorab, nicht im Weg zum ersten Ton
    if getattr(a, "file", None):
        problem = check_file(a.file)
        if problem:
            sys.exit(f"cannot open file: {problem}")
        try:
            inp = av.open(a.file)
        except Exception as e:
            sys.exit(f"cannot open file: {explain_error(e)}")
    else:
        head = os.read(0, 65536)
        if not head:                            # sofort geschlossen (verworfen/abgebrochen): still beenden
            return
        if dev and time.monotonic() - t_idx > OUT_STALE_S:   # lange gewartet: AirPods evtl. neu verbunden
            idx = resolve_output(av, dev)
        try:
            inp = av.open(_Stdin(head), format="mp3",
                          options={"probesize": "32", "analyzeduration": "0", "fflags": "nobuffer"})
        except Exception as e:
            sys.exit(f"cannot decode mp3: {e}")
    if not inp.streams.audio:
        sys.exit("no audio stream")
    ist = inp.streams.audio[0]
    out, ost, rs = None, None, None
    vol = max(0.0, min(2.0, a.volume))
    import numpy as np
    for fr in _frames(av, inp, ist):
        if out is None:
            rate = fr.sample_rate or 24000
            opts = {"audio_device_index": idx} if idx is not None else {}
            try:
                out = av.open("", "w", format="audiotoolbox", options=opts)
            except Exception:
                if not opts:
                    raise
                print(f"output device failed: {dev}", file=sys.stderr, flush=True)
                out = av.open("", "w", format="audiotoolbox")   # Gerät weg: lieber Standard als stumm
            ost = out.add_stream("pcm_f32le", rate=rate, layout="mono")
            rs = av.AudioResampler(format="flt", layout="mono", rate=rate)
        fr.pts = None
        for r in rs.resample(fr):
            _mux_frame(av, np, r, vol, rate, ost, out)
    if out is not None:
        for r in rs.resample(None):                 # Rest des Resamplers: sonst fehlen die letzten Millisekunden
            _mux_frame(av, np, r, vol, rate, ost, out)
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
    mics = parse_devices(str(m) for _lvl, _name, m in logs)
    try:
        outputs = list_outputs(av)
    except Exception:
        outputs = []
    print(json.dumps({"mics": mics, "outputs": outputs}), flush=True)


def main(argv=None):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # Leser weg (Stopp): still beenden statt Traceback
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
    p.add_argument("--device", default="")
    p.add_argument("--file")
    sub.add_parser("list")
    a = ap.parse_args(argv)
    if a.cmd == "play" and not math.isfinite(a.volume):      # nan würde sonst zu maximaler Lautstärke
        ap.error("--volume muss eine endliche Zahl sein")
    if a.cmd == "capture" and not 8000 <= a.rate <= 48000:
        ap.error("--rate muss zwischen 8000 und 48000 liegen")
    if a.cmd == "capture" and validate_af(a.af):
        ap.error("--af: ungültiger Filtername: " + ", ".join(validate_af(a.af)))
    try:
        {"capture": capture, "play": play, "list": list_devices}[a.cmd](a)
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    except Exception as e:                      # noqa: BLE001 – ein Traceback hilft der Engine nicht, eine Zeile schon
        sys.exit(f"error: {explain_error(e)}")


if __name__ == "__main__":
    main()
