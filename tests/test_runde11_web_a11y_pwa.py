# ruff: noqa: E501
"""Runde 11 Web: Installierbarkeit und statische Zugaenglichkeitspruefung (Ueberschriften, Landmarks, Kontrast, Fokus, Live-Regionen, Tippziele)."""
import json
import re
from html.parser import HTMLParser

import pytest

from _webhelpers import HAVE_NODE, HTML, ROOT, SCRIPT, run

MANIFEST = json.loads((ROOT / "manifest.webmanifest").read_text(encoding="utf-8"))
SW = (ROOT / "sw.js").read_text(encoding="utf-8")
BODY = HTML[HTML.index("<body>"):HTML.index("<script>")]
CSS = re.search(r"<style>(.*?)</style>", HTML, re.S).group(1)
VOID = {"meta", "link", "br", "input", "img", "hr", "source"}


class Tree(HTMLParser):
    """Flacher Elementbaum mit Vorfahren und Reihenfolge (genug fuer Ueberschriften, Landmarks, Fokus)."""

    def __init__(self):
        super().__init__()
        self.els, self.stack = [], []

    def handle_starttag(self, tag, attrs):
        el = {"tag": tag, "a": dict(attrs), "anc": [e["tag"] for e in self.stack], "i": len(self.els)}
        self.els.append(el)
        if tag not in VOID:
            self.stack.append(el)

    def handle_endtag(self, tag):
        for k in range(len(self.stack) - 1, -1, -1):
            if self.stack[k]["tag"] == tag:
                del self.stack[k:]
                break


T = Tree()
T.feed(BODY)
EL = T.els


def tag(name):
    return [e for e in EL if e["tag"] == name]


# ---- Manifest ----
def test_manifest_install_fields():
    assert MANIFEST["lang"] == "de" and MANIFEST["dir"] == "ltr" and MANIFEST["id"] == "./"
    assert MANIFEST["categories"] and all(c in ("travel", "utilities", "education", "productivity") for c in MANIFEST["categories"])
    assert MANIFEST["display_override"][0] == "standalone" and MANIFEST["display"] == "standalone"
    assert MANIFEST["prefer_related_applications"] is False


def test_manifest_shortcuts_and_share_target_work_without_server():
    ids = re.search(r"const PRESET_IDS = \[([^\]]*)\]", SW).group(1)
    for s in MANIFEST["shortcuts"]:
        m = re.fullmatch(r"\./#preset=([\w-]+)", s["url"])
        assert m and f"'{m.group(1)}'" in ids, s["url"]          # Hash-Verknuepfung: kein Server noetig
        assert s["name"] and (ROOT / s["icons"][0]["src"]).is_file()
    st = MANIFEST["share_target"]
    assert st["method"] == "GET" and st["action"] == "./"           # GET auf die statische Seite; parseDeepLink liest ?text=
    assert set(st["params"].values()) <= {"title", "text", "url"} and "parseDeepLink(location.hash, location.search" in SCRIPT


def test_manifest_icons_not_marked_maskable_without_safe_zone():
    # Ohne eigenes Icon mit Sicherheitsrand (80 %-Kreis) darf nichts "maskable" heissen: Android schneidet sonst das Motiv ab.
    for i in MANIFEST["icons"]:
        assert "maskable" not in i.get("purpose", "any")


def test_sw_cache_bumped():
    assert re.search(r"const CACHE = 'dolmetscher-web-v(\d+)'", SW) and int(re.search(r"-v(\d+)'", SW).group(1)) >= 12


# ---- Installiert-Zustand und Update-Hinweis ----
def test_installed_state_and_update_notice_wired():
    assert 'id="appState"' in HTML and "'appinstalled'" in SCRIPT and "display-mode: standalone" in SCRIPT
    assert "t('installedState')" in SCRIPT and "t('installHint')" in SCRIPT and "t('installBtn')" in SCRIPT
    assert "announce(t('newVersion'), UI)" in SCRIPT                  # Update-Band wird auch vorgelesen
    assert "reg.update()" in SCRIPT and "visibilitychange" in SCRIPT   # lange offene App fragt nach Updates
    assert "controllerchange" in SCRIPT and "location.reload()" in SCRIPT and "if (!hadController) return" in SCRIPT


def test_no_hardcoded_install_text_and_no_variable_named_t():
    seg = SCRIPT[SCRIPT.index("function maybeInstallHint"):SCRIPT.index("// ---- Sprachvarianten")]
    assert "Installieren'" not in seg and "Schließen'" not in seg
    assert not re.search(r"\((?:[^()]*,\s*)?t(?:\s*,[^()]*)?\)\s*=>", seg)   # kein Parameter namens t


def test_new_strings_in_all_ui_languages():
    for k in ("installedState", "installedNow", "installHint", "installHintIos", "installBtn", "closeBtn", "hTalk", "hLog"):
        assert len(re.findall(rf'^  "{k}": ', SCRIPT, re.M)) == 3, k
    for k in ("installedState", "installedNow", "installHintIos"):   # alle drei Texte tatsaechlich verschieden
        assert len(set(re.findall(rf'^  "{k}": (.*),$', SCRIPT, re.M))) == 3, k
    assert re.search(r'^  "installedState": ".*[฀-๿]', SCRIPT, re.M)


# ---- Ueberschriften und Landmarks ----
def test_heading_order_has_no_gaps():
    page = [e for e in EL if re.fullmatch(r"h[1-6]", e["tag"]) and not ({"dialog"} & set(e["anc"]))]
    levels = [int(e["tag"][1]) for e in page]
    assert levels and levels[0] == 1 and levels.count(1) == 1
    for a, b in zip(levels, levels[1:]):
        assert b <= a + 1, levels
    assert levels.count(2) >= 2                                      # Bereiche sind per Ueberschrift anspringbar


def test_landmarks():
    assert len(tag("main")) == 1 and tag("main")[0]["a"].get("id") == "content"
    assert len(tag("header")) == 1 and not ({"main", "article", "section", "aside", "nav"} & set(tag("header")[0]["anc"]))
    main = tag("main")[0]["i"]
    assert tag("header")[0]["i"] < main
    for d in tag("dialog") + [e for e in EL if e["a"].get("role") == "dialog"]:
        assert "main" not in d["anc"]                                # Dialoge liegen ausserhalb von main
    assert not [e for e in EL if e["a"].get("role") == "main"]


# ---- Fokusreihenfolge ----
def test_focus_order():
    assert not [e for e in EL if int(e["a"].get("tabindex", "0") or 0) > 0]   # nie positive tabindex
    focusable = [e for e in EL if e["tag"] in ("a", "button", "select", "input", "textarea", "summary") and "hidden" not in e["a"]
                 and e["a"].get("type") != "hidden"]
    skip = focusable[0]
    assert skip["a"].get("id") == "skipLink" and skip["a"]["href"] == "#pbBox"
    assert 'id="pbBox"' in HTML
    in_main = [e["i"] for e in focusable if "main" in e["anc"]]
    modal = [e["i"] for e in focusable if "dialog" in e["anc"] or "partner" in str(e["a"].get("id"))]
    assert in_main and (not modal or min(modal) > max(in_main))      # Dialog-Inhalt kommt nach der Seite
    assert "$('main').inert = want" in SCRIPT                        # hinter der Grossansicht ist die Seite nicht fokussierbar
    assert [e for e in EL if e["tag"] == "div" and e["a"].get("id") == "main"]


# ---- aria-live ----
def test_live_regions():
    live = {e["a"].get("id"): e for e in EL if "aria-live" in e["a"] or e["a"].get("role") in ("status", "alert")}
    assert live["warn"]["a"]["role"] == "alert"
    a = live["announce"]["a"]
    assert a.get("aria-live") == "polite" and a.get("aria-atomic") == "true" and "sr-only" in a["class"]   # zentrale Sprechstelle
    assert not [e for e in EL if e["a"].get("aria-live") == "assertive"]       # nie unterbrechen
    assert live["status"]["a"]["aria-live"] == "off" and live["live"]["a"]["aria-live"] == "off"   # laufende Zeilen nur ueber announce()
    assert live["log"]["a"]["aria-live"] == "off"
    assert live["appState"]["a"]["role"] == "status" and live["swState"]["a"]["role"] == "status"
    for ref in re.findall(r'aria-(?:labelledby|describedby)="([^"]+)"', BODY):
        for i in ref.split():
            assert f'id="{i}"' in HTML, i
    ids = re.findall(r'\bid="([^"]+)"', BODY)
    assert len(ids) == len(set(ids)), [i for i in set(ids) if ids.count(i) > 1]


# ---- Kontraste der Farb-Tokens (WCAG 2.x, rechnerisch) ----
def _lum(h):
    if len(h) == 4:
        h = "#" + "".join(ch * 2 for ch in h[1:])
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ratio(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def _tokens():
    light = dict(re.findall(r"--([\w-]+):(#[0-9a-fA-F]{3,6})", re.search(r":root \{(.*?)\}", CSS, re.S).group(1)))
    dark = dict(light)
    dark.update(re.findall(r"--([\w-]+):(#[0-9a-fA-F]{3,6})", re.search(r"prefers-color-scheme: dark\) \{\s*:root \{(.*?)\}", CSS, re.S).group(1)))
    return {"hell": light, "dunkel": dark}


TEXT_PAIRS = [("fg", "bg"), ("fg", "card"), ("mut", "bg"), ("mut", "card"), ("mut", "note-bg"), ("fg", "note-bg"), ("fg", "warn-bg"),
              ("fg", "kbd"), ("btn-fg", "btn-en"), ("btn-fg", "btn-th"), ("btn-fg", "yes"), ("btn-fg", "no"),
              ("crit", "bg"), ("crit", "card"), ("th-text", "bg"), ("th-text", "card"), ("star", "card"), ("focus", "note-bg")]
UI_PAIRS = [("focus", "bg"), ("focus", "card"), ("line", "bg")]       # Fokusring und Rahmen: 3:1 (WCAG 1.4.11) – Rahmen nur wo allein tragend


@pytest.mark.parametrize("scheme", ["hell", "dunkel"])
def test_text_contrast_tokens(scheme):
    tok = _tokens()[scheme]
    for a, b in TEXT_PAIRS:
        assert ratio(tok[a], tok[b]) >= 4.5, (scheme, a, b, round(ratio(tok[a], tok[b]), 2))


@pytest.mark.parametrize("scheme", ["hell", "dunkel"])
def test_focus_ring_contrast_tokens(scheme):
    tok = _tokens()[scheme]
    for a, b in UI_PAIRS[:2]:
        assert ratio(tok[a], tok[b]) >= 3.0, (scheme, a, b)


@pytest.mark.skipif(not HAVE_NODE, reason="node nicht installiert")
def test_ratio_known_values():
    assert ratio("#000000", "#ffffff") == pytest.approx(21.0)
    assert run("", ["1+1"]) == [2]


# ---- Tippziele >= 44 px ----
def _min_heights():
    out = {}
    for sel, body in re.findall(r"(?m)^\s*([^@{}\n][^{}\n]*)\{([^}]*)\}", CSS):
        m = re.search(r"min-height:\s*(\d+)px", body)
        if m:
            for s in sel.split(","):
                out[s.strip()] = max(out.get(s.strip(), 0), int(m.group(1)))
    return out


def test_tap_targets_at_least_44px():
    mh = _min_heights()
    for sel in ("button.mode", ".small", "select", "details.box > summary", ".tile", ".star", ".yn", ".opts label", ".logtools input[type=search]", "#pbQ"):
        if sel == "button.mode":
            assert "padding:22px" in CSS      # Hoehe aus Polster und 20-px-Schrift: 22*2 + Zeile > 44
            continue
        assert mh.get(sel, 0) >= 44, (sel, mh.get(sel))
    assert not [s for s, v in mh.items() if v < 44 and not s.startswith("#partner")], {s: v for s, v in mh.items() if v < 44}
