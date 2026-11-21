"""Thai-Uhrzeiten deterministisch (Runde 27: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen ohne Zustand: Sechs-Stunden-System (ตีสาม, สองทุ่ม, บ่ายสองโมง) und Minuten in 24-Stunden-Ziffern."""
import re

_TH_NUM_W = {"หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9,
             "สิบเอ็ด": 11, "สิบสอง": 12, "สิบ": 10}
_TH_NUM_RX = r"(?<!สิบ)(สิบเอ็ด|สิบสอง|สิบ|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า|\d{1,2})"
# Runde 27: optionale Minuten „… สิบห้านาที“ / „… 15 นาที“ (Gruppe 3) nach der Stunde
_TH_MIN_RX = (r"(?:(?!\s*นาที)\s*((?:(?:ยี่|สาม|สี่|ห้า)?สิบ)?(?:เอ็ด|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)?|\d{1,2})"
              r"\s*นาที)?")
_TH_TIME_RULES = (
    (re.compile(r"เที่ยง\s*คืน"), "midnight"),
    (re.compile(r"(?:บ่าย\s*)?" + _TH_NUM_RX + r"\s*โมง\s*เย็น(\s*ครึ่ง)?" + _TH_MIN_RX), "eve"),
    (re.compile(r"บ่าย\s*(?:" + _TH_NUM_RX + r"\s*)?โมง(\s*ครึ่ง)?" + _TH_MIN_RX), "pm"),
    (re.compile(_TH_NUM_RX + r"\s*โมง\s*เช้า(\s*ครึ่ง)?" + _TH_MIN_RX), "morn"),
    (re.compile(_TH_NUM_RX + r"\s*ทุ่ม(\s*ครึ่ง)?" + _TH_MIN_RX), "tum"),
    (re.compile(r"ตี\s*" + _TH_NUM_RX + r"(\s*ครึ่ง)?" + _TH_MIN_RX), "tee"),
)
_TH_TENS = {None: 1, "ยี่": 2, "สาม": 3, "สี่": 4, "ห้า": 5}
_TH_UNITS = {"เอ็ด": 1, "หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9}


def th_minutes(tok):
    """Minutenangabe als Zahl 0-59: Ziffern oder Thai-Wörter (สิบห้า = 15, ยี่สิบเอ็ด = 21, ห้า = 5); sonst None."""
    if not tok:
        return None
    if tok.isdigit():
        return int(tok) if int(tok) < 60 else None
    mt = re.fullmatch(r"(?:(ยี่|สาม|สี่|ห้า)?สิบ)?(เอ็ด|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)?", tok)
    if not mt or not (mt.group(2) or "สิบ" in tok):
        return None
    tens = _TH_TENS[mt.group(1)] if "สิบ" in tok else 0
    return tens * 10 + _TH_UNITS.get(mt.group(2), 0)


def _th_num(tok):
    if tok is None:
        return 1
    return int(tok) if tok.isdigit() else _TH_NUM_W.get(tok)


def th_times_for_mt(text):
    """Eindeutige Thai-Uhrzeiten in 24-Stunden-Ziffern (HH:MM) umschreiben; alles Mehrdeutige („สองโมง“ allein) und
    alles andere bleibt unverändert."""
    if not text or not re.search(r"โมง|ทุ่ม|ตี|เที่ยงคืน", text):
        return text

    def make(kind):
        def sub(m):
            if kind == "midnight":
                return " 00:00 "
            if kind == "pm":
                n, half = _th_num(m.group(1)), m.group(2)
                ok = n is not None and 1 <= n <= 6
                h = 12 + n if ok else None
            else:
                n, half = _th_num(m.group(1)), m.group(2)
                rng = {"eve": (4, 6), "morn": (6, 11), "tum": (1, 5), "tee": (1, 5)}[kind]
                ok = n is not None and rng[0] <= n <= rng[1]
                h = {"eve": (n or 0) + 12, "morn": n, "tum": (n or 0) + 18, "tee": n}[kind]
            if not ok:
                return m.group(0)
            mi = 30 if half else 0
            if m.lastindex and m.lastindex >= 3 and m.group(3) and not half:
                mi = th_minutes(m.group(3))
                if mi is None:
                    return m.group(0)
            return f" {h % 24:02d}:{mi:02d} "
        return sub
    new = text
    for rx, kind in _TH_TIME_RULES:
        new = rx.sub(make(kind), new)
    return text if new == text else re.sub(r" {2,}", " ", new).strip()
