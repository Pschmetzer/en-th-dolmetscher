"""Runde 21 (py1) Welle 1: kleine Robustheits- und Sprachausgabe-Korrekturen der Engine."""
import email.utils
import os
import time
import urllib.error

import pytest

import dolmetscher as d


class _E:
    def __init__(self, ra):
        self.headers = {"Retry-After": ra}


def test_run_tag_format():
    assert len(d._run_tag()) == 3


def test_run_tags_vary():
    assert len({d._run_tag() for _ in range(40)}) > 1


def test_volume_word():
    assert d.parse_command("volume three") == "volume:3"
    assert d.parse_command("speed to ten") == "speed:10"
    assert d.parse_command("volume 4") == "volume:4"


def test_retry_after_http_date():
    when = email.utils.formatdate(time.time() + 50, usegmt=True)
    assert 40 <= d._retry_after(_E(when)) <= 60
    assert d._retry_after(_E("kaputt")) == 30.0
    assert d._retry_after(_E("7")) == 7.0


def test_other_4xx_pauses_provider():
    d.reset_net_backoff()
    d._note_fail("google", urllib.error.HTTPError("u", 403, "x", {}, None))
    assert d._PROV["google"]["until"] > time.monotonic()
    d.reset_net_backoff()


def test_hallucination_accepts_generator():
    class S:
        compression_ratio = 1.0
        no_speech_prob = 0.99
        avg_logprob = -2.0
    assert d.looks_hallucinated("ok", 1.0, (s for s in [S()])) == "stille"
    assert d.looks_hallucinated("ok", 1.0, (s for s in [])) is None


def test_llm_reset_drops_client():
    d.LLM["client"] = object()
    d.llm_reset_backoff()
    assert d.LLM["client"] is None


def test_chunk_long_thai_no_cluster_split():
    text = "ก" * 5 + "เ" + "ก" * 20
    out = d.chunk_long([text], "th", limit=6)
    assert "".join(out) == text
    assert all(not o.endswith("เ") for o in out)


def test_phone_spoken_digitwise():
    assert d.speak_form("call 0812345678 now", "en") == "call 0 8 1 2 3 4 5 6 7 8 now"
    assert d.speak_form("1,000,000 baht", "en") == "1,000,000 baht"


def test_thai_abbrev_soi():
    assert "ซอย" in d.speak_form("ไป ซ. สุขุมวิท", "th")


def test_speak_cur_more_langs():
    assert d.speak_form("฿100", "ja") == "100 バーツ"
    assert d.speak_form("฿100", "it") == "100 baht"


def test_laugh_out_all_langs():
    for k in ("it", "tr", "pl", "nl", "uk", "vi", "ar", "hi"):
        assert k in d.LAUGH_OUT


def test_json_line_scrubs_path_fields():
    home = os.path.expanduser("~")
    assert home not in d._json_line("x", {"path": home + "/a/b"})


def test_oversize_reply_rejected(monkeypatch):
    class R:
        status = 200
        reason = "OK"
        headers = {}
        will_close = True

        def read(self, n=-1):
            return b"x" * (d.MAX_REPLY_BYTES + 1)

        def getheader(self, *_):
            return "text/html"

    class C:
        sock = None
        timeout = 1

        def request(self, *a, **k):
            pass

        def getresponse(self):
            return R()

        def close(self):
            pass

    ka = d.KeepAlive()
    monkeypatch.setattr(ka, "_take", lambda h, t: (C(), False))
    with pytest.raises(d.NotJSON):
        ka.get_json("https://x.test/a?q=1", 1)
