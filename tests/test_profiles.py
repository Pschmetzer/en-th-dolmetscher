import numpy as np
import profiles


def test_error_rate_english_words():
    assert profiles.error_rate("Can you send the invoice", "can you send the invoice", "en") == 0
    assert profiles.error_rate("a b c d", "a x c d", "en") == 0.25


def test_error_rate_thai_chars_ignores_spaces():
    assert profiles.error_rate("ฉันง่วงนอน", "ฉัน ง่วง นอน", "th") == 0
    assert profiles.error_rate("ฉันง่วงนอน", "ฉันม่วงนอน", "th") > 0


def test_storage_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setattr(profiles, "PROFILE_DIR", str(tmp_path))
    profiles.save_profile({"name": "Nok", "lang": "th", "embedding": [0.1, 0.2], "vocab": []})
    assert [p["name"] for p in profiles.list_profiles()] == ["Nok"]
    p = profiles.set_vocab("Nok", ["Sukhumvit", " Siam ", ""])
    assert p["vocab"] == ["Sukhumvit", "Siam"]
    assert "embedding" not in profiles.public(p)
    assert profiles.delete_profile("Nok") and profiles.list_profiles() == []


def test_identify_threshold_and_margin():
    spk = profiles.SpeakerID.__new__(profiles.SpeakerID)
    spk.profiles = [{"name": "A", "lang": "en"}, {"name": "B", "lang": "th"}]
    spk.mat = np.eye(2, dtype=np.float32)
    audio = np.zeros(int(profiles.SR * 2), dtype=np.float32)
    spk.embed = lambda a: np.array([0.95, 0.31], dtype=np.float32)
    assert spk.identify(audio)[0]["name"] == "A"
    spk.embed = lambda a: np.array([0.6, 0.58], dtype=np.float32)      # too close to call
    assert spk.identify(audio)[0] is None
    assert spk.identify(audio[: profiles.SR])[0] is None                # too short
