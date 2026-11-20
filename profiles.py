"""Voice profiles: who is speaking, plus personal vocabulary.

A profile is created once by reading 8 sentences aloud (~1 minute). It stores
  * a voiceprint (speaker embedding, wespeaker ResNet34 via sherpa-onnx, no torch),
  * the person's language (en/th) – used as a tie-breaker when language detection is unsure,
  * personal vocabulary (names, companies, places) – passed to Whisper as hotwords,
  * how well the engine understood the enrollment sentences (word/char error rate).

Profiles are biometric data. They stay on this Mac in
~/Library/Application Support/Dolmetscher/profiles/ (or $DOLMETSCHER_HOME/profiles) and never leave it.
"""
import contextlib, datetime, fcntl, hashlib, json, os, re, shutil, sys, threading, time, unicodedata
import urllib.request
from collections import Counter
import numpy as np

SR = 16000
BASE = os.environ.get("DOLMETSCHER_HOME") or os.path.expanduser("~/Library/Application Support/Dolmetscher")
PROFILE_DIR = os.path.join(BASE, "profiles")
MODEL_PATH = os.path.join(BASE, "models", "wespeaker_en_voxceleb_resnet34.onnx")
MODEL_URL = ("https://github.com/k2-fsa/sherpa-onnx/releases/download/"
             "speaker-recongition-models/wespeaker_en_voxceleb_resnet34.onnx")
MODEL_SHA256 = "5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94"
# Env-Overrides: lokale Datei importieren / zweite Download-Quelle (SHA-256 wird immer geprüft)
ENV_MODEL_FILE = "DOLMETSCHER_SPEAKER_MODEL"
ENV_MODEL_URL = "DOLMETSCHER_SPEAKER_MODEL_URL"
DOWNLOAD_TIMEOUT = 30          # Sekunden je Socket-Operation
DOWNLOAD_CHUNK = 1 << 20
MODEL_MAX_BYTES = 200 << 20    # Abbruch weit über der erwarteten Größe (~26 MB): kein endloser Strom
LOCK_TIMEOUT_S = 10.0          # flock-Wartezeit, danach klare Fehlermeldung statt Einfrieren
BAD_KEEP_DAYS = 7              # Quarantäne-Dateien (*.bad, Stimmabdrücke) verfallen nach so vielen Tagen
BAD_KEEP_MAX = 5               # ... und höchstens so viele je Verzeichnis
TMP_MAX_AGE_S = 3600           # Reste abgebrochener Schreibvorgänge (*.tmp)

SCHEMA_VERSION = 2             # fehlendes Feld in der Datei = Version 1
EMBED_MODEL_ID = "wespeaker_en_voxceleb_resnet34"
MAX_VOCAB = 30
MAX_VOCAB_LEN = 60
MAX_NAME_LEN = 64
MAX_DRIFT_COS = 0.90           # learn(): Abdruck darf sich nie weiter vom Original entfernen
LEARN_MIN_SIM = 0.5            # learn(): Äußerung muss dem aktuellen Abdruck mindestens so ähnlich sein
                               # (Poisoning-Schutz: eine falsch erkannte Fremdstimme zieht ihn nicht weg)
MAX_LEARN_WEIGHT = 0.3         # größtes Gewicht eines Lernschritts
EMBED_MIN_SECONDS = 0.3        # kürzer: kein verlässlicher Abdruck
EMBED_MIN_RMS = 1e-4           # leiser = Stille

MIN_SECONDS = 1.5      # shorter clips give unreliable voiceprints
MIN_SIM = 0.68         # cosine similarity needed to accept a match (enrolled voices ~0.85+, strangers ~0.6)
MIN_MARGIN = 0.05      # best match must beat the runner-up by this much
MIN_SIM_SINGLE = 0.75  # bei nur EINEM Profil gibt es keinen Zweitplatzierten -> strengere Schwelle

# Enroll: eine Mindestlänge für Annahme UND Stimmabdruck (vorher 0,8 s vs 1,5 s)
ENROLL_MIN_SECONDS = MIN_SECONDS
ENROLL_MIN_USABLE = 5          # mindestens so viele brauchbare Sätze
ENROLL_OUTLIER_DROP = 0.15     # Satz-Embedding so weit unter dem Median der Ähnlichkeiten -> verworfen
ENROLL_OUTLIER_FLOOR = 0.40    # ... oder absolut darunter

# Zwei-Personen-Modus ("Englisch = ich, jede andere Stimme = Thai"): nur EIN Profil nötig.
# Gemessen (wespeaker, Fenster 0,6-1,5 s): eigene Stimme 0,58-0,89, fremde Stimme 0,32-0,64.
# Asymmetrisch streng: fälschlich "ich" würde Thai mit englischer Erkennung lesen -> Müll.
ROLE_MIN_SECONDS = 0.6
ROLE_ME_MIN = 0.76          # Untergrenze (ähnliche Test-Stimmen erreichten max. 0,73); pro Profil kalibriert
ROLE_OTHER_MAX = 0.50       # darunter sicher eine andere Stimme
ROLE_OTHER_MAX_LONG = 0.55  # ab 1,5 s sind die Werte stabiler

ENROLL = {
    "en": [
        "Good morning, thank you for meeting with me today.",
        "We should discuss the price and the delivery date.",
        "Can you please send me the invoice by Friday?",
        "The hotel is near the beach, about ten minutes from the airport.",
        "I would like to order two coffees and a bottle of water.",
        "Let's sign the contract next week if everything looks good.",
        "How much does it cost per month, including tax?",
        "Translator, pause. Translator, resume.",
    ],
    "de": [
        "Guten Morgen, vielen Dank für das Treffen heute.",
        "Wir sollten den Preis und den Liefertermin besprechen.",
        "Können Sie mir bitte bis Freitag die Rechnung schicken?",
        "Das Hotel liegt am Strand, etwa zehn Minuten vom Flughafen.",
        "Ich hätte gern zwei Kaffee und eine Flasche Wasser.",
        "Wir unterschreiben den Vertrag nächste Woche, wenn alles passt.",
        "Was kostet das pro Monat, inklusive Steuern?",
        "Übersetzer, Pause. Übersetzer, weiter.",
    ],
    "es": [
        "Buenos días, gracias por reunirse conmigo hoy.",
        "Deberíamos hablar del precio y de la fecha de entrega.",
        "¿Puede enviarme la factura antes del viernes, por favor?",
        "El hotel está cerca de la playa, a diez minutos del aeropuerto.",
        "Quisiera pedir dos cafés y una botella de agua.",
        "Firmaremos el contrato la semana que viene si todo está bien.",
        "¿Cuánto cuesta al mes, con impuestos incluidos?",
        "Traductor, pausa. Traductor, continuar.",
    ],
    "fr": [
        "Bonjour, merci de me recevoir aujourd'hui.",
        "Nous devrions parler du prix et de la date de livraison.",
        "Pouvez-vous m'envoyer la facture avant vendredi, s'il vous plaît ?",
        "L'hôtel est près de la plage, à dix minutes de l'aéroport.",
        "Je voudrais deux cafés et une bouteille d'eau.",
        "Nous signerons le contrat la semaine prochaine si tout va bien.",
        "Combien cela coûte-t-il par mois, taxes comprises ?",
        "Traducteur, pause. Traducteur, reprise.",
    ],
    "th": [
        "สวัสดีครับ ยินดีที่ได้รู้จัก",
        "ราคานี้รวมภาษีแล้วหรือยัง",
        "พรุ่งนี้เราจะไปประชุมที่ออฟฟิศ",
        "ช่วยส่งใบแจ้งหนี้มาให้หน่อยได้ไหม",
        "โรงแรมอยู่ใกล้ชายหาด",
        "ขอกาแฟสองแก้วและน้ำหนึ่งขวด",
        "เราจะเซ็นสัญญาสัปดาห์หน้า",
        "ขอบคุณมากสำหรับความช่วยเหลือ",
    ],
}


# ---------- storage ----------
class ProfileNameError(ValueError):
    """Ungültiger Profilname (leer, zu lang, nur Sonderzeichen, kein String)."""


CORRUPT = []                   # Meldungen über Quarantäne/Lesefehler seit Start
_THREAD_LOCK = threading.RLock()
_depth = [0]
_lockfd = [None]
_CLEANED = [False]


def _nfc(s):
    return unicodedata.normalize("NFC", s) if isinstance(s, str) else s


def _safe(name):
    if not isinstance(name, str):
        raise ProfileNameError("invalid profile name")
    s = re.sub(r"[^\w\- ]", "", _nfc(name), flags=re.U).strip()
    if not s or len(s) > MAX_NAME_LEN:
        raise ProfileNameError("invalid profile name")
    return s


def _ensure_dir():
    os.makedirs(PROFILE_DIR, mode=0o700, exist_ok=True)
    with contextlib.suppress(OSError):
        os.chmod(PROFILE_DIR, 0o700)


def _flock(fd, timeout=None):
    """Exklusive Sperre mit Wartegrenze: ein hängender CLI-Prozess friert den Engine-Thread nicht ein."""
    end = time.monotonic() + (LOCK_TIMEOUT_S if timeout is None else timeout)
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            if time.monotonic() >= end:
                raise TimeoutError("profile store is locked by another process") from None
            time.sleep(0.05)


def cleanup_stale(now=None):
    """Aufräumen: Quarantäne (*.bad) nach BAD_KEEP_DAYS Tagen bzw. über BAD_KEEP_MAX Stück, übrig gebliebene *.tmp
    älter als TMP_MAX_AGE_S. -> Anzahl gelöschter Dateien. Stimmabdrücke sollen nicht ewig liegen bleiben."""
    now = time.time() if now is None else now
    try:
        names = os.listdir(PROFILE_DIR)
    except OSError:
        return 0
    n = 0
    bad = []
    for f in names:
        path = os.path.join(PROFILE_DIR, f)
        try:
            mt = os.stat(path).st_mtime
        except OSError:
            continue
        if f.endswith(".tmp") and now - mt > TMP_MAX_AGE_S:
            with contextlib.suppress(OSError):
                os.remove(path)
                n += 1
        elif f.endswith(".bad"):
            bad.append((mt, path))
    bad.sort(reverse=True)                                  # neueste zuerst
    for i, (mt, path) in enumerate(bad):
        if i >= BAD_KEEP_MAX or now - mt > BAD_KEEP_DAYS * 86400:
            with contextlib.suppress(OSError):
                os.remove(path)
                n += 1
    return n


@contextlib.contextmanager
def _locked():
    """Prozessübergreifende Sperre (CLI + Engine) plus Thread-Sperre; wiederbetretbar."""
    with _THREAD_LOCK:
        if _depth[0] == 0:
            _ensure_dir()
            fd = os.open(os.path.join(PROFILE_DIR, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
            try:
                _flock(fd)
            except BaseException:
                os.close(fd)
                raise
            _lockfd[0] = fd
            if not _CLEANED[0]:                       # einmal je Prozess alte .bad/.tmp-Dateien aufräumen
                _CLEANED[0] = True
                with contextlib.suppress(Exception):
                    cleanup_stale()
        _depth[0] += 1
        try:
            yield
        finally:
            _depth[0] -= 1
            if _depth[0] == 0:
                fd, _lockfd[0] = _lockfd[0], None
                try:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                finally:
                    os.close(fd)


def _stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%f")


def _utcnow():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _quarantine(path, why):
    """Kaputte Datei nicht still ignorieren: nach .bad verschieben und melden."""
    dest = "%s.%s.bad" % (path, _stamp())
    try:
        os.replace(path, dest)
    except OSError:
        dest = path
    # ohne Dateinamen: er enthält den Profilnamen (stderr/Log sollen keine Namen tragen)
    msg = "Profil-Datei unlesbar (%s)%s" % (why, " -> .bad" if dest != path else "")
    CORRUPT.append(msg)
    print(json.dumps({"profile_corrupt": msg}, ensure_ascii=False), file=sys.stderr)


def _load_file(path):
    try:
        with open(path, encoding="utf-8") as fh:
            p = json.load(fh)
        if not isinstance(p, dict) or not isinstance(p.get("name"), str) or not p["name"].strip():
            raise ValueError("kein gültiges Profil")
        p["name"] = _nfc(p["name"])
        p.setdefault("schema_version", 1)
        return p
    except FileNotFoundError:
        return None
    except (ValueError, UnicodeDecodeError) as e:
        with _locked():
            if os.path.exists(path):
                _quarantine(path, str(e)[:80])
        return None
    except OSError as e:
        msg = "Profil-Datei %s nicht lesbar: %s" % (os.path.basename(path), e)
        if msg not in CORRUPT:                   # nicht bei jedem Aufruf erneut anhängen (Wachstum, Dauerwarnung)
            CORRUPT.append(msg)
        return None


def _files():
    if not os.path.isdir(PROFILE_DIR):
        return []
    return sorted(f for f in os.listdir(PROFILE_DIR) if f.endswith(".json") and not f.startswith("."))


def _locate(name):
    """Pfad der Datei, die exakt dieses Profil (nach echtem Namen) enthält, sonst None."""
    name = _nfc(name)
    try:
        legacy = os.path.join(PROFILE_DIR, _safe(name) + ".json")
    except ProfileNameError:
        legacy = None
    if legacy and os.path.exists(legacy):
        p = _load_file(legacy)
        if p and p["name"] == name:
            return legacy
    for f in _files():
        path = os.path.join(PROFILE_DIR, f)
        if path != legacy:
            p = _load_file(path)
            if p and p["name"] == name:
                return path
    return None


def _target_path(name):
    """Bestehende Datei des Profils, sonst neuer Pfad; Kollisionen ("Anna!" vs "Anna", Groß/Klein auf
    APFS) bekommen einen Hash-Suffix. Bestehende Dateien behalten ihren Namen."""
    found = _locate(name)
    if found:
        return found
    stem = _safe(name)
    taken = {f.lower() for f in os.listdir(PROFILE_DIR)}
    if stem.lower() + ".json" in taken:
        stem += "-" + hashlib.sha1(_nfc(name).encode("utf-8")).hexdigest()[:8]
    return os.path.join(PROFILE_DIR, stem + ".json")


def list_profiles():
    out = []
    for f in _files():
        p = _load_file(os.path.join(PROFILE_DIR, f))
        if p:
            out.append(p)
    return out


def get_profile(name):
    path = _locate(name)
    return _load_file(path) if path else None


def _write_atomic(path, p):
    tmp = "%s.%d.%d.tmp" % (path, os.getpid(), threading.get_ident())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)    # nie kurz für andere lesbar
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(p, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.remove(tmp)
        raise
    with contextlib.suppress(OSError):
        dfd = os.open(os.path.dirname(path), os.O_RDONLY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)


def save_profile(p):
    p = dict(p)
    p["name"] = _nfc(p["name"])
    _safe(p["name"])
    p.setdefault("schema_version", SCHEMA_VERSION)
    with _locked():
        _write_atomic(_target_path(p["name"]), p)


MAX_BACKUPS = 2               # so viele .bak je Profil behalten (enthalten Stimmabdrücke)
_SIDE_SUFFIXES = (".bak", ".bad", ".tmp")   # .tmp: Rest eines abgebrochenen Schreibvorgangs
_ALL_SUFFIXES = (".json", ".bak", ".bad", ".tmp")


def _side_files(path):
    """Sicherungen/Quarantäne-Dateien genau dieses Profils (<datei>.json.<...>.bak|.bad), älteste zuerst.
    Präfix-Vergleich statt glob: "Anna.json" trifft nie "Anna-<hash>.json.*"."""
    base = os.path.basename(path) + "."
    d = os.path.dirname(path)
    try:
        names = os.listdir(d)
    except OSError:
        return []
    return [os.path.join(d, f) for f in sorted(names) if f.startswith(base) and f.endswith(_SIDE_SUFFIXES)]


def delete_profile(name):
    """Profil löschen – samt Sicherungen (.bak) und Quarantäne-Kopien (.bad): Stimmabdrücke sind
    biometrische Daten und dürfen nach "Löschen" nicht als Kopie liegen bleiben."""
    with _locked():
        path = _locate(name)
        if not path:
            return False
        for f in _side_files(path):
            with contextlib.suppress(FileNotFoundError):
                os.remove(f)
        try:
            os.remove(path)
            return True
        except FileNotFoundError:
            return False


def delete_all_profiles():
    """Alle Stimmdaten löschen (Profile, Sicherungen, Quarantäne, Reste). -> Anzahl gelöschter Dateien.
    Die Sperrdatei bleibt (ein anderer Prozess kann sie halten), das Sprechermodell auch (keine
    persönlichen Daten)."""
    if not os.path.isdir(PROFILE_DIR):
        return 0
    n = 0
    with _locked():
        for f in os.listdir(PROFILE_DIR):
            if f.startswith(".") or not f.endswith(_ALL_SUFFIXES):
                continue
            with contextlib.suppress(FileNotFoundError):
                os.remove(os.path.join(PROFILE_DIR, f))
                n += 1
    return n


def rename_profile(old, new):
    """Profil umbenennen (Stimmabdruck bleibt). Unbekannt: KeyError, Ziel existiert: FileExistsError,
    ungültiger Name: ProfileNameError. Die alte Datei samt Sicherungen wird gelöscht."""
    new = _nfc(new)
    _safe(new)
    with _locked():
        p = get_profile(old)
        if p is None:
            raise KeyError(old)
        if _nfc(old) == new:
            return p
        if get_profile(new) is not None:
            raise FileExistsError(new)
        p = dict(p)
        p["name"] = new
        save_profile(p)
        delete_profile(old)
    return p


def _backup(name):
    """Altes Profil vor dem Überschreiben sichern (<datei>.json.<zeit>.bak, wird nicht als Profil geladen).
    Nur die letzten MAX_BACKUPS bleiben."""
    path = _locate(name)
    if not path:
        return None
    dest = "%s.%s.bak" % (path, _stamp())
    shutil.copy2(path, dest)
    os.chmod(dest, 0o600)
    baks = [f for f in _side_files(path) if f.endswith(".bak")]
    for f in baks[:-MAX_BACKUPS]:
        with contextlib.suppress(OSError):
            os.remove(f)
    return dest


def clean_vocab(words):
    """Wörter (Liste oder String; Trenner , ; Zeilenumbruch) -> NFC, getrimmt, ohne Duplikate, max. MAX_VOCAB."""
    if isinstance(words, str):
        words = [words]
    out, seen = [], set()
    for chunk in words or []:
        if not isinstance(chunk, str):
            continue                                     # None/Zahlen sind keine Wörter (nicht "None" aufnehmen)
        for w in re.split(r"[,;\n\r]", _nfc(chunk)):
            w = re.sub(r"\s+", " ", w).strip()[:MAX_VOCAB_LEN]
            if w and w.casefold() not in seen:
                seen.add(w.casefold())
                out.append(w)
    return out[:MAX_VOCAB]


def set_vocab(name, words):
    with _locked():                                  # frisch lesen + schreiben: keine fremden Änderungen überschreiben
        p = get_profile(name)
        if not p:
            raise KeyError(name)
        p["vocab"] = clean_vocab(words)
        save_profile(p)
    return p


def set_polite(name, polite):
    """Höflichkeitsform der Person für Thai-Ausgaben (krub/ka); "", "-" oder None entfernt sie (dann gilt
    die Einstellung der App). Unbekannter Wert: ValueError, unbekanntes Profil: KeyError."""
    if polite in ("", "-", None):
        polite = None
    elif polite not in ("krub", "ka"):
        raise ValueError(polite)
    with _locked():
        p = get_profile(name)
        if not p:
            raise KeyError(name)
        if polite:
            p["polite"] = polite
        else:
            p.pop("polite", None)
        save_profile(p)
    return p


PUBLIC_KEYS = ("name", "lang", "created", "self_similarity", "role_me_min", "vocab", "error_rate", "polite",
               "enroll_results", "adapted", "schema_version", "embedding_model")


def public(p):
    """Nur freigegebene Felder (Allowlist): nie Stimmabdruck oder künftige interne Felder."""
    return {k: p[k] for k in PUBLIC_KEYS if k in p}


def reset_learning(name):
    """Nachgeführten Stimmabdruck verwerfen und auf den ursprünglichen zurücksetzen."""
    with _locked():
        p = get_profile(name)
        if not p or not p.get("embedding_orig"):
            return False
        p["embedding"] = p.pop("embedding_orig")
        p["adapted"] = 0
        save_profile(p)
        return True


# ---------- model ----------
def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(DOWNLOAD_CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def _download(url, tmp):
    """Streamt in Chunks auf die Platte und hasht dabei (kein ganzes Modell im RAM)."""
    if not url.lower().startswith(("https://", "file://")):
        raise ValueError("only https:// (or file://) model sources are allowed")     # kein Klartext-http
    h = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": "dolmetscher"})
    total = 0
    with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as r, open(tmp, "wb") as out:
        while True:
            chunk = r.read(DOWNLOAD_CHUNK)
            if not chunk:
                break
            total += len(chunk)
            if total > MODEL_MAX_BYTES:
                raise RuntimeError("download larger than expected")
            h.update(chunk)
            out.write(chunk)
        out.flush()
        os.fsync(out.fileno())
    return h.hexdigest()


OFFLINE_ONLY = False      # Privatmodus (--private): nur eine lokale Datei, nie ein Download


def _model_ok():
    """Vorhandenes Modell prüfen: SHA-256 gilt nicht nur beim Download. Ein Stempel (Größe + mtime) neben der Datei
    macht die Prüfung nach dem ersten Mal billig; weicht er ab, wird neu gehasht (abgeschnitten/ersetzt -> False)."""
    try:
        st = os.stat(MODEL_PATH)
    except OSError:
        return False
    key = "%d:%d:%s" % (st.st_size, st.st_mtime_ns, MODEL_SHA256)
    stamp = MODEL_PATH + ".ok"
    try:
        with open(stamp, encoding="utf-8") as f:
            if f.read().strip() == key:
                return True
    except OSError:
        pass
    if _sha256_file(MODEL_PATH) != MODEL_SHA256:
        return False
    with contextlib.suppress(OSError):
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(key)
    return True


def ensure_model():
    if os.path.exists(MODEL_PATH):
        if _model_ok():
            return MODEL_PATH
        with contextlib.suppress(OSError):                  # beschädigt/ersetzt: neu laden statt blind zu vertrauen
            os.remove(MODEL_PATH)
    mdir = os.path.dirname(MODEL_PATH)
    os.makedirs(mdir, exist_ok=True)
    with open(os.path.join(mdir, ".download.lock"), "w") as lk:
        _flock(lk, 600)                                     # nur ein Prozess lädt gleichzeitig (max. 10 min)
        if os.path.exists(MODEL_PATH) and _model_ok():
            return MODEL_PATH
        base = os.path.basename(MODEL_PATH)
        for f in os.listdir(mdir):                          # Reste abgebrochener Läufe
            if f.startswith(base) and f.endswith(".part"):
                with contextlib.suppress(OSError):
                    os.remove(os.path.join(mdir, f))
        tmp = "%s.%d.part" % (MODEL_PATH, os.getpid())
        errors = []
        local = os.environ.get(ENV_MODEL_FILE)
        sources = ([("file", local)] if local else []) + \
                  ([] if OFFLINE_ONLY else [("url", u) for u in (MODEL_URL, os.environ.get(ENV_MODEL_URL)) if u])
        for kind, src in sources:
            try:
                if kind == "file":
                    shutil.copyfile(src, tmp)
                    digest = _sha256_file(tmp)
                else:
                    digest = _download(src, tmp)
                if digest != MODEL_SHA256:
                    raise RuntimeError("checksum mismatch")
                os.replace(tmp, MODEL_PATH)
                _model_ok()                                 # Stempel gleich mitschreiben (kein erneutes Hashen)
                return MODEL_PATH
            except Exception as e:                          # nächste Quelle probieren
                errors.append("%s: %s" % (src, e))
            finally:
                with contextlib.suppress(OSError):
                    os.remove(tmp)
        raise RuntimeError("speaker model unavailable (%s). Offline? Set %s=/path/to/model.onnx or %s=<url>"
                           % ("; ".join(errors), ENV_MODEL_FILE, ENV_MODEL_URL))


_EX_LOCK = threading.Lock()      # sherpa-Extractor ist nicht thread-sicher


def _created_key(p):
    return (str(p.get("created") or "").replace(" ", "T"), p.get("name", ""))


DEFAULT_PAIR = ("en", "th")          # (Sprache von "ich", Sprache der Partnerin)
EXTRA_MIN_EMBS = 6                   # ab so vielen brauchbaren Sätzen lohnt ein zweiter Zentroid
EXTRA_MIN_CLUSTER = 3                # jeder Zentroid braucht so viele Sätze
EXTRA_MAX_SIM = 0.92                 # Zentroide, die sich ähnlicher sind, sind praktisch einer


def pair_from_langs(me_lang, partner_lang):
    """Sprachpaar prüfen -> (me, partner), klein geschrieben. Gleiche oder ungültige Sprachen: ValueError."""
    pair = tuple(str(x or "").strip().lower() for x in (me_lang, partner_lang))
    if not all(re.fullmatch(r"[a-z]{2,3}(-[a-z0-9]{2,8})?", x) for x in pair) or pair[0] == pair[1]:
        raise ValueError("ungültiges Sprachpaar: %r" % (pair,))
    return pair


def kmeans_centroids(embs, k=2, iters=10):
    """Deterministisches k-means auf normierten Stimmabdrücken (Kosinus). -> [(zentroid, größe)], größte Gruppe
    zuerst. Wenige/gleiche Abdrücke liefern weniger als k Zentroide."""
    arr = np.stack([np.asarray(e, dtype=np.float32) for e in embs])
    arr = arr / (np.linalg.norm(arr, axis=1, keepdims=True) + 1e-9)
    cents = [arr[0]]
    while len(cents) < min(k, len(arr)):                 # Start: jeweils der am weitesten entfernte Abdruck
        far = np.min(np.stack([1 - arr @ c for c in cents]), axis=0)
        if float(far.max()) < 1e-6:
            break
        cents.append(arr[int(np.argmax(far))])
    c = np.stack(cents)
    lab = np.zeros(len(arr), dtype=int)
    for _ in range(iters):
        lab = np.argmax(arr @ c.T, axis=1)
        new = []
        for i in range(len(c)):
            m = arr[lab == i]
            v = m.mean(axis=0) if len(m) else c[i]
            new.append(v / (np.linalg.norm(v) + 1e-9))
        new = np.stack(new)
        if np.allclose(new, c, atol=1e-6):
            break
        c = new
    sizes = [int((lab == i).sum()) for i in range(len(c))]
    return sorted(((c[i], sizes[i]) for i in range(len(c))), key=lambda t: -t[1])


CLUSTER_MIN_SIM = 0.55               # Abdrücke, die sich mindestens so ähnlich sind, gehören zu einer Person
CLUSTER_MAX = 8                      # mehr Personen in einer Sitzung unterscheiden wir nicht


def cluster_speakers(embs, min_sim=CLUSTER_MIN_SIM, max_k=CLUSTER_MAX):
    """Sprecher ohne Profil trennen (Runde 24, auch mehr als zwei): Abdrücke -> Labels 0..k-1, die größte Gruppe
    hat Label 0. Greedy nach Kosinus zum Zentroid (Reihenfolge der Äußerungen), danach k-means-Verfeinerung; Gruppen
    mit nur einem Satz werden der ähnlichsten größeren zugeschlagen. Leere Liste -> []."""
    if not len(embs):
        return []
    arr = np.stack([np.asarray(e, dtype=np.float32) for e in embs])
    arr = arr / (np.linalg.norm(arr, axis=1, keepdims=True) + 1e-9)
    cents, lab = [], []
    for v in arr:
        sims = [float(c @ v) for c in cents]
        if sims and max(sims) >= min_sim:
            i = int(np.argmax(sims))
        elif len(cents) < max(1, int(max_k)):
            cents.append(v.copy())
            i = len(cents) - 1
        else:
            i = int(np.argmax(sims))
        lab.append(i)
        m = arr[[j for j, x in enumerate(lab) if x == i]].mean(axis=0)
        cents[i] = m / (np.linalg.norm(m) + 1e-9)
    c = np.stack(cents)
    for _ in range(5):                                   # Verfeinerung: früh falsch zugeordnete Sätze nachziehen
        new_lab = np.argmax(arr @ c.T, axis=1)
        if (new_lab == np.array(lab)).all():
            break
        lab = [int(x) for x in new_lab]
        for i in range(len(c)):
            idx = [j for j, x in enumerate(lab) if x == i]
            if idx:
                m = arr[idx].mean(axis=0)
                c[i] = m / (np.linalg.norm(m) + 1e-9)
    sizes = {i: lab.count(i) for i in set(lab)}
    big = [i for i, n in sizes.items() if n >= 2]
    if big:                                              # Einzelne Ausreißer-"Sprecher" nicht als Person zählen
        for i, n in sizes.items():
            if n == 1:
                j = max(big, key=lambda b_: float(c[b_] @ c[i]))
                lab = [j if x == i else x for x in lab]
    order = sorted(set(lab), key=lambda i: (-lab.count(i), i))
    remap = {old: new for new, old in enumerate(order)}
    return [remap[x] for x in lab]


def extra_centroids(embs):
    """Zusätzliche Zentroide (Liste von Listen) für eine Stimme mit zwei Klangfarben (Flüstern/Laut, Headset/Mikro)
    oder [] wenn eine Gruppe genügt."""
    if len(embs) < EXTRA_MIN_EMBS:
        return []
    cents = kmeans_centroids(embs, 2)
    if len(cents) < 2 or min(n for _, n in cents) < EXTRA_MIN_CLUSTER:
        return []
    if float(cents[0][0] @ cents[1][0]) >= EXTRA_MAX_SIM:
        return []
    return [[round(float(x), 6) for x in c] for c, _ in cents]


_LEARN_LOCK = threading.Lock()


class SpeakerID:
    pair = DEFAULT_PAIR
    _learn_q = None

    def __init__(self):
        import sherpa_onnx as so
        cfg = so.SpeakerEmbeddingExtractorConfig(model=ensure_model(), num_threads=2)
        self.ex = so.SpeakerEmbeddingExtractor(cfg)
        self.reload()

    def reload(self):
        """Profile laden, Embeddings einmal normalisieren/vorberechnen; unpassende (andere Modell-ID oder
        Dimension, NaN, leer) werden übersprungen und in self.skipped gemeldet.
        Nr. 198: alles in lokalen Variablen bauen und am Ende in einem Zug zuweisen – ein Leser im
        Arbeits-Thread sieht nie profiles und mat aus verschiedenen Ständen."""
        skipped = []
        cands = []
        for p in list_profiles():
            emb = p.get("embedding")
            if not emb:
                continue
            if p.get("embedding_model") not in (None, EMBED_MODEL_ID):
                skipped.append((p["name"], "anderes Modell"))
                continue
            try:
                a = np.asarray(emb, dtype=np.float32)
            except (ValueError, TypeError):
                skipped.append((p["name"], "unlesbar"))
                continue
            if a.ndim != 1 or not np.isfinite(a).all() or np.linalg.norm(a) < 1e-6:
                skipped.append((p["name"], "ungültig"))
                continue
            cands.append((p, a))
        dim = getattr(getattr(self, "ex", None), "dim", None)
        if not isinstance(dim, int) and cands:
            dim = Counter(len(a) for _, a in cands).most_common(1)[0][0]
        profiles, emb = [], {}
        for p, a in cands:
            if len(a) != dim:
                skipped.append((p["name"], "falsche Dimension %d != %s" % (len(a), dim)))
                continue
            profiles.append(p)
            emb[p["name"]] = a / np.linalg.norm(a)
        mat = np.stack([emb[p["name"]] for p in profiles]) if profiles else None
        # identify() liest profiles und mat über _state (ein Zugriff, immer zusammengehörig)
        self._state = (profiles, emb, mat)
        self.profiles, self._emb, self.mat, self.skipped = profiles, emb, mat, skipped

    def _emb_of(self, p):
        e = getattr(self, "_emb", {}).get(p["name"])
        return e if e is not None else np.array(p["embedding"], dtype=np.float32)

    def _sim(self, p, e):
        """Ähnlichkeit zu einem Profil: Hauptabdruck oder – falls vorhanden – der beste zusätzliche Zentroid."""
        best = float(self._emb_of(p) @ e)
        for x in p.get("embedding_extra") or ():
            try:
                v = np.asarray(x, dtype=np.float32)
                if v.shape == e.shape and np.isfinite(v).all():
                    best = max(best, float(v @ e) / (float(np.linalg.norm(v)) + 1e-9))
            except (ValueError, TypeError):
                continue
        return best

    def embed(self, audio):
        """Normierter Stimmabdruck oder None (Stille, NaN, zu kurz, Modellfehler) – nie ein Nullvektor."""
        a = np.asarray(audio, dtype=np.float32).ravel()
        if a.size < EMBED_MIN_SECONDS * SR or not np.isfinite(a).all():
            return None
        if float(np.sqrt(np.mean(a * a))) < EMBED_MIN_RMS:
            return None
        with _EX_LOCK:
            s = self.ex.create_stream()
            s.accept_waveform(SR, a)
            s.input_finished()
            e = np.array(self.ex.compute(s), dtype=np.float32)
        n = float(np.linalg.norm(e)) if e.size else 0.0
        if not np.isfinite(n) or n < 1e-6 or not np.isfinite(e).all():
            return None
        return e / n

    def set_pair(self, me_lang, partner_lang):
        """Sprachpaar der Unterhaltung setzen: me()/partner() suchen dann Profile dieser Sprachen."""
        self.pair = pair_from_langs(me_lang, partner_lang)
        return self.pair

    def _pick(self, lang):
        """Deterministisch: das zuletzt angelegte Profil der Sprache (Gleichstand: Name)."""
        c = [p for p in self.profiles if p.get("lang") == lang]
        return max(c, key=_created_key) if c else None

    def me(self):
        """Das Profil der Person, die Englisch spricht (im Zwei-Personen-Modus 'ich')."""
        return self._pick(self.pair[0])

    def partner(self):
        """Das Profil der Person, die Thai spricht (im Zwei-Personen-Modus 'Partnerin'), falls angelegt."""
        return self._pick(self.pair[1])

    def role(self, audio, prev=None):
        """-> ('me'|'other'|None, ähnlichkeit zu mir). None = unklar, dann entscheidet die Spracherkennung."""
        r = self.classify(audio, prev)
        return r["role"], r.get("sim_me", 0.0)

    def lazy_embed(self, audio):
        """-> Funktion, die den Stimmabdruck von `audio` beim ersten Aufruf berechnet und danach (auch
        ein None-Ergebnis) wiederverwendet: identify() und classify() teilen sich so einen Modelllauf."""
        memo = []

        def get():
            if not memo:
                memo.append(self.embed(audio))
            return memo[0]
        return get

    def classify(self, audio, prev=None, emb=None):
        """Wer spricht? -> {"role", "sim_me", "sim_her", "emb", "how"}. `prev` = Rolle der direkt
        vorangehenden Äußerung (nur bei kurzer Pause), entscheidet knappe Fälle. `emb` = optional
        Funktion aus lazy_embed() (spart den zweiten Modelllauf)."""
        me = self.me()
        if me is None or audio.size < ROLE_MIN_SECONDS * SR:
            return {"role": None, "how": "kein profil" if me is None else "zu kurz"}
        e = emb() if emb else self.embed(audio)
        if e is None:
            return {"role": None, "how": "kein stimmabdruck"}
        me_e = self._emb_of(me)
        her = self.partner()
        her_e = self._emb_of(her) if her else None
        if me_e.shape != e.shape or (her_e is not None and her_e.shape != e.shape):
            return {"role": None, "how": "abdruck passt nicht"}
        sim_me = self._sim(me, e)
        sim_her = self._sim(her, e) if her_e is not None else None
        role, how = decide_role(sim_me, sim_her, audio.size / SR,
                                max(ROLE_ME_MIN, float(me.get("role_me_min") or 0)), prev)
        return {"role": role, "how": how, "sim_me": round(sim_me, 3),
                "sim_her": None if sim_her is None else round(sim_her, 3), "emb": e}

    def learn(self, name, emb, weight):
        """Stimmabdruck vorsichtig nachführen (gleitender Mittelwert) und speichern. Das Original bleibt
        als embedding_orig erhalten; Drift über MAX_DRIFT_COS hinaus wird abgelehnt."""
        if emb is None or not any(p["name"] == name for p in self.profiles):
            return False
        emb = np.asarray(emb, dtype=np.float32)
        if not np.isfinite(emb).all() or np.linalg.norm(emb) < 1e-6:
            return False
        weight = min(MAX_LEARN_WEIGHT, max(0.0, float(weight)))
        with _locked():
            p = get_profile(name)                    # frisch von Platte (Vokabular etc. nicht überschreiben)
            if p is None:
                return False
            old = np.array(p["embedding"], dtype=np.float32)
            if old.shape != emb.shape:
                return False
            if float(old @ emb) / (np.linalg.norm(old) * np.linalg.norm(emb) + 1e-9) < LEARN_MIN_SIM:
                return False                         # klingt nicht nach diesem Profil: nichts lernen
            orig = np.array(p.get("embedding_orig") or p["embedding"], dtype=np.float32)
            new = (1 - weight) * old + weight * emb / np.linalg.norm(emb)
            new /= np.linalg.norm(new) + 1e-9
            if float(new @ (orig / (np.linalg.norm(orig) + 1e-9))) < MAX_DRIFT_COS:
                return False
            p.setdefault("embedding_orig", [round(float(x), 6) for x in old])
            p["embedding"] = [round(float(x), 6) for x in new]
            p["adapted"] = int(p.get("adapted") or 0) + 1
            save_profile(p)
        self._reload_one(p)
        return True

    def learn_async(self, name, emb, weight, done=None):
        """learn() im Hintergrund-Thread (Datei-Sperre + fsync halten sonst den Arbeits-Thread an). Aufträge laufen
        nacheinander; `done(ok)` wird im Hintergrund-Thread gerufen. Voll (>32 wartend): verworfen -> False."""
        import queue
        with _LEARN_LOCK:
            if self._learn_q is None:
                self._learn_q = queue.Queue(maxsize=32)

                def work(q=self._learn_q):
                    while True:
                        item = q.get()
                        try:
                            ok = False
                            with contextlib.suppress(Exception):
                                ok = self.learn(item[0], item[1], item[2])
                            if item[3]:
                                with contextlib.suppress(Exception):
                                    item[3](ok)
                        finally:
                            q.task_done()
                threading.Thread(target=work, name="profile-learn", daemon=True).start()
            q = self._learn_q
        try:
            q.put_nowait((name, emb, weight, done))
        except queue.Full:
            return False
        return True

    def flush_learning(self, timeout=5.0):
        """Wartende learn_async()-Aufträge abwarten (Beenden, Tests). -> True, wenn alles erledigt."""
        q = self._learn_q
        end = time.monotonic() + timeout
        while q is not None and q.unfinished_tasks and time.monotonic() < end:
            time.sleep(0.01)
        return q is None or not q.unfinished_tasks

    def delete(self, name):
        """Profil samt Sicherungen löschen und den Speicher neu aufbauen. -> True, wenn es existierte."""
        ok = delete_profile(name)
        self.reload()
        return ok

    def _reload_one(self, new_p):
        """Nur dieses Profil im Speicher ersetzen (statt alle Dateien neu zu lesen: learn() läuft im Arbeits-Thread).
        Bei jedem Zweifel der volle Neuaufbau."""
        try:
            name = new_p["name"]
            emb_new = np.asarray(new_p["embedding"], dtype=np.float32)
            profiles = [new_p if p["name"] == name else p for p in self.profiles]
            emb = dict(self._emb)
            emb[name] = emb_new / np.linalg.norm(emb_new)
            mat = np.stack([emb[p["name"]] for p in profiles])
        except Exception:                                  # noqa: BLE001
            self.reload()
            return
        self._state = (profiles, emb, mat)
        self.profiles, self._emb, self.mat = profiles, emb, mat

    def reset_learning(self, name):
        ok = reset_learning(name)
        self.reload()
        return ok

    def identify(self, audio, emb=None):
        """-> (profile, similarity, scores) or (None, best_sim, scores). `emb` wie bei classify()."""
        st = getattr(self, "_state", None)       # ein Lesezugriff: profiles und mat aus demselben reload()
        profiles, mat = (st[0], st[2]) if st is not None else (self.profiles, self.mat)
        if mat is None or audio.size < MIN_SECONDS * SR:
            return None, 0.0, {}
        e = emb() if emb else self.embed(audio)
        if e is None or e.shape[0] != mat.shape[1]:
            return None, 0.0, {}
        sims = mat @ e
        if any(p.get("embedding_extra") for p in profiles):
            sims = np.array([self._sim(p, e) for p in profiles], dtype=np.float32)
        order = np.argsort(-sims)
        scores = {profiles[i]["name"]: round(float(sims[i]), 3) for i in order}
        best = float(sims[order[0]])
        if len(order) > 1:
            ok = best >= MIN_SIM and best - float(sims[order[1]]) >= MIN_MARGIN
        else:
            ok = best >= MIN_SIM_SINGLE               # kein Vergleichswert -> höhere Hürde
        if ok:
            return profiles[order[0]], best, scores
        return None, best, scores

    def hotwords(self, lang, who=None, role=None):
        """Eigene Wörter (Whisper-Hotwords) für die Erkennung in `lang`: zuerst das erkannte Profil,
        dann das Profil der Rolle ("me"/"other"), dann alle übrigen Profile derselben Sprache.
        Nur Profile der passenden Sprache; höchstens MAX_HOTWORDS Einträge. -> str oder None."""
        return pick_hotwords(self.profiles, lang, who,
                             self.me() if role == "me" else self.partner() if role == "other" else None)


# Zwei Profile (ich = Englisch, Partnerin = Thai): Vergleich "klingt eher wie ich / wie sie".
# Startwerte, noch nicht an echten Gesprächen gemessen – im Log stehen sim_me/sim_her pro Satz.
ROLE_PAIR_MIN = 0.55        # die bessere der beiden Ähnlichkeiten muss mindestens so hoch sein
ROLE_PAIR_MARGIN = 0.10     # und die andere um so viel schlagen
ROLE_LEAN_MARGIN = 0.03     # knapper Vorsprung: nur zusammen mit dem vorherigen Sprecher
# "ich" nie darunter: fremde Stimmen erreichen bis 0,64 (falsch "ich" = Thai als Englisch gelesen)
ROLE_ME_FLOOR = 0.65


MAX_HOTWORDS = 2 * MAX_VOCAB
HOTWORD_BUDGET = 400          # gewichtete Zeichen (Thai × 3) für den Whisper-Prompt


_LATIN_LANGS = {"en", "de", "es", "fr", "it", "pt", "nl", "vi", "id", "tr", "pl"}


def _script_fits(word, lang):
    """Passt das Wort zur Schrift der Erkennungssprache? Thai nur mit Thai-Zeichen, lateinische Sprachen nur ohne
    Thai-Zeichen und mit Buchstaben; andere Sprachen: nein (nur ihre eigenen Profile)."""
    has_thai = any("฀" <= c <= "๿" for c in word)
    if lang == "th":
        return has_thai
    if lang in _LATIN_LANGS:
        return not has_thai and any(c.isalpha() and c.isascii() or "À" <= c <= "ɏ" for c in word)
    return False


def pick_hotwords(profs, lang, who=None, role_p=None):
    """Reine Auswahlregel zu SpeakerID.hotwords() (testbar ohne Modell)."""
    order = [p for p in (who, role_p) if p] + [p for p in profs or [] if p not in (who, role_p)]
    out, seen = [], set()
    for p in order:
        same = p.get("lang", "en") == lang
        for w in p.get("vocab") or []:
            # eigene Profilsprache: alles; andere Profile: Wörter in der Schrift der gesuchten Sprache
            # (thailändische Ortsnamen im englischen Profil helfen der Thai-Erkennung)
            if not same and not (isinstance(w, str) and _script_fits(w, lang)):
                continue
            if isinstance(w, str) and w.strip() and w.casefold() not in seen:
                seen.add(w.casefold())
                out.append(w.strip())
    # Token-Budget: Thai kostet je Zeichen mehrere Token, eine Überlänge schneidet Whisper still ab – die wichtigsten
    # (zuerst gewählten) Wörter bleiben, der Rest fällt weg
    kept, used = [], 0
    for w in out[:MAX_HOTWORDS]:
        cost = sum(3 if "฀" <= c <= "๿" else 1 for c in w) + 1
        if used + cost > HOTWORD_BUDGET and kept:
            break
        kept.append(w)
        used += cost
    return " ".join(kept) or None


def decide_role(sim_me, sim_her, dur, me_min, prev=None):
    """Reine Entscheidungsregel (testbar ohne Audio). -> (role|None, begründung)."""
    long_ = dur >= MIN_SECONDS
    if sim_her is not None:
        best = max(sim_me, sim_her)
        if sim_me >= me_min and sim_me > sim_her:
            return "me", "profil ich"
        if best >= ROLE_PAIR_MIN and abs(sim_me - sim_her) >= ROLE_PAIR_MARGIN:
            if sim_her > sim_me:
                return "other", "vergleich"
            if sim_me >= ROLE_ME_FLOOR:
                return "me", "vergleich"
        if sim_me <= (ROLE_OTHER_MAX_LONG if long_ else ROLE_OTHER_MAX) and sim_her > sim_me:
            return "other", "nicht ich"
        lean = "me" if sim_me - sim_her >= ROLE_LEAN_MARGIN else \
               "other" if sim_her - sim_me >= ROLE_LEAN_MARGIN else None
        if lean and lean == prev and (lean == "other" or sim_me >= ROLE_ME_FLOOR):
            return lean, "knapp + vorher"
        return None, "unklar"
    if sim_me >= me_min:
        return "me", "profil ich"
    if sim_me <= (ROLE_OTHER_MAX_LONG if long_ else ROLE_OTHER_MAX):
        return "other", "nicht ich"
    # Graubereich ohne Partnerprofil: Tendenz nur zusammen mit dem vorherigen Sprecher
    mid = (me_min + (ROLE_OTHER_MAX_LONG if long_ else ROLE_OTHER_MAX)) / 2
    lean = "me" if sim_me >= max(mid, ROLE_ME_FLOOR) else "other"
    if lean == prev:
        return lean, "knapp + vorher"
    return None, "unklar"


# ---------- quality ----------
def _norm_text(s):
    """NFC, klein, nur Buchstaben/Zahlen/Kombizeichen/Leerraum (Thai-Tonmarken und Vokalzeichen sind
    Mn und bleiben erhalten – `\\w` würde sie fälschlich entfernen)."""
    s = unicodedata.normalize("NFC", s).lower()
    return "".join(c for c in s if c.isspace() or unicodedata.category(c)[0] in "LMN")


def _clusters(s):
    """Zeichen ohne Leerraum, Kombizeichen (Thai-Vokale/Töne) an ihren Grundbuchstaben gebunden."""
    out = []
    for c in s:
        if c.isspace():
            continue
        if out and unicodedata.category(c)[0] == "M":
            out[-1] += c
        else:
            out.append(c)
    return out


def error_rate(ref, hyp, lang):
    """Word error rate for English, character(-cluster) error rate for Thai (no spaces)."""
    r, h = _norm_text(ref), _norm_text(hyp)
    r, h = (_clusters(r), _clusters(h)) if lang == "th" else (r.split(), h.split())
    if not r:
        return 0.0
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / len(r)


def _drop_outliers(embs):
    """-> (Indizes der behaltenen Embeddings, Zentroid). Ausreißer = weit unter dem Median der
    Ähnlichkeiten zum Median-Zentroid (falscher Sprecher, Husten, Störgeräusch)."""
    arr = np.stack(embs)
    c = np.median(arr, axis=0)
    c /= np.linalg.norm(c) + 1e-9
    sims = arr @ c
    thr = max(ENROLL_OUTLIER_FLOOR, float(np.median(sims)) - ENROLL_OUTLIER_DROP)
    keep = [i for i, s in enumerate(sims) if s >= thr]
    return keep


def enroll(name, lang, record_one, transcribe, emit, spk=None):
    """Guide the person through the sentences, build and save the profile.

    record_one() -> np.ndarray of one spoken sentence (float32, 16 kHz) or None
    transcribe(audio, lang) -> text
    """
    name = _nfc(name)
    _safe(name)                                   # früh: ungültiger Name -> ProfileNameError vor der Aufnahme
    if lang not in ENROLL:
        raise ValueError("Keine Einschreibe-Sätze für Sprache %r (verfügbar: %s)" % (lang, ", ".join(sorted(ENROLL))))
    spk = spk or SpeakerID()
    sents = ENROLL[lang]
    embs, rows, auds = [], [], []
    for i, sent in enumerate(sents, 1):
        emit("enroll_prompt", i=i, n=len(sents), sentence=sent, name=name)
        best = None                               # (err, audio, hyp)
        for attempt in range(3):                  # bis zu 3 Versuche pro Satz
            audio = record_one()
            if audio is None or audio.size < ENROLL_MIN_SECONDS * SR:
                emit("enroll_retry", i=i, reason="zu kurz", code="too_short")
                continue
            hyp = transcribe(audio, lang)
            er = error_rate(sent, hyp, lang)
            emit("enroll_heard", i=i, heard=hyp, err=round(er, 3))
            if best is None or er < best[0]:
                best = (er, audio, hyp)
            # nur bei offensichtlichem Durcheinander wiederholen (Störgeräusch, falsche Zeile) –
            # nicht weil die Erkennung schwächelt: genau dafür ist das Profil ja da
            other = min((error_rate(o, hyp, lang) for o in sents if o != sent), default=1.0)
            if er <= 0.85 and not other < er - 0.2:
                break
            emit("enroll_retry", i=i, reason="anderer Satz gehört", code="other_sentence")
        if best is None:                          # Satz übersprungen; Gesamtergebnis zählt unten
            emit("enroll_retry", i=i, reason="übersprungen", code="skipped")
            continue
        er, audio, hyp = best
        e = spk.embed(audio)
        if e is not None:
            embs.append(e)
            auds.append(audio)
        rows.append({"ref": sent, "hyp": hyp, "err": round(min(er, 1.0), 3)})
    if len(embs) < ENROLL_MIN_USABLE:
        emit("enroll_failed", reason="zu wenige brauchbare Aufnahmen", code="too_few")
        return None
    keep = _drop_outliers(embs)
    if len(keep) < ENROLL_MIN_USABLE:
        emit("enroll_failed", reason="zu wenige brauchbare Aufnahmen (Stimme uneinheitlich)",
             code="inconsistent")
        return None
    embs, auds = [embs[k] for k in keep], [auds[k] for k in keep]
    e = np.mean(embs, axis=0)
    e /= np.linalg.norm(e)
    # how consistent is the voice? (helps to pick thresholds later)
    self_sim = float(np.mean([x @ e for x in embs]))
    # Kalibrierung für kurze Sätze ("ok", "yes"): Ähnlichkeit kurzer Ausschnitte der eigenen Stimme
    short = []
    for a in auds:
        n = int(0.8 * SR)
        for i in range(0, max(1, a.size - n), n):
            se = spk.embed(a[i:i + n])
            if se is not None:
                short.append(float(se @ e))
    p10 = float(np.percentile(short, 10)) if short else 0.0
    role_me_min = round(min(0.85, max(ROLE_ME_MIN, p10 - 0.02)), 3)
    with _locked():
        old = get_profile(name) or {}
        if old:
            _backup(name)                         # Neuanlegen überschreibt nicht still
        p = {
            "name": name, "lang": lang, "created": _utcnow(), "schema_version": SCHEMA_VERSION,
            "embedding": [round(float(x), 6) for x in e],
            "embedding_model": EMBED_MODEL_ID, "embedding_dim": int(e.shape[0]),
            "self_similarity": round(self_sim, 3),
            "role_me_min": role_me_min,
            "vocab": old.get("vocab", []),
            "error_rate": round(float(np.mean([r["err"] for r in rows])), 3),
            "enroll_results": rows,
        }
        extra = extra_centroids(embs)
        if extra:
            p["embedding_extra"] = extra
        if old.get("polite") in ("krub", "ka"):          # Neu-Aufnahme behält die Höflichkeitsform
            p["polite"] = old["polite"]
        save_profile(p)
    emit("enroll_done", profile=public(p))
    return p
