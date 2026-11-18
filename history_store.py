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


SCHEMA_VERSION = 2
# v2 (Runde 6, Nr. 205/206): t_begin (Sprechbeginn, für Untertitel), role (me/other), speaker (Profilname)
V2_COLUMNS = (("t_begin", "REAL"), ("role", "TEXT"), ("speaker", "TEXT"))


class Store:
    def __init__(self, path=None):
        self.path = path or db_path()
        d = os.path.dirname(self.path)
        fresh = not os.path.isdir(d)
        os.makedirs(d, mode=0o700, exist_ok=True)
        if fresh:                                      # nie die Rechte eines vorhandenen Ordners ändern
            os.chmod(d, 0o700)
        if not os.path.exists(self.path):
            os.close(os.open(self.path, os.O_CREAT | os.O_WRONLY, 0o600))
        os.chmod(self.path, 0o600)
        # busy-Timeout 10 s: ein parallel laufender Export/Löschlauf sperrt die Datenbank nur kurz
        self.db = sqlite3.connect(self.path, check_same_thread=False, timeout=10.0)
        # Nr. 204: eine Verbindung für mehrere Threads – Schreibvorgänge nur unter Lock und als eine Transaktion
        self.lock = threading.RLock()
        # Gelöschte Zeilen mit Nullen überschreiben statt nur freizugeben (gilt pro Verbindung).
        self.db.execute("PRAGMA secure_delete = ON")
        try:                                           # WAL: Leser (Export) blockieren den Schreiber nicht
            self.db.execute("PRAGMA journal_mode = WAL")
            self.db.execute("PRAGMA synchronous = NORMAL")
        except sqlite3.Error:
            pass
        self.db.execute("""CREATE TABLE IF NOT EXISTS utt (
            id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, ts REAL NOT NULL, session TEXT NOT NULL,
            lang TEXT, text TEXT, translation TEXT, translit TEXT, conf REAL, provider TEXT)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_ts ON utt(ts)")
        self.fts = self._init_fts()
        self._migrate()
        self.db.commit()

    def _migrate(self):
        """Nr. 207: Schema-Version (PRAGMA user_version). Neue Spalten kommen hier als Schritt
        `if v < N: ALTER TABLE …` dazu; eine Datenbank aus einer neueren Version wird nicht angefasst."""
        v = self.db.execute("PRAGMA user_version").fetchone()[0]
        if v > SCHEMA_VERSION:
            raise sqlite3.DatabaseError(f"Verlauf hat Schema {v}, diese Version kennt {SCHEMA_VERSION}")
        if v < 2:
            # v0 -> v1: nur die Version (Tabellen oben sind v1); v1 -> v2: neue Spalten (Nr. 205/206)
            have = {r[1] for r in self.db.execute("PRAGMA table_info(utt)")}
            for col, typ in V2_COLUMNS:
                if col not in have:
                    self.db.execute(f"ALTER TABLE utt ADD COLUMN {col} {typ}")
        if v < SCHEMA_VERSION:
            self.db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")

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
        try:
            self.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        except sqlite3.Error:
            pass
        self.db.close()

    def add(self, text, translation=None, lang=None, translit=None, conf=None, provider=None,
            session="", ts=None, uid=None, replaces=None, t_begin=None, role=None, speaker=None):
        # Ersetzen, Einfügen und Suchindex in einer Transaktion: ein Absturz dazwischen verliert oder
        # verdoppelt keine Zeile (with self.db: commit bzw. rollback)
        with self.lock, self.db:
            if replaces:
                self._delete_rows("uid = ?", (replaces,))
            cur = self.db.execute(
                "INSERT INTO utt (uid, ts, session, lang, text, translation, translit, conf, provider, t_begin, role,"
                " speaker) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (uid, time.time() if ts is None else ts, session, lang, text, translation, translit, conf, provider,
                 t_begin, role, speaker))
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
                self.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")    # gelöschter Text nicht in der WAL-Datei lassen
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
            # Unterabfrage statt Liste von Treffer-IDs: kein "too many SQL variables" bei häufigen Trigrammen
            where = "id IN (SELECT rowid FROM utt_fts WHERE utt_fts MATCH ?)"
            args = ('"' + query.replace('"', '""') + '"',)
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


def _csv_safe(v):
    """Excel/Numbers führen Zellen aus, die mit = + - @ (oder Tab/CR) beginnen, als Formel aus: ' voranstellen."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v


def _flat(s):
    return " ".join((s or "").split())


def _start(r):
    """Nr. 205: Sprechbeginn, wenn gespeichert (ab Schema 2), sonst Zeitpunkt der fertigen Übersetzung."""
    tb = r.get("t_begin")
    return tb if isinstance(tb, (int, float)) and math.isfinite(tb) and tb <= r["ts"] else r["ts"]


def _cues(rows):
    """[(start, end, text)] relativ zum Sitzungsstart; Ende = Beginn der nächsten Äußerung (max. 7 s)."""
    starts = {}
    for r in rows:
        starts[r["session"]] = min(starts.get(r["session"], _start(r)), _start(r))
    out = []
    for i, r in enumerate(rows):
        s = _start(r) - starts[r["session"]]
        own = min(7.0, max(1.5, 0.06 * len(r["text"] or "")))
        nxt = rows[i + 1] if i + 1 < len(rows) and rows[i + 1]["session"] == r["session"] else None
        e = s + own if nxt is None else min(s + own, max(s + 0.5, _start(nxt) - starts[r["session"]]))
        body = _flat(r["text"])                    # eine Leerzeile würde den Cue beenden
        if r["translation"] and _flat(r["translation"]) != body:
            body += "\n" + _flat(r["translation"])
        out.append((s, e, body))
    return out


WHO = ("role", "speaker")


def export(rows, fmt):
    fmt = fmt.lower()
    if fmt not in FORMATS:
        raise ValueError(f"unbekanntes Format: {fmt}")
    if fmt == "json":
        return json.dumps([{"time": _iso(r["ts"]), "session": r["session"], "lang": r["lang"], "text": r["text"],
                            "translation": r["translation"], "translit": r["translit"],
                            "confidence": r["conf"], "provider": r["provider"],
                            **{k: r[k] for k in WHO if r.get(k)}} for r in rows],
                          ensure_ascii=False, indent=2) + "\n"
    if fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        who = [k for k in WHO if any(r.get(k) for r in rows)]   # Nr. 206: Spalten nur, wenn bekannt
        w.writerow(["time", "session", "lang", "text", "translation", "translit", "confidence", "provider", *who])
        for r in rows:
            w.writerow([_csv_safe(v) for v in (
                _iso(r["ts"]), r["session"], r["lang"], r["text"], r["translation"] or "",
                r["translit"] or "", "" if r["conf"] is None else r["conf"], r["provider"] or "",
                *(r.get(k) or "" for k in who))])
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
        who = r.get("speaker") or {"me": "ich", "other": "Partner"}.get(r.get("role") or "")
        tag += f" · {_flat(who)}" if who else ""                 # Nr. 206: wer hat was gesagt
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
        self.fails = 0                              # aufeinanderfolgende vorübergehende Fehler (Datenbank gesperrt)
        self.last_t = None                          # letzte Äußerung (neue Sitzung nach Pause/Tageswechsel)
        self.last_purge = 0.0

    SESSION_GAP_S = 1800.0                          # Pause ab der eine neue Sitzung beginnt
    PURGE_EVERY_S = 3600.0                          # Aufbewahrungsfrist auch bei tagelang laufender Engine
    MAX_FAILS = 3

    def _roll(self, now):
        """Neue Sitzung nach langer Pause oder Tageswechsel (Untertitel-Export nimmt sonst Tage am Stück);
        stündlich die Aufbewahrungsfrist durchsetzen."""
        if self.last_t is not None and (now - self.last_t > self.SESSION_GAP_S
                                        or time.localtime(now).tm_yday != time.localtime(self.last_t).tm_yday):
            self.session = uuid.uuid4().hex[:12]
        self.last_t = now
        mono = time.monotonic()
        if self.keep_days and self.store and mono - self.last_purge >= self.PURGE_EVERY_S:
            self.last_purge = mono
            # eigener Thread: VACUUM/Löschen hält sonst den Ausgabe-Lock (emit) und die Aufzeichnung läuft weiter,
            # auch wenn das Aufräumen scheitert
            self._purge_thread = threading.Thread(target=self._purge_bg, args=(self.store, self.keep_days),
                                                  name="history-purge", daemon=True)
            self._purge_thread.start()

    @staticmethod
    def _purge_bg(store, days):
        try:
            store.purge(days)
        except Exception:
            pass

    def enable(self, on=True, keep_days=None):
        """-> True, wenn der Verlauf im gewünschten Zustand ist; False, wenn die Datenbank nicht geht."""
        if not on:
            self.flush()                             # erst fertig schreiben, dann aus
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

    # Engine-Betrieb: Schreiben in eigenem Thread (SQLite-Commit mit fsync hält sonst den Ausgabe-Lock von emit)
    async_mode = False

    def utt(self, kw):
        if not self.on or not self.store or not kw.get("text"):
            return
        now = time.time()
        if self.async_mode:
            self._queue().put((kw, now))
            return
        self._write(kw, now)

    def _queue(self):
        import queue
        q = getattr(self, "_q", None)
        if q is None:
            q = self._q = queue.Queue()

            def work():
                while True:
                    item = q.get()
                    try:
                        if item is not None:
                            self._write(*item)
                    finally:
                        q.task_done()
            threading.Thread(target=work, name="history-writer", daemon=True).start()
        return q

    def flush(self):
        """Wartende Schreibvorgänge abwarten (Ausschalten, Export, Beenden)."""
        q = getattr(self, "_q", None)
        if q is not None:
            q.join()

    def _write(self, kw, now):
        if not self.on or not self.store:
            return
        try:
            self._roll(now)
            lp = kw.get("lp") or 0.0
            self.store.add(
                kw["text"], kw.get("out") if kw.get("translated") else None, lang=kw.get("lang"),
                translit=kw.get("text_latin") or kw.get("out_latin"),
                conf=round(math.exp(lp), 3) if lp < 0 else None, provider=kw.get("provider"),
                session=self.session, uid=kw.get("id"), replaces=kw.get("replaces"), ts=now,
                t_begin=_t_begin(kw, now),
                role=kw.get("role") if kw.get("role") in ("me", "other") else None,
                speaker=kw.get("speaker") if isinstance(kw.get("speaker"), str) else None)
            self.fails = 0
        except sqlite3.OperationalError as e:
            if "locked" in str(e).lower() or "busy" in str(e).lower():
                self.fails += 1                     # Export läuft nebenher: diese Zeile fehlt, Aufzeichnung bleibt an
                if self.fails < self.MAX_FAILS:
                    return
            self._fail()
        except Exception:
            self._fail()

    def _fail(self):
        self.on = False                             # Platte voll, Datei weg …: nicht bei jedem Satz neu scheitern
        if self.on_error:
            try:
                self.on_error()
            except Exception:
                pass


def _t_begin(kw, now=None):
    """Sprechbeginn aus `utt`: jetzt − ready_s (Satzende bis Übersetzung) − dur (Länge der Äußerung)."""
    ready, dur = kw.get("ready_s"), kw.get("dur")
    if not all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and x >= 0
               for x in (ready, dur)):
        return None
    return (time.time() if now is None else now) - ready - dur


RECORDER = Recorder()


# ---------------------------------------------------------------- CLI

def wants_cli(a):
    return bool(a.history_export or a.history_search is not None or a.history_purge is not None or a.history_clear
                or getattr(a, "history_sessions", False))


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
                os.fchmod(fd, 0o600)                  # auch eine schon vorhandene Zieldatei: nur für den Nutzer
                # CSV mit BOM (utf-8-sig): Excel erkennt sonst UTF-8 nicht (Thai/Umlaute als Zeichensalat)
                enc = "utf-8-sig" if a.history_export == "csv" else "utf-8"
                with os.fdopen(fd, "w", encoding=enc, newline="") as f:
                    f.write(text)
                # Nr. 388: Erfolg ausdrücklich melden (die App prüfte nur, ob die Datei existiert)
                print(json.dumps({"exported": True, "bytes": len(text.encode(enc))}), flush=True)
            else:
                print(text, end="")
        elif getattr(a, "history_sessions", False):   # [{id, start, count}] – neueste zuerst
            print(json.dumps([{"id": sid, "start": _iso(ts), "count": n} for sid, ts, n in st.sessions()]))
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
