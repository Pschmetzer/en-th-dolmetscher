"""Runde 5 (Bau und Mac-App, Quelltext-Prüfungen): translate-helper im Bundle, Einstellungen, Preset-Hinweise,
kleine Mac-Punkte. Laufen ohne macOS (nur Text)."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = (ROOT / "build.sh").read_text(encoding="utf-8")
SWIFT = {f.name: f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift")}
ALL_SWIFT = "\n".join(SWIFT.values())
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")
HELPER = (ROOT / "tools" / "translate-helper" / "main.swift").read_text(encoding="utf-8")


# ---- build.sh -------------------------------------------------------------------------------------------------

def test_build_kompiliert_helfer_mit_eigenem_ziel_und_rueckfall():
    assert 'HELPER_MIN_MACOS="26.0"' in BUILD
    assert re.search(r'if ! swiftc .*-target "arm64-apple-macos\$HELPER_MIN_MACOS" -o "\$TH_IN"', BUILD)
    assert "tools/translate-helper/main.swift" in BUILD
    assert 'TH_IN="$NEWAPP/Contents/Helpers/translate-helper"' in BUILD
    # fehlt das SDK, wird übersprungen statt abgebrochen (release.yml baut auf macos-15)
    block = BUILD.split('if ! swiftc -O -parse-as-library -target "arm64-apple-macos$HELPER_MIN_MACOS"', 1)[1]
    assert 'rm -f "$TH_IN"' in block.split("fi", 1)[0]


def test_build_signiert_helfer_mit_hardened_runtime_vor_dem_bundle():
    fn = BUILD.split("sign_helpers() {", 1)[1].split("\n}\n", 1)[0]
    assert re.search(r'codesign -s "\$id" --force --options runtime "\$@" \\\s*\n\s*--identifier '
                     r'io\.github\.dolmetscher\.en-th\.translate-helper "\$TH_IN"', fn)
    assert 'sign_helpers "$SIGN" --timestamp' in BUILD          # Release: mit Zeitstempel
    assert "sign_helpers \"$SIGN\" || sign_helpers -" in BUILD  # Ad-hoc-Rückfall auch für die Helfer
    assert BUILD.index('sign_helpers "$SIGN" --timestamp') < BUILD.index("--entitlements \"$ENTITLEMENTS\" \"$NEWAPP\"")
    assert "*flags=*runtime*)" in BUILD                              # Prüfung nach dem Signieren


def test_build_install_beendet_laufende_app():
    inst = BUILD.split('if [ "$INSTALL" = 1 ]; then', 1)[1]
    assert inst.index("pgrep -f") < inst.index('rm -rf "$HOME/Applications/Dolmetscher.app"')
    assert "quit app id" in inst


def test_build_skip_schalter_dokumentiert():
    head = BUILD.split("set -euo pipefail", 1)[0]
    assert "DOLMETSCHER_SKIP_TRANSLATE_HELPER" in head


# ---- translate-helper: Zeitgrenze je Anfrage (Nr. 218) --------------------------------------------------------------

def test_helfer_hat_zeitgrenze():
    assert '"--timeout"' in HELPER and "HelperTimeout" in HELPER
    assert "work.cancel()" in HELPER and 'return "timeout"' in HELPER
    assert "translate(session(src, dst), text, timeout: timeout)" in HELPER
    assert "withThrowingTaskGroup" not in HELPER                 # wartet sonst auf die hängende Kind-Task


# ---- Mac: Offline-Übersetzung, Privatmodus ------------------------------------------------------------------------

def test_app_offline_mt_einstellung():
    paths, eng, sv = SWIFT["Paths.swift"], SWIFT["Engine.swift"], SWIFT["SettingsView.swift"]
    assert '"Contents/Helpers/translate-helper"' in paths
    assert "majorVersion: 26, minorVersion: 4" in paths
    assert '(ud.object(forKey: "offlineMT") as? Bool) ?? (Paths.bundledTranslateHelper != nil)' in eng
    assert 'args += ["--offline-translator", helper]' in eng
    assert "|\\(offlineMT)" in eng                                  # Startargument: Neustart nötig
    assert "$m.offlineMT" in sv and 'L.t("offline_mt")' in sv


def test_app_privatmodus():
    eng = SWIFT["Engine.swift"]
    assert 'if privateMode { args.append("--private") }' in eng and "|\\(privateMode)" in eng
    assert "$m.privateMode" in SWIFT["SettingsView.swift"]
    assert "`--private`" in DOCS


# ---- Mac: Preset-Hinweis und kritische Sätze ------------------------------------------------------------------------

def test_app_liest_note_und_critical():
    pr, eng, views = SWIFT["Presets.swift"], SWIFT["Engine.swift"], SWIFT["Views.swift"]
    assert 'json["note"]' in pr and 'd["critical"] as? Bool' in pr
    assert 'o["note"]' in eng and 'o["phrases"]' in eng            # Ereignis `preset`
    assert "Preset.noteText((fromEvent ? m.activePresetNote : nil) ?? pr.note)" in views
    assert "let fromEvent = m.activePreset?.id == pr.id" in views
    assert "list.filter(\\.critical)" in views and "exclamationmark.triangle.fill" in views
    assert 'L.t("preset_critical")' in views                        # VoiceOver, nicht nur Farbe
    assert "`critical: true`" in DOCS and "`note`" in DOCS


def test_note_sprache_mit_englisch_als_rueckfall():
    pr = SWIFT["Presets.swift"]
    assert 'note[L.lang.rawValue] ?? note["en"]' in pr


# ---- Mac: kleine Punkte -----------------------------------------------------------------------------------------

def test_export_hinweis_bei_gekuerzten_blasen():
    assert "trimmedCount += drop.count" in SWIFT["Engine.swift"]   # Runde 27: Auswahl in BubbleTrimLogic
    assert '"export_trimmed"' in SWIFT["Support.swift"]
    assert "m.resetTrimmed()" in SWIFT["Views.swift"]


def test_langes_laden_bietet_log_und_neustart():
    v = SWIFT["Views.swift"]
    block = v.split("if m.loadSlow {", 1)[1].split("if let med", 1)[0]
    assert "openLog()" in block and "m.restart()" in block


def test_kuerzel_fehler_als_banner():
    v = SWIFT["Views.swift"]
    assert "hotKeys.failures.isEmpty && !hotKeysDismissed" in v and "retryIfNeeded()" in v


def test_profile_ladezustand_und_lange_saetze():
    p = SWIFT["Profiles.swift"]
    assert "pm.profiles.isEmpty && pm.loading" in p and "self?.loading = false" in p
    assert ".minimumScaleFactor(0.4)" in p


def test_neue_l10n_schluessel_vorhanden():
    l10n = SWIFT["L10n.swift"]
    for k in ("offline_mt", "offline_mt_help", "offline_mt_missing_help", "preset_note", "preset_critical",
              "private_mode", "private_mode_help", "export_trimmed", "profiles_loading", "err_preset_invalid",
              "err_vad_failed"):
        m = re.search(r'"' + k + r'": \[(.*?)\]', l10n, re.S)
        assert m and all(f'"{lang}":' in m.group(1) for lang in ("de", "en", "th")), k
