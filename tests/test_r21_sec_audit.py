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
