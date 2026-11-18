"""Round 19 (iPhone app): audio-session checks that run without Xcode (Swift tests: xcodebuild test)."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def test_texts_complete_and_registered():
    src = _src("Dolmetscher", "L10n+R19.swift")
    rows = {k: dict(re.findall(r'"(de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "((?:[^"\\]|\\.)*)"', body))
            for k, body in re.findall(r'"([a-z_]+)": \[(.*?)\],\n', src, re.S)}
    assert set(rows) == {"interrupt_resumed", "route_output_lost"}
    for key, row in rows.items():
        assert set(row) == set(LANGS) and all(v.strip() for v in row.values()), key
    l10n = _src("Dolmetscher", "L10n.swift")
    assert "round19]" in l10n and "round19.keys" in l10n


def test_route_and_interruption_use_the_policy():
    cap = _src("Dolmetscher", "AudioCapture.swift")
    assert "AudioSessionPolicy.routeAction" in cap
    model = _src("Dolmetscher", "Model.swift")
    assert model.count("AudioSessionPolicy.mayRebuild") == 2
    assert "AudioSessionPolicy.effectiveIdle" in model
    stop = model[model.index("func stop(endConversation"):]
    assert "interrupted = false" in stop[:300]
