"""Round 13 (iPhone app): accessibility audit as source checks. The Swift tests run via xcodebuild test."""
import pathlib
import re

import pytest

IOS = pathlib.Path(__file__).resolve().parent.parent / "ios"
LANGS = ("de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id")
VIEW_FILES = sorted(p for d in ("Dolmetscher", "Shared") for p in (IOS / d).glob("*.swift")
                    if not p.name.startswith("L10n") and p.name not in ("DebugScreens.swift", "StatusColor.swift"))


def _read(p):
    return p.read_text(encoding="utf-8")


def _lum(rgb):
    def ch(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _contrast(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def _status_colors():
    src = _read(IOS / "Shared" / "StatusColor.swift")
    found = dict(re.findall(r"static let (\w+): RGB = \(([\d., ]+)\)", src))
    return {k: tuple(float(x) for x in v.split(",")) for k, v in found.items()}


def test_status_colors_meet_contrast_in_both_modes():
    colors = _status_colors()
    assert len(colors) == 8
    light_bgs = [(1.0, 1.0, 1.0), (0.949, 0.949, 0.969)]   # systemBackground, secondarySystemBackground
    dark_bgs = [(0.0, 0.0, 0.0), (0.11, 0.11, 0.118)]
    for name, rgb in colors.items():
        for bg in (light_bgs if name.endswith("Light") else dark_bgs):
            assert _contrast(rgb, bg) >= 4.5, (name, _contrast(rgb, bg))


def test_filled_buttons_keep_white_text_readable():
    colors = _status_colors()
    for name in ("okLight", "errorLight", "infoLight"):
        assert _contrast(colors[name], (1.0, 1.0, 1.0)) >= 4.5, name
    views = _read(IOS / "Dolmetscher" / "Views.swift")
    m = re.search(r"static func fill.*?\? Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", views, re.S)
    assert m and _contrast(tuple(float(x) for x in m.groups()), (1.0, 1.0, 1.0)) >= 4.5
    pattern = r"static let partnerColor = .*?UIColor\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)"
    partner = re.search(pattern, views, re.S)
    assert partner and _contrast(tuple(float(x) for x in partner.groups()), (1.0, 1.0, 1.0)) >= 4.5


@pytest.mark.parametrize("path", VIEW_FILES, ids=lambda p: p.name)
def test_no_raw_system_status_colors(path):
    src = _read(path)
    assert not re.search(r"foregroundStyle\(\.(red|orange|green|blue|yellow)\)", src)
    assert not re.search(r"\bColor\.(red|orange|green|blue|yellow)\b", src)
    assert not re.search(r"\.tint\(\.(red|orange|green|blue)\)", src)


@pytest.mark.parametrize("path", VIEW_FILES, ids=lambda p: p.name)
def test_every_animation_respects_reduce_motion(path):
    lines = _read(path).splitlines()
    for i, line in enumerate(lines, 1):
        if re.search(r"withAnimation|\.animation\(|\.transition\(|symbolEffect|repeatForever", line):
            assert "Motion.animation(reduce: reduceMotion)" in line, f"{path.name}:{i}"
    if "Motion.animation" in "\n".join(lines):
        assert "accessibilityReduceMotion" in "\n".join(lines), path.name


@pytest.mark.parametrize("path", VIEW_FILES, ids=lambda p: p.name)
def test_symbol_buttons_have_label_and_44pt_target(path):
    lines = _read(path).splitlines()
    for i, line in enumerate(lines):
        opener = r"(label: \{|Button\(action: \w+\) \{|Link\(destination: \w+\) \{|ShareLink\(item: \w+\) \{)"
        if not re.search(opener + r" *Image\(systemName:", line):
            continue
        context = "\n".join(lines[i:i + 4])
        assert ".accessibilityLabel(" in context or "accessibilityHidden" in context, f"{path.name}:{i + 1} no label"
        if "ShareLink" not in line:
            assert ".minTapTarget()" in line, f"{path.name}:{i + 1} tap target"


def test_min_tap_target_is_44pt():
    assert "frame(minWidth: 44, minHeight: 44)" in _read(IOS / "Dolmetscher" / "Round9.swift")


@pytest.mark.parametrize("path", VIEW_FILES, ids=lambda p: p.name)
def test_progress_views_are_named_or_next_to_text(path):
    lines = _read(path).splitlines()
    for i, line in enumerate(lines):
        if "ProgressView(" in line:
            context = "\n".join(lines[max(0, i - 1):i + 3])
            assert re.search(r'ProgressView\(T\(|accessibility(Label|Hidden)|Text\(', context), f"{path.name}:{i + 1}"


@pytest.mark.parametrize("path", VIEW_FILES, ids=lambda p: p.name)
def test_no_fixed_text_sizes(path):
    src = _read(path)
    for m in re.finditer(r"\.font\(\.system\(size: ([^,)]+)", src):
        assert m.group(1).startswith(("scaled", "iconSize")), (path.name, m.group(1))
    assert not re.search(r"\.frame\(width: \d", src), path.name


def test_voiceover_hears_state_changes():
    model = _read(IOS / "Dolmetscher" / "Model.swift")
    for key in ("a11y_started", "a11y_stopped", "a11y_failed", "a11y_translation_failed"):
        assert f'voiceOverSay("{key}"' in model, key
    assert "func voiceOverSay" in model and "isVoiceOverRunning" in model
    assert "a11y_ready" in model


def test_new_texts_complete_and_wired():
    src = _read(IOS / "Dolmetscher" / "L10n+R13.swift")
    rows = re.findall(r'"(a11y_[a-z_]+)": \[\n(.*?)\n        \],', src, re.S)
    assert {k for k, _ in rows} == {"a11y_started", "a11y_stopped", "a11y_failed", "a11y_translation_failed"}
    for key, body in rows:
        assert len(re.findall(r'"(?:de|en|th|es|fr|ja|ko|zh-Hans|vi|id)": "[^"]+"', body)) == len(LANGS), key
    l10n = _read(IOS / "Dolmetscher" / "L10n.swift")
    registered = l10n[l10n.index("static func text("):]
    assert re.search(r"\bround13\b", registered)   # Nachschlag und allKeys kennen die Tabelle, egal in welcher Schreibweise


def test_state_is_not_only_a_color():
    conv = _read(IOS / "Dolmetscher" / "ConversationView.swift")
    assert "strokeBorder(.white.opacity(0.9), lineWidth: active ? 3 : 0)" in conv   # active turn: border
    assert "accessibilityAddTraits(expecting ? .isSelected : [])" in conv
    priv = _read(IOS / "Dolmetscher" / "PrivacyView.swift")
    assert 'T(local ? "pv_local" : "pv_net")' in priv and "accessibilityHidden(true)" in priv
    prep = _read(IOS / "Dolmetscher" / "Round4Views.swift")
    assert 'accessibilityValue(ok ? T("prep_ok") : T("prep_missing"))' in prep


def test_headings_and_decorative_images():
    assert ".accessibilityAddTraits(.isHeader)" in _read(IOS / "Dolmetscher" / "Round9.swift")
    assert ".accessibilityAddTraits(.isHeader)" in _read(IOS / "Dolmetscher" / "Tools.swift")
    assert "accessibilityHidden(true)" in _read(IOS / "Dolmetscher" / "Round6.swift")
