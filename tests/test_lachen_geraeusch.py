from dolmetscher import looks_like_laugh_noise as f


def test_laughter_as_words_dropped():
    assert f("Recover, recover, recover.", 2.0, -0.5)
    assert not f("Okay, wait.", 1.4, -0.9)


def test_real_sentences_kept():
    assert not f("Where is the toilet?", 1.8, -0.3)
    assert not f("I need to fix it when we giggle that it doesn't count as words", 4.5, -0.9)
    assert not f("Thank you", 1.0, -0.3)
