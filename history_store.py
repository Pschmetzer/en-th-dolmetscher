"""Optionaler, lokaler Gesprächsverlauf (Standard: AUS). Nur Standardbibliothek.

Speichert Äußerungen in einer SQLite-Datei unter
  $DOLMETSCHER_HOME oder ~/Library/Application Support/Dolmetscher/history.sqlite
(Ordner 0700, Datei 0600). Es wird nur aufgezeichnet, wenn der Nutzer es einschaltet
(`--history` bzw. stdin `{"history": true}`). Texte landen nie im Log.
"""
import csv
import io
import json
import math
import os
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timezone

FORMATS = ("md", "json", "csv", "srt", "vtt", "anki")


def home_dir():
    return os.environ.get("DOLMETSCHER_HOME") or os.path.expanduser("~/Library/Application Support/Dolmetscher")


def db_path():
    return os.path.join(home_dir(), "history.sqlite")


class Store:
    def __init__(self, path=None):
        self.path = path or db_path()
        d = os.path.dirname(self.path)
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
        if not os.path.exists(self.path):
            os.close(os.open(self.path, os.O_CREAT | os.O_WRONLY, 0o600))
        os.chmod(self.path, 0o600)
        self.db = sqlite3.connect(self.path, check_same_thread=False)
        # Nr. 204: eine Verbindung für mehrere Threads – Schreibvorgänge nur unter Lock und als eine Transaktion
        self.lock = threading.RLock()
        # Gelöschte Zeilen mit Nullen überschreiben statt nur freizugeben (gilt pro Verbindung).
        self.db.execute("PRAGMA secure_delete = ON")
        self.db.execute("""CREATE TABLE IF NOT EXISTS utt (
            id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL, session TEXT NOT NULL,
            lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL, provider TEXT)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_ts ON utt(ts)")
        self.fts = self._init_fts()
        self.db.commit()

    def _init_fts(self):
        # trigram: Teilstring-Suche auch für Thai (ohne Leerzeichen); fehlt FTS5/trigram -> LIKE
        try:
            self.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS utt_fts USING fts5("
                            "text, translation, tokenize='trigram')")
        except sqlite3.Error:
            return False
        try:   # FTS5 entfernt Gelöschtes sonst erst beim Zusammenführen aus dem Index (SQLite >= 3.42)
            self.db.execute("INSERT INTO utt_fts(utt_fts, rank) VALUES('secure-delete', 1)")
        except sqlite3.Error:
            pass
        return True

    def close(self):
        self.db.close()

    def add(self, text, translation=None, lang=None, translit=None, conf=None, provider=None,
            session="", ts=None, uid=None, replaces=None):
        # Ersetzen, Einfügen und Suchindex in einer Transaktion: ein Absturz dazwischen verliert oder
        # verdoppelt keine Zeile (with self.db: commit bzw. rollback)
        with self.lock, self.db:
            if replaces:
                self._delete_rows("uid = ?", (replaces,))
            cur = self.db.execute(
                "INSERT INTO utt (uid, ts, session, lang, text, translation, translit, conf, provider) "
                "VALUES (?,?,?,?,?,?,?,?,?)",
                (uid, time.time() if ts is None else ts, session, lang, text, translation, translit, conf, provider))
            if self.fts:
                self.db.execute("INSERT INTO utt_fts (rowid, text, translation) VALUES (?,?,?)",
                                (cur.lastrowid, text or "", translation or ""))
            return cur.lastrowid

    def _delete_rows(self, where, args):
        if self.fts:
            self.db.execute(f"DELETE FROM utt_fts WHERE rowid IN (SELECT id FROM utt WHERE {where})", args)
        return self.db.execute(f"DELETE FROM utt WHERE {where}", args).rowcount

    def _delete_where(self, where, args):
        with self.lock, self.db:
            return self._delete_rows(where, args)

    def purge(self, days):
        """Einträge älter als `days` Tage löschen; Anzahl zurück. `days` muss eine endliche Zahl > 0 sein
        (0, negativ oder inf würden sonst den ganzen Verlauf löschen) – sonst ValueError."""
        days = valid_days(days)
        if days is None:
            raise ValueError("Tage müssen eine Zahl größer 0 sein")
        n = self._delete_where("ts < ?", (time.time() - days * 86400,))
        if n:
            self._compact()
        return n

    def clear(self):
        n = self._delete_where("1 = 1", ())
        self._compact()
        return n

    def _compact(self):
        """Nach dem Löschen: FTS-Index zusammenführen und Datei neu schreiben, damit gelöschte Texte nicht in
        freien Seiten oder alten Index-Segmenten lesbar bleiben."""
        with self.lock:
            try:
                if self.fts:
                    self.db.execute("INSERT INTO utt_fts(utt_fts) VALUES('optimize')")
                    self.db.commit()
                self.db.execute("VACUUM")
            except sqlite3.Error:
                pass

    def rows(self, session=None):
        q, args = "SELECT * FROM utt", ()
        if session:
            q, args = q + " WHERE session = ?", (session,)
        cur = self.db.execute(q + " ORDER BY ts, id", args)
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]

    def sessions(self):
        """[(session, start_ts, count)] – neueste zuerst."""
        return self.db.execute("SELECT session, MIN(ts), COUNT(*) FROM utt GROUP BY session "
                               "ORDER BY MIN(ts) DESC").fetchall()

    def search(self, query, limit=200):
        query = (query or "").strip()
        if not query:
            return []
        if self.fts and len(query) >= 3:
            ids = [r[0] for r in self.db.execute(
                "SELECT rowid FROM utt_fts WHERE utt_fts MATCH ? ORDER BY rowid",
                ('"' + query.replace('"', '""') + '"',))]
            if not ids:
                return []
            marks = ",".join("?" * len(ids))
            where, args = f"id IN ({marks})", ids
        else:
            like = "%" + query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            where, args = "text LIKE ? ESCAPE '\\' OR translation LIKE ? ESCAPE '\\'", (like, like)
        cur = self.db.execute(f"SELECT * FROM utt WHERE {where} ORDER BY ts DESC, id DESC LIMIT ?", (*args, limit))
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def valid_days(days):
    """Aufbewahrungsdauer als float, wenn endlich und > 0; sonst None (auch für Text, bool, nan, inf)."""
    if isinstance(days, bool):
        return None
    try:
        d = float(days)
    except (TypeError, ValueError):
        return None
    return d if math.isfinite(d) and d > 0 else None


# ---------------------------------------------------------------- Export

def _iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _clock(sec, sep):
    ms = int(round(max(0.0, sec) * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}{sep}{ms % 1000:03d}"


def _flat(s):
    return " ".join((s or "").split())


def _cues(rows):
    """[(start, end, text)] relativ zum Sitzungsstart; Ende = Beginn der nächsten Äußerung (max. 7 s)."""
    starts = {}
    for r in rows:
        starts[r["session"]] = min(starts.get(r["session"], r["ts"]), r["ts"])
    out = []
    for i, r in enumerate(rows):
        s = r["ts"] - starts[r["session"]]
        own = min(7.0, max(1.5, 0.06 * len(r["text"] or "")))
        nxt = rows[i + 1] if i + 1 < len(rows) and rows[i + 1]["session"] == r["session"] else None
        e = s + own if nxt is None else min(s + own, max(s + 0.5, nxt["ts"] - starts[r["session"]]))
        body = r["text"] or ""
        if r["translation"] and r["translation"] != r["text"]:
            body += "\n" + r["translation"]
        out.append((s, e, body))
    return out


def export(rows, fmt):
    fmt = fmt.lower()
    if fmt not in FORMATS:
        raise ValueError(f"unbekanntes Format: {fmt}")
    if fmt == "json":
        return json.dumps([{"time": _iso(r["ts"]), "session": r["session"], "lang": r["lang"], "text": r["text"],
                            "translation": r["translation"], "translit": r["translit"],
                            "confidence": r["conf"], "provider": r["provider"]} for r in rows],
                          ensure_ascii=False, indent=2) + "\n"
    if fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        w.writerow(["time", "session", "lang", "text", "translation", "translit", "confidence", "provider"])
        for r in rows:
            w.writerow([_iso(r["ts"]), r["session"], r["lang"], r["text"], r["translation"] or "",
                        r["translit"] or "", "" if r["conf"] is None else r["conf"], r["provider"] or ""])
        return buf.getvalue()
    if fmt == "anki":
        lines = ["#separator:tab", "#html:false"]
        for r in rows:
            if r["translation"] and _flat(r["translation"]) != _flat(r["text"]):
                lines.append(f"{_flat(r['text'])}\t{_flat(r['translation'])}\t{_flat(r['translit'])}")
        return "\n".join(lines) + "\n"
    if fmt in ("srt", "vtt"):
        sep = "," if fmt == "srt" else "."
        parts = ["WEBVTT\n"] if fmt == "vtt" else []
        for n, (s, e, body) in enumerate(_cues(rows), 1):
            head = f"{n}\n" if fmt == "srt" else ""
            parts.append(f"{head}{_clock(s, sep)} --> {_clock(e, sep)}\n{body}\n")
        return "\n".join(parts)
    # Markdown
    lines, cur = ["# Gesprächsverlauf", ""], None
    for r in rows:
        if r["session"] != cur:
            cur = r["session"]
            lines += [f"## Sitzung {cur} ({_iso(r['ts'])})", ""]
        tag = (r["lang"] or "?").upper()
        lines.append(f"- **{_iso(r['ts'])[11:19]}** [{tag}] {_flat(r['text'])}")
        if r["translation"] and _flat(r["translation"]) != _flat(r["text"]):
            tl = f" ({_flat(r['translit'])})" if r["translit"] else ""
            lines.append(f"  → {_flat(r['translation'])}{tl}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- Aufzeichnung (Engine)

class Recorder:
    """Hängt an emit("utt"). Tut nichts, solange nicht eingeschaltet. Fehler werden still geschluckt
    (der Verlauf darf die Übersetzung nie stören) und nie mit Text geloggt."""

    def __init__(self):
        self.on = False
        self.session = uuid.uuid4().hex[:12]
        self.store = None
        self.keep_days = None
        self.on_error = None                        # Nr. 191: Rückmeldung an die Engine (ohne Text)

    def enable(self, on=True, keep_days=None):
        """-> True, wenn der Verlauf im gewünschten Zustand ist; False, wenn die Datenbank nicht geht."""
        self.on = bool(on)
        if keep_days is not None:
            self.keep_days = valid_days(keep_days)   # ungültig (0, negativ …): nicht löschen, Verlauf bleibt an
        if self.on:
            try:
                self.store = self.store or Store()
                if self.keep_days:
                    self.store.purge(self.keep_days)
            except Exception:
                self.on = False
                return False
        return True

    def utt(self, kw):
        if not self.on or not self.store or not kw.get("text"):
            return
        try:
            lp = kw.get("lp") or 0.0
            self.store.add(
                kw["text"], kw.get("out") if kw.get("translated") else None, lang=kw.get("lang"),
                translit=kw.get("text_latin") or kw.get("out_latin"),
                conf=round(math.exp(lp), 3) if lp < 0 else None, provider=kw.get("provider"),
                session=self.session, uid=kw.get("id"), replaces=kw.get("replaces"))
        except Exception:
            self.on = False                         # Platte voll, Datei weg …: nicht bei jedem Satz neu scheitern
            if self.on_error:
                try:
                    self.on_error()
                except Exception:
                    pass


RECORDER = Recorder()


# ---------------------------------------------------------------- CLI

def wants_cli(a):
    return bool(a.history_export or a.history_search is not None or a.history_purge is not None or a.history_clear)


def run_cli(a):
    st = Store()
    try:
        if a.history_export:
            session = a.history_session
            if not session and a.history_export in ("srt", "vtt"):
                s = st.sessions()
                session = s[0][0] if s else None      # Untertitel: eine Sitzung, Zeiten ab deren Start
            text = export(st.rows(session), a.history_export)
            if a.out:
                fd = os.open(a.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                # CSV mit BOM (utf-8-sig): Excel erkennt sonst UTF-8 nicht (Thai/Umlaute als Zeichensalat)
                enc = "utf-8-sig" if a.history_export == "csv" else "utf-8"
                with os.fdopen(fd, "w", encoding=enc, newline="") as f:
                    f.write(text)
                # Nr. 388: Erfolg ausdrücklich melden (die App prüfte nur, ob die Datei existiert)
                print(json.dumps({"exported": True, "bytes": len(text.encode(enc))}), flush=True)
            else:
                print(text, end="")
        elif a.history_search is not None:
            print(json.dumps([{"time": _iso(r["ts"]), "session": r["session"], "lang": r["lang"],
                               "text": r["text"], "translation": r["translation"]}
                              for r in st.search(a.history_search)], ensure_ascii=False))
        elif a.history_purge is not None:
            if valid_days(a.history_purge) is None:
                print(json.dumps({"error": "history_purge braucht eine Zahl größer 0"}))
                return 2
            print(json.dumps({"deleted": st.purge(a.history_purge)}))
        elif a.history_clear:
            print(json.dumps({"deleted": st.clear()}))
    finally:
        st.close()
    return 0
