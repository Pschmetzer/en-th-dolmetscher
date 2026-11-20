"""Sicherheits-Audit R21: Checkout ohne gespeicherte Zugangsdaten, dolmetscher://-Erlaubnis nur je Aufruf."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_checkout_ohne_gespeicherte_zugangsdaten():
    for wf in (ROOT / ".github" / "workflows").glob("*.yml"):
        text = wf.read_text(encoding="utf-8")
        n_checkout = len(re.findall(r"uses: actions/checkout@", text))
        n_off = len(re.findall(r"persist-credentials: false", text))
        assert n_checkout == n_off, wf.name


def test_url_schema_erlaubnis_wird_nicht_dauerhaft_gesetzt():
    src = (ROOT / "app" / "Extras.swift").read_text(encoding="utf-8")
    assert "set(true, forKey: Prefs.urlAllowed)" not in src


def test_ios_gespraechstext_nicht_oeffentlich_im_system_log():
    for f in (ROOT / "ios" / "Dolmetscher").glob("*.swift"):
        for ln in f.read_text(encoding="utf-8").splitlines():
            if re.search(r"\.(debug|info|error|notice|warning|fault)\(", ln) and "privacy: .public" in ln:
                # nur Sprachcodes, Fehlertexte und Zustände dürfen öffentlich sein, nie Satztexte
                bad = re.search(r"\\\((text|raw|translation|sentence|out)\b[^)]*privacy: \.public", ln)
                assert not bad, (f.name, ln)


def test_ios_kursabfrage_ohne_geteilten_cache():
    src = (ROOT / "ios" / "Dolmetscher" / "Tools.swift").read_text(encoding="utf-8")
    assert "URLSession.shared" not in src


def test_ios_kurscode_nur_ascii_buchstaben():
    src = (ROOT / "ios" / "Dolmetscher" / "Round7.swift").read_text(encoding="utf-8")
    assert "code.allSatisfy({ $0.isASCII && $0.isLetter })" in src
