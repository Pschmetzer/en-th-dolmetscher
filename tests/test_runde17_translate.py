"""Runde 17: Übersetzung – Glossar-Platzhalter und Thai-Partikel (Fake-Übersetzer)."""
import pytest

import dolmetscher as d


def _mt_with(monkeypatch, glossary, text, dst="th"):
    d.load_glossary(glossary)
    seen = []

    def fake(t, src, dst_, *extra):
        seen.append(t)
        return t                          # Fake-Dienst: gibt die geschützte Fassung unverändert zurück
    return d._mt(fake, text, "en", dst), seen


def test_glossarname_zerreisst_keine_email(monkeypatch):
    out, _ = _mt_with(monkeypatch, "Pat => แพท", "Write to pat@example.com please")
    assert "pat@example.com" in out


def test_glossarname_zerreisst_keine_url(monkeypatch):
    out, _ = _mt_with(monkeypatch, "Grab => แกร็บ", "See https://www.grab.com/th/pat?x=Grab now")
    assert "https://www.grab.com/th/pat?x=Grab" in out


def test_glossarname_ausserhalb_der_email_wird_weiter_ersetzt(monkeypatch):
    out, _ = _mt_with(monkeypatch, "Pat => แพท", "Pat wrote from pat@example.com")
    assert out.startswith("แพท") and "pat@example.com" in out


def test_klammerzahl_im_text_wird_nicht_als_platzhalter_gelesen(monkeypatch):
    out, _ = _mt_with(monkeypatch, "Pat => แพท", "Pat said see [1] and [2]")
    assert "see [1] and [2]" in out


@pytest.mark.parametrize("word", ["คะน้า", "ผัดคะน้า", "คับขัน", "คับใจ", "คับที่", "คะนอง"])
def test_partikel_anpassung_laesst_woerter_in_ruhe(word):
    assert d.fit_thai_particles(f"สั่ง{word}หน่อย", "krub") == f"สั่ง{word}หน่อย"
    assert d.fit_thai_particles(f"สั่ง{word}หน่อย", "ka") == f"สั่ง{word}หน่อย"


def test_partikel_echte_faelle_bleiben():
    assert d.fit_thai_particles("ขอบคุณค่ะ", "krub") == "ขอบคุณครับ"
    assert d.fit_thai_particles("ผัดคะน้าครับ", "ka") == "ผัดคะน้าค่ะ"
