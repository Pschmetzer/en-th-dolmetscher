"""Runde 4: Protokoll-Ergänzungen (Nr. 66, 182, 184, 188, 190, 191) und Kontrakt mit App und Doku."""
import pathlib
import re
import types

import pytest

import dolmetscher as d
import history_store

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
SWIFT = "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift"))


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _eng():
    return types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                                 paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)


# --- 188: unbekannte Steuerfelder ----------------------------------------------------------------------------

def test_unbekanntes_steuerfeld_meldet_control_ignored(ev):
    d.apply_control(_eng(), {"volme": 1.0, "rate": 5})
    assert ("control_ignored", {"keys": ["volme"]}) in ev


def test_bekannte_felder_still(ev):
    d.apply_control(_eng(), {"rate": 5, "tr_en": True, "voice_th": "", "ping": 1})
    assert not [e for e, _ in ev if e == "control_ignored"]


def test_ctrl_keys_deckt_alles_ab_was_apply_control_liest():
    body = SRC[SRC.index("def apply_control("):SRC.index("def _run_all(")]
    read = set(re.findall(r'(?:_flag\(d, |d\.get\(|d\[)"([a-z_]+)"', body))
    read |= set(re.findall(r'"([a-z_]+)" in d\b', body))
    assert read and not read - d.CTRL_KEYS, sorted(read - d.CTRL_KEYS)


def _top_level_keys(src, start):
    """Schlüssel des Swift-Dictionary-Literals ab `start` (nach `send([`), nur auf oberster Ebene."""
    keys, depth, i = [], 0, start
    while i < len(src):
        c = src[i]
        if c == '"':
            j = src.index('"', i + 1)
            before = src[:i].rstrip()[-1:]          # Schlüssel stehen nach `[` oder `,` (nicht im ?: -Ausdruck)
            if depth == 0 and before in ("[", ",", "") and re.match(r'\s*:', src[j + 1:]):
                keys.append(src[i + 1:j])
            i = j + 1
            continue
        if c in "[(":
            depth += 1
        elif c in "])":
            if depth == 0:
                break
            depth -= 1
        i += 1
    return keys


def test_app_sendet_nur_bekannte_steuerfelder():
    sent = set()
    for m in re.finditer(r'(?:send|push)\(\[', SWIFT):
        sent |= {k for k in _top_level_keys(SWIFT, m.end()) if re.fullmatch(r"[a-z_]+", k)}
    assert {"llm", "mic", "output_device", "rate", "volume"} <= sent
    assert not sent - d.CTRL_KEYS, sorted(sent - d.CTRL_KEYS)


# --- 190: llm-Ereignis ---------------------------------------------------------------------------------------

def test_llm_meldet_verfuegbarkeit(ev, monkeypatch):
    monkeypatch.setattr(d, "llm_available", lambda: False)
    monkeypatch.setitem(d.LLM, "on", False)
    d.apply_control(_eng(), {"llm": True})
    assert ("llm", {"on": True, "available": False}) in ev


# --- 191: Verlauf-Fehler -------------------------------------------------------------------------------------

def test_history_fehler_wird_gemeldet(ev, monkeypatch):
    rec = history_store.Recorder()
    monkeypatch.setattr(history_store, "RECORDER", rec)

    def boom(*a, **k):
        raise OSError("Platte voll")
    monkeypatch.setattr(history_store, "Store", boom)
    d.history_enable(True, 7)
    assert rec.on is False and ev[-1][1]["code"] == "history_failed"


def test_history_days_ungueltig(ev, monkeypatch, tmp_path):
    rec = history_store.Recorder()
    monkeypatch.setattr(history_store, "RECORDER", rec)
    real = history_store.Store
    monkeypatch.setattr(history_store, "Store", lambda: real(str(tmp_path / "h.db")))
    d.history_enable(True, -1)
    assert [k["code"] for e, k in ev if e == "error"] == ["history_days_invalid"] and rec.on
    ev.clear()
    d.history_enable(True, 0)                  # 0 = nie löschen: kein Fehler
    d.history_enable(True, None)
    assert not [e for e, _ in ev if e == "error"]


def test_offline_uebersetzung_meldet_nicht_online():
    """Nr. 28/165: ein Apple-Ergebnis heißt „kein Netz“ – sonst meldete die App „Internet wieder da“."""
    assert 'net_state("translate", meta.get("provider") != "apple")' in SRC


def test_history_schreibfehler_einmal_melden(monkeypatch):
    calls = []
    rec = history_store.Recorder()
    rec.on, rec.on_error = True, lambda: calls.append(1)
    rec.store = types.SimpleNamespace(add=lambda *a, **k: (_ for _ in ()).throw(OSError("voll")))
    rec.utt({"text": "a"})
    rec.utt({"text": "b"})
    assert calls == [1] and rec.on is False


# --- 182: Nachlernen sichtbar und zurücksetzbar ---------------------------------------------------------------

def test_reset_learning_steuerfeld(ev):
    eng = _eng()
    eng.spk = types.SimpleNamespace(reset_learning=lambda n: n == "Pat")
    d.apply_control(eng, {"reset_learning": "Pat"})
    d.apply_control(eng, {"reset_learning": "Nobody"})
    d.apply_control(eng, {"reset_learning": 5})
    assert ("learning_reset", {"name": "Pat", "ok": True}) in ev
    assert ("learning_reset", {"name": "Nobody", "ok": False}) in ev
    assert ev[-1][1].get("code") == "profile_name_invalid"


def test_learn_auto_meldet_profile_adapted(ev, monkeypatch):
    e = d.Engine.__new__(d.Engine)
    e.spk = types.SimpleNamespace(me=lambda: {"name": "Pat"}, partner=lambda: None, learn=lambda n, emb, w: True)
    e._learn_auto("me", {"role_how": "profil ich", "sim_me": 0.99}, 10.0, [0.1])
    assert ("profile_adapted", {"name": "Pat", "role": "me"}) in ev


def test_profile_stdin_reset_learning_wird_gelesen():
    assert 'req.get("reset_learning")' in SRC and '"reset_learning": p.name' in SWIFT


# --- 184: Profilfehler mit Code ------------------------------------------------------------------------------

def test_profilfehler_tragen_codes():
    body = SRC[SRC.index("def profile_cli("):SRC.index("def _flag(")]
    assert not re.search(r'emit\("error", msg=', body)
    for code in ("profile_name_invalid", "profile_invalid", "profile_not_found", "profile_delete_failed"):
        assert f'"{code}"' in SWIFT, code


# --- 66: retry_in_s -------------------------------------------------------------------------------------------

def test_translate_retry_in(monkeypatch):
    now = d.time.monotonic()
    assert d.translate_retry_in() == 0
    d._PROV["google"]["until"] = now + 30
    d._PROV["mymemory"]["until"] = now + 12
    assert 11 <= d.translate_retry_in() <= 12
    d._OFFLINE["until"] = now + 40
    assert 39 <= d.translate_retry_in() <= 40
