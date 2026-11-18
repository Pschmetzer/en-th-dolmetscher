"""Oberflaeche in Deutsch, Englisch, Thai: gleiche Schluessel, Platzhalter, deutscher Text wie im HTML."""
import json
import re
from html.parser import HTMLParser

from _webhelpers import HTML, SCRIPT

STR = json.loads(re.search(r"^const STR = (\{.*?^\});", SCRIPT, re.S | re.M).group(1))


class Collect(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.stack, self.found = [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        key = a.get("data-i18n") or a.get("data-i18n-html")
        if tag in ("br", "input", "meta", "link", "img", "hr"):
            return
        self.stack.append([tag, key, bool(a.get("data-i18n-html")), []])

    def handle_data(self, d):
        for f in self.stack:
            f[3].append(d)

    handle_entityref = lambda self, n: self.handle_data(f"&{n};")   # noqa: E731

    def handle_endtag(self, tag):
        while self.stack:
            f = self.stack.pop()
            if f[1]:
                self.found.append((f[1], f[2], "".join(f[3])))
            if f[0] == tag:
                break


def test_same_keys_and_placeholders():
    assert set(STR) == {"de", "en", "th"}
    assert set(STR["de"]) == set(STR["en"]) == set(STR["th"])
    for k, de in STR["de"].items():
        for lang in ("en", "th"):
            assert set(re.findall(r"\{(\w+)\}", de)) == set(re.findall(r"\{(\w+)\}", STR[lang][k])), (k, lang)
            assert STR[lang][k].strip() or not de.strip(), (k, lang)


def test_html_keys_exist_and_german_matches():
    c = Collect()
    c.feed(HTML.split("<body>")[1].split("<script>")[0])
    assert len(c.found) > 50
    for key, is_html, inner in c.found:
        assert key in STR["de"], key
        if not is_html:
            de = STR["de"][key].strip()
            assert de == re.sub(r"\s+", " ", inner).strip() or de == inner.strip(), key


def test_html_variant_strings_have_equal_tags():
    for k, de in STR["de"].items():
        tags = sorted(re.findall(r"<(\w+)", de))
        for lang in ("en", "th"):
            assert sorted(re.findall(r"<(\w+)", STR[lang][k])) == tags, (k, lang)


def test_dynamic_keys_used_in_script():
    code = SCRIPT.split("function applyUi()")[1]
    used = set(re.findall(r"\bt\('(\w+)'", code))
    assert used and used <= set(STR["de"]), used - set(STR["de"])


def test_ui_switch_and_fallback():
    assert "navigator.language" in SCRIPT and "UI_LANGS" in SCRIPT and 'id="uiLang"' in HTML
    assert "document.documentElement.lang = UI" in SCRIPT
