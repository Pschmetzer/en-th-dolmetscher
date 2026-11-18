"""Round 14 (iPhone app): onboarding checks that run without Xcode. The Swift tests run via xcodebuild test."""
import pathlib
import re

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")


def _src(*parts):
    return IOS.joinpath(*parts).read_text(encoding="utf-8")


def _rows():
    src = _src("Dolmetscher", "L10n+R14.swift")
    return {k: dict(re.findall(r'"(de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "((?:[^"\\]|\\.)*)"', body))
            for k, body in re.findall(r'"(ob_[a-z_]+)": \[(.*?)\],\n', src, re.S)}


def test_texts_complete_in_all_languages_with_same_placeholders():
    rows = _rows()
    assert len(rows) >= 20
    for key, row in rows.items():
        assert set(row) == set(LANGS), key
        assert all(v.strip() for v in row.values()), key
        ph = re.findall(r"%[@d]", row["en"])
        assert all(re.findall(r"%[@d]", v) == ph for v in row.values()), key


def test_keys_used_by_the_views_exist():
    rows = _rows()
    src = "".join(_src("Dolmetscher", n) for n in ("OnboardingView.swift", "Onboarding.swift", "Views.swift"))
    assert set(re.findall(r'"(ob_[a-z_]+)"', src)) <= set(rows)
    for step in ("pair", "mic", "speech", "packs", "test"):  # titleKey/bodyKey of each step
        assert f"ob_{step}_t" in rows and f"ob_{step}_b" in rows, step


def test_flow_is_wired_into_the_app():
    views = _src("Dolmetscher", "Views.swift")
    assert "case .welcome: OnboardingView()" in views
    assert "PermissionBanner()" in views
    assert "ob_replay" in views  # reachable again from the help
    assert "welcome" in _src("Dolmetscher", "Model.swift")
    assert "round14" in _src("Dolmetscher", "L10n.swift")


def test_permissions_explained_before_the_system_dialog_and_settings_offered():
    view = _src("Dolmetscher", "OnboardingView.swift")
    assert "UIApplication.openSettingsURLString" in view
    assert "ob_later" in view
    logic = _src("Dolmetscher", "Onboarding.swift")
    assert "explainThenAsk" in logic and "restricted" in logic
    # the system dialog is only requested by a button in the onboarding view, never on appear
    assert "requestMicrophone()" in view and ".task { await PermissionProbe.request" not in view


def test_logic_file_has_no_ui_imports_and_is_tested():
    logic = _src("Dolmetscher", "Onboarding.swift")
    assert "import SwiftUI" not in logic and "import AVFoundation" not in logic and "import Speech" not in logic
    tests = _src("DolmetscherTests", "Round14Tests.swift")
    for name in ("OnboardingFlow", "PermissionAdvice", "PermissionSummary", "OnboardingPolicy", "PackSize"):
        assert name in tests, name
