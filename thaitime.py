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
    (re.compile(r"(?<!ไม่)(?<!ซื่อ)เที่ยง(?:วัน|ตรง)?(\s*ครึ่ง)?(?!(?!ครับ|ค่ะ|คะ|นะ)[ก-๙])"), "noon"),
    (re.compile(r"(?:บ่าย\s*)?" + _TH_NUM_RX + r"\s*โมง\s*เย็น(\s*ครึ่ง)?" + _TH_MIN_RX), "eve"),
    (re.compile(r"บ่าย\s*(?:" + _TH_NUM_RX + r"\s*)?โมง(\s*ครึ่ง)?" + _TH_MIN_RX), "pm"),
    (re.compile(_TH_NUM_RX + r"\s*โมง\s*เช้า(\s*ครึ่ง)?" + _TH_MIN_RX), "morn"),
    (re.compile(_TH_NUM_RX + r"\s*ทุ่ม(\s*ครึ่ง)?" + _TH_MIN_RX), "tum"),
    (re.compile(r"ตี\s*" + _TH_NUM_RX + r"(\s*ครึ่ง)?" + _TH_MIN_RX), "tee"),
)
_TH_TENS = {None: 1, "ยี่": 2, "สาม": 3, "สี่": 4, "ห้า": 5}
_TH_UNITS = {"เอ็ด": 1, "หนึ่ง": 1, "สอง": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7, "แปด": 8, "เก้า": 9}


# Runde 28: „14 นาฬิกา 30 นาที“ und „10.30 น.“ -> 14:30 / 10:30
_TH_CLOCK_WORD = re.compile(r"(?<![\d:.])(\d{1,2})\s*นาฬิกา(?:\s*(\d{1,2})\s*นาที)?")
_TH_CLOCK_DOT = re.compile(r"(?<![\d:.])(\d{1,2})[.:](\d{2})\s*น\.(?![ก-๙])")


def _clock_word(m):
    h, mi = int(m.group(1)), int(m.group(2) or 0)
    return f" {h:02d}:{mi:02d} " if h < 24 and mi < 60 else m.group(0)


def _clock_dot(m):
    h, mi = int(m.group(1)), int(m.group(2))
    return f" {h:02d}:{mi:02d} " if h < 24 and mi < 60 else m.group(0)


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
    if not text or not re.search(r"โมง|ทุ่ม|ตี|เที่ยง|นาฬิกา|น\.", text):
        return text

    def make(kind):
        def sub(m):
            if kind == "midnight":
                return " 00:00 "
            if kind == "noon":
                return " 12:30 " if m.group(1) else " 12:00 "
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
    new = _TH_CLOCK_WORD.sub(_clock_word, new)
    new = _TH_CLOCK_DOT.sub(_clock_dot, new)
    return text if new == text else re.sub(r" {2,}", " ", new).strip()


# Runde 28: Datum mit Monatsnamen und buddhistischer Zeitrechnung (พ.ศ. = n. Chr. + 543)
_TH_MONTHS = (("มกราคม", "ม.ค."), ("กุมภาพันธ์", "ก.พ."), ("มีนาคม", "มี.ค."), ("เมษายน", "เม.ย."),
              ("พฤษภาคม", "พ.ค."), ("มิถุนายน", "มิ.ย."), ("กรกฎาคม", "ก.ค."), ("สิงหาคม", "ส.ค."),
              ("กันยายน", "ก.ย."), ("ตุลาคม", "ต.ค."), ("พฤศจิกายน", "พ.ย."), ("ธันวาคม", "ธ.ค."))
_EN_MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
              "November", "December")
_MONTH_NUM = {}
for _i, (_full, _abbr) in enumerate(_TH_MONTHS, 1):
    _MONTH_NUM[_full] = _MONTH_NUM[_abbr] = _i
_MONTH_RX = "|".join(re.escape(k) for k in sorted(_MONTH_NUM, key=len, reverse=True))
_DAYS_IN = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
_TH_DATE = re.compile(r"(?<![\d๐-๙])(?:วันที่\s*)?([\d๐-๙]{1,2})\s*(" + _MONTH_RX + r")(?![ก-๙])"
                      r"(?:\s*(?:พ\.ศ\.|ค\.ศ\.)?\s*([\d๐-๙]{4})(?![\d๐-๙]))?")
_TH_ERA_YEAR = re.compile(r"(พ\.ศ\.|ค\.ศ\.)\s*([\d๐-๙]{4})(?![\d๐-๙])")
_DIGITS = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")


def th_year_to_ce(year, era=None):
    """Jahr in christlicher Zeitrechnung. Thai schreibt พ.ศ. (2569 = 2026); ohne Angabe gilt: ab 2400 buddhistisch,
    1900-2399 christlich, alles andere (zweistellig, 0) -> None."""
    y = int(str(year).translate(_DIGITS))
    if era == "พ.ศ." or (era is None and y >= 2400):
        y -= 543
    return y if 1800 <= y <= 2399 else None


def th_dates_for_mt(text):
    """Thai-Datum eindeutig machen: „15 มกราคม 2569“ -> „15 January 2026“, „วันที่ 3 ก.พ. 2570“ -> „3 February 2027“,
    „พ.ศ. 2569“ -> „2026“. Ungültige Tage (31 กุมภาพันธ์), Jahre außerhalb 1800-2399 und alles ohne Monatsnamen
    bleiben unverändert."""
    if not text or not re.search(r"[ก-๙]", text):
        return text

    def date(m):
        d, mon = int(m.group(1).translate(_DIGITS)), _MONTH_NUM[m.group(2)]
        if not 1 <= d <= _DAYS_IN[mon - 1]:
            return m.group(0)
        era = re.search(r"พ\.ศ\.|ค\.ศ\.", m.group(0))
        out = f"{d} {_EN_MONTHS[mon - 1]}"
        if m.group(3):
            y = th_year_to_ce(m.group(3), era.group(0) if era else None)
            if y is None:
                return m.group(0)
            if mon == 2 and d == 29 and not (y % 4 == 0 and (y % 100 or y % 400 == 0)):
                return m.group(0)
            out += f" {y}"
        return out

    def era_year(m):
        y = th_year_to_ce(m.group(2), m.group(1))
        return str(y) if y else m.group(0)
    return _TH_ERA_YEAR.sub(era_year, _TH_DATE.sub(date, text))
