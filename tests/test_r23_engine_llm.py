"""Runde 23: Claude-Aufruf (Pool, Router, Kosten, Cache-Zähler, Warmup, Few-Shot, Streaming, Namen)."""
import collections
import threading
import time
import types

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _fresh(monkeypatch):
    monkeypatch.setattr(d, "LLM_STATS", {"calls": 0, "input": 0, "cache_read": 0, "cache_write": 0, "output": 0,
                                         "last_t": 0.0, "warm_t": 0.0, "ttft": collections.deque(maxlen=20),
                                         "cache_told": False})
    monkeypatch.setattr(d, "ENTITIES", collections.OrderedDict())
    monkeypatch.setitem(d.LLM, "router", False)
    monkeypatch.setitem(d.LLM, "stream", False)
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "usd", 0.0)
    monkeypatch.setattr(d, "_spend_add", lambda usd: None)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "llm_over_budget", lambda: False)


def _msg(text="Hallo", **usage):
    return types.SimpleNamespace(stop_reason="end_turn", usage=types.SimpleNamespace(**usage),
                                 content=[types.SimpleNamespace(type="text", text=text)])


# 1-2: Pool aus Daemon-Threads
def test_daemon_pool_runs_in_daemon_threads_and_is_bounded():
    pool = d._DaemonPool(2, "t")
    gate, seen = threading.Event(), []

    def job(i):
        seen.append(threading.current_thread().daemon)
        gate.wait(2)
        return i
    futs = [pool.submit(job, i) for i in range(5)]
    time.sleep(0.1)
    assert len(pool.threads) <= 2
    gate.set()
    assert [f.result(2) for f in futs] == [0, 1, 2, 3, 4]
    assert all(seen)


def test_daemon_pool_hands_exceptions_to_future():
    pool = d._DaemonPool(1, "t")
    f = pool.submit(lambda: 1 / 0)
    with pytest.raises(ZeroDivisionError):
        f.result(2)
    assert pool.submit(lambda: 7).result(2) == 7            # Arbeiter lebt weiter


def test_claude_async_uses_pool_and_checks_answer(monkeypatch):
    monkeypatch.setattr(d, "claude_translate", lambda *a: "Hallo Welt")
    fut = d._claude_async("Hello world", "en", "de", (), (), "krub")
    assert fut.result(2) == "Hallo Welt"
    assert threading.current_thread().name not in [t.name for t in d._CLAUDE_POOL.threads]


# 3-4: Modell-Router
def test_router_off_by_default():
    assert d.route_model("x" * 500, ["alt"]) == "claude-haiku-5-5"


def test_router_sends_heavy_sentences_to_sonnet(monkeypatch):
    monkeypatch.setitem(d.LLM, "router", True)
    assert d.route_model("ok thanks") == "claude-haiku-5-5"
    assert d.route_model("x" * d.ROUTER_LONG_CHARS) == "claude-sonnet-5-5"
    assert d.route_model("short", ["other hypothesis"]) == "claude-sonnet-5-5"
    assert d.route_model("call 0812345678 at 5") == "claude-sonnet-5-5"
    assert d.route_model("a, b, c, d, e") == "claude-sonnet-5-5"


def test_router_leaves_other_models_alone(monkeypatch):
    monkeypatch.setitem(d.LLM, "router", True)
    monkeypatch.setitem(d.LLM, "model", "claude-opus-5-5")
    assert d.route_model("x" * 500) == "claude-opus-5-5"


def test_claude_translate_uses_routed_model_for_request_and_price(monkeypatch):
    monkeypatch.setitem(d.LLM, "router", True)
    sent = {}

    class Msgs:
        def create(self, **kw):
            sent.update(kw)
            return _msg("ok", input_tokens=1_000_000, output_tokens=0)
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    d.claude_translate("x" * 200, "en", "de")
    assert sent["model"] == "claude-sonnet-5-5"
    assert sent["timeout"] == d.llm_timeout("claude-sonnet-5-5")
    assert abs(d.LLM["usd"] - d.LLM_PRICE["claude-sonnet-5-5"][0]) < 1e-9    # Preis des benutzten Modells


# 5-7: Kosten, Cache-Zähler, Hinweis
def test_llm_cost_counts_cache_read_and_write():
    u = types.SimpleNamespace(input_tokens=1_000_000, cache_read_input_tokens=1_000_000,
                              cache_creation_input_tokens=1_000_000, output_tokens=1_000_000)
    pin, pout = d.LLM_PRICE["claude-haiku-5-5"]
    assert abs(d._llm_cost(u, "claude-haiku-5-5") - (pin + 0.1 * pin + 1.25 * pin + pout)) < 1e-9


def test_llm_cost_ignores_unreadable_usage_fields():
    u = types.SimpleNamespace(input_tokens=None, cache_read_input_tokens="x", output_tokens=True)
    assert d._llm_cost(u, "claude-haiku-5-5") == 0.0
    assert d._llm_cost(None, "unknown-model") == 0.0


def test_usage_stats_report_cache_share():
    d._note_usage(types.SimpleNamespace(input_tokens=100, cache_read_input_tokens=300,
                                        cache_creation_input_tokens=0, output_tokens=5), "m", ttft=0.2)
    s = d.llm_stats()
    assert s["calls"] == 1 and s["cache_read"] == 300 and s["cache_share"] == 0.75 and s["ttft_p50"] == 0.2


def test_inactive_prompt_cache_is_logged_once(monkeypatch):
    logged = []
    monkeypatch.setattr(d, "log", lambda x: logged.append(x))
    u = types.SimpleNamespace(input_tokens=10, output_tokens=1)
    for _ in range(d.CACHE_INACTIVE_AFTER + 3):
        d._note_usage(u, "m")
    assert sum(1 for x in logged if isinstance(x.get("llm"), str) and "prompt-cache" in x["llm"]) == 1


# 8-9: Few-Shot
def test_few_shot_only_for_english_thai():
    en_th = d._static_system(("en", "th"))
    assert "Examples (speech => translation)" in en_th and "{setting}" not in en_th
    assert "Examples (speech" not in d._static_system(("de", "th"))
    assert "Examples (speech" not in d._static_system(("en", "de"))
    assert d.llm_system(("en", "th")) is d.LLM_SYSTEM and "Examples (speech" not in d.LLM_SYSTEM


def test_system_blocks_cache_first_block_only():
    blocks = d._system_blocks("th")
    assert blocks[0]["cache_control"] == {"type": "ephemeral"} and "cache_control" not in blocks[1]


# 10-11: Warmup und Keepalive
def test_warmup_sends_one_token_and_counts_usage(monkeypatch):
    sent = {}

    class Msgs:
        def create(self, **kw):
            sent.update(kw)
            return _msg("x", input_tokens=700, cache_creation_input_tokens=0, output_tokens=1)
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda fn: fn()))
    assert d.llm_warmup() is True
    assert sent["max_tokens"] == 1 and sent["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert d.llm_stats()["calls"] == 0 and d.LLM["usd"] > 0          # Warmup zählt Kosten, nicht als Nutzung


@pytest.mark.parametrize("why", ["off", "paused", "budget", "no_key"])
def test_warmup_gated(monkeypatch, why):
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda fn: pytest.fail("kein Warmup")))
    if why == "off":
        monkeypatch.setitem(d.LLM, "on", False)
    elif why == "paused":
        monkeypatch.setitem(d.LLM, "skip_until", time.monotonic() + 60)
    elif why == "budget":
        monkeypatch.setattr(d, "llm_over_budget", lambda: True)
    else:
        monkeypatch.setattr(d, "llm_available", lambda: False)
    assert d.llm_warmup() is False


def test_warmup_not_repeated_within_30s(monkeypatch):
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda fn: None))
    assert d.llm_warmup() is True and d.llm_warmup() is False and d.llm_warmup(force=True) is True


def test_keepalive_only_while_conversation_is_active(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "llm_warmup", lambda force=False: calls.append(force) or True)
    now = time.monotonic() + 100000.0                          # CI-Rechner mit kurzer Laufzeit: nie negativ
    assert d.llm_keepalive(now) is False                       # noch nie gedolmetscht
    d.LLM_STATS["cache_write"] = 100                           # Cache greift
    d.LLM_STATS["last_t"] = now - (d.KEEPALIVE_AFTER_S + 5)
    assert d.llm_keepalive(now) is True and calls == [True]
    d.LLM_STATS["last_t"] = now - 10
    assert d.llm_keepalive(now) is False                       # Cache noch frisch
    d.LLM_STATS["last_t"] = now - (d.KEEPALIVE_WHILE_S + 5)
    assert d.llm_keepalive(now) is False                       # lange Pause: Cache ruhen lassen


def test_warmup_alone_never_starts_a_keepalive_cycle(monkeypatch):
    """Regression: der Warmup selbst darf nicht als „es wird gedolmetscht“ zählen, sonst feuert alle 4 min eine
    bezahlte Anfrage, solange die App offen ist."""
    n = []

    class Msgs:
        def create(self, **kw):
            n.append(1)
            return _msg("x", input_tokens=10, cache_read_input_tokens=500, output_tokens=1)
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    monkeypatch.setattr(d, "_BG_POOL", types.SimpleNamespace(submit=lambda fn: fn()))
    assert d.llm_warmup() is True
    assert d.LLM_STATS["last_t"] == 0.0 and d.LLM_STATS["calls"] == 0 and d.LLM_STATS["cache_read"] == 500
    later = time.monotonic() + d.KEEPALIVE_AFTER_S + 1
    assert d.llm_keepalive(later) is False and len(n) == 1


def test_keepalive_needs_an_engaged_prompt_cache(monkeypatch):
    monkeypatch.setattr(d, "llm_warmup", lambda force=False: pytest.fail("Cache greift nicht: nur Kosten"))
    now = time.monotonic() + 100000.0                          # CI-Rechner mit kurzer Laufzeit: nie negativ
    d.LLM_STATS["last_t"] = now - (d.KEEPALIVE_AFTER_S + 5)       # echte Nutzung, aber nie ein Cache-Treffer
    assert d.llm_keepalive(now) is False


def test_warm_translate_warms_claude(monkeypatch):
    called = []
    monkeypatch.setattr(d, "_get_json", lambda *a, **k: None)
    monkeypatch.setattr(d, "thai_active", lambda: False)
    monkeypatch.setattr(d, "llm_client", lambda: called.append("client"))
    monkeypatch.setattr(d, "llm_warmup", lambda force=False: called.append("warm"))
    d.warm_translate()
    assert called == ["client", "warm"]


# 12-14: Streaming und erste Teilphrase
@pytest.mark.parametrize("buf,lang,want", [
    ("", None, None),
    ("Hello there", None, None),                         # noch kein Satzzeichen
    ("Well, ok", None, None),                            # zu kurz
    ("I think that we should go, and then", None, "I think that we should go,"),
    ("It costs 3.5 baht per piece, fine", None, "It costs 3.5 baht per piece,"),
    ("It costs 3.5", None, None),                        # Dezimalpunkt, nichts dahinter
    ("ผมจะไปที่นั่น, แล้วก็", "th", "ผมจะไปที่นั่น,"),
    ("ครับ,", "th", None),                               # Satzzeichen noch am Ende: Zeichen könnte unterwegs sein
])
def test_first_clause(buf, lang, want):
    assert d.first_clause(buf, lang) == want


def test_stream_mode_collects_text_and_calls_on_clause(monkeypatch):
    monkeypatch.setitem(d.LLM, "stream", True)
    clauses = []

    class S:
        text_stream = iter(["I would like ", "a table, ", "please."])

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def get_final_message(self):
            return _msg("I would like a table, please.", input_tokens=5, output_tokens=7)

    class Msgs:
        def stream(self, **kw):
            return S()

        def create(self, **kw):
            pytest.fail("create nicht im Stream-Modus")
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    out = d.claude_translate("Ich möchte einen Tisch", "de", "en", on_clause=clauses.append)
    assert out == "I would like a table, please." and clauses == ["I would like a table,"]
    assert d.llm_stats()["ttft_p50"] is not None


def test_stream_mode_falls_back_to_create_without_stream_api(monkeypatch):
    monkeypatch.setitem(d.LLM, "stream", True)

    class Msgs:
        def create(self, **kw):
            return _msg("Hallo")
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    assert d.claude_translate("Hello", "en", "de") == "Hallo"


def test_stream_mode_keeps_effort_retry(monkeypatch):
    monkeypatch.setitem(d.LLM, "stream", True)
    monkeypatch.setitem(d.LLM, "no_effort_models", set())
    seen = []

    class Err(Exception):
        status_code = 400

    class S:
        text_stream = iter(["Hallo"])

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def get_final_message(self):
            return _msg("Hallo")

    class Msgs:
        def stream(self, **kw):
            seen.append("output_config" in kw)
            if "output_config" in kw:
                raise Err("effort")
            return S()
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    assert d.claude_translate("Hello", "en", "de") == "Hallo" and seen == [True, False]
    assert "claude-haiku-5-5" in d.LLM["no_effort_models"]


# 15-16: Namen der Sitzung
def test_entities_from_intro_and_midsentence():
    assert d.note_entities("Hi, my name is Somchai and I live in Chiang Mai", "en")
    assert "Somchai" in d.ENTITIES
    d.note_entities("We met Anna yesterday, then went to Phuket", "en")
    assert "Anna" in d.ENTITIES and "Phuket" in d.ENTITIES
    assert "Thai" not in d.ENTITIES and "Monday" not in d.ENTITIES


def test_entities_latin_words_in_thai_text_and_cap():
    d.note_entities("ผมชื่อ Somchai ครับ", "th")
    assert "Somchai" in d.ENTITIES
    for i in range(d.ENTITY_MAX + 5):
        d.note_entities(f"my name is Name{'abcdefghijklmnopqrstuvwxyz'[i % 26]}x", "en")
    assert len(d.ENTITIES) <= d.ENTITY_MAX


def test_entity_hint_only_with_history(monkeypatch):
    d.ENTITIES["Somchai"] = True
    sent = {}

    class Msgs:
        def create(self, **kw):
            sent.update(kw)
            return _msg("Hallo")
    monkeypatch.setattr(d, "llm_client", lambda: types.SimpleNamespace(messages=Msgs()))
    d.claude_translate("Hello", "en", "de")
    assert "Somchai" not in sent["messages"][0]["content"]             # ohne Verlauf: Cache-Schlüssel bleibt gültig
    d.claude_translate("Hello", "en", "de", history=[("en", "Hi", "Hallo")])
    assert "Somchai" in sent["messages"][0]["content"]
    d.clear_entities()
    assert d.entity_hint() == ""


def test_clear_context_forgets_entities_and_pending_deliveries():
    eng = d.Engine.__new__(d.Engine)
    eng.history = collections.deque()
    d.ENTITIES["Somchai"] = True
    gen = d._DELIVER["gen"]
    eng.speaker = None
    try:
        d.Engine.clear_context(eng)
    except Exception:                      # noqa: BLE001 – nur die beiden Zustände zählen hier
        pass
    assert not d.ENTITIES and d._DELIVER["gen"] == gen + 1
