"""Runde 23: Hedge, Vorab-Übersetzung, Cache in Bytes, früher Satzschluss, Thai-Uhrzeiten, Entkopplung der Übersetzung,
Rückübersetzung, Budget-Warnung, STT-Prompt."""
import collections
import json
import queue
import threading
import time
import types

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


@pytest.fixture(autouse=True)
def _fresh(monkeypatch):
    monkeypatch.setattr(d, "_CACHE", collections.OrderedDict())
    monkeypatch.setattr(d, "_CBYTES", {"id": None, "n": 0})
    monkeypatch.setattr(d, "ENTITIES", collections.OrderedDict())
    monkeypatch.setitem(d.LLM, "on", False)
    monkeypatch.setitem(d.LLM, "stream", False)
    monkeypatch.setitem(d.LLM, "router", False)
    monkeypatch.setitem(d.LLM, "hedge_s", None)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    yield
    d._cache_clear()


class _Fut:
    def __init__(self):
        self.ev = threading.Event()
        self.res = self.exc = None

    def set_result(self, r):
        self.res = r
        self.ev.set()

    def result(self, timeout=None):
        import concurrent.futures
        if not self.ev.wait(timeout):
            raise concurrent.futures.TimeoutError()
        if self.exc:
            raise self.exc
        return self.res

    def exception(self, timeout=None):
        return self.exc

    def done(self):
        return self.ev.is_set()

    def add_done_callback(self, fn):
        threading.Thread(target=lambda: (self.ev.wait(5), fn(self)), daemon=True).start()


# 17-19: Hedge parallel, Vorab-Übersetzung als Ersatz
def _llm_on(monkeypatch, fut):
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "hedge_s", 0.3)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "llm_over_budget", lambda: False)
    monkeypatch.setattr(d, "_llm_gate", lambda: True)
    monkeypatch.setattr(d, "_claude_async", lambda *a: fut)


def test_long_sentence_starts_google_immediately(monkeypatch):
    fut, started = _Fut(), []
    _llm_on(monkeypatch, fut)

    def mt(text, src, dst, meta, deadline=None):
        started.append(time.monotonic())
        meta["provider"] = "google"
        return "Übersetzung (g)"
    monkeypatch.setattr(d, "_mt_chain", mt)
    t0, meta = time.monotonic(), {}
    out = d._translate("x " * d.HEDGE_PARALLEL_CHARS, "en", "de", meta=meta)
    assert out == "Übersetzung (g)" and meta["provider"] == "google"
    assert started and started[0] - t0 < 0.2                      # lange vor dem Hedge (0,3 s) gestartet


def test_long_sentence_claude_still_wins_when_fast(monkeypatch):
    fut = _Fut()
    fut.set_result("Claude-Fassung")
    _llm_on(monkeypatch, fut)
    monkeypatch.setattr(d, "_mt_chain", lambda text, src, dst, meta, deadline=None: "Google-Fassung")
    meta = {}
    assert d._translate("x " * d.HEDGE_PARALLEL_CHARS, "en", "de", meta=meta) == "Claude-Fassung"
    assert meta["provider"] == "claude"


def test_short_sentence_does_not_start_google_early(monkeypatch):
    fut = _Fut()
    fut.set_result("Hallo")
    _llm_on(monkeypatch, fut)
    monkeypatch.setattr(d, "_HEDGE_POOL", types.SimpleNamespace(submit=lambda *a, **k: pytest.fail("kein Google")))
    assert d._translate("Hello", "en", "de", meta={}) == "Hallo"


def test_pretranslated_text_replaces_slow_claude(monkeypatch):
    fut = _Fut()                                                  # Claude kommt nie
    _llm_on(monkeypatch, fut)
    d._cache_put(d._cache_key("Hello", "en", "de", False, "krub"), ("Hallo (vorab)", "google"))
    monkeypatch.setattr(d, "_mt_chain", lambda *a, **k: pytest.fail("Google nicht nötig"))
    meta = {}
    assert d._translate("Hello", "en", "de", meta=meta) == "Hallo (vorab)"
    assert meta["provider"] == "google" and meta["cached"] is True
    fut.set_result("spät")                                        # aufräumen (Callback-Thread)


def test_pretranslate_caches_google_only(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "google_translate", lambda t, s, ds: calls.append(t) or "Guten Morgen")
    monkeypatch.setattr(d, "claude_translate", lambda *a, **k: pytest.fail("kein Claude"))
    assert d.pretranslate("good morning", "en", "de") is True
    assert d._cache_get(d._cache_key("good morning", "en", "de", False, "krub")) == ("Guten Morgen", "google")
    assert d.pretranslate("good morning", "en", "de") is False    # schon im Cache
    assert calls == ["good morning"]


@pytest.mark.parametrize("text", ["", "   ", "x" * 500, "555555", "haha"])
def test_pretranslate_skips_unsuitable_text(monkeypatch, text):
    monkeypatch.setattr(d, "google_translate", lambda *a: pytest.fail("nicht anfragen"))
    assert d.pretranslate(text, "th" if text == "555555" else "en", "de") is False


def test_pretranslate_respects_backoff_and_failure(monkeypatch):
    monkeypatch.setattr(d, "google_translate", lambda *a: "x")
    monkeypatch.setitem(d._PROV["google"], "until", time.monotonic() + 30)
    assert d.pretranslate("hello there", "en", "de") is False
    monkeypatch.setitem(d._PROV["google"], "until", 0.0)

    def boom(*a):
        raise RuntimeError("down")
    monkeypatch.setattr(d, "google_translate", boom)
    assert d.pretranslate("hello there", "en", "de") is False
    assert d._PROV["google"]["until"] == 0.0                      # spekulativ: kein Backoff ausgelöst


def test_engine_pretranslate_gated(monkeypatch):
    sub = []
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda *a, **k: sub.append(a)))
    eng = d.Engine.__new__(d.Engine)
    eng.translate_dir, eng.polite = {}, "krub"
    assert eng._pretranslate("hello there", "en") is True and sub[0][1:3] == ("hello there", "en")
    monkeypatch.setitem(d.PRETRANSLATE, "on", False)
    assert eng._pretranslate("hello there", "en") is False
    monkeypatch.setitem(d.PRETRANSLATE, "on", True)
    eng.translate_dir = {"en": False}
    assert eng._pretranslate("hello there", "en") is False       # Sprache wird nicht übersetzt
    eng.translate_dir = {}
    monkeypatch.setattr(d, "_backlog", lambda: d.DEGRADE_AT)
    assert eng._pretranslate("hello there", "en") is False       # Stau: keine Spekulation
    assert eng._pretranslate("", "en") is False


def test_pretranslate_never_in_private_mode_or_with_claude(monkeypatch):
    sub = []
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda *a, **k: sub.append(a)))
    monkeypatch.setattr(d, "google_translate", lambda *a: pytest.fail("kein Google im Privatmodus"))
    eng = d.Engine.__new__(d.Engine)
    eng.translate_dir, eng.polite = {}, "krub"
    monkeypatch.setitem(d.PRIVATE, "on", True)
    assert eng._pretranslate("hello there", "en") is False and d.pretranslate("hello there", "en", "de") is False
    monkeypatch.setitem(d.PRIVATE, "on", False)
    monkeypatch.setitem(d.LLM, "on", True)                        # Claude: halbfertige Fassungen nicht an Google
    assert eng._pretranslate("hello there", "en") is False and not sub


def test_hedge_google_runs_on_its_own_pool():
    assert d._HEDGE_POOL is not d._BG_POOL and d._HEDGE_POOL.size >= 1


def test_pool_grows_for_queued_tasks():
    pool = d._DaemonPool(3, "g")
    gate = threading.Event()
    futs = [pool.submit(gate.wait, 3) for _ in range(3)]          # direkt nacheinander: alle drei Arbeiter nötig
    time.sleep(0.1)
    assert len(pool.threads) == 3
    gate.set()
    assert all(f.result(2) for f in futs)


# 20-21: Cache in Bytes
def test_cache_evicts_by_bytes(monkeypatch):
    monkeypatch.setattr(d, "_CACHE_MAX_BYTES", 2000)
    for i in range(50):
        d._cache_put((f"text{i}", "en", "th", "mt", ""), ("ก" * 100, "google"))
    assert 1 <= len(d._CACHE) < 50
    assert d.cache_bytes() <= 2000 + d._entry_bytes(("text0", "en", "th", "mt", ""), ("ก" * 100, "g"))
    assert ("text49", "en", "th", "mt", "") in d._CACHE            # neueste bleibt, älteste gehen


def test_cache_keeps_single_oversized_entry_and_updates_in_place(monkeypatch):
    monkeypatch.setattr(d, "_CACHE_MAX_BYTES", 10)
    d._cache_put(("a", "en", "th", "mt", ""), ("x" * 100, "g"))
    assert len(d._CACHE) == 1
    d._cache_put(("a", "en", "th", "mt", ""), ("y" * 50, "g"))
    assert len(d._CACHE) == 1 and d._CBYTES["n"] == d.cache_bytes()


def test_cache_ignores_empty_translation():
    d._cache_put(("a", "en", "th", "mt", ""), ("   ", "g"))
    d._cache_put(("b", "en", "th", "mt", ""), None)
    assert not d._CACHE


def test_cache_count_limit_still_applies(monkeypatch):
    monkeypatch.setattr(d, "_CACHE_MAX", 5)
    for i in range(20):
        d._cache_put((f"t{i}", "en", "de", "mt", ""), ("x", "g"))
    assert len(d._CACHE) == 5


# 22-24: früher Satzschluss
@pytest.mark.parametrize("text,ok", [
    ("วันนี้อากาศดีมากเลยครับ", True),
    ("ขอบคุณมากเลยนะคะ", True),
    ("ขอบคุณค่ะ", False),                        # kurze Floskel: lieber abwarten
    ("คุณชื่ออะไรคะ?", True),
    ("ไปกินข้าวกันนะ", False),                  # นะ allein beendet auch Teilsätze
    ("ครับ", False),                            # zu kurz
    ("ผมอยากไปที่ตลาดแล้วก็", False),
    ("วันนี้ผมไปตลาดมาแล้วครับ...", False),
    ("", False),
])
def test_sentence_complete_th(text, ok):
    assert d.sentence_complete_th(text) is ok


def test_early_end_ok_per_language():
    assert d.early_end_ok("Where is the station?", "en", -0.2)
    assert not d.early_end_ok("Where is the station?", "en", -0.9)
    assert d.early_end_ok("วันนี้อากาศดีมากเลยครับ", "th", -0.3)
    assert not d.early_end_ok("วันนี้อากาศดีมากเลยครับ", "th", -0.55)      # Thai strenger
    assert d.early_end_ok("Wo ist der Bahnhof bitte?", "de", -0.3)
    assert not d.early_end_ok("Ich gehe jetzt nach Hause.", "de", -0.3)    # Punkt ist bei de nicht sicher
    assert not d.early_end_ok("Hola?", "es", -0.3)                         # zu kurz
    assert not d.early_end_ok("你好吗？", "zh", -0.1)


def test_prerecognize_early_end_for_thai_only_with_endpoint_flag(monkeypatch):
    class Det:
        def detect_language(self, audio, language_detection_segments=2):
            return None, None, [("th", 0.95), ("en", 0.02)]
    eng = d.Engine.__new__(d.Engine)
    eng.m_det, eng.lock, eng.m, eng.m_th, eng.beam = Det(), "auto", None, None, 1
    eng.spk, eng.translate_dir, eng.polite = None, {}, "krub"
    eng._stt = lambda a, lang, hotwords=None, model=None, quick=False: ("วันนี้อากาศดีมากเลยครับ", -0.2, [])
    monkeypatch.setattr(d, "PRE", {})
    monkeypatch.setattr(d, "EARLY_END", {})
    monkeypatch.setattr(d, "PRETRANSLATE", {"on": False})
    monkeypatch.setitem(d.FAST, "endpoint", False)
    eng.prerecognize("u1", 0, np.zeros(16000, dtype=np.float32))
    assert "u1" not in d.EARLY_END
    monkeypatch.setitem(d.FAST, "endpoint", True)
    eng.prerecognize("u2", 0, np.zeros(16000, dtype=np.float32))
    assert d.EARLY_END.get("u2") == 0


# 25-26: Thai-Uhrzeiten für Google
@pytest.mark.parametrize("src,want", [
    ("ตีสามแล้ว", "03:00 แล้ว"),
    ("เจอกันสองทุ่มนะ", "เจอกัน 20:00 นะ"),
    ("เจอกันบ่ายสองโมงครึ่ง", "เจอกัน 14:30"),
    ("บ่ายโมงตรง", "13:00 ตรง"),
    ("ห้าโมงเย็น", "17:00"),
    ("บ่ายสี่โมงเย็น", "16:00"),
    ("หกโมงเช้าครับ", "06:00 ครับ"),
    ("เที่ยงคืนนะ", "00:00 นะ"),
    ("ตี 5 ครึ่ง", "05:30"),
    ("3 ทุ่มครึ่ง", "21:30"),
])
def test_th_times_for_mt(src, want):
    assert d.th_times_for_mt(src) == want


@pytest.mark.parametrize("src", ["สองโมง", "ตีกัน", "ตีหก", "ฉันชอบกินข้าว", "บ่ายเจ็ดโมง", "สิบสามทุ่ม", ""])
def test_th_times_for_mt_leaves_ambiguous_and_other_text(src):
    assert d.th_times_for_mt(src) == src


def test_mt_rewrites_times_only_for_thai_source():
    seen = []
    fn = lambda text, src, dst, *e: seen.append(text) or "x"       # noqa: E731
    d._mt(fn, "เจอกันตีสาม", "th", "en")
    d._mt(fn, "see you at ตีสาม", "en", "th")
    assert seen == ["เจอกัน 03:00", "see you at ตีสาม"]


# 27: Thai teilt früher
def test_split_sentences_thai_min_len_default_and_explicit():
    th = "สวัสดีครับ วันนี้อากาศดีมากเลย ผมอยากไปเดินเล่นที่สวน"
    assert d.split_min_len("th") < 60 <= d.split_min_len("en") == 60
    assert len(d.split_sentences(th, "th")) >= 2                    # mit 36 geteilt
    assert d.split_sentences(th, "th", min_len=200) == [th]          # explizit unverändert
    en = "Hello there my friend. It is a nice day today, isn't it? Let us go."
    assert d.split_sentences(en, "en") == d.split_sentences(en, "en", min_len=60)


# 28-30: Entkopplung vom Arbeits-Thread
def test_deliver_later_keeps_order_and_drain_waits(ev):
    order = []

    def job(i):
        time.sleep(0.05 * (3 - i))
        order.append(i)
    for i in range(3):
        d.deliver_later(f"u{i}", job, i)
    assert d.deliver_drain(5) is True
    assert order == [0, 1, 2] and d._DELIVER["pending"] == 0


def test_deliver_later_drops_after_clear_and_reports(ev):
    gate = threading.Event()
    ran = []
    d.deliver_later("u0", lambda: gate.wait(2))
    d.deliver_later("u1", lambda: ran.append("u1"))
    d._DELIVER["gen"] += 1                                          # „Gespräch löschen“ während der Wartezeit
    gate.set()
    assert d.deliver_drain(5)
    assert ran == [] and ("dropped", {"id": "u1", "code": "stopped", "reason": "gestoppt"}) in ev


def test_deliver_later_survives_exceptions(ev):
    d.deliver_later("u0", lambda: 1 / 0)
    assert d.deliver_drain(5)
    assert any(e == "dropped" and kw["code"] == "error" for e, kw in ev)
    out = []
    d.deliver_later("u1", lambda: out.append(1))
    assert d.deliver_drain(5) and out == [1]


def test_deliver_drain_times_out():
    gate = threading.Event()
    d.deliver_later("u0", gate.wait, 3)
    assert d.deliver_drain(0.1) is False
    gate.set()
    assert d.deliver_drain(5)


def _run_loop(eng, items):
    q = queue.Queue()
    for it in items:
        q.put(it)
    q.put(None)
    d.work_loop(eng, q, speak=False)


def test_work_loop_passes_defer_only_when_enabled_and_supported(monkeypatch, ev):
    seen = []

    class Plain:
        speaker = types.SimpleNamespace(pending=lambda: 0)

        def process(self, audio, speak=True, rms=None, uid=None, **kw):
            seen.append("defer" in kw)

    class Defer(Plain):
        supports_defer = True
    audio = (np.zeros(16000, dtype=np.float32), 0.05, time.time(), "vad")
    _run_loop(Defer(), [audio])
    monkeypatch.setitem(d.DEFER, "on", True)
    _run_loop(Plain(), [audio])
    _run_loop(Defer(), [audio])
    assert seen == [False, False, True]


def test_work_loop_drains_deferred_before_jobs(monkeypatch, ev):
    order = []
    gate = threading.Event()
    d.deliver_later("u0", lambda: (gate.wait(2), order.append("deliver")))
    threading.Timer(0.1, gate.set).start()
    _run_loop(types.SimpleNamespace(speaker=None), [("job", lambda: order.append("job"))])
    assert order == ["deliver", "job"]


def test_process_defer_hands_delivery_to_worker(monkeypatch, ev):
    called = []
    eng = d.Engine.__new__(d.Engine)
    eng.deliver = lambda *a, **k: called.append((threading.current_thread().name, a[0]))
    assert d.Engine.supports_defer is True
    d.deliver_later("u9", eng.deliver, "u9", "en", "hi", 0.0, 0.1)
    assert d.deliver_drain(5) and called and called[0][1] == "u9" and called[0][0].startswith("deliver")


# 31-32: Rückübersetzung per Claude für Kritisches
@pytest.mark.parametrize("text,crit", [
    ("The room costs 1500 baht", True), ("I am allergic to peanuts", True), ("ผมแพ้ถั่ว", True),
    ("ช่วยด้วย ฉุกเฉิน", True), ("Where is the bathroom", False), ("I have 2 sisters", False), ("", False),
])
def test_is_critical_text(text, crit):
    assert d.is_critical_text(text) is crit


def _back(monkeypatch, ev, out):
    monkeypatch.setattr(d, "_BACK_SLOTS", threading.BoundedSemaphore(2))
    th = []
    real = threading.Thread
    monkeypatch.setattr(d.threading, "Thread", lambda *a, **k: th.append(real(*a, **k)) or th[-1])
    d.back_translate_async("u1", out, "th", "en")
    th[0].join(3)
    return [kw for e, kw in ev if e == "back"]


def test_back_translation_uses_claude_for_critical_text(monkeypatch, ev):
    monkeypatch.setattr(d, "claude_back", lambda text, src, dst: "Room costs 1500 baht")
    monkeypatch.setattr(d, "google_translate", lambda *a: pytest.fail("Google nicht nötig"))
    assert _back(monkeypatch, ev, "ห้องราคา 1500 บาท") == [{"id": "u1", "text": "Room costs 1500 baht", "lang": "en"}]


def test_back_translation_non_critical_stays_on_google(monkeypatch, ev):
    monkeypatch.setattr(d, "claude_back", lambda *a: pytest.fail("kein Claude"))
    monkeypatch.setattr(d, "google_translate", lambda *a: "Where is the bathroom")
    assert _back(monkeypatch, ev, "ห้องน้ำอยู่ไหน")[0]["text"] == "Where is the bathroom"


def test_back_translation_falls_back_to_google_when_claude_fails(monkeypatch, ev):
    def boom(*a):
        raise RuntimeError("claude down")
    monkeypatch.setattr(d, "claude_back", boom)
    monkeypatch.setattr(d, "google_translate", lambda *a: "costs 1500")
    assert _back(monkeypatch, ev, "ราคา 1500")[0]["text"] == "costs 1500"


def test_claude_back_gated(monkeypatch):
    monkeypatch.setitem(d.LLM, "on", False)
    assert d.claude_back("x", "th", "en") is None
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "_llm_gate", lambda: True)
    monkeypatch.setattr(d, "llm_over_budget", lambda: True)
    assert d.claude_back("x", "th", "en") is None


# 33: Budget-Warnung zweistufig
def test_budget_warns_at_80_and_95_once_each(monkeypatch, ev, tmp_path):
    monkeypatch.setattr(d, "LLM_SPEND_FILE", str(tmp_path / "s.json"))
    monkeypatch.setattr(d, "_SPEND", {"month": d._month(), "usd": 8.2, "warned": None})
    monkeypatch.setitem(d.LLM, "budget", 10.0)
    assert d.llm_over_budget() is False and d.llm_over_budget() is False
    assert sum(1 for e, _ in ev if e == "llm_budget_warn") == 1
    d._SPEND["usd"] = 9.6
    assert d.llm_over_budget() is False and d.llm_over_budget() is False
    assert sum(1 for e, _ in ev if e == "llm_budget_warn") == 2
    d._SPEND["usd"] = 10.5
    assert d.llm_over_budget() is True


def test_budget_jump_straight_to_95_warns_once(monkeypatch, ev, tmp_path):
    monkeypatch.setattr(d, "LLM_SPEND_FILE", str(tmp_path / "s.json"))
    monkeypatch.setattr(d, "_SPEND", {"month": d._month(), "usd": 9.7, "warned": None})
    monkeypatch.setitem(d.LLM, "budget", 10.0)
    d.llm_over_budget()
    d.llm_over_budget()
    assert sum(1 for e, _ in ev if e == "llm_budget_warn") == 1


# 34: STT initial_prompt
def test_stt_prompt_opt_in_and_short(monkeypatch):
    d.ENTITIES.update({"Somchai": True, "Anna": True})
    assert d.stt_prompt("en") == ""                                 # aus
    monkeypatch.setitem(d.STT_PROMPT, "on", True)
    assert d.stt_prompt("en") == "Somchai, Anna" and d.stt_prompt("de") == ""
    d.ENTITIES.clear()
    for i in range(30):
        d.ENTITIES[f"Name{i:02d}xxxxxxxxxx"] = True
    assert len(d.stt_prompt("th")) <= d.STT_PROMPT_MAX
    d.ENTITIES.clear()
    assert d.stt_prompt("en") == ""


def test_stt_passes_initial_prompt_only_when_set(monkeypatch):
    got = []

    class M:
        def transcribe(self, audio, **kw):
            got.append(kw)
            return iter([]), None
    eng = d.Engine.__new__(d.Engine)
    eng.m, eng.m_th, eng.beam = M(), None, 1
    audio = np.zeros(16000, dtype=np.float32)
    eng._stt(audio, "en")
    assert "initial_prompt" not in got[-1]
    monkeypatch.setitem(d.STT_PROMPT, "on", True)
    d.ENTITIES["Somchai"] = True
    eng._stt(audio, "en")
    assert got[-1]["initial_prompt"] == "Somchai"
    eng._stt(audio, "en", quick=True)                               # Gegenprobe ohne Prompt
    assert "initial_prompt" not in got[-1]


# 35: parallele Gegenprobe (Opt-in) – Pool-Vertrag
def test_alt_stt_flag_default_off_and_pool_is_single_worker():
    assert d.PARALLEL_ALT["on"] is False and d.DEFER["on"] is False
    assert d._ALT_POOL.size == 1 and d._DELIVER_POOL.size == 1
    assert d._ALT_POOL.submit(lambda: 42).result(2) == 42


def test_defaults_keep_existing_behaviour():
    assert d.LLM["stream"] is False and d.LLM["router"] is False
    assert d.PRETRANSLATE["on"] is True and d.STT_PROMPT["on"] is False
    json.dumps(d.llm_stats())                                       # JSON-fähig fürs Log
