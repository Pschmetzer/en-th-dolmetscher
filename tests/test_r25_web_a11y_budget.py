# ruff: noqa: E501
"""Runde 25 (Web): Kontrast-Matrix (WCAG 2.1) für helles und dunkles Farbschema, Größen- und Ladebudget.

Ein echter Lighthouse-Lauf braucht Chrome und ist hier nicht Teil der Tests; die Budgets unten sind die statischen
Größen, die ihn am stärksten bestimmen (Seitengröße, blockierende Skripte, Vorab-Dateien, Paketgrößen)."""
import json
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
CSS = HTML.split("<style>", 1)[1].split("</style>", 1)[0]


def _tokens(block):
    out = {}
    for name, val in re.findall(r"--([a-z-]+):\s*(#[0-9a-fA-F]{3,6})\b", block):
        if len(val) == 4:
            val = "#" + "".join(c * 2 for c in val[1:])
        out[name] = val.lower()
    return out


def _palettes():
    light = _tokens(CSS.split(":root {", 1)[1].split("}", 1)[0])
    auto_dark = _tokens(CSS.split("@media (prefers-color-scheme: dark) {", 1)[1].split("}", 1)[0])
    manual_dark = _tokens(CSS.rsplit(':root[data-theme="dark"] {', 1)[1].split("}", 1)[0])
    return {"light": light, "dark-auto": {**light, **auto_dark}, "dark-manual": {**light, **manual_dark}}


def _lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ratio(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


PAL = _palettes()
SCHEMES = sorted(PAL)
# (Vordergrund, Hintergrund, Mindestwert, wofür): 4,5 für normalen Text, 3 für große Schrift (ab 24 px) und Bedienelemente
MATRIX = [
    ("fg", "bg", 4.5, "Fließtext"), ("fg", "card", 4.5, "Text auf Karten"), ("mut", "bg", 4.5, "Nebentext"), ("mut", "card", 4.5, "Nebentext auf Karten"),
    ("th-text", "bg", 4.5, "Thai-Text"), ("th-text", "card", 4.5, "Thai-Text auf Karten"), ("crit", "bg", 4.5, "kritische Sätze"), ("crit", "card", 4.5, "kritische Sätze auf Karten"),
    ("star", "card", 4.5, "Favoritenstern"), ("fg", "note-bg", 4.5, "Hinweisbox"), ("fg", "warn-bg", 4.5, "Warnbox"), ("fg", "kbd", 4.5, "Tastenkürzel"),
    ("btn-fg", "btn-en", 4.5, "Sprechtaste A"), ("btn-fg", "btn-th", 4.5, "Sprechtaste B"), ("btn-fg", "yes", 4.5, "Ja-Taste"), ("btn-fg", "no", 4.5, "Nein-Taste"),
    ("yes-text", "bg", 4.5, "Ja-Antwort riesig auf der Zeigeseite"), ("no-text", "bg", 4.5, "Nein-Antwort riesig auf der Zeigeseite"),
    ("focus", "bg", 3, "Fokusrahmen"), ("focus", "card", 3, "Fokusrahmen auf Karten"), ("en", "bg", 3, "Rahmen Sprache A"), ("th", "bg", 3, "Rahmen Sprache B"),
]


@pytest.mark.parametrize("scheme", SCHEMES)
@pytest.mark.parametrize("fg,bg,need,what", MATRIX, ids=[f"{m[0]}-on-{m[1]}" for m in MATRIX])
def test_contrast_matrix(scheme, fg, bg, need, what):
    pal = PAL[scheme]
    if fg == "btn-fg":
        pal = {**pal, "btn-fg": "#ffffff"}
    assert fg in pal and bg in pal, (scheme, fg, bg)
    assert ratio(pal[fg], pal[bg]) >= need, (scheme, what, fg, bg, round(ratio(pal[fg], pal[bg]), 2))


def test_dark_schemes_define_the_same_tokens_in_both_ways():
    assert PAL["dark-auto"] == PAL["dark-manual"]                       # Gerät dunkel und manuell dunkel sehen gleich aus


def test_every_token_used_as_text_color_is_in_the_matrix():
    used = set(re.findall(r"(?<![-a-z])color:\s*var\(--([a-z-]+)\)", CSS))
    covered = {m[0] for m in MATRIX}
    ignore = {"fg"}                                                     # Standardtext, mit allen Hintergründen geprüft
    assert (used - covered - ignore) == set(), used - covered


def test_partner_yes_no_text_uses_the_readable_tokens():
    assert "#partnerText.yes { color:var(--yes-text); }" in CSS and "#partnerText.no { color:var(--no-text); }" in CSS
    for scheme in SCHEMES:
        assert ratio(PAL[scheme]["yes-text"], PAL[scheme]["bg"]) >= 4.5 and ratio(PAL[scheme]["no-text"], PAL[scheme]["bg"]) >= 4.5


def test_contrast_helper_matches_known_values():
    assert round(ratio("#000000", "#ffffff"), 2) == 21.0 and ratio("#777777", "#ffffff") < 4.5 <= ratio("#767676", "#ffffff")


# ---------------------------------------------------------------- Budgets (Lighthouse-nah)

def test_page_weight_budgets():
    assert len(HTML.encode("utf-8")) <= 256_000                          # wie Runde 23: Seite selbst
    sizes = {f: (ROOT / f).stat().st_size for f in ("web-extras.js", "web-qr.js", "web-search-worker.js", "sw.js", "manifest.webmanifest", "languages.json")}
    assert sizes["web-extras.js"] <= 45_000 and sizes["web-qr.js"] <= 9_000 and sizes["web-search-worker.js"] <= 5_000, sizes
    assert sizes["sw.js"] <= 17_500 and sizes["languages.json"] <= 16_000


def test_new_scripts_are_lazy_not_render_blocking():
    head_and_body = HTML
    assert "web-qr.js" not in head_and_body and "web-search-worker.js" not in head_and_body      # nie im HTML: erst bei Gebrauch
    tags = re.findall(r"<script[^>]*\ssrc=[^>]*>", HTML, re.I)
    assert tags == [] or all("defer" in t or "async" in t for t in tags)                          # keine blockierenden Fremd- oder Zusatzskripte
    extras = re.findall(r"e\.src = '([^']+)'", HTML)
    assert extras == ["web-extras.js"]                                                            # Werkzeuge: nur auf Knopfdruck geladen


def test_precache_is_core_only_and_packs_are_small():
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    core = re.search(r"const CORE = \[([^\]]*)\]", sw).group(1)
    core_bytes = sum((ROOT / f).stat().st_size for f in re.findall(r"'([^']+)'", core) if f != "index.html" and (ROOT / f).is_file())
    assert core_bytes <= 330_000, core_bytes                                                      # Vorab-Speicher ohne Pakete; index.html kommt immer zuerst vom Netz
    sizes = {p.stem: p.stat().st_size for p in (ROOT / "presets").glob("*.json")}
    assert max(sizes.values()) <= 22_000, max(sizes.items(), key=lambda x: x[1])
    assert sum(sizes.values()) <= 1_900_000
    idx = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
    assert len(idx["packs"]) == len(sizes)
