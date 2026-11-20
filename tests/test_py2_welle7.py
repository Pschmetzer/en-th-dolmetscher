"""Welle 7 (Notfall-Sätze beim Tempowechsel neu rendern, Zeitstempel beim Vergessen/Leeren)."""
import types

import dolmetscher as d


def _eng():
    return types.SimpleNamespace(translate_dir={}, voices={}, lock="auto", mute=False, rate=0, volume=1.0,
                                 stop_speaking=lambda: None)


def test_rate_change_rerenders_critical_phrases_when_preset_active(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "prerender_critical", lambda eng, p: calls.append(p))
    monkeypatch.setattr(d.presets, "load_all", lambda: {"hospital": {"id": "hospital"}})
    monkeypatch.setattr(d.PRESET, "active", "hospital")
    e = _eng()
    d.apply_control(e, {"rate": 10})
    assert calls == [{"id": "hospital"}] and e.rate == 10
    d.apply_control(e, {"rate": 10})                         # gleiches Tempo: nichts zu tun
    assert len(calls) == 1


def test_rate_change_without_preset_does_nothing(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "prerender_critical", lambda eng, p: calls.append(p))
    monkeypatch.setattr(d.PRESET, "active", None)
    d.apply_control(_eng(), {"rate": 20})
    assert calls == []


def test_prerender_critical_renders_equal_sentences_once(monkeypatch):
    rendered = []
    monkeypatch.setattr(d, "edge_prerender", lambda text, voice, rate: rendered.append((text, voice, rate)) or True)
    monkeypatch.setattr(d, "NET", {"tts": True, "translate": True})
    monkeypatch.setitem(d.PRIVATE, "on", False)

    class E:
        tts, mute, rate = "edge", False, 0
        voice_for = staticmethod(lambda lg: "v")
    same = {"critical": True, "en": "Call an ambulance.", "th": "เรียกรถพยาบาล"}
    t = d.prerender_critical(E, {"phrases": [same, dict(same)]})
    t.join(5)
    assert len(rendered) == len(set(rendered)) == 2           # ein Satz je Sprache, nicht doppelt


def test_forget_and_clear_drop_recent_stamps():
    e = d.Engine.__new__(d.Engine)
    e.history = d.collections.deque(maxlen=8)
    e.recent = d.collections.OrderedDict(a=(b"x", None))
    e._recent_t = {"a": 1.0}
    e._forget("a")
    assert "a" not in e.recent and "a" not in e._recent_t
    e.recent["b"] = (b"y", None)
    e._recent_t["b"] = 2.0
    e.texts, e._hist_ids, e.last = {"b": ("en", "t")}, {}, None
    e.speaker = None
    e.clear_context()
    assert not e._recent_t and not e.recent
