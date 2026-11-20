# ruff: noqa: E501
"""Runde 23 (Infrastruktur und Doku): Links, Hosting-Konfigurationen, Datenschutz-Angleichung, CI, Benchmark-Fälle."""
import importlib.util
import json
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_keine_toten_relativen_links_in_der_doku():
    links = _load("check_doc_links")
    assert links.dead_links() == []


def test_link_pruefer_findet_tote_links_und_ignoriert_code(tmp_path):
    links = _load("check_doc_links")
    (tmp_path / "docs").mkdir()
    (tmp_path / "README.md").write_text(
        "[ok](docs/a.md) [tot](docs/fehlt.md) [web](https://example.org/x) [anker](#x)\n"
        "`[im code](nirgends.md)`\n```\n[im block](auch-nirgends.md)\n```\n", encoding="utf-8")
    (tmp_path / "docs" / "a.md").write_text("[zurück](../README.md#oben) ![bild](../fehlt.png)", encoding="utf-8")
    bad = {(f, t) for f, _n, t in links.dead_links(tmp_path)}
    assert bad == {("README.md", "docs/fehlt.md"), ("docs/a.md", "../fehlt.png")}


def test_tests_importieren_nicht_ueber_das_paket_tests():
    """Ein fremdes Paket `tests` im site-packages verdeckt tests/ (kein __init__.py): geschwisterliche Importe nutzen."""
    pat = re.compile(r"^\s*(from tests[. ]|import tests\b)", re.M)
    me = pathlib.Path(__file__).name
    for f in sorted((ROOT / "tests").glob("*.py")):
        if f.name != me:
            assert not pat.search(f.read_text(encoding="utf-8")), f.name


# --- Hosting-Konfigurationen -------------------------------------------------------------------------------------

HOSTING = ("netlify_headers", "cloudflare_headers", "nginx.conf", "Caddyfile")
MUST = ("Permissions-Policy", "Referrer-Policy", "Cross-Origin-Opener-Policy", "X-Content-Type-Options", "frame-ancestors 'none'",
        "no-cache", "application/manifest+json", "microphone=(self)")


@pytest.mark.parametrize("name", HOSTING)
def test_hosting_konfiguration_setzt_die_empfohlenen_header(name):
    text = _read(f"docs/hosting/{name}")
    for needle in MUST:
        assert needle in text, (name, needle)
    assert f"hosting/{name}" in _read("docs/WEB-HOSTING.md")


def test_hosting_header_stimmen_mit_der_doku_ueberein():
    doc = _read("docs/WEB-HOSTING.md")
    for needle in ("Permissions-Policy: microphone=(self), camera=(), geolocation=()", "Referrer-Policy: no-referrer"):
        assert needle in doc
    # Die CSP im <meta> bleibt Quelle der Wahrheit: die Konfigurationen setzen keine zweite, widersprüchliche.
    for name in HOSTING:
        assert "default-src" not in _read(f"docs/hosting/{name}"), name


# --- Datenschutz: iOS-Online-Fallback ----------------------------------------------------------------------------

def test_datenschutz_beschreibt_den_parallelen_mymemory_start_per_post():
    long = _read("docs/DATENSCHUTZ.md")
    iphone = next(ln for ln in long.splitlines() if ln.startswith("- **Übersetzung**") and "Apples Übersetzung" in ln)
    assert "1,2 Sekunden" in iphone and "parallel" in iphone and "MyMemory" in iphone
    assert "per GET" not in iphone and "in der URL**" not in iphone
    for rel, needle in (("docs/DATENSCHUTZ-KURZ.md", "1,2 s"), ("docs/en/PRIVACY-SHORT.md", "1.2 s"),
                        ("docs/th/PRIVACY-SHORT.md", "1.2")):
        text = _read(rel)
        sect = text.split("## iPhone", 1)[1].split("## Browser", 1)[0] if "## iPhone" in text else text
        assert needle in sect and "MyMemory" in sect, rel


def test_datenschutz_aussage_deckt_sich_mit_dem_swift_code():
    swift = _read("ios/Dolmetscher/Translator.swift")
    assert "hedgeDelay = 1.2" in swift
    assert re.search(r'URLRequest\(url: URL\(string: "https://api\.mymemory\.translated\.net/get"\)!\)\s*req\.httpMethod = "POST"', swift)


# --- CI ----------------------------------------------------------------------------------------------------------

def test_dependabot_deckt_actions_pip_und_npm_ab():
    text = _read(".github/dependabot.yml")
    for eco in ("github-actions", "pip", "npm"):
        assert f"package-ecosystem: {eco}" in text
    assert "directory: /tests/web-e2e" in text
    assert (ROOT / "tests" / "web-e2e" / "package.json").is_file()


def test_workflows_sind_gueltiges_yaml_mit_festen_action_versionen():
    yaml = pytest.importorskip("yaml")
    for name in ("docs-links.yml", "pages-smoke.yml", "ci.yml"):
        doc = yaml.safe_load(_read(f".github/workflows/{name}"))
        assert doc["permissions"] == {"contents": "read"}, name
        assert doc["jobs"], name
    for f in (ROOT / ".github" / "workflows").glob("*.yml"):
        for ref in re.findall(r"uses:\s*(\S+)", f.read_text(encoding="utf-8")):
            assert re.search(r"@[0-9a-f]{40}$", ref), (f.name, ref)


def test_ci_prueft_shell_skripte_mit_shellcheck():
    ci = _read(".github/workflows/ci.yml")
    assert re.search(r"shellcheck build\.sh", ci) and "tools/*.sh" in ci


# --- build.sh ----------------------------------------------------------------------------------------------------

def test_build_sh_erzwingt_pip_audit_beim_release_und_meldet_adhoc():
    sh = _read("build.sh")
    assert "pip-audit --disable-pip --require-hashes -r requirements.txt" in sh
    audit = sh.index("pip-audit --disable-pip")
    assert sh.rfind('if [ "$RELEASE" = 1 ]; then', 0, audit) > sh.rfind("UV_BIN=", 0, audit)
    assert "exit 1" in sh[audit:audit + 400]
    assert "AD HOC signiert" in sh and "Signature=adhoc" in sh
    assert re.search(r"^pip-audit==", _read("requirements-dev.in"), re.M)


# --- Benchmark ---------------------------------------------------------------------------------------------------

def test_bench_korpus_hat_zahlen_uhrzeiten_und_telefonnummern():
    cases = json.loads(_read("bench/cases.json"))
    assert len({c["id"] for c in cases}) == len(cases)
    by_tag = {t: [c for c in cases if t in c.get("tags", [])] for t in ("num", "time", "phone", "clock", "digits")}
    assert len(by_tag["phone"]) >= 4 and len(by_tag["clock"]) >= 3 and len(by_tag["digits"]) >= 6
    for c in by_tag["phone"]:
        assert re.search(r"\d{2,3} \d{3} \d{4}", c["text"]), c["id"]
    for lang in ("th", "en"):
        assert any(c["lang"] == lang for c in by_tag["phone"]), lang
    for c in cases:
        assert c["lang"] in ("th", "en") and c["text"].strip()
        if not c.get("expect_command") and "command" not in c.get("tags", []):
            assert c.get("en_ref" if c["lang"] == "th" else "th_ref"), c["id"]


def test_neue_dokumente_sind_verlinkt():
    assert "TH-QUALITAET.md" in _read("docs/ROADMAP.md")
    assert "Safari" in _read("docs/FAQ.md") and "Safari" in _read("docs/en/FAQ.md") and "Safari" in _read("docs/th/FAQ.md")
    assert "docs/WEB-HOSTING.md" in _read("README.md")
