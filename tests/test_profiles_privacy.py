"""Stimmprofile: Löschen ohne Reste, alle Stimmdaten löschen, Hotwords, ein Embedding pro Äußerung."""
import numpy as np
import pytest

import profiles


@pytest.fixture
def pdir(tmp_path, monkeypatch):
    d = tmp_path / "profiles"
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(d))
    return d


def _p(name, **kw):
    return {"name": name, "lang": "en", "embedding": [1.0, 0.0], **kw}


def test_delete_profile_removes_backups_and_quarantine(pdir):
    profiles.save_profile(_p("Anna"))
    profiles.save_profile(_p("Anna!"))                    # Kollision -> Anna-<hash>.json, darf bleiben
    other = profiles._locate("Anna!")
    profiles._backup("Anna"); profiles._backup("Anna!")
    (pdir / "Anna.json.20260101T000000000000.bad").write_text("{kaputt")
    assert profiles.delete_profile("Anna")
    left = sorted(f.name for f in pdir.iterdir() if not f.name.startswith("."))
    assert not any(f.startswith("Anna.json") for f in left)
    assert profiles.get_profile("Anna!") is not None
    assert any(f.endswith(".bak") and f.startswith(other.rsplit("/", 1)[1]) for f in left)


def test_backup_keeps_only_last_two(pdir):
    profiles.save_profile(_p("B"))
    for _ in range(5):
        profiles._backup("B")
    assert len(list(pdir.glob("B.json.*.bak"))) == profiles.MAX_BACKUPS


def test_delete_all_profiles(pdir):
    assert profiles.delete_all_profiles() == 0            # Ordner fehlt: kein Fehler
    profiles.save_profile(_p("A")); profiles.save_profile(_p("T", lang="th"))
    profiles._backup("A")
    (pdir / "X.json.1.bad").write_text("x")
    (pdir / "notes.txt").write_text("fremd")
    assert profiles.delete_all_profiles() == 4
    assert profiles.list_profiles() == []
    assert sorted(f.name for f in pdir.iterdir()) == [".lock", "notes.txt"]


def test_cli_delete_all_dispatches_without_engine(pdir, monkeypatch, capsys):
    import dolmetscher as d
    profiles.save_profile(_p("A"))
    monkeypatch.setattr(d, "JSON", True)
    a = type("A", (), dict(profiles=False, delete_all_profiles=True, delete_profile=None, vocab=None,
                           enroll=None))()
    d.profile_cli(a)
    out = capsys.readouterr().out
    assert '"profiles_deleted_all"' in out and '"files": 1' in out
    assert profiles.list_profiles() == []


ME = {"name": "Me", "lang": "en", "vocab": ["Patong", "Nok"]}
HER = {"name": "Her", "lang": "th", "vocab": ["ภูเก็ต"]}
EN2 = {"name": "Bob", "lang": "en", "vocab": ["nok", "Karon"]}


@pytest.mark.parametrize("lang,who,role_p,want", [
    ("en", None, None, "Patong Nok Karon"),               # nichts erkannt: alle EN-Profile
    ("en", EN2, None, "nok Karon Patong"),                # erkanntes Profil zuerst, Duplikate raus
    ("en", None, ME, "Patong Nok Karon"),                 # Rolle "me" liefert ebenfalls Wörter
    ("th", None, HER, "ภูเก็ต"),
    ("th", ME, None, "ภูเก็ต"),                           # Profil anderer Sprache trägt nichts bei
])
def test_pick_hotwords(lang, who, role_p, want):
    assert profiles.pick_hotwords([ME, HER, EN2], lang, who, role_p) == want


def test_pick_hotwords_empty_and_capped():
    assert profiles.pick_hotwords([], "en") is None
    many = [{"name": "M", "lang": "en", "vocab": ["w%d" % i for i in range(200)]}]
    assert len(profiles.pick_hotwords(many, "en").split()) == profiles.MAX_HOTWORDS


def test_identify_and_classify_share_one_embedding():
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    s.profiles = [dict(ME, embedding=[1.0, 0.0]), dict(HER, embedding=[0.0, 1.0])]
    s.mat = np.array([[1.0, 0.0], [0.0, 1.0]], np.float32)
    calls = []

    def embed(a):
        calls.append(1)
        return np.array([1.0, 0.0], np.float32)
    s.embed = embed
    audio = np.zeros(profiles.SR * 2, np.float32)
    get = s.lazy_embed(audio)
    assert s.identify(audio, emb=get)[0]["name"] == "Me"
    r = s.classify(audio, None, emb=get)
    assert r["role"] == "me" and r["emb"] is not None
    assert len(calls) == 1
    assert s.hotwords("en", role="me") == "Patong Nok"


def test_lazy_embed_caches_none():
    s = profiles.SpeakerID.__new__(profiles.SpeakerID)
    calls = []
    s.embed = lambda a: calls.append(1)
    get = s.lazy_embed(np.zeros(10, np.float32))
    assert get() is None and get() is None and len(calls) == 1
