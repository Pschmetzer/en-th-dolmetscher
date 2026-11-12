"""Voice profiles: who is speaking, plus personal vocabulary.

A profile is created once by reading 8 sentences aloud (~1 minute). It stores
  * a voiceprint (speaker embedding, wespeaker ResNet34 via sherpa-onnx, no torch),
  * the person's language (en/th) – used as a tie-breaker when language detection is unsure,
  * personal vocabulary (names, companies, places) – passed to Whisper as hotwords,
  * how well the engine understood the enrollment sentences (word/char error rate).

Profiles are biometric data. They stay on this Mac in
~/Library/Application Support/Dolmetscher/profiles/ and never leave it.
"""
import hashlib, json, os, re, time, urllib.request
import numpy as np

SR = 16000
BASE = os.path.expanduser("~/Library/Application Support/Dolmetscher")
PROFILE_DIR = os.path.join(BASE, "profiles")
MODEL_PATH = os.path.join(BASE, "models", "wespeaker_en_voxceleb_resnet34.onnx")
MODEL_URL = ("https://github.com/k2-fsa/sherpa-onnx/releases/download/"
             "speaker-recongition-models/wespeaker_en_voxceleb_resnet34.onnx")
MODEL_SHA256 = "5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94"

MIN_SECONDS = 1.5      # shorter clips give unreliable voiceprints
MIN_SIM = 0.68         # cosine similarity needed to accept a match (enrolled voices ~0.85+, strangers ~0.6)
MIN_MARGIN = 0.05      # best match must beat the runner-up by this much

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
def _safe(name):
    s = re.sub(r"[^\w\- ]", "", name, flags=re.U).strip()
    if not s:
        raise ValueError("invalid profile name")
    return s


def _path(name):
    return os.path.join(PROFILE_DIR, _safe(name) + ".json")


def list_profiles():
    out = []
    if os.path.isdir(PROFILE_DIR):
        for f in sorted(os.listdir(PROFILE_DIR)):
            if f.endswith(".json"):
                try:
                    with open(os.path.join(PROFILE_DIR, f)) as fh:
                        out.append(json.load(fh))
                except (OSError, ValueError):
                    pass
    return out


def save_profile(p):
    os.makedirs(PROFILE_DIR, exist_ok=True)
    tmp = _path(p["name"]) + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(p, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, _path(p["name"]))
    try:
        os.chmod(_path(p["name"]), 0o600)
    except OSError:
        pass


def delete_profile(name):
    try:
        os.remove(_path(name))
        return True
    except FileNotFoundError:
        return False


def set_vocab(name, words):
    p = next((x for x in list_profiles() if x["name"] == name), None)
    if not p:
        raise KeyError(name)
    p["vocab"] = [w.strip() for w in words if w.strip()]
    save_profile(p)
    return p


public = lambda p: {k: v for k, v in p.items() if k != "embedding"}


# ---------- model ----------
def ensure_model():
    if os.path.exists(MODEL_PATH):
        return MODEL_PATH
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    tmp = MODEL_PATH + ".part"
    urllib.request.urlretrieve(MODEL_URL, tmp)
    with open(tmp, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    if digest != MODEL_SHA256:
        os.remove(tmp)
        raise RuntimeError("speaker model checksum mismatch")
    os.replace(tmp, MODEL_PATH)
    return MODEL_PATH


class SpeakerID:
    def __init__(self):
        import sherpa_onnx as so
        cfg = so.SpeakerEmbeddingExtractorConfig(model=ensure_model(), num_threads=2)
        self.ex = so.SpeakerEmbeddingExtractor(cfg)
        self.reload()

    def reload(self):
        self.profiles = [p for p in list_profiles() if p.get("embedding")]
        self.mat = (np.array([p["embedding"] for p in self.profiles], dtype=np.float32)
                    if self.profiles else None)

    def embed(self, audio):
        s = self.ex.create_stream()
        s.accept_waveform(SR, audio.astype(np.float32))
        s.input_finished()
        e = np.array(self.ex.compute(s), dtype=np.float32)
        return e / (np.linalg.norm(e) + 1e-9)

    def me(self):
        """Das Profil der Person, die Englisch spricht (im Zwei-Personen-Modus 'ich')."""
        return next((p for p in self.profiles if p.get("lang") == "en"), None)

    def role(self, audio):
        """-> ('me'|'other'|None, ähnlichkeit). None = unklar, dann entscheidet die Spracherkennung."""
        me = self.me()
        if me is None or audio.size < ROLE_MIN_SECONDS * SR:
            return None, 0.0
        sim = float(np.array(me["embedding"], dtype=np.float32) @ self.embed(audio))
        long_ = audio.size >= MIN_SECONDS * SR
        if sim >= max(ROLE_ME_MIN, float(me.get("role_me_min") or 0)):
            return "me", sim
        if sim <= (ROLE_OTHER_MAX_LONG if long_ else ROLE_OTHER_MAX):
            return "other", sim
        return None, sim

    def identify(self, audio):
        """-> (profile, similarity, scores) or (None, best_sim, scores)."""
        if self.mat is None or audio.size < MIN_SECONDS * SR:
            return None, 0.0, {}
        sims = self.mat @ self.embed(audio)
        order = np.argsort(-sims)
        scores = {self.profiles[i]["name"]: round(float(sims[i]), 3) for i in order}
        best = float(sims[order[0]])
        second = float(sims[order[1]]) if len(order) > 1 else -1.0
        if best >= MIN_SIM and best - second >= MIN_MARGIN:
            return self.profiles[order[0]], best, scores
        return None, best, scores


# ---------- quality ----------
def error_rate(ref, hyp, lang):
    """Word error rate for English, character error rate for Thai (no spaces)."""
    norm = lambda s: re.sub(r"[^\w\s]", "", s.lower(), flags=re.U)
    r, h = norm(ref), norm(hyp)
    r, h = (list(r.replace(" ", "")), list(h.replace(" ", ""))) if lang == "th" else (r.split(), h.split())
    if not r:
        return 0.0
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / len(r)


def enroll(name, lang, record_one, transcribe, emit, spk=None):
    """Guide the person through the sentences, build and save the profile.

    record_one() -> np.ndarray of one spoken sentence (float32, 16 kHz) or None
    transcribe(audio, lang) -> text
    """
    spk = spk or SpeakerID()
    sents = ENROLL[lang]
    embs, rows, auds = [], [], []
    for i, sent in enumerate(sents, 1):
        emit("enroll_prompt", i=i, n=len(sents), sentence=sent, name=name)
        best = None                               # (err, audio, hyp)
        for attempt in range(3):                  # bis zu 3 Versuche pro Satz
            audio = record_one()
            if audio is None or audio.size < 0.8 * SR:
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
        if best is None:
            emit("enroll_failed", reason="keine Aufnahme")
            return None
        er, audio, hyp = best
        if audio.size >= MIN_SECONDS * SR:        # Stimmabdruck braucht nur genug Sprache
            embs.append(spk.embed(audio))
            auds.append(audio)
        rows.append({"ref": sent, "hyp": hyp, "err": round(min(er, 1.0), 3)})
    if len(embs) < 3:
        emit("enroll_failed", reason="zu wenige brauchbare Aufnahmen")
        return None
    e = np.mean(embs, axis=0)
    e /= np.linalg.norm(e)
    # how consistent is the voice? (helps to pick thresholds later)
    self_sim = float(np.mean([x @ e for x in embs]))
    # Kalibrierung für kurze Sätze ("ok", "yes"): Ähnlichkeit kurzer Ausschnitte der eigenen Stimme
    short = []
    for a in auds:
        n = int(0.8 * SR)
        for i in range(0, max(1, a.size - n), n):
            short.append(float(spk.embed(a[i:i + n]) @ e))
    p10 = float(np.percentile(short, 10)) if short else 0.0
    role_me_min = round(min(0.85, max(ROLE_ME_MIN, p10 - 0.02)), 3)
    old = next((p for p in list_profiles() if p["name"] == name), {})
    p = {
        "name": name, "lang": lang, "created": time.strftime("%Y-%m-%d %H:%M"),
        "embedding": [round(float(x), 6) for x in e],
        "self_similarity": round(self_sim, 3),
        "role_me_min": role_me_min,
        "vocab": old.get("vocab", []),
        "error_rate": round(float(np.mean([r["err"] for r in rows])), 3),
        "enroll_results": rows,
    }
    save_profile(p)
    emit("enroll_done", profile=public(p))
    return p
