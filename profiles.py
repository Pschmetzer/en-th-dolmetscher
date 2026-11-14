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

SCHEMA_VERSION = 2             # fehlendes Feld in der Datei = Version 1
EMBED_MODEL_ID = "wespeaker_en_voxceleb_resnet34"
MAX_VOCAB = 30
MAX_VOCAB_LEN = 60
MAX_NAME_LEN = 64
MAX_DRIFT_COS = 0.90           # learn(): Abdruck darf sich nie weiter vom Original entfernen
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


@contextlib.contextmanager
def _locked():
    """Prozessübergreifende Sperre (CLI + Engine) plus Thread-Sperre; wiederbetretbar."""
    with _THREAD_LOCK:
        if _depth[0] == 0:
            _ensure_dir()
            fd = os.open(os.path.join(PROFILE_DIR, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
            except BaseException:
                os.close(fd)
                raise
            _lockfd[0] = fd
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
    msg = "Profil-Datei %s unlesbar (%s) -> %s" % (os.path.basename(path), why, os.path.basename(dest))
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
        CORRUPT.append("Profil-Datei %s nicht lesbar: %s" % (os.path.basename(path), e))
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


def delete_profile(name):
    with _locked():
        path = _locate(name)
        if not path:
            return False
        try:
            os.remove(path)
            return True
        except FileNotFoundError:
            return False


def _backup(name):
    """Altes Profil vor dem Überschreiben sichern (<datei>.json.<zeit>.bak, wird nicht als Profil geladen)."""
    path = _locate(name)
    if not path:
        return None
    dest = "%s.%s.bak" % (path, _stamp())
    shutil.copy2(path, dest)
    os.chmod(dest, 0o600)
    return dest


def clean_vocab(words):
    """Wörter (Liste oder String; Trenner , ; Zeilenumbruch) -> NFC, getrimmt, ohne Duplikate, max. MAX_VOCAB."""
    if isinstance(words, str):
        words = [words]
    out, seen = [], set()
    for chunk in words or []:
        for w in re.split(r"[,;\n\r]", _nfc(str(chunk))):
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


PUBLIC_KEYS = ("name", "lang", "created", "self_similarity", "role_me_min", "vocab", "error_rate",
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
    h = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": "dolmetscher"})
    with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as r, open(tmp, "wb") as out:
        while True:
            chunk = r.read(DOWNLOAD_CHUNK)
            if not chunk:
                break
            h.update(chunk)
            out.write(chunk)
        out.flush()
        os.fsync(out.fileno())
    return h.hexdigest()


def ensure_model():
    if os.path.exists(MODEL_PATH):
        return MODEL_PATH
    mdir = os.path.dirname(MODEL_PATH)
    os.makedirs(mdir, exist_ok=True)
    with open(os.path.join(mdir, ".download.lock"), "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)                      # nur ein Prozess lädt/importiert gleichzeitig
        if os.path.exists(MODEL_PATH):
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
                  [("url", u) for u in (MODEL_URL, os.environ.get(ENV_MODEL_URL)) if u]
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


class SpeakerID:
    def __init__(self):
        import sherpa_onnx as so
        cfg = so.SpeakerEmbeddingExtractorConfig(model=ensure_model(), num_threads=2)
        self.ex = so.SpeakerEmbeddingExtractor(cfg)
        self.reload()

    def reload(self):
        """Profile laden, Embeddings einmal normalisieren/vorberechnen; unpassende (andere Modell-ID oder
        Dimension, NaN, leer) werden übersprungen und in self.skipped gemeldet."""
        self.skipped = []
        cands = []
        for p in list_profiles():
            emb = p.get("embedding")
            if not emb:
                continue
            if p.get("embedding_model") not in (None, EMBED_MODEL_ID):
                self.skipped.append((p["name"], "anderes Modell"))
                continue
            try:
                a = np.asarray(emb, dtype=np.float32)
            except (ValueError, TypeError):
                self.skipped.append((p["name"], "unlesbar"))
                continue
            if a.ndim != 1 or not np.isfinite(a).all() or np.linalg.norm(a) < 1e-6:
                self.skipped.append((p["name"], "ungültig"))
                continue
            cands.append((p, a))
        dim = getattr(getattr(self, "ex", None), "dim", None)
        if not isinstance(dim, int) and cands:
            dim = Counter(len(a) for _, a in cands).most_common(1)[0][0]
        self.profiles, self._emb = [], {}
        for p, a in cands:
            if len(a) != dim:
                self.skipped.append((p["name"], "falsche Dimension %d != %s" % (len(a), dim)))
                continue
            self.profiles.append(p)
            self._emb[p["name"]] = a / np.linalg.norm(a)
        self.mat = np.stack([self._emb[p["name"]] for p in self.profiles]) if self.profiles else None

    def _emb_of(self, p):
        e = getattr(self, "_emb", {}).get(p["name"])
        return e if e is not None else np.array(p["embedding"], dtype=np.float32)

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

    def _pick(self, lang):
        """Deterministisch: das zuletzt angelegte Profil der Sprache (Gleichstand: Name)."""
        c = [p for p in self.profiles if p.get("lang") == lang]
        return max(c, key=_created_key) if c else None

    def me(self):
        """Das Profil der Person, die Englisch spricht (im Zwei-Personen-Modus 'ich')."""
        return self._pick("en")

    def partner(self):
        """Das Profil der Person, die Thai spricht (im Zwei-Personen-Modus 'Partnerin'), falls angelegt."""
        return self._pick("th")

    def role(self, audio, prev=None):
        """-> ('me'|'other'|None, ähnlichkeit zu mir). None = unklar, dann entscheidet die Spracherkennung."""
        r = self.classify(audio, prev)
        return r["role"], r.get("sim_me", 0.0)

    def classify(self, audio, prev=None):
        """Wer spricht? -> {"role", "sim_me", "sim_her", "emb", "how"}. `prev` = Rolle der direkt
        vorangehenden Äußerung (nur bei kurzer Pause), entscheidet knappe Fälle."""
        me = self.me()
        if me is None or audio.size < ROLE_MIN_SECONDS * SR:
            return {"role": None, "how": "kein profil" if me is None else "zu kurz"}
        e = self.embed(audio)
        if e is None:
            return {"role": None, "how": "kein stimmabdruck"}
        me_e = self._emb_of(me)
        her = self.partner()
        her_e = self._emb_of(her) if her else None
        if me_e.shape != e.shape or (her_e is not None and her_e.shape != e.shape):
            return {"role": None, "how": "abdruck passt nicht"}
        sim_me = float(me_e @ e)
        sim_her = float(her_e @ e) if her_e is not None else None
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
        weight = min(0.5, max(0.0, float(weight)))
        with _locked():
            p = get_profile(name)                    # frisch von Platte (Vokabular etc. nicht überschreiben)
            if p is None:
                return False
            old = np.array(p["embedding"], dtype=np.float32)
            if old.shape != emb.shape:
                return False
            orig = np.array(p.get("embedding_orig") or p["embedding"], dtype=np.float32)
            new = (1 - weight) * old + weight * emb / np.linalg.norm(emb)
            new /= np.linalg.norm(new) + 1e-9
            if float(new @ (orig / (np.linalg.norm(orig) + 1e-9))) < MAX_DRIFT_COS:
                return False
            p.setdefault("embedding_orig", [round(float(x), 6) for x in old])
            p["embedding"] = [round(float(x), 6) for x in new]
            p["adapted"] = int(p.get("adapted") or 0) + 1
            save_profile(p)
        self.reload()
        return True

    def reset_learning(self, name):
        ok = reset_learning(name)
        self.reload()
        return ok

    def identify(self, audio):
        """-> (profile, similarity, scores) or (None, best_sim, scores)."""
        if self.mat is None or audio.size < MIN_SECONDS * SR:
            return None, 0.0, {}
        e = self.embed(audio)
        if e is None or e.shape[0] != self.mat.shape[1]:
            return None, 0.0, {}
        sims = self.mat @ e
        order = np.argsort(-sims)
        scores = {self.profiles[i]["name"]: round(float(sims[i]), 3) for i in order}
        best = float(sims[order[0]])
        if len(order) > 1:
            ok = best >= MIN_SIM and best - float(sims[order[1]]) >= MIN_MARGIN
        else:
            ok = best >= MIN_SIM_SINGLE               # kein Vergleichswert -> höhere Hürde
        if ok:
            return self.profiles[order[0]], best, scores
        return None, best, scores


# Zwei Profile (ich = Englisch, Partnerin = Thai): Vergleich "klingt eher wie ich / wie sie".
# Startwerte, noch nicht an echten Gesprächen gemessen – im Log stehen sim_me/sim_her pro Satz.
ROLE_PAIR_MIN = 0.55        # die bessere der beiden Ähnlichkeiten muss mindestens so hoch sein
ROLE_PAIR_MARGIN = 0.10     # und die andere um so viel schlagen
ROLE_LEAN_MARGIN = 0.03     # knapper Vorsprung: nur zusammen mit dem vorherigen Sprecher
ROLE_ME_FLOOR = 0.65        # "ich" nie darunter: fremde Stimmen erreichen bis 0,64 (falsch "ich" = Thai als Englisch gelesen)


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
    spk = spk or SpeakerID()
    sents = ENROLL[lang]
    embs, rows, auds = [], [], []
    for i, sent in enumerate(sents, 1):
        emit("enroll_prompt", i=i, n=len(sents), sentence=sent, name=name)
        best = None                               # (err, audio, hyp)
        for attempt in range(3):                  # bis zu 3 Versuche pro Satz
            audio = record_one()
            if audio is None or audio.size < ENROLL_MIN_SECONDS * SR:
                emit("enroll_retry", i=i, reason="zu kurz")
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
            emit("enroll_retry", i=i, reason="anderer Satz gehört")
        if best is None:                          # Satz übersprungen; Gesamtergebnis zählt unten
            emit("enroll_retry", i=i, reason="übersprungen")
            continue
        er, audio, hyp = best
        e = spk.embed(audio)
        if e is not None:
            embs.append(e)
            auds.append(audio)
        rows.append({"ref": sent, "hyp": hyp, "err": round(min(er, 1.0), 3)})
    if len(embs) < ENROLL_MIN_USABLE:
        emit("enroll_failed", reason="zu wenige brauchbare Aufnahmen")
        return None
    keep = _drop_outliers(embs)
    if len(keep) < ENROLL_MIN_USABLE:
        emit("enroll_failed", reason="zu wenige brauchbare Aufnahmen (Stimme uneinheitlich)")
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
        save_profile(p)
    emit("enroll_done", profile=public(p))
    return p
