"""Optionaler, lokaler Gesprächsverlauf (Standard: AUS). Nur Standardbibliothek.

Speichert Äußerungen in einer SQLite-Datei unter
  $DOLMETSCHER_HOME oder ~/Library/Application Support/Dolmetscher/history.sqlite
(Ordner 0700, Datei 0600). Es wird nur aufgezeichnet, wenn der Nutzer es einschaltet
(`--history` bzw. stdin `{"history": true}`). Texte landen nie im Log.
"""
import csv
import hashlib
import hmac
import io
import json
import math
import os
import sqlite3
import threading
import unicodedata
import time
import uuid
from datetime import datetime, timezone

FORMATS = ("md", "json", "csv", "srt", "vtt", "anki", "txt")   # txt: nur die Übersetzungen, eine je Zeile


def home_dir():
    return os.environ.get("DOLMETSCHER_HOME") or os.path.expanduser("~/Library/Application Support/Dolmetscher")


def db_path():
    return os.path.join(home_dir(), "history.sqlite")


SUGGESTED_KEEP_DAYS = 30   # Vorschlag für die Oberfläche; ohne ausdrückliche Wahl wird nichts automatisch gelöscht
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
        try:
            self._setup()
        except BaseException:                          # Schema neuer/Fehler: Verbindung (und WAL) nicht offen lassen
            self.db.close()
            raise

    def _setup(self):
        # Nr. 204: eine Verbindung für mehrere Threads – Schreibvorgänge nur unter Lock und als eine Transaktion
        self.lock = threading.RLock()
        # Runde 8: LIKE kennt Groß/klein nur für ASCII ("É" fand man nicht mit "é"): eigene Faltfunktion
        self.db.create_function("fold", 1, lambda v: (v or "").casefold(), deterministic=True)
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
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_uid ON utt(uid)")           # „replaces“ löscht per uid
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_session_ts ON utt(session, ts)")   # rows(session), sessions()
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_lang ON utt(lang)")        # Runde 22: search(lang=…), stats()
        self.db.create_function("wc", 1, lambda v: len((v or "").split()), deterministic=True)
        self.db.create_function("flatkey", 1, lambda v: _flat(v).casefold(), deterministic=True)
        self.db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
        self.fts = self._init_fts()
        self._migrate()
        self.db.commit()
        self._auto_repair_index()
        self.apply_retention()

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
        self.db.execute("CREATE INDEX IF NOT EXISTS utt_role ON utt(role)")   # Runde 22 (Spalte gibt es ab v2)
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
            if uid:      # Runde 22: dieselbe uid mit gleichem Inhalt (Doppel-Emission) legt keine zweite Zeile an
                dup = self.db.execute(
                    "SELECT id FROM utt WHERE uid = ? AND text IS ? AND translation IS ? AND session = ? LIMIT 1",
                    (uid, text, translation, session)).fetchone()
                if dup:
                    return dup[0]
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
                return True
            except sqlite3.Error:
                return False                                          # Löschung evtl. unvollständig (best effort)

    # ---- Aufbewahrung (persistent) und Wartung
    def get_keep_days(self):
        """Gespeicherte Aufbewahrungsdauer in Tagen oder None (= unbegrenzt)."""
        with self.lock:
            r = self.db.execute("SELECT value FROM meta WHERE key = 'keep_days'").fetchone()
        return valid_days(r[0]) if r else None

    def set_keep_days(self, days):
        """Aufbewahrungsdauer dauerhaft in der Datenbank merken (None löscht die Einstellung) und sofort
        anwenden. Ungültiger Wert: ValueError. -> Anzahl gelöschter Zeilen."""
        if days is None:
            with self.lock, self.db:
                self.db.execute("DELETE FROM meta WHERE key = 'keep_days'")
            return 0
        d = valid_days(days)
        if d is None:
            raise ValueError("Tage müssen eine Zahl größer 0 sein")
        with self.lock, self.db:
            self.db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('keep_days', ?)", (repr(d),))
        return self.apply_retention()

    def apply_retention(self):
        """Gespeicherte Aufbewahrungsfrist durchsetzen (läuft beim Öffnen). -> Anzahl gelöschter Zeilen."""
        try:
            d = self.get_keep_days()
            return self.purge(d) if d else 0
        except sqlite3.Error:
            return 0

    def count(self, session=None):
        with self.lock:
            if session:
                return self.db.execute("SELECT COUNT(*) FROM utt WHERE session = ?", (session,)).fetchone()[0]
            return self.db.execute("SELECT COUNT(*) FROM utt").fetchone()[0]

    def db_size(self):
        """Dateigröße der Datenbank samt WAL in Bytes."""
        total = 0
        for suffix in ("", "-wal", "-shm"):
            try:
                total += os.path.getsize(self.path + suffix)
            except OSError:
                pass
        return total

    def purge_session(self, session):
        """Eine ganze Sitzung löschen -> Anzahl Zeilen."""
        if not isinstance(session, str) or not session:
            raise ValueError("Sitzung fehlt")
        n = self._delete_where("session = ?", (session,))
        if n:
            self._compact()
        return n

    def index_status(self):
        """{"fts", "rows", "indexed", "ok"} – ok, wenn Suchindex und Tabelle gleich viele Zeilen haben."""
        rows = self.count()
        if not self.fts:
            return {"fts": False, "rows": rows, "indexed": 0, "ok": True}
        with self.lock:
            idx = self.db.execute("SELECT COUNT(*) FROM utt_fts").fetchone()[0]
        return {"fts": True, "rows": rows, "indexed": idx, "ok": idx == rows}

    def reindex(self):
        """Suchindex komplett neu aus der Tabelle aufbauen (nach Absturz/Fremdzugriff). -> Anzahl Zeilen."""
        if not self.fts:
            return 0
        with self.lock, self.db:
            self.db.execute("DELETE FROM utt_fts")
            self.db.execute("INSERT INTO utt_fts (rowid, text, translation) "
                            "SELECT id, COALESCE(text, ''), COALESCE(translation, '') FROM utt")
        return self.count()

    def _auto_repair_index(self):
        try:
            if not self.index_status()["ok"]:
                self.reindex()
        except sqlite3.Error:
            pass

    def iter_rows(self, session=None, chunk=500):
        """Wie rows(), aber als Generator in Blöcken (kein ganzer Verlauf im Speicher). Zwischen den Blöcken ist
        die Sperre frei: ein Schreiber wartet nie auf einen langsamen Leser."""
        last_ts, last_id = float("-inf"), -1
        while True:
            q = "SELECT * FROM utt WHERE (ts > ? OR (ts = ? AND id > ?))"
            args = [last_ts, last_ts, last_id]
            if session:
                q, args = q + " AND session = ?", args + [session]
            with self.lock:
                cur = self.db.execute(q + " ORDER BY ts, id LIMIT ?", args + [int(chunk)])
                cols = [c[0] for c in cur.description]
                batch = cur.fetchall()
            for r in batch:
                yield dict(zip(cols, r))
            if len(batch) < chunk:
                return
            last_ts, last_id = batch[-1][cols.index("ts")], batch[-1][cols.index("id")]

    def rows(self, session=None):
        q, args = "SELECT * FROM utt", ()
        if session:
            q, args = q + " WHERE session = ?", (session,)
        with self.lock:
            cur = self.db.execute(q + " ORDER BY ts, id", args)
            cols = [c[0] for c in cur.description]
            return [dict(zip(cols, r)) for r in cur.fetchall()]

    MAX_IMPORT_ROWS = 100000

    def stats(self, top=10, tz_offset_s=0):
        """Auswertung ohne Schreibzugriff: {total, sessions, first, last, per_day: {YYYY-MM-DD: {utterances, words}},
        top_sentences: [{text, count}]}. Wörter = durch Leerraum getrennte Teile des Originaltextes (Thai ohne
        Leerzeichen zählt je Äußerung grob als ein Wort). tz_offset_s verschiebt die Tagesgrenze (z. B. 7*3600).
        Aggregation in SQL: es werden nie alle Zeilen in den Speicher geladen."""
        off = float(tz_offset_s or 0)
        n_top = max(0, int(top))
        with self.lock:
            total, sessions, first, last = self.db.execute(
                "SELECT COUNT(*), COUNT(DISTINCT session), MIN(ts), MAX(ts) FROM utt").fetchone()
            days = self.db.execute(
                "SELECT strftime('%Y-%m-%d', ts + ?, 'unixepoch') AS d, COUNT(*), SUM(wc(text)) FROM utt "
                "GROUP BY d ORDER BY d", (off,)).fetchall()
            best = []
            if n_top:
                best = self.db.execute(
                    "SELECT k, COUNT(*) AS n, MIN(ts) FROM (SELECT flatkey(text) AS k, ts FROM utt) "
                    "WHERE k != '' GROUP BY k HAVING n > 1 ORDER BY n DESC, k LIMIT ?", (n_top,)).fetchall()
            shown = {}
            for k, _n, ts0 in best:       # Anzeigetext = erste Schreibweise, nur für die Top-Treffer geholt
                r = self.db.execute("SELECT text FROM utt WHERE ts = ? AND flatkey(text) = ? ORDER BY id LIMIT 1",
                                    (ts0, k)).fetchone()
                shown[k] = _flat(r[0]) if r else k
        per_day = {d: {"utterances": n, "words": w or 0} for d, n, w in days}
        top_s = sorted(({"text": shown[k], "count": n} for k, n, _ in best), key=lambda x: (-x["count"], x["text"]))
        return {"total": total, "sessions": sessions, "first": first, "last": last, "per_day": per_day,
                "top_sentences": top_s}

    def import_json(self, text):
        """Verlauf aus einem JSON-Export (`export(rows, "json")`) einspielen, z. B. beim Gerätewechsel.
        Zeilen, die schon vorhanden sind (gleiche Zeit, Sitzung und Text), werden übersprungen.
        -> (neu, übersprungen, ungültig). Ungültige Datei -> ValueError."""
        try:
            data = json.loads(text)
        except (TypeError, ValueError) as e:
            raise ValueError("kein gültiges JSON") from e
        if not isinstance(data, list) or len(data) > self.MAX_IMPORT_ROWS:
            raise ValueError("erwartet eine Liste von Einträgen")
        added = skipped = bad = 0
        with self.lock, self.db:
            for r in data:
                try:
                    ts = datetime.strptime(r["time"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc).timestamp()
                    body, sess = r["text"], r.get("session") or ""
                    if not isinstance(body, str) or not body or not isinstance(sess, str):
                        raise ValueError
                except (KeyError, TypeError, ValueError):
                    bad += 1
                    continue
                if self.db.execute("SELECT 1 FROM utt WHERE ts BETWEEN ? AND ? AND session = ? AND text = ? LIMIT 1",
                                   (ts - 0.002, ts + 0.002, sess, body)).fetchone():   # nutzt utt_session_ts-Index
                    skipped += 1
                    continue
                tr = r.get("translation") if isinstance(r.get("translation"), str) else None
                lang = r.get("lang") if isinstance(r.get("lang"), str) else None
                cur = self.db.execute(
                    "INSERT INTO utt (ts, session, lang, text, translation, translit, conf, provider, role, speaker)"
                    " VALUES (?,?,?,?,?,?,?,?,?,?)",
                    (ts, sess, lang, body, tr, r.get("translit") if isinstance(r.get("translit"), str) else None,
                     r.get("confidence") if isinstance(r.get("confidence"), (int, float)) else None,
                     r.get("provider") if isinstance(r.get("provider"), str) else None,
                     r.get("role") if r.get("role") in ("me", "other") else None,
                     r.get("speaker") if isinstance(r.get("speaker"), str) else None))
                if self.fts:
                    self.db.execute("INSERT INTO utt_fts (rowid, text, translation) VALUES (?,?,?)",
                                    (cur.lastrowid, body, tr or ""))
                added += 1
        return added, skipped, bad

    def export_encrypted(self, passphrase, session=None):
        """JSON-Export (wie export(rows, "json")) mit Passwort verschlüsselt -> Bytes."""
        return encrypt_bytes(export(self.rows(session), "json").encode("utf-8"), passphrase)

    def import_encrypted(self, blob, passphrase):
        """Verschlüsselten Export einspielen -> (neu, übersprungen, ungültig). Falsches Passwort: ValueError."""
        return self.import_json(decrypt_bytes(blob, passphrase).decode("utf-8", "replace"))

    def last_translation(self):
        """Letzte Zeile mit Übersetzung ({lang, translation}) oder None."""
        with self.lock:
            r = self.db.execute("SELECT lang, translation FROM utt WHERE translation IS NOT NULL AND translation != '' "
                                "ORDER BY ts DESC, id DESC LIMIT 1").fetchone()
        return {"lang": r[0], "translation": r[1]} if r else None

    def sessions(self):
        """[(session, start_ts, count)] – neueste zuerst."""
        with self.lock:
            return self.db.execute("SELECT session, MIN(ts), COUNT(*) FROM utt GROUP BY session "
                                   "ORDER BY MIN(ts) DESC").fetchall()

    def search(self, query, limit=200, context=0, lang=None, session=None, since=None):
        """Treffer (neueste zuerst). context=N: je Treffer `context` = bis zu N Zeilen davor/danach aus derselben
        Sitzung; lang/session/since (Unix-Zeit) filtern."""
        rows = self._search(query, limit, lang=lang, session=session, since=since)
        n = max(0, min(int(context or 0), 10))
        if n:
            for r in rows:
                with self.lock:
                    near = self.db.execute(
                        "SELECT * FROM utt WHERE session = ? AND id BETWEEN ? AND ? AND id != ? ORDER BY id",
                        (r["session"], r["id"] - n, r["id"] + n, r["id"]))
                    cols = [c[0] for c in near.description]
                    found = near.fetchall()
                r["context"] = [{"id": x["id"], "lang": x["lang"], "text": x["text"], "translation": x["translation"]}
                                for x in (dict(zip(cols, y)) for y in found)]
        return rows

    def _search(self, query, limit=200, lang=None, session=None, since=None):
        query = (query or "").strip()
        if not query:
            return []
        if self.fts and len(query) >= 3:
            # Unterabfrage statt Liste von Treffer-IDs: kein "too many SQL variables" bei häufigen Trigrammen
            where = "id IN (SELECT rowid FROM utt_fts WHERE utt_fts MATCH ?)"
            args = ('"' + query.replace('"', '""') + '"',)
        else:
            like = "%" + query.casefold().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            where = "fold(text) LIKE ? ESCAPE '\\' OR fold(translation) LIKE ? ESCAPE '\\'"
            args = (like, like)
        where = f"({where})"                            # Filter in der WHERE-Klausel: LIMIT zählt nur echte Treffer
        if lang:
            where, args = where + " AND lang = ?", (*args, lang)
        if session:
            where, args = where + " AND session = ?", (*args, session)
        if since is not None:
            where, args = where + " AND ts >= ?", (*args, since)
        with self.lock:
            cur = self.db.execute(f"SELECT * FROM utt WHERE {where} ORDER BY ts DESC, id DESC LIMIT ?",
                                  (*args, max(0, int(limit))))
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


# ---------------------------------------------------------------- Verschlüsselter Export (Runde 24)
# Optional und ohne Schlüsselbund: Passwort -> scrypt (sonst PBKDF2) -> Schlüssel für Verschlüsselung und MAC.
# Aufbau: MAGIC | KDF-Kennung | salt(16) | nonce(16) | Chiffretext | HMAC-SHA256 (encrypt-then-MAC).
# Nur Standardbibliothek; der Chiffretext ist ein HMAC-SHA256-Zählerstrom (PRF-CTR).
# Schützt Exportdateien, nicht die laufende Datenbank.
ENC_MAGIC = b"DOLHX1"
_KDF_SCRYPT, _KDF_PBKDF2 = 1, 2
_SCRYPT = {"n": 2 ** 15, "r": 8, "p": 1, "maxmem": 128 * 1024 * 1024}
_PBKDF2_ITER = 600_000


def _derive_key(passphrase, salt, kdf):
    pw = passphrase.encode("utf-8")
    if kdf == _KDF_SCRYPT:
        return hashlib.scrypt(pw, salt=salt, dklen=64, **_SCRYPT)
    if kdf == _KDF_PBKDF2:
        return hashlib.pbkdf2_hmac("sha256", pw, salt, _PBKDF2_ITER, dklen=64)
    raise ValueError("unbekannte Schlüsselableitung")


def _keystream_xor(key, nonce, data):
    out = bytearray(len(data))
    for i in range(0, len(data), 32):
        block = hmac.new(key, nonce + (i // 32).to_bytes(8, "big"), hashlib.sha256).digest()
        chunk = data[i:i + 32]
        out[i:i + len(chunk)] = bytes(a ^ b for a, b in zip(chunk, block))
    return bytes(out)


def encrypt_bytes(data, passphrase):
    """Bytes mit Passwort verschlüsseln -> Bytes. Leeres/kein Passwort: ValueError."""
    if not isinstance(passphrase, str) or not passphrase:
        raise ValueError("Passwort fehlt")
    kdf = _KDF_SCRYPT if hasattr(hashlib, "scrypt") else _KDF_PBKDF2
    salt, nonce = os.urandom(16), os.urandom(16)
    try:
        key = _derive_key(passphrase, salt, kdf)
    except (ValueError, MemoryError):                  # OpenSSL ohne scrypt-Speicher: PBKDF2
        kdf = _KDF_PBKDF2
        key = _derive_key(passphrase, salt, kdf)
    head = ENC_MAGIC + bytes([kdf]) + salt + nonce
    body = _keystream_xor(key[:32], nonce, bytes(data))
    return head + body + hmac.new(key[32:], head + body, hashlib.sha256).digest()


def decrypt_bytes(blob, passphrase):
    """Gegenstück zu encrypt_bytes. Falsches Passwort oder veränderte Datei: ValueError (nie Müll als Ergebnis)."""
    blob = bytes(blob)
    hl = len(ENC_MAGIC) + 1 + 32
    if not isinstance(passphrase, str) or not passphrase or len(blob) < hl + 32 or not blob.startswith(ENC_MAGIC):
        raise ValueError("keine verschlüsselte Verlaufsdatei oder Passwort fehlt")
    kdf, salt, nonce = blob[len(ENC_MAGIC)], blob[len(ENC_MAGIC) + 1:len(ENC_MAGIC) + 17], blob[len(ENC_MAGIC) + 17:hl]
    key = _derive_key(passphrase, salt, kdf)
    head, body, tag = blob[:hl], blob[hl:-32], blob[-32:]
    if not hmac.compare_digest(tag, hmac.new(key[32:], head + body, hashlib.sha256).digest()):
        raise ValueError("falsches Passwort oder beschädigte Datei")
    return _keystream_xor(key[:32], nonce, body)


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
    """Einzeilig: Umbruchzeichen (auch U+2028/2029) und Steuerzeichen werden zu Leerzeichen bzw. entfernt."""
    s = "".join(" " if unicodedata.category(c) in ("Zl", "Zp") else c
                for c in (s or "") if c in "\t\n\r" or unicodedata.category(c) != "Cc")
    return " ".join(s.split())


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
        body = _flat(r["text"]).replace("-->", "->")   # eine Leerzeile würde den Cue beenden, „-->“ ihn sprengen
        if r["translation"] and _flat(r["translation"]) != _flat(r["text"]):
            body += "\n" + _flat(r["translation"]).replace("-->", "->")
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
    if fmt == "txt":
        return "".join(_flat(r["translation"]) + "\n" for r in rows if r["translation"])
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
        # GUID (erneuter Import aktualisiert statt zu verdoppeln), Stapel und Tags (Sprache, Sitzung)
        lines = ["#separator:tab", "#html:false", "#guid column:1", "#deck:Dolmetscher", "#tags column:5"]
        for r in rows:
            if r["translation"] and _flat(r["translation"]) != _flat(r["text"]):
                guid = hashlib.sha1(f"{r['session']}|{r['ts']}|{r['text']}".encode("utf-8")).hexdigest()[:16]
                tags = f"lang_{(r['lang'] or 'x').lower()} session_{r['session']}".replace("\t", " ")
                lines.append(f"{guid}\t{_flat(r['text'])}\t{_flat(r['translation'])}\t{_flat(r['translit'])}\t{tags}")
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


STREAM_FORMATS = ("md", "json", "csv", "anki", "txt")   # srt/vtt brauchen den Blick auf die nächste Zeile
_ANKI_HEAD = "#separator:tab\n#html:false\n#guid column:1\n#deck:Dolmetscher\n#tags column:5\n"


def export_stream(store, fmt, write, session=None):
    """Export ohne den ganzen Verlauf zu laden: ruft `write(text)` blockweise auf; Ergebnis byte-gleich zu
    export(rows, fmt). srt/vtt: Fallback auf den normalen Export. -> Anzahl Zeilen."""
    fmt = fmt.lower()
    if fmt not in FORMATS:
        raise ValueError(f"unbekanntes Format: {fmt}")
    if fmt not in STREAM_FORMATS:
        rows = store.rows(session)
        write(export(rows, fmt))
        return len(rows)
    n = 0
    who = []
    if fmt == "csv":
        with store.lock:
            who = [k for k in WHO if store.db.execute(
                f"SELECT 1 FROM utt WHERE {k} IS NOT NULL AND {k} != '' LIMIT 1").fetchone()]
        buf = io.StringIO()
        csv.writer(buf, lineterminator="\n").writerow(
            ["time", "session", "lang", "text", "translation", "translit", "confidence", "provider", *who])
        write(buf.getvalue())
    elif fmt == "json":
        write("[")
    elif fmt == "md":
        write("# Gesprächsverlauf\n\n")
    elif fmt == "anki":
        write(_ANKI_HEAD)
    cur = None
    for r in store.iter_rows(session):
        if fmt == "json":
            one = export([r], "json")                            # "[\n  {...}\n]\n"
            write(("," if n else "") + "\n" + one[2:one.rindex("\n]")])
        elif fmt == "csv":
            buf = io.StringIO()
            csv.writer(buf, lineterminator="\n").writerow([_csv_safe(v) for v in (
                _iso(r["ts"]), r["session"], r["lang"], r["text"], r["translation"] or "",
                r["translit"] or "", "" if r["conf"] is None else r["conf"], r["provider"] or "",
                *(r.get(k) or "" for k in who))])
            write(buf.getvalue())
        elif fmt == "md":
            body = export([r], "md")[len("# Gesprächsverlauf\n\n"):]
            if r["session"] == cur:                              # Sitzungskopf nur beim Wechsel
                body = body.split("\n", 2)[2]
            cur = r["session"]
            write(body)
        elif fmt == "anki":
            write(export([r], "anki")[len(_ANKI_HEAD):])
        else:
            write(export([r], "txt"))
        n += 1
    if fmt == "json":
        write("\n]\n" if n else "]\n")
    return n


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
        self.dropped = 0                            # verworfene Äußerungen (volle Warteschlange)
        self.fails = 0                              # aufeinanderfolgende vorübergehende Fehler (Datenbank gesperrt)
        self.last_t = None                          # letzte Äußerung (neue Sitzung nach Pause/Tageswechsel)
        self.last_purge = -self.PURGE_EVERY_S   # monotonic() kann auf frisch gestarteten Rechnern < 3600 sein

    SESSION_GAP_S = 1800.0                          # Pause ab der eine neue Sitzung beginnt
    PURGE_EVERY_S = 3600.0                          # Aufbewahrungsfrist auch bei tagelang laufender Engine
    MAX_FAILS = 3
    QUEUE_MAX = 1000                                # wartende Äußerungen im Writer-Thread
    FLUSH_TIMEOUT_S = 10.0                          # flush() gibt danach auf (haengende Platte)

    def _roll(self, now):
        """Neue Sitzung nach langer Pause oder Tageswechsel (Untertitel-Export nimmt sonst Tage am Stück);
        stündlich die Aufbewahrungsfrist durchsetzen."""
        if not self.fixed_session and self.last_t is not None and (now - self.last_t > self.SESSION_GAP_S
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
        """-> True, wenn der Verlauf im gewünschten Zustand ist; False, wenn die Datenbank nicht geht.
        keep_days="suggested" setzt SUGGESTED_KEEP_DAYS (Option; der Standard bleibt unbegrenzt, wie dokumentiert)."""
        if keep_days == "suggested":
            keep_days = SUGGESTED_KEEP_DAYS
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
    _q_lock = threading.Lock()
    async_mode = False
    store_speakers = True                           # False: Profilnamen nicht in die Datenbank schreiben
    file_pos = None                                 # --file: Position (s) in der Datei statt Wanduhr (Untertitel)
    file_base = 0.0
    fixed_session = False                           # --subtitles: eine Sitzung für die ganze Datei

    def utt(self, kw):
        if not self.on or not self.store or not kw.get("text"):
            return
        now = time.time() if self.file_pos is None else self.file_base + self.file_pos
        if self.async_mode:
            try:
                self._queue().put_nowait((kw, now))
            except Exception:                       # Warteschlange voll (Platte hängt): verwerfen
                self.dropped += 1
            return
        self._write(kw, now)

    def _queue(self):
        import queue
        q = getattr(self, "_q", None)
        if q is not None:
            return q
        with self._q_lock:                          # Runde 25: emit() ruft utt() aus mehreren Threads, ohne Lock
            q = getattr(self, "_q", None)
            if q is not None:
                return q
            q = queue.Queue(maxsize=self.QUEUE_MAX)

            def work():
                while True:
                    item = q.get()
                    try:
                        if item is not None:
                            self._write(*item)
                    finally:
                        q.task_done()
            threading.Thread(target=work, name="history-writer", daemon=True).start()
            self._q = q                             # erst jetzt sichtbar: nie eine Queue ohne Schreib-Thread
        return q

    def flush(self):
        """Wartende Schreibvorgänge abwarten (Ausschalten, Export, Beenden)."""
        q = getattr(self, "_q", None)
        end = time.monotonic() + self.FLUSH_TIMEOUT_S
        while q is not None and q.unfinished_tasks and time.monotonic() < end:
            time.sleep(0.01)

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
                t_begin=_t_begin(kw, now, self.file_pos is not None),
                role=kw.get("role") if kw.get("role") in ("me", "other") else None,
                speaker=kw.get("speaker") if self.store_speakers and isinstance(kw.get("speaker"), str) else None)
            self.fails = 0
        except sqlite3.OperationalError:
            self.fails += 1                         # gesperrt/Platte kurz weg: Zeile fehlt, Aufzeichnung bleibt an
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


def _t_begin(kw, now=None, file_mode=False):
    """Sprechbeginn aus `utt`: jetzt − ready_s (Satzende bis Übersetzung) − dur (Länge der Äußerung).
    Dateimodus: `now` ist schon das Ende der Äußerung in der Datei, also nur − dur."""
    ready, dur = (0.0 if file_mode else kw.get("ready_s")), kw.get("dur")
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
            if session and not any(s[0] == session for s in st.sessions()):
                print(json.dumps({"error": "unbekannte Sitzung"}))
                return 2
            text = export(st.rows(session), a.history_export)
            if a.out:
                fd = os.open(a.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
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
            ctx = getattr(a, "history_context", 0) or 0
            hits = st.search(a.history_search, context=ctx, lang=getattr(a, "history_lang", None),
                             session=a.history_session)
            print(json.dumps([{"time": _iso(r["ts"]), "session": r["session"], "lang": r["lang"],
                               "text": r["text"], "translation": r["translation"],
                               **({"context": r["context"]} if "context" in r else {})}
                              for r in hits], ensure_ascii=False))
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
