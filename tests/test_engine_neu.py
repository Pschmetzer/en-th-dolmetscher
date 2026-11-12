"""Neue Engine-Teile ohne Mikrofon, Lautsprecher und Netz: Übersetzungskette, Cache, Thai-Formen,
Satzteilung, Normalisierung, Halluzinationsfilter, Live-Steuerung, Sprecher-Warteschlange."""
import json
import queue
import threading
import time
import types
import urllib.error

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _iso(monkeypatch):
    class Null:
        def info(self, s):
            pass
    monkeypatch.setattr(d, "_logger", lambda: Null())
    monkeypatch.setattr(d, "_CACHE", d.collections.OrderedDict())
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setitem(d.LLM, "client", None)
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    return events


def _google(text):
    return {"x": 0, "data": [[[text, "src"]]]}


def test_translate_cache_skips_second_request(monkeypatch):
    calls = []

    def gj(url, timeout=0):
        calls.append(url)
        return [[["Hello", "x"]]]
    monkeypatch.setattr(d, "_get_json", gj)
    meta = {}
    assert d.translate("สวัสดี", "th", "en", meta=meta) == "Hello" and meta["provider"] == "google"
    meta = {}
    assert d.translate("สวัสดี ", "th", "en", meta=meta) == "Hello" and meta.get("cached")
    assert len(calls) == 1


def test_google_untranslated_falls_back_to_mymemory(monkeypatch):
    def gj(url, timeout=0):
        if "googleapis" in url:
            return [[["Hello there", "x"]]]          # kein Thai -> unübersetzt
        return {"responseData": {"translatedText": "สวัสดีครับ"}, "responseStatus": 200}
    monkeypatch.setattr(d, "_get_json", gj)
    meta = {}
    assert d.translate("Hello there", "en", "th", meta=meta) == "สวัสดีครับ"
    assert meta["provider"] == "mymemory"


def test_claude_used_when_enabled_and_falls_back(monkeypatch):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    seen = {}

    def fake_claude(text, src, dst, history, alts, polite):
        seen.update(history=history, alts=alts)
        return "I'm sleepy."
    monkeypatch.setattr(d, "claude_translate", fake_claude)
    meta = {}
    out = d.translate("ฉันม่วงนอน", "th", "en", history=(("en", "Hi", "สวัสดี"),), alts=("ฉันง่วงนอน",), meta=meta)
    assert out == "I'm sleepy." and meta["provider"] == "claude" and seen["alts"] == ("ฉันง่วงนอน",)

    def broken(*a):
        raise RuntimeError("timeout")
    monkeypatch.setattr(d, "claude_translate", broken)
    monkeypatch.setattr(d, "_get_json", lambda url, timeout=0: [[["Good night", "x"]]])
    meta = {}
    assert d.translate("ราตรีสวัสดิ์", "th", "en", meta=meta) == "Good night" and meta["provider"] == "google"


def test_claude_translate_builds_request(monkeypatch):
    sent = {}

    class Msgs:
        def create(self, **kw):
            sent.update(kw)
            return types.SimpleNamespace(stop_reason="end_turn",
                                         content=[types.SimpleNamespace(type="thinking"),
                                                  types.SimpleNamespace(type="text", text="“ง่วงนอนครับ”")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    out = d.claude_translate("I'm sleepy", "en", "th", history=[("th", "ไปไหน", "Where are you going?")],
                             alts=["I am sleepy"], polite="krub")
    assert out == "ง่วงนอนครับ"
    assert sent["model"] == d.LLM["model"] and sent["output_config"] == {"effort": "low"}
    body = sent["messages"][0]["content"]
    assert "ไปไหน" in body and "I am sleepy" in body and "ครับ" in body


def test_fix_thai_question_particle_female():
    assert d.fix_thai("ห้องน้ำอยู่ที่ไหนค่ะ", "ka") == "ห้องน้ำอยู่ที่ไหนคะ"
    assert d.fix_thai("ขอบคุณค่ะ", "ka") == "ขอบคุณค่ะ"
    assert d.fix_thai("ราคาเท่าไหร่ ไหมค่ะ", "ka").endswith("ไหมคะ")
    assert d.fix_thai("คุณ/ท่านสบายดีไหม", "krub") == "คุณสบายดีไหม"


def test_split_sentences():
    assert d.split_sentences("Short one.", "en") == ["Short one."]
    long_en = "This is the first sentence of a long answer. And here comes the second one, a bit longer. Third!"
    parts = d.split_sentences(long_en, "en")
    assert len(parts) >= 2 and " ".join(parts) == long_en
    long_th = "วันนี้อากาศดีมากเลยครับ เราไปเที่ยวทะเลกันไหม แล้วค่อยกลับมากินข้าวเย็นที่บ้าน"
    assert "".join(d.split_sentences(long_th, "th")).replace(" ", "") == long_th.replace(" ", "")


def test_normalize_caps_gain_and_peak():
    quiet = (np.random.default_rng(0).standard_normal(16000) * 0.001).astype(np.float32)
    out, pk = d.normalize(quiet)
    assert np.sqrt(np.mean(out ** 2)) <= 0.0101 + 1e-6          # höchstens 10x
    loud = np.full(16000, 0.5, dtype=np.float32)
    assert np.max(np.abs(d.normalize(loud)[0])) <= 0.95 + 1e-6


def test_hallucination_filter():
    seg = types.SimpleNamespace(compression_ratio=3.1)
    assert d.looks_hallucinated("ha ha ha ha ha ha", 2.0, [seg]) == "wiederholung"
    ok = types.SimpleNamespace(compression_ratio=1.2)
    assert d.looks_hallucinated("x" * 200, 1.0, [ok]) == "zu schnell"
    assert d.looks_hallucinated("Where is the station?", 2.0, [ok]) is None


def _eng():
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                              paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    e.stop_speaking = lambda: setattr(e, "stopped", True)
    e.say_phrase = lambda t, l: setattr(e, "phrase", (t, l))
    e.retranslate = lambda i, t, l: setattr(e, "fixed", (i, t, l))
    return e


def test_apply_control_live_settings(monkeypatch):
    monkeypatch.setattr(d, "SILENCE_END", 0.8)
    monkeypatch.setitem(d.VAD, "start", 0.5)
    e = _eng()
    assert d.apply_control(e, {"rate": 80, "volume": 5, "silence": 1.2, "sensitivity": "high",
                               "voice_th": "th-TH-PremwadeeNeural", "voice_en": "bad; rm -rf",
                               "earcons": True, "stop_speaking": True}) is None
    assert e.rate == 50 and e.volume == 2.0 and d.SILENCE_END == 1.2 and d.VAD["start"] == 0.3
    assert e.voices == {"en": None, "th": "th-TH-PremwadeeNeural"} and e.earcons and e.stopped
    job = d.apply_control(e, {"say": {"text": "Thank you", "lang": "en"}})
    job()
    assert e.phrase == ("Thank you", "en")
    d.apply_control(e, {"retranslate": {"id": "u3", "text": "ฉันง่วงนอน", "lang": "th"}})()
    assert e.fixed == ("u3", "ฉันง่วงนอน", "th")


def test_quietest_cut_finds_pause():
    N = d.StreamVAD.N
    loud = [np.full(N, 0.3, dtype=np.float32) for _ in range(100)]
    loud[80] = np.zeros(N, dtype=np.float32)
    assert d.quietest_cut(loud) == 81


def test_speaker_skips_when_far_behind(monkeypatch, _iso):
    played = []
    gate = threading.Event()

    class E:
        tts, mute, rate, volume = "say", False, 0, 1.0

        def voice_for(self, lang):
            return "x"

        def speak(self, text, lang, stream=None, on_start=None, boost=0, cancelled=None, local=None):
            gate.wait(2)
            on_start and on_start(0.1)
            played.append((text, boost))
    sp = d.Speaker(E())
    monkeypatch.setitem(d._QSTATE, "speaker", sp)
    for i in range(6):
        sp.add(f"s{i}", "en", f"u{i}")
    gate.set()
    sp.wait_idle(5)
    done = [kw for ev, kw in _iso if ev == "speak_done"]
    skipped = [x["id"] for x in done if x["skipped"]]
    assert skipped and "u5" not in skipped                       # das Neueste wird immer vorgelesen
    assert played[-1][0] == "s5" and any(b > 0 for _, b in played)   # Aufhol-Tempo
    assert len(done) == 6


def test_speaker_flush_reports_skipped(monkeypatch, _iso):
    gate = threading.Event()

    class E:
        tts, mute, rate, volume = "say", False, 0, 1.0

        def voice_for(self, lang):
            return "x"

        def speak(self, *a, **k):
            gate.wait(2)
    sp = d.Speaker(E())
    sp.add("a", "en", "a1")
    time.sleep(0.05)
    sp.add("b", "en", "b1")
    assert sp.flush()
    gate.set()
    sp.wait_idle(3)
    assert ("speak_done", {"id": "b1", "skipped": True, "interrupted": True}) in _iso


def test_stop_during_wait_cancels_part(monkeypatch, _iso):
    """Stopp, während noch auf den ersten Ton gewartet wird, bricht die Ausgabe ab (Review-Punkt 1)."""
    waiting, played = threading.Event(), []

    class E:
        tts, mute, rate, volume = "say", False, 0, 1.0

        def voice_for(self, lang):
            return "x"

        def speak(self, text, lang, stream=None, on_start=None, boost=0, cancelled=None, local=None):
            waiting.set()
            t = time.time()
            while time.time() - t < 2 and not cancelled():
                time.sleep(0.01)
            if not cancelled():
                played.append(text)
    sp = d.Speaker(E())
    long = "This is the first sentence of a long answer. And here comes the second one, a bit longer."
    sp.add(long, "en", "x1")
    assert waiting.wait(2)
    sp.flush()
    sp.wait_idle(3)
    assert played == []
    assert ("speak_done", {"id": "x1", "skipped": False, "interrupted": True}) in _iso
    assert not any(ev == "speaking" for ev, _ in _iso)


def test_alts_are_masked_without_log_text(monkeypatch):
    seen = []

    class L:
        def info(self, s):
            seen.append(json.loads(s))
    monkeypatch.setattr(d, "_logger", lambda: L())
    monkeypatch.setattr(d, "LOG_TEXT", False)
    d.log({"alts": ["geheim"], "lang": "th"})
    assert seen == [{"alts": ["<6 Zeichen>"], "lang": "th"}]


def test_claude_truncated_is_error(monkeypatch):
    class Msgs:
        def create(self, **kw):
            return types.SimpleNamespace(stop_reason="max_tokens",
                                         content=[types.SimpleNamespace(type="text", text="halb")])
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    with pytest.raises(RuntimeError, match="max_tokens"):
        d.claude_translate("x", "en", "th")


def test_work_loop_handles_audio_and_jobs(monkeypatch, _iso):
    """Regression: Audio-Tupel (numpy-Array vorn) dürfen nicht mit "job" verglichen werden –
    das ließ die Engine nach jedem gesprochenen Satz abstürzen."""
    seen = []

    class E:
        speaker = types.SimpleNamespace(pending=lambda: 0)

        def process(self, audio, speak=True, rms=None, uid=None, **kw):
            seen.append(("audio", audio.size, uid))
            if audio.size == 8000:
                raise RuntimeError("kaputt")
    q = queue.Queue()
    q.put((np.zeros(16000, dtype=np.float32), 0.05, time.time(), "vad"))
    q.put(("job", lambda: seen.append(("job",))))
    q.put((np.zeros(8000, dtype=np.float32), 0.05, time.time(), "vad"))
    q.put((np.zeros(4000, dtype=np.float32), 0.05, time.time(), "vad"))
    q.put(None)
    d.work_loop(E(), q, speak=False)
    assert [x[0] for x in seen] == ["audio", "job", "audio", "audio"]
    assert any(ev == "dropped" and kw.get("reason") == "fehler" for ev, kw in _iso)


def test_stt_caps_tokens_and_disables_temperature_fallback():
    """Regression: ohne Token-Grenze und mit Temperatur-Fallback brauchte ein 2-s-Satz 60 s."""
    seen = {}

    class M:
        def transcribe(self, audio, **kw):
            seen.update(kw)
            return iter([types.SimpleNamespace(text="สวัสดี ครับ", avg_logprob=-0.2)]), None
    e = types.SimpleNamespace(m=M(), m_en=None, m_th=M(), beam=3)
    text, lp, _ = d.Engine._stt(e, np.zeros(2 * d.SR, dtype=np.float32), "th")
    assert text == "สวัสดีครับ" and seen["temperature"] == 0.0 and seen["max_new_tokens"] <= 60
    d.Engine._stt(e, np.zeros(18 * d.SR, dtype=np.float32), "th")
    assert seen["max_new_tokens"] >= 250                      # lange Sätze passen hinein
    d.Engine._stt(e, np.zeros(2 * d.SR, dtype=np.float32), "en", quick=True)
    assert seen["beam_size"] == 1


def test_tts_cache_serves_without_request(monkeypatch):
    key = ("v", "+5%", "Thank you")
    monkeypatch.setitem(d.TTS_CACHE, key, b"MP3")
    st = d.EdgeStream("Thank you", "v", "+5%")
    assert st.cached == b"MP3" and st.futs == []
    assert st.first(0.1)[0] == b"MP3"


def test_race_falls_back_to_prepared_local_voice(monkeypatch, tmp_path):
    monkeypatch.setattr(d, "NULL_AUDIO", True)
    monkeypatch.setattr(d, "TTS_RACE", 0.2)
    aiff = tmp_path / "x.aiff"
    aiff.write_bytes(b"x")

    class SlowStream:
        voice, cached, text = "edge", None, "hi"

        def first(self, deadline=None):
            assert deadline == 0.2
            raise RuntimeError("edge-tts lieferte keine Audiodaten")

        def cancel(self):
            pass
    local = types.SimpleNamespace(voice="Samantha", ready_path=lambda timeout=6.0: str(aiff))
    started = []
    e = types.SimpleNamespace(mute=False, tts="edge", volume=1.0, rate=0)
    d.Engine.speak(e, "hi", "en", stream=SlowStream(), on_start=started.append, local=local)
    assert started, "lokale Stimme hat nicht übernommen"


def _fake_engine(calls):
    class Det:
        def detect_language(self, audio=None, language_detection_segments=2):
            calls.append("detect")
            return "en", 0.95, [("en", 0.95), ("de", 0.02)]
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.spk, e.lock, e.paused, e.awake_until = Det(), None, "auto", False, 0.0
    e.translate_dir = {"en": True, "th": True}

    def fake_stt(audio, lang, hotwords=None, model=None, quick=False):
        calls.append(("stt", lang, quick))
        return "Where is the station?", -0.2, [types.SimpleNamespace(compression_ratio=1.1)]
    e._stt = fake_stt
    e.deliver = lambda uid, lang, text, *a, **k: calls.append(("deliver", uid, text)) or (lang, text, "x")
    return e


def test_prerecognition_is_reused_only_for_same_version(monkeypatch):
    monkeypatch.setitem(d.FAST, "endpoint", True)
    calls = []
    e = _fake_engine(calls)
    audio = np.full(d.SR * 2, 0.05, dtype=np.float32)
    e.prerecognize("u1", 0, audio)
    assert d.EARLY_END.get("u1") == 0                     # Englisch mit Fragezeichen -> sofort fertig
    n = len(calls)
    e.process(audio, speak=False, uid="u1", version=0)
    assert calls[n:] == [("deliver", "u1", "Where is the station?")]   # keine zweite Erkennung
    e.prerecognize("u2", 0, audio)
    n = len(calls)
    e.process(audio, speak=False, uid="u2", version=1)    # weitergesprochen -> neu erkennen
    assert "detect" in calls[n:] and ("stt", "en", False) in calls[n:]
    assert "u1" not in d.PRE and "u2" not in d.PRE
