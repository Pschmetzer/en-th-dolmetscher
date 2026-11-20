import dolmetscher as d


def test_particles_words():
    assert d.fit_thai_particles('เขาคะยั้นคะยอให้ไป', 'krub') == 'เขาคะยั้นคะยอให้ไป'
    assert d.thai_speaker_sex('ผมคะเนว่าจะถึงสามโมง') != 'female'
    assert d.fit_thai_particles('ได้ครับผม', 'ka').count('ค่ะ') == 1


def test_speak_thai_boundaries():
    assert d.speak_form('ประชุม 9.30 น. ครับ', 'th') == 'ประชุม 9.30 นาฬิกา ครับ'
    assert 'องศา' in d.speak_form('วันนี้ 30°Cค่ะ', 'th') and '°' not in d.speak_form('วันนี้ 30°Cค่ะ', 'th')
    assert 'บาท' in d.speak_form('ราคา 1,000฿ครับ', 'th')
    assert 'กรุงเทพมหานคร' in d.speak_form('ไปกทม.ครับ', 'th')


def test_million_order():
    assert d.speak_form('It costs $1.5 million', 'en') == 'It costs 1.5 million dollars'


def test_cache_clear_vs_save(monkeypatch, tmp_path):
    import threading, time
    f = tmp_path / "c.json"
    monkeypatch.setattr(d, "CACHE_FILE", str(f))
    d._CACHE_DISK["on"] = True
    d._cache_clear()
    d._CACHE[("hello", "en", "th", "mt", "")] = ("สวัสดี", "google")
    orig = d._write_private

    def slow(p, t):
        time.sleep(0.3)
        orig(p, t)
    monkeypatch.setattr(d, "_write_private", slow)
    th = threading.Thread(target=lambda: d._cache_save(force=True))
    th.start()
    time.sleep(0.1)
    d._cache_clear()
    th.join()
    d._CACHE_DISK["on"] = False
    assert not f.exists()
    assert not d._CACHE


def test_numbers_false_positives():
    assert not d.numbers_differ('The rent is 2500 baht per year', 'ค่าเช่าต่อปี 2500 บาท')
    assert not d.numbers_differ('We grow 15 varieties of rice', 'เราปลูกข้าว 15 พันธุ์')
    assert not d.numbers_differ('It will be 77-86°F today', 'วันนี้ 25-30 องศาเซลเซียส')


def test_refusal_not_for_speaker_cannot_translate():
    d._check_llm('ฉันไม่สามารถแปลเอกสารนี้ได้', "I can't translate this document.", 'en', 'th')


def test_mt_order(monkeypatch):
    calls = []
    monkeypatch.setattr(d, "google_translate", lambda t, s, ds: calls.append("g") or "G")
    monkeypatch.setattr(d, "mymemory_translate", lambda t, s, ds, e1=None, timeout=8.0: calls.append("m") or "M")
    try:
        assert d.set_mt_order("bogus") == ("google", "mymemory")
        assert d._mt_chain("hello", "en", "th", {}) == "G"
        d.set_mt_order("mymemory, google")
        meta = {}
        assert d._mt_chain("hello", "en", "th", meta) == "M" and meta["provider"] == "mymemory"
        monkeypatch.setattr(d, "mymemory_translate", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("x")))
        d._PROV["mymemory"]["until"] = 0
        assert d._mt_chain("hello", "en", "th", {}) == "G"
    finally:
        d.set_mt_order("")
        d._PROV["mymemory"]["until"] = 0
        d._PROV["google"]["until"] = 0
