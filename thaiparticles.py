"""Thai-Höflichkeitspartikel, Sprechergeschlecht und Dehnungen (Runde 25: aus dolmetscher.py ausgelagert, dort
re-exportiert). Reine Funktionen ohne Zustand."""
import re

_TH_STRETCH = re.compile(r"([ก-ฺเ-ๅๆ])\1{2,}")                  # ค่าาา, ครับบบ: Dehnung (3+ gleiche Zeichen)


def thai_stretch(s):
    """Dehnungen normalisieren: ครับบบ -> ครับ, ค่าาา -> ค่า (3+ gleiche Konsonanten/Vokale -> eines)."""
    return _TH_STRETCH.sub(r"\1", s) if s else s


_TH_FEMALE = re.compile(r"ค่ะ|คะ(?!แนน|ยั้น|เน|น้า|นอง|นึง|ยอ)|ดิฉัน")
_TH_MALE = re.compile(r"ครับ|คับ|กระผม")


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
_TH_KRUB = re.compile(r"ครับผม|ครับ|(?<!บัง)คับ(?!แคบ|คั่ง|ข้อง|ขัน|ใจ|ที่)")


def fit_thai_particles(text, polite):
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
