"""Runde 21 (py1) Welle 4: Wiederholungs-Kürzung, Füllwörter weiterer Sprachen, Offline-Helfer-Zeilenpuffer."""
import os
import stat
import sys

import pytest

import dolmetscher as d


@pytest.mark.parametrize("text,expected", [
    ("Ja ja ja ja ja ja ja", "Ja Ja Ja"),
    ("ha ha ha ha ha ha", "ha ha ha"),
    ("ฮ่าฮ่าฮ่าฮ่าฮ่า", "ฮ่าฮ่าฮ่า"),
    ("okokokokokok", "okokok"),
    ("0808080808", "0808080808"),
    ("1111111", "1111111"),
])
def test_squash_repeats_keeps_script_spacing(text, expected):
    assert d.squash_repeats(text) == expected


@pytest.mark.parametrize("lang,text,expected", [
    ("it", "Ehm dove è la stazione", "dove è la stazione"),
    ("nl", "Uhm waar is het station", "waar is het station"),
    ("pl", "yyy gdzie jest dworzec", "gdzie jest dworzec"),
    ("ru", "Э, где вокзал", "где вокзал"),
    ("pt", "Hum onde fica o banheiro", "onde fica o banheiro"),
    ("tr", "eee tren nerede", "tren nerede"),
    ("hi", "उम्म स्टेशन कहाँ है", "स्टेशन कहाँ है"),
])
def test_fillers_other_languages(lang, text, expected):
    assert d.strip_fillers(text, lang) == expected


@pytest.mark.parametrize("lang,text", [
    ("it", "Dove è l'hotel"), ("nl", "Hoe laat is het"), ("ru", "Где метро"), ("pt", "Onde é a praia"),
])
def test_fillers_leave_normal_sentences(lang, text):
    assert d.strip_fillers(text, lang) == text


HELPER = """#!{py}
import sys, json
print(json.dumps({{"ready": True, "pairs": {{"en-th": "installed"}}}}), flush=True)
for line in sys.stdin:
    r = json.loads(line)
    # zwei Zeilen in einem Schreibvorgang: erst eine fremde id, dann die richtige
    a, b = {{"id": 0, "out": "alt"}}, {{"id": r["id"], "out": "สวัสดี"}}
    sys.stdout.write(json.dumps(a) + "\\n" + json.dumps(b) + "\\n")
    sys.stdout.flush()
"""


def test_offline_helper_reads_each_line(tmp_path):
    h = tmp_path / "translate-helper"
    h.write_text(HELPER.format(py=sys.executable))
    h.chmod(h.stat().st_mode | stat.S_IXUSR)
    mt = d.OfflineMT()
    try:
        assert mt.configure(str(h), True)
        assert mt.translate("hello", "en", "th") == "สวัสดี"
        assert mt.translate("again", "en", "th") == "สวัสดี"         # Puffer bleibt zwischen Aufrufen sauber
    finally:
        mt.close()


def test_offline_buffer_reset_on_close():
    mt = d.OfflineMT()
    mt._buf = b"rest"
    mt.close()
    assert mt._buf == b""
    assert os.path.exists(__file__)


@pytest.mark.parametrize("a,b,differ", [
    ("He is 6 feet tall", "สูง 1.8 เมตร", False),
    ("a 2 rai plot", "ที่ดิน 3,200 ตารางเมตร", False),
    ("a 5 inch screen", "จอ 13 ซม.", False),
    ("5 gallons", "19 ลิตร", False),
    ("8 feet", "3 เมตร", True),
    ("1,500 km", "1500 กิโลเมตร", False),
    ("1,500 km", "1600 กิโลเมตร", True),
    ("2 rai", "2,000 ตารางเมตร", True),
])
def test_more_units_in_number_check(a, b, differ):
    assert d.numbers_differ(a, b) is differ


def test_private_tmp_is_0700_even_with_open_umask(monkeypatch):
    monkeypatch.setitem(d._TMPDIR, "path", None)
    old = os.umask(0)
    try:
        p = d.private_tmp()
    finally:
        os.umask(old)
    try:
        assert stat.S_IMODE(os.stat(p).st_mode) == 0o700
        assert d.private_tmp() == p
    finally:
        os.rmdir(p)
        monkeypatch.setitem(d._TMPDIR, "path", None)


def test_enqueue_many_producers_never_blocks_and_keeps_important(monkeypatch):
    import queue
    import threading
    q = queue.Queue(maxsize=20)
    monkeypatch.setitem(d._OUT, "q", q)
    monkeypatch.setitem(d._OUT, "dropped", 0)
    done = []

    def producer(n):
        for i in range(300):
            d._enqueue("level", '{"event": "level", "rms": %d}' % i)
        d._enqueue("error", '{"event": "error", "n": %d}' % n)
        done.append(n)
    ts = [threading.Thread(target=producer, args=(n,), daemon=True) for n in range(6)]
    for t in ts:
        t.start()
    for t in ts:
        t.join(5)
    assert len(done) == 6, "ein Erzeuger blockiert bei voller Warteschlange"
    assert q.qsize() <= 20
    assert any(str(x).startswith('{"event": "error"') for x in list(q.queue))
