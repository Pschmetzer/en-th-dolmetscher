"""Qualitaet der Spracherkennung (Runde 28: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen ohne Zustand. Segmentfelder von Whisper (`avg_logprob`, `no_speech_prob`, `compression_ratio`,
`start`, `end`) koennen bei anderen Backends/Mocks fehlen, None oder NaN sein: `seg_float` liefert dann einen
Vorgabewert statt eines TypeError mitten in der Verarbeitung einer Aeusserung."""
import math
from typing import Any, Iterable, Optional, Tuple

NO_SPEECH_P, NO_SPEECH_LP = 0.9, -0.7      # wie Whispers eigene Stille-Regel, nur strenger (alle Segmente)
COMPRESSION_MAX = 2.6                      # darueber: Wiederholungsschleife


def seg_float(seg: Any, name: str, default: Optional[float]) -> Optional[float]:
    """Zahlenfeld eines Segments; fehlend, None, nicht numerisch, NaN/inf -> default."""
    v = getattr(seg, name, default)
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        try:
            v = float(v)
        except (TypeError, ValueError):
            return default
    return float(v) if math.isfinite(v) else default


def mean_logprob(segs: Optional[Iterable[Any]]) -> float:
    """Mittlere log-prob, nach Segmentdauer gewichtet: ein kurzes unsicheres Segment zieht einen langen sicheren
    Satz nicht mehr unter die Verwerfungsschwelle. Ohne Zeiten: ungewichtet. Keine Segmente: -9.
    Segmente ohne verwertbaren Wert zaehlen nicht mit (alle ohne Wert: -9)."""
    segs = list(segs or ())
    num = tot = 0.0
    for sg in segs:
        lp = seg_float(sg, "avg_logprob", None)
        if lp is None:
            continue
        w = seg_float(sg, "end", 0.0) - seg_float(sg, "start", 0.0)
        w = w if w > 0.05 else 0.05
        num += lp * w
        tot += w
    return float(num / tot) if tot else -9.0


def segment_flags(segs: Iterable[Any]) -> Tuple[bool, bool]:
    """(Wiederholungsschleife, alle Segmente Stille); fehlende Felder zaehlen als unauffaellig."""
    segs = list(segs)
    loop = any(seg_float(s, "compression_ratio", 0.0) > COMPRESSION_MAX for s in segs)
    silent = bool(segs) and all(seg_float(s, "no_speech_prob", 0.0) > NO_SPEECH_P
                                and seg_float(s, "avg_logprob", 0.0) < NO_SPEECH_LP for s in segs)
    return loop, silent
