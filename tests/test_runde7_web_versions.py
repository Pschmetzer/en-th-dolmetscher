"""Versionsstaende lesen (nur lesend): Mac/Engine (pyproject), iPhone (pbxproj), Dokumentation docs/VERSIONEN.md."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
KNOWN_IOS = "1.0"   # dokumentierte Abweichung, siehe docs/VERSIONEN.md


def _mac():
    return re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "pyproject.toml").read_text(encoding="utf-8"), re.M).group(1)


def _ios():
    text = (ROOT / "ios" / "Dolmetscher.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    return set(re.findall(r"MARKETING_VERSION = ([\d.]+);", text))


def test_ios_targets_share_one_marketing_version():
    assert len(_ios()) == 1, _ios()


def test_ios_version_equals_mac_or_is_the_documented_exception():
    ios = _ios().pop()
    if ios != _mac():
        doc = (ROOT / "docs" / "VERSIONEN.md").read_text(encoding="utf-8")
        assert ios == KNOWN_IOS and f"iPhone `{ios}`" in doc, f"iPhone {ios} != Mac {_mac()}: Abweichung nicht dokumentiert"


def test_changelog_mentions_current_version():
    assert _mac() in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
