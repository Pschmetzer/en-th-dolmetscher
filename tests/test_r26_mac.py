"""Runde 26, Mac-App: Textetabelle (de/en/th), Verdrahtung von Gruppenmodus, Quelle, Verlauf-Passwort, Schaltern, Latenz,
Aufteilung von Views.swift, Steuerfelder gegen die Engine."""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
ENGINE = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def rows():
    body = src("L10n+R26.swift")
    body = body[body.index("static let table") :]
    out = {}
    for m in re.finditer(r'"([A-Za-z0-9_]+)":\s*\[((?:"[a-z]{2}":\s*"(?:\\.|[^"\\])*",?\s*)+)\]', body):
        out[m.group(1)] = dict(re.findall(r'"([a-z]{2})":\s*"((?:\\.|[^"\\])*)"', m.group(2)))
    return out


def test_table_has_three_languages_and_matching_placeholders():
    thai = re.compile("[฀-๿]")
    ph = re.compile(r"%(?:\.\d+)?[@dfs]")
    t = rows()
    assert len(t) > 40
    for key, row in t.items():
        assert all(row.get(lg, "").strip() for lg in ("de", "en", "th")), key
        assert thai.search(row["th"]), key
        sets = {lg: sorted(ph.findall(x)) for lg, x in row.items()}
        assert sets["de"] == sets["en"] == sets["th"], (key, sets)


def test_used_keys_exist():
    t = rows()
    used = set()
    for f in APP.glob("*.swift"):
        used |= set(re.findall(r'R26T\.[tf]\("([a-z0-9_]+)"', f.read_text(encoding="utf-8")))
    used = {k for k in used if not k.endswith("_")}   # "exp_" + id / "lat_" + kind sind dynamisch (unten geprüft)
    assert used and used <= set(t), sorted(used - set(t))
    # dynamische Schlüssel der Schalter und Latenzzeilen
    from_ids = re.search(r"static let ids = \[(.*?)\]", src("ExperimentalLogic.swift"), re.S).group(1)
    for i in re.findall(r'"([a-z_]+)"', from_ids):
        assert f"exp_{i}" in t and f"exp_{i}_note" in t, i
    for k in ("stt", "tr", "sound"):
        assert f"lat_{k}" in t


def test_experimental_ids_are_engine_controls():
    ids = re.findall(r'"([a-z_]+)"', re.search(r"static let ids = \[(.*?)\]", src("ExperimentalLogic.swift"), re.S).group(1))
    assert ids == ["llm_stream", "llm_router", "defer", "parallel_alt", "stt_prompt", "speak_numbers"]
    for i in ids:
        assert f'"{i}"' in ENGINE, i
    # Fähigkeiten: die Engine meldet control:<Feld>
    assert '"control:"' in ENGINE or "control:" in ENGINE


def test_controls_sent_by_app_exist_in_engine():
    s = src("R26Model.swift")
    for k in ("group_speakers", "source", "history_password", "get_state"):
        assert f'"{k}"' in s, k
        assert f'"{k}"' in ENGINE, k


def test_engine_wiring():
    e = src("Engine.swift")
    assert "r26.engineReady(o)" in e and 'case "state": r26.handleState(o)' in e and 'case "hint": r26.handleHint(o)' in e
    assert "AudioSourceLogic.launchArgs(r26.source)" in e
    assert "engineEnvironment(historyPassword: history)" in e
    assert '"system_audio_missing": "err_system_audio_missing"' in e
    assert 'o["msg_en"] as? String' in e and "ErrorTextLogic.fallback" in e
    assert 'o["group_speaker"]' in e and "r26.resetSession()" in e
    # Passwort vor `history` senden
    assert e.index("r26.sendHistoryPassword()") < e.index('push(["history": history])')


def test_history_password_never_logged_or_in_file():
    paths = src("Paths.swift")
    assert "env[HistoryPasswordLogic.envName] = nil" in paths   # App-Umgebung wird nie durchgereicht
    m = src("R26Model.swift")
    assert "NSLog" not in m and "print(" not in m
    assert "SecItemAdd" in m and "writeFile" not in m and "write(to" not in m   # nur Schlüsselbund
    assert "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in m
    # CLI-Aufrufe des Verlaufs bekommen das Passwort, andere nicht
    assert "needsEnv(args: args)" in src("Profiles.swift")
    assert "DOLMETSCHER_HISTORY_PASSWORD" in ENGINE


def test_settings_and_views_wired():
    s = src("SettingsView.swift")
    assert "ExperimentalSettings(r: m.r26)" in s and "SourceAndGroupSection(r: m.r26)" in s
    assert "HistoryPasswordSection(r: m.r26)" in s
    assert "R26Banners(r: m.r26)" in "".join(src(f) for f in ("Views.swift", "ViewsBanners.swift", "ViewsToolbar.swift"))
    assert "GroupSpeakerMenu(r: m.r26)" in src("ViewsToolbar.swift")
    assert "GroupSpeakerDot(n: g)" in src("BubbleViews.swift")


def test_views_split_and_size():
    with open(APP / "Views.swift", encoding="utf-8") as f:   # roh lesen (conftest hängt sonst die Teile an)
        assert len(f.read().splitlines()) < 1000
    for n in ("ViewsToolbar.swift", "ViewsBanners.swift"):
        assert (APP / n).exists()
    # keine Struktur doppelt definiert
    names = []
    for f in ("Views.swift", "ViewsToolbar.swift", "ViewsBanners.swift"):
        with open(APP / f, encoding="utf-8") as fh:
            names += re.findall(r"^(?:final )?(?:struct|enum) ([A-Za-z]+)", fh.read(), re.M)
    assert len(names) == len(set(names))


def test_smoke_test_still_covers_windows():
    ids = re.findall(r'Entry\(id:\s*"([a-z]+)"', src("WindowCatalog.swift"))
    smoke = src("SmokeTest.swift")
    assert not [i for i in ids if f'case "{i}":' not in smoke]


def test_error_code_documented_and_localized():
    assert "system_audio_missing" in (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
    assert "err_system_audio_missing" in src("L10n.swift")


def test_review_fixes_in_place():
    assert "v.isFinite, v <= 1e12" in src("PriceLogic.swift")
    assert "stopWork?.cancel()" in src("R23SetViews.swift") and "onDisappear { tester.stop() }" in src("R23SetViews.swift")
    assert "onChange(of: current?.id)" in src("R24Views.swift")
    assert "=== window" in src("PartnerView.swift")
