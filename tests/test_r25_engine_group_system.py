"""Runde 25: Gruppenmodus (Sprecher N) und Systemton-Quelle in der Engine verdrahtet."""
import types

import numpy as np
import pytest

import dolmetscher as d
import online_speakers as osp


@pytest.fixture(autouse=True)
def _state(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setitem(d.SOURCE, "kind", "mic")


def _stub(group=True, spk=None):
    import threading
    return types.SimpleNamespace(group_speakers=group, group=osp.OnlineSpeakers(), spk=spk, _grp_spk=None,
                                 _grp_lock=threading.Lock(), translate_dir={}, lock="auto", polite="krub",
                                 mute=False, paused=False, rate=0, volume=1.0, voices={}, earcons=False,
                                 stop_speaking=lambda: None, _group_embedder=lambda: None)


def _v(k, seed):
    b = np.zeros(32, dtype=np.float32)
    b[k * 4:k * 4 + 4] = 1
    return b + np.random.default_rng(seed).normal(0, 0.05, 32).astype(np.float32)


AUDIO = np.zeros(16000, dtype=np.float32)


def test_group_number_uses_precomputed_embedding_without_second_model_run():
    st = _stub()
    calls = []

    def get():
        calls.append(1)
        return _v(0, 1)
    assert d.Engine._group_number(st, AUDIO, get) == 1
    assert calls == [1]


def test_group_number_off_returns_none_and_does_not_touch_model():
    st = _stub(group=False)
    assert d.Engine._group_number(st, AUDIO, lambda: 1 / 0) is None


def test_group_number_none_embedding_is_none_not_a_new_speaker():
    st = _stub()
    assert d.Engine._group_number(st, AUDIO, lambda: None) is None
    assert st.group.speakers() == []


def test_group_number_swallows_model_errors(monkeypatch):
    st = _stub()
    assert d.Engine._group_number(st, AUDIO, lambda: 1 / 0) is None


def test_group_number_without_profiles_uses_own_embedder():
    st = _stub()
    st._group_embedder = lambda: types.SimpleNamespace(embed=lambda a: _v(2, 5))
    assert d.Engine._group_number(st, AUDIO) == 1


def test_group_embedder_prefers_profile_model():
    spk = object()
    assert d.Engine._group_embedder(_stub(spk=spk)) is spk


def test_group_embedder_failure_turns_mode_off_with_error(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    import profiles

    def boom():
        raise RuntimeError("kein modell")
    monkeypatch.setattr(profiles, "SpeakerID", boom)
    st = _stub()
    assert d.Engine._group_embedder(st) is None
    assert st.group_speakers is False
    assert ev[-1][0] == "error" and ev[-1][1]["code"] == "profiles_failed"
    assert "Gruppenmodus" in ev[-1][1]["msg"]


def test_group_embedder_is_created_once(monkeypatch):
    import profiles
    made = []
    monkeypatch.setattr(profiles, "SpeakerID", lambda: made.append(1) or object())
    st = _stub()
    a, b = d.Engine._group_embedder(st), d.Engine._group_embedder(st)
    assert a is b and made == [1]


def test_control_group_speakers_and_capability():
    st = _stub(group=False)
    assert "group_speakers" in d.CTRL_KEYS and "group_speakers" in d.CTRL_LOG_KEYS
    d.apply_control(st, {"group_speakers": True})
    assert st.group_speakers is True
    d.apply_control(st, {"group_speakers": "false"})
    assert st.group_speakers is False
    d.apply_control(st, {"group_speakers": [1]})
    assert st.group_speakers is False
    caps = d.capabilities()
    assert "control:group_speakers" in caps and "feature:group_speakers" in caps


def test_clear_context_restarts_group_numbers():
    st = _stub()
    d.Engine._group_number(st, AUDIO, lambda: _v(0, 1))
    d.Engine._group_number(st, AUDIO, lambda: _v(1, 2))
    assert st.group.speakers() == [1, 2]
    st.group.reset()
    assert d.Engine._group_number(st, AUDIO, lambda: _v(3, 3)) == 1


def test_clear_context_source_calls_group_reset():
    src = open(d.__file__, encoding="utf-8").read()
    i = src.index("def clear_context")
    assert "self.group.reset()" in src[i:i + 1200]


def test_utt_extra_field_and_label_wiring_in_process_source():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'dkw["extra"]["group_speaker"] = gnum' in src and "online_speakers.label(gnum)" in src


# ---- Systemton ------------------------------------------------------------------------------------------

MICS = [{"index": "0", "name": "MacBook Pro Microphone"}, {"index": "2", "name": "BlackHole 2ch"},
        {"index": "3", "name": "Loopback Audio"}]


def test_system_device_picks_first_loopback_index():
    assert d.system_device(MICS) == "2"


@pytest.mark.parametrize("mics", [[], None, [{"index": "0", "name": "USB Mic"}], [{"name": "x"}]])
def test_system_device_none_without_loopback(mics):
    assert d.system_device(mics) is None


def test_resolve_system_mic_survives_list_error(monkeypatch):
    def boom():
        raise RuntimeError("avhelper tot")
    monkeypatch.setattr(d, "list_mics", boom)
    assert d.resolve_system_mic() is None


def test_resolve_system_mic_looks_up_each_time(monkeypatch):
    seq = iter([MICS, [{"index": "5", "name": "blackhole 16ch"}]])
    monkeypatch.setattr(d, "list_mics", lambda: next(seq))
    assert d.resolve_system_mic() == "2" and d.resolve_system_mic() == "5"


def test_control_source_switches_and_rejects_garbage(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    st = _stub()
    d.apply_control(st, {"source": "system"})
    assert d.SOURCE["kind"] == "system"
    d.apply_control(st, {"source": "bluetooth"})
    assert d.SOURCE["kind"] == "system" and ("control_invalid", {"key": "source", "reason": "value"}) in ev
    d.apply_control(st, {"source": 5})
    d.apply_control(st, {"source": "mic"})
    assert d.SOURCE["kind"] == "mic"
    assert "source" in d.CTRL_KEYS


class _FakeMic(d.Mic):
    def __init__(self):
        super().__init__(types.SimpleNamespace(), "0", d.queue.Queue(), idle=True)


def test_mic_start_system_without_loopback_reports_code(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setattr(d, "list_mics", lambda: [{"index": "0", "name": "USB Mic"}])
    d.SOURCE["kind"] = "system"
    m = _FakeMic()
    assert m.start() is False
    assert [kw["code"] for e, kw in ev if e == "error"] == ["system_audio_missing"]
    assert "system_audio_missing" in d.ERROR_EN


def test_mic_start_system_opens_loopback_device(monkeypatch):
    seen = {}
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "list_mics", lambda: MICS)
    monkeypatch.setattr(d, "capture_cmd", lambda dev=None, **kw: seen.setdefault("dev", dev) and ["true"])
    monkeypatch.setattr(d, "hint", lambda code, **kw: seen.setdefault("hint", code))

    class Boom(Exception):
        pass

    def popen(*a, **k):
        raise Boom()
    monkeypatch.setattr(d.subprocess, "Popen", popen)
    d.SOURCE["kind"] = "system"
    m = _FakeMic()
    try:
        m.start(fatal=False)
    except Boom:
        pass
    assert seen["dev"] == "2" and seen["hint"] == "system_audio"


def test_mic_start_default_source_does_not_list_loopback(monkeypatch):
    monkeypatch.setattr(d, "list_mics", lambda: pytest.fail("Mikrofonmodus darf keine Loopback-Suche machen"))
    monkeypatch.setattr(d, "resolve_mic", lambda mic, strict=False: None)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    assert _FakeMic().start() is False


def test_source_start_argument_default_is_mic():
    import re
    src = open(d.__file__, encoding="utf-8").read()
    assert re.search(r'add_argument\("--source", choices=SOURCES, default="mic"', src)
    assert d.SOURCES == ("mic", "system")
