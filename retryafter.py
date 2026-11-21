"""`Retry-After` (Runde 28): eine Stelle fuer Sekunden, HTTP-Datum und Millisekunden-Variante.
Reine Funktionen; die Engine nutzt sie fuer Google/MyMemory (urllib) und fuer das Claude-SDK (httpx)."""
import email.utils
import math
import time
from typing import Any, Optional


def _header(headers: Any, name: str) -> Any:
    """Kopfzeile ohne Beachtung der Gross-/Kleinschreibung (urllib/httpx tun das selbst, ein dict nicht)."""
    if not headers:
        return None
    try:
        v = headers.get(name)
        if v is not None:
            return v
        low = name.lower()
        for k in headers.keys():
            if str(k).lower() == low:
                return headers[k]
    except (AttributeError, TypeError):
        return None
    return None


def parse_seconds(raw: Any, now: Optional[float] = None) -> Optional[float]:
    """'30', '1.5', 'Wed, 21 Oct 2026 07:28:00 GMT' -> Sekunden (kann <= 0 sein) oder None."""
    if raw is None:
        return None
    try:
        v = float(raw)
    except (TypeError, ValueError):
        try:
            v = email.utils.parsedate_to_datetime(str(raw)).timestamp() - (time.time() if now is None else now)
        except (TypeError, ValueError, IndexError, OverflowError):
            return None
    return v if math.isfinite(v) else None


def retry_after(headers: Any, default: Optional[float] = None, lo: float = 1.0, hi: float = 120.0,
                now: Optional[float] = None) -> Optional[float]:
    """Wartezeit aus den Kopfzeilen, begrenzt auf lo … hi; `retry-after-ms` (Anthropic) hat Vorrang.
    Nichts Verwertbares -> default."""
    ms = parse_seconds(_header(headers, "retry-after-ms"))
    if ms is not None:
        return min(max(ms / 1000.0, lo), hi)
    v = parse_seconds(_header(headers, "retry-after"), now)
    return default if v is None else min(max(v, lo), hi)
