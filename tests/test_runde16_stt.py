"""Runde 16: Spracherkennung – Floskel-Liste, Hotword-Liste, Stille-Halluzination, Gegenprobe (Fake-Modelle)."""
from types import SimpleNamespace

import pytest

import dolmetscher as d


@pytest.mark.parametrize("s", [
    "Thank you so much for watching!", "Thanks for watching, see you next time.", "Thank you for watching the video.",
    "Thanks for watching this video", "Thank you for watching. Bye!",
    "สวัสดีครับ ขอบคุณที่รับชม", "ขอบคุณสำหรับการรับชมครับ", "ขอบคุณทุกท่านที่รับชม", "ฝากติดตามด้วยนะครับ",
    "อย่าลืมกดติดตามช่อง", "ขอบคุณที่รับชมครับผม",
])
def test_abspann_floskeln_fallen_weg(s):
    assert d.is_junk(s) is True


@pytest.mark.parametrize("s", [
    "Thanks for watching the kids", "Thank you for watching my bag", "ขอบคุณที่ชม", "ขอบคุณครับ",
    "Thank you", "Please subscribe me to the list",
])
def test_echte_sprache_bleibt(s):
    assert d.is_junk(s) is False


def test_kurzes_thank_you_nur_bei_stille():
    assert d.is_junk("Thank you.", rms=0.001, dur=1.0) is True
    assert d.is_junk("Thank you.", rms=0.05, dur=1.0) is False
    assert d.is_junk("Thank you.") is False


def test_hotwords_satzzeichen_sind_dubletten():
    assert d.merge_hotwords(None, ["Pat", "pat", "PAT.", "Pat,"]) == "Pat"
    assert d.merge_hotwords("Somchai, Somchai", ["somchai", "Soi"]) == "Somchai, Soi"


def test_hotwords_ein_langes_wort_sperrt_den_rest_nicht():
    out = d.merge_hotwords("a b", ["x" * 400, "short"])
    assert out == "a b short"


def test_hotwords_ueberlaenge_bleibt_begrenzt():
    out = d.merge_hotwords(None, [f"wort{i}" for i in range(200)])
    assert len(out) <= d.HOTWORDS_MAX_CHARS


def _seg(text, nsp, lp=-1.5, cr=1.0):
    return SimpleNamespace(text=text, no_speech_prob=nsp, avg_logprob=lp, compression_ratio=cr)


def test_stille_halluzination_ueber_no_speech_prob():
    assert d.looks_hallucinated("Okay.", 2.0, [_seg("Okay.", 0.95)], "en") == "stille"
    assert d.looks_hallucinated("Okay.", 2.0, [_seg("Okay.", 0.95, lp=-0.1)], "en") is None   # sicher erkannt
    assert d.looks_hallucinated("Okay.", 2.0, [_seg("Okay.", 0.2)], "en") is None
    assert d.looks_hallucinated("Okay.", 2.0, [_seg("Okay.", 0.95), _seg("yes", 0.1)], "en") is None


def test_stille_wird_als_halluzination_gemeldet():
    assert d.drop_code("halluzination (stille)") == d.drop_code("halluzination (zu schnell)")


def test_gegenprobe_floskel_gewinnt_nicht():
    # Thai-Gegenprobe liefert „ขอบคุณที่รับชม“ mit besserer log-prob: darf den echten englischen Text nicht verdrängen
    assert d.is_junk("ขอบคุณที่รับชม") is True
    assert d.junk_candidate_wins("ขอบคุณที่รับชม", -0.2, "Where is the station", -0.9) is False
    assert d.junk_candidate_wins("ที่ไหนสถานี", -0.2, "Where is the station", -0.9) is True
    assert d.junk_candidate_wins("ที่ไหนสถานี", -1.2, "Where is the station", -0.9) is False
