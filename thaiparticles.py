"""Thai-Höflichkeitspartikel, Sprechergeschlecht und Dehnungen (Runde 25: aus dolmetscher.py ausgelagert, dort
re-exportiert). Reine Funktionen ohne Zustand."""
import re

_TH_STRETCH = re.compile(r"([ก-ฺเ-ๅๆ็-๎])\1{2,}")                 # ค่าาา, ครับบบ, ค่่่ะ: Dehnung (3+ gleiche Zeichen)


def thai_stretch(s):
    """Dehnungen normalisieren: ครับบบ -> ครับ, ค่าาา -> ค่า (3+ gleiche Konsonanten/Vokale -> eines)."""
    return _TH_STRETCH.sub(r"\1", s) if s else s


_TH_FEMALE = re.compile(r"ค่ะ|คะ(?!แนน|ยั้น|เน|น้า|นอง|นึง|ยอ)|ดิฉัน")
_TH_MALE = re.compile(r"ครับ|คร้าบ|คร๊าบ|ครัช|คับ|กระผม")             # Runde 28: auch Schreibvarianten คร้าบ, คร๊าบ, ครัช


def thai_speaker_sex(text):
    """Nr. 51: Geschlecht der Thai sprechenden Person aus Höflichkeitspartikeln ("female"/"male"/None).
    Nur eindeutige Fälle: beide Formen im Satz (Zitat) oder keine -> None. คะแนน (Punkte), บังคับ, คับแคบ … zählen
    nicht."""
    t = re.sub(r"คะแนน|คะน้า|คะนอง|คะนึง|บังคับ|คับแคบ|คับคั่ง|คับข้อง", "", text or "")
    f, m = bool(_TH_FEMALE.search(t)), bool(_TH_MALE.search(t))
    return "female" if f and not m else "male" if m and not f else None


_TH_Q_END = re.compile(r"(ไหม|มั้ย|หรือ|เหรอ|หรือเปล่า|รึเปล่า|อะไร|ไหน|ใคร|เท่าไร|เท่าไหร่|เมื่อไร|เมื่อไหร่|ทำไม"
                       r"|อย่างไร|ยังไง|กี่\S*|\?)\s*$")
_TH_KA = re.compile(r"ค่ะ|คะ(?!แนน|ยั้น|เน|น้า|นอง|นึง|ยอ)")
_TH_KRUB = re.compile(r"ครับผม|ครับ|คร้าบ|คร๊าบ|ครัช|(?<!บัง)คับ(?!แคบ|คั่ง|ข้อง|ขัน|ใจ|ที่)")


def _fit_particles_only(text, polite):
    """Runde 11: Thai-Partikel an das Sprechergeschlecht anpassen (deterministisch, nach Claude). krub: ค่ะ/คะ ->
    ครับ; ka: ครับ -> ค่ะ (Frage am Satzende: คะ). Enthält ein Text beide Formen (Zitat), bleibt er
    unverändert, ebenso Text ohne Partikel."""
    if not text or polite not in ("krub", "ka"):
        return text
    t = re.sub(r"คะแนน|บังคับ|คับแคบ|คับคั่ง|คับข้อง|คะน้า|คะนอง|คะนึง|คะยั้นคะยอ|คะเน|คับขัน|คับใจ|คับที่", "", text)
    has_ka, has_krub = bool(_TH_KA.search(t)), bool(_TH_KRUB.search(t))
    if has_ka and has_krub:
        return text
    if polite == "krub" and has_ka:
        return _TH_KA.sub("ครับ", text)
    if polite == "ka" and has_krub:
        def sub(m):
            before = text[:m.start()].rstrip().split("\n")[-1]
            after = text[m.end():].lstrip()
            q = bool(_TH_Q_END.search(before)) and not after[:1].isalnum()
            return "คะ" if q else "ค่ะ"
        return _TH_KRUB.sub(sub, text)
    return text


_TH_PRON_FEM = re.compile(r"ดิฉัน")        # Frauen-Ich: nur das eindeutige ดิฉัน
_TH_PRON_FORMAL_M = re.compile(r"กระผม")                              # Männer-Ich, förmlich
_TH_PRON_M = re.compile(r"(?<![ก-๙])ผม")     # „ผม“ am Wortanfang (เส้นผม = Haar zählt nicht)


def fit_thai_particles(text, polite):
    """Runde 11/27: Partikel UND das eindeutig geschlechtsgebundene Ich-Pronomen an das Sprechergeschlecht anpassen.
    krub: ค่ะ/คะ -> ครับ, ดิฉัน -> ผม; ka: ครับ -> ค่ะ/คะ, กระผม -> ดิฉัน (ผม allein bleibt: ผม heißt auch „Haar“).
    Zitate (beide Geschlechtsformen im Text) und Text ohne Treffer bleiben unverändert."""
    if not text or polite not in ("krub", "ka"):
        return text
    fem, male = bool(_TH_PRON_FEM.search(text)), bool(_TH_PRON_FORMAL_M.search(text) or _TH_PRON_M.search(text))
    particles = _fit_particles_only(text, polite)
    if fem and male:
        return particles
    if polite == "krub" and fem:
        return _TH_PRON_FEM.sub("ผม", particles)
    if polite == "ka" and _TH_PRON_FORMAL_M.search(particles) and not fem:
        return _TH_PRON_FORMAL_M.sub("ดิฉัน", particles)
    return particles


# Runde 28: Höflichkeitsstufe und Frage-/Aussage-Partikel der Frau
_RUDE = re.compile(r"(?<![ก-๙])กู(?!เกิล|รู)|มึง|(?:เว้ย|โว้ย|ว่ะ|วุ้ย|เฮ้ย|(?<!ส)วะ)(?![ก-๙])")
_FORMAL = re.compile(r"กระผม|ดิฉัน|ขอรับ|เจ้าค่ะ|เจ้าข้า|ท่านผู้")
_POLITE = re.compile(r"ครับ|ค่ะ|คะ(?!แนน|ยั้น|เน|น้า|นอง|นึง|ยอ)|คร้าบ|คร๊าบ|ครัช|(?<!บัง)คับ(?!แคบ|คั่ง|ข้อง|ขัน|ใจ|ที่)")
_CASUAL = re.compile(r"(?:จ้ะ|จ้า|จ๊ะ|เนอะ|อ่ะ|เหอะ|เถอะ|น่ะ|แหละ|ล่ะ|ป่ะ)(?![ก-๙])")


def thai_politeness_level(text):
    """Höflichkeitsstufe eines Thai-Satzes aus Partikeln und Pronomen: "rude" (กู/มึง, เว้ย, วะ), "formal" (กระผม,
    ดิฉัน, ขอรับ), "polite" (ครับ/ค่ะ/คะ), "casual" (จ้ะ, เนอะ, น่ะ, แหละ) oder None ohne Hinweis. Die gröbste Stufe
    gewinnt, damit ein derber Ausdruck nie als höflich durchgeht (Quelle für Ton und Stil der Übersetzung)."""
    t = re.sub(r"คะแนน|บังคับ|คับแคบ|คับคั่ง|คับข้อง|คะน้า|คะนอง|คะนึง", "", text or "")
    if not t.strip():
        return None
    for name, rx in (("rude", _RUDE), ("formal", _FORMAL), ("polite", _POLITE), ("casual", _CASUAL)):
        if rx.search(t):
            return name
    return None


_TH_KA_ANY = re.compile(r"ค่ะ|คะ(?!แนน|ยั้น|เน|น้า|นอง|นึง|ยอ)")


def normalize_ka(text):
    """Frauen-Partikel richtig schreiben: Frage -> คะ (ไหมคะ, ที่ไหนคะ), Aussage -> ค่ะ (ขอบคุณค่ะ). ASR und LLM
    vertauschen beide oft. Nur wenn die Partikel am Satzteilende steht (kein Thai-Zeichen direkt dahinter);
    ครับ und alles andere bleibt unverändert."""
    if not text or not _TH_KA_ANY.search(text):
        return text

    def sub(m):
        nxt = text[m.end():m.end() + 1]
        if nxt and "฀" <= nxt <= "๿":
            return m.group(0)                                   # คะ/ค่ะ mitten im Wort oder Satz
        before = text[:m.start()].rstrip().split("\n")[-1]
        return "คะ" if _TH_Q_END.search(before) else "ค่ะ"
    return _TH_KA_ANY.sub(sub, text)
