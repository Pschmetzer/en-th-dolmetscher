"""Runde 6 (Mac-App und Protokoll-Kontrakt): Ideenliste Nr. 69/171/176 (Einstellungen), 360, 370, 371, 374, 377,
379, 380, 381, 382, 383, 384, 385, 396, 398, 399, 402, 413, 420. Quelltext-Tests (die App läuft in CI nicht)."""
import pathlib
import re

import dolmetscher as d
import profiles

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


def _src(name):
    return (APP / name).read_text(encoding="utf-8")


ENGINE, VIEWS, SETTINGS = _src("Engine.swift"), _src("Views.swift"), _src("SettingsView.swift")
BUBBLES, PARTNER, PROFILES = _src("BubbleViews.swift"), _src("PartnerView.swift"), _src("Profiles.swift")
APPMAIN, HOTKEYS, L10N = _src("DolmetscherApp.swift"), _src("HotKeys.swift"), _src("L10n.swift")


# ---- 69 / 171 / 176: Einstellungen senden die neuen Steuerfelder ---------------------------------------------

def test_app_sendet_neue_steuerfelder_und_startargumente():
    for field in ('send(["let_finish": letFinish])', 'send(["catch_up": catchUp])', 'send(["beam": beam])'):
        assert field in ENGINE
    for arg in ('"--let-finish"', '"--catch-up"', '"--beam"'):
        assert arg in ENGINE
    for key in ("$m.letFinish", "$m.catchUp", "$m.beam"):
        assert key in SETTINGS
    assert 'letFinish = 0; catchUp = "skip"; beam = 0' in ENGINE      # „Alle Einstellungen zurücksetzen“


def test_catch_up_werte_passen_zur_engine():
    tags = set(re.findall(r'Text\(L\.t\("catch_up_\w+"\)\)\.tag\("(\w+)"\)', SETTINGS))
    assert tags == set(d.CATCH_UP_MODES)


# ---- 360: Menüleisten-Symbol zeigt Laden, Problem, Offline --------------------------------------------------

def test_menueleiste_zeigt_mehr_zustaende():
    body = APPMAIN[APPMAIN.index("private var menuIcon"):APPMAIN.index("var body: some Scene")]
    for s in ("model.crashLog != nil", "model.loadingModel", "model.netDown.isEmpty", "menu_state_offline"):
        assert s in body


# ---- 370 / 371 / 381: Kontrast und Trefferflächen -----------------------------------------------------------

def _contrast(a, b):
    def lum(h):
        c = [((h >> s) & 255) / 255 for s in (16, 8, 0)]
        c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def test_farben_haben_genug_kontrast():
    light = int(re.search(r"static let success = adaptive\(light: 0x([0-9A-F]{6})", VIEWS).group(1), 16)
    assert _contrast(light, 0xFFFFFF) >= 4.5
    for name in ("fillGreen", "fillOrange", "fillRed", "fillBlue"):
        h = int(re.search(rf"static let {name} = Color\(nsColor: rgb\(0x([0-9A-F]{{6}})\)\)", VIEWS).group(1), 16)
        assert _contrast(h, 0xFFFFFF) >= 4.5, name


def test_kein_systemgruen_mehr_fuer_text():
    for name in ("Views.swift", "SettingsView.swift", "EnvSetup.swift", "Setup.swift"):
        assert not re.search(r"foregroundStyle\(\.green\)|Color\.green", _src(name)), name
    assert ".tint(queued ? LangStyle.fillOrange : m.active ? LangStyle.fillRed : LangStyle.fillGreen)" in VIEWS


def test_blasen_knoepfe_gross_und_sichtbar():
    assert ".frame(minWidth: 26, minHeight: 26)" in BUBBLES
    assert ".opacity(hovering ? 1 : 0.85)" in BUBBLES and ".opacity(hovering ? 1 : 0.5)" not in BUBBLES


# ---- 374: Höflichkeitsform im Hauptfenster und in der Menüleiste --------------------------------------------

def test_hoeflichkeit_im_hauptfenster_und_menue():
    assert VIEWS.count("selection: $m.polite") == 1 and APPMAIN.count("selection: $m.polite") == 1


# ---- 377: Beim Start zuhören, beim Anmelden starten ---------------------------------------------------------

def test_start_optionen():
    assert "if Self.ud.bool(forKey: Prefs.listenOnLaunch) { startListening() }" in ENGINE
    assert "SMAppService.mainApp.register()" in SETTINGS and "import ServiceManagement" in SETTINGS
    assert "listenOnLaunch]" in VIEWS                                 # gehört zu „zurücksetzen“


# ---- 379: globale Kürzel für Vorlesen abbrechen / letzte nochmal --------------------------------------------

def test_globale_kuerzel():
    assert 'name: "⌃⌥S") { [weak model] in model?.stopSpeaking() }' in HOTKEYS
    assert 'name: "⌃⌥R") { [weak model] in model?.replayLast() }' in HOTKEYS
    ids = re.findall(r"register\(id: (\d+)", HOTKEYS)
    assert len(ids) == len(set(ids))
    assert "⌃⌥S" in L10N and "⌃⌥R" in L10N


# ---- 380: L10n-Beobachter auf dem Haupt-Thread --------------------------------------------------------------

def test_l10n_beobachter_main():
    assert "didChangeNotification, object: nil, queue: .main)" in L10N
    assert "queue: nil" not in L10N[L10N.index("private static func start()"):L10N.index("static func sync")]


# ---- 382 / 383 / 384: VoiceOver-Aktionen, Blase löschen, Lesarten im Dialog ---------------------------------

def test_voiceover_aktionen_und_loeschen():
    for key in ("alt_reading", "save_phrase", "delete_bubble"):
        # seit Runde 8 als Liste (Name, Aktion) in einem Helfer, der sie per .accessibilityAction(named:) anhängt
        assert f'(L.t("{key}"), {{' in BUBBLES and ".accessibilityAction(named: a.0, a.1)" in BUBBLES
    assert 'L.reassign(Langs.reassignRole(u.lang)), {' in BUBBLES   # Nr. 41: Text mit Sprachnamen des Paars
    assert "func deleteItem(_ u: Utterance)" in ENGINE and "m.deleteItem(u)" in BUBBLES


def test_lesarten_im_korrekturdialog():
    sheet = BUBBLES[BUBBLES.index("struct CorrectSheet"):]
    assert "ForEach(Array(u.alts.enumerated())" in sheet and "text = alt" in sheet


# ---- 385: Partner-Ansicht drehen und zoomen ----------------------------------------------------------------

def test_partneransicht_drehen_und_zoomen():
    assert ".rotationEffect(.degrees(rotated ? 180 : 0))" in PARTNER
    assert "* CGFloat(zoom)" in PARTNER and '@AppStorage("partnerZoom")' in PARTNER


# ---- 396 / 398 / 420: Profile ------------------------------------------------------------------------------

def test_woerter_erst_nach_erfolg_verwerfen():
    assert "vocabEdit[p.name] = nil }" not in PROFILES
    assert "vocab_save_failed" in PROFILES and 'o["event"] as? String == "profile_saved"' in PROFILES


def test_assistent_sagt_an():
    body = PROFILES[PROFILES.index("private func handle("):PROFILES.index("struct ProfilesView")]
    assert body.count("Announcer.post(") >= 4
    assert '"✅").font(.system(size: 64)).accessibilityHidden(true)' in PROFILES


def test_enroll_codes_stimmen_mit_engine_ueberein():
    src = (ROOT / "profiles.py").read_text(encoding="utf-8")
    retry = set(re.findall(r'emit\("enroll_retry", [^)]*code="(\w+)"', src))
    failed = set(re.findall(r'emit\("enroll_failed", reason="[^"]*",\s*code="(\w+)"', src))
    app_retry = set(re.findall(r'"(\w+)": "enroll_\w+"', PROFILES[PROFILES.index("static let retryKeys"):
                                                                  PROFILES.index("static let failKeys")]))
    app_failed = set(re.findall(r'"(\w+)": "enroll_\w+"', PROFILES[PROFILES.index("static let failKeys"):]
                                .split("\n")[0]))
    assert retry == app_retry == {"too_short", "other_sentence", "skipped"}
    assert failed == app_failed == {"too_few", "inconsistent"}
    for c in retry | failed:
        assert f"`{c}`" in DOCS


def test_enroll_meldet_codes(monkeypatch):
    ev = []
    emit = lambda e, **kw: ev.append((e, kw))          # noqa: E731
    spk = type("S", (), {"embed": lambda self, a: None})()
    import numpy as np
    profiles.enroll("Pat", "en", lambda: np.zeros(10, dtype=np.float32), lambda a, lang: "", emit, spk)
    codes = [kw.get("code") for e, kw in ev if e in ("enroll_retry", "enroll_failed")]
    assert "too_short" in codes and "skipped" in codes and codes[-1] == "too_few"


# ---- 399 / 413 ---------------------------------------------------------------------------------------------

def test_beispielsatz_klickbar_und_pegel_in_einstellungen():
    assert 'm.say("Where is the toilet?", lang: "en")' in VIEWS
    mic = SETTINGS[SETTINGS.index("private struct MicSection"):]
    assert "LevelBar(meter: m.meter)" in mic.split("private func load()")[0]


# ---- 402: Fehlercode python_env_broken ---------------------------------------------------------------------

def test_app_erkennt_kaputte_umgebung_am_code():
    assert '"python_env_broken": "crash_env"' in ENGINE
    assert 'if code == "python_env_broken" { envBrokenReported = true }' in ENGINE
    assert "let envBroken = envBrokenReported ||" in ENGINE


# ---- Protokoll-Kontrakt Runde 6 ----------------------------------------------------------------------------

def test_protokoll_runde6_dokumentiert():
    sec = DOCS.split("## Runde 6 (Ideenliste)", 1)[1]
    for s in ("`let_finish`", "`catch_up`", "`beam`", "`state.latency`", "`utt.dur`", "`hotwords`", "`llm_hint`",
              "`python_env_broken`", "`DOLMETSCHER_TUNE`", "Schema 2"):
        assert s in sec, s
    for k in ("let_finish", "catch_up", "beam"):
        assert f"| `{k}` |" in DOCS                         # Tabelle der Steuerfelder
    assert "`latency` (siehe „Runde 6“)" in DOCS and "`dur` (s, Länge der Äußerung" in DOCS
    assert d.PROTOCOL == 1
