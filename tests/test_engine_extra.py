import dolmetscher as d


def test_context_const():
    assert d.LLM["context"] == 8


def test_pronounce(tmp_path, monkeypatch):
    f = tmp_path / "p.txt"
    f.write_text("Kubernetes => Kuberneetis\nkaputt\n", encoding="utf-8")
    monkeypatch.setattr(d, "PRONOUNCE", [])
    d.load_pronounce(str(f))
    assert d.PRONOUNCE == [("Kubernetes", "Kuberneetis")]
    assert d.apply_pronounce("I like kubernetes.") == "I like Kuberneetis."
    monkeypatch.setattr(d, "PRONOUNCE", [])
    assert d.apply_pronounce("x") == "x"


def test_warm_translate_silent(monkeypatch):
    def boom(*a):
        raise OSError("x")
    monkeypatch.setattr(d, "_get_json", boom)
    d.warm_translate()
