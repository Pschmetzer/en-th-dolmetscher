"""Runde 29 (Doku, CI, Werkzeuge): Changelog-Auszug und -Pruefung, Workflow-Hausregeln, Doku-Landkarte, Versionen."""
import importlib.util
import pathlib
import re
import textwrap

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    import sys
    sys.path.insert(0, str(ROOT / "tools"))
    spec.loader.exec_module(mod)
    return mod


CHANGELOG = textwrap.dedent("""\
    # Changelog

    ## Unreleased

    ### Neu
    - etwas

    ## 1.3 (20 November 2026)

    Text zu 1.3.

    ### Fix
    - a

    ## 1.2 and earlier

    alt
    """)


# --- changelog_extract -------------------------------------------------------------------------------------------

def test_extract_findet_version_mit_und_ohne_v():
    ce = _load("changelog_extract")
    assert ce.extract(CHANGELOG, "1.3").startswith("Text zu 1.3.")
    assert ce.extract(CHANGELOG, "v1.3") == ce.extract(CHANGELOG, "1.3")
    assert "### Fix" in ce.extract(CHANGELOG, "1.3")


def test_extract_unreleased_und_fehlende_version():
    ce = _load("changelog_extract")
    assert ce.extract(CHANGELOG, "unreleased").startswith("### Neu")
    assert ce.extract(CHANGELOG, "9.9") is None
    assert ce.extract(CHANGELOG, "1.2").strip() == "alt"


def test_extract_ignoriert_ueberschriften_in_codebloecken():
    ce = _load("changelog_extract")
    text = "## Unreleased\n\n```\n## 2.0 (x)\n```\n\n## 1.0 (1 Mai 2026)\n\nA\n"
    assert [n for n, _ in ce.sections(text)] == ["Unreleased", "1.0 (1 Mai 2026)"]


def test_extract_cli_exitcodes(tmp_path, capsys):
    ce = _load("changelog_extract")
    f = tmp_path / "C.md"
    f.write_text(CHANGELOG, encoding="utf-8")
    assert ce.main(["1.3", "--file", str(f)]) == 0
    assert "Text zu 1.3." in capsys.readouterr().out
    assert ce.main(["7.7", "--file", str(f)]) == 1
    assert ce.main(["--list", "--file", str(f)]) == 0
    assert "1.2 and earlier" in capsys.readouterr().out


def test_extract_leerer_abschnitt_ist_fehler(tmp_path):
    ce = _load("changelog_extract")
    f = tmp_path / "C.md"
    f.write_text("## Unreleased\n\n## 1.0 (1 Mai 2026)\n\n", encoding="utf-8")
    assert ce.main(["1.0", "--file", str(f)]) == 1


def test_extract_aus_echtem_changelog_nicht_leer():
    ce = _load("changelog_extract")
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    version = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "pyproject.toml").read_text(), re.M).group(1)
    body = ce.extract(text, version)
    assert body and body.strip(), f"CHANGELOG.md braucht einen Abschnitt fuer die Version {version}"


# --- changelog_lint ----------------------------------------------------------------------------------------------

def test_lint_gueltiger_changelog():
    cl = _load("changelog_lint")
    assert cl.lint(CHANGELOG, "1.3") == []


def test_lint_findet_formfehler():
    cl = _load("changelog_lint")
    bad = "## 1.3 (20 November 2026)\n\ntext\n\n## 1.4 (21 November 2026)\n\ntext\n\n## 1.3 (1 Mai 2026)\n\nx\n"
    problems = "\n".join(cl.lint(bad, "1.3"))
    assert "erster Abschnitt muss 'Unreleased'" in problems
    assert "doppelt" in problems
    assert "Reihenfolge" in problems
    assert "neuer als pyproject.toml" in problems


def test_lint_leerer_und_unlesbarer_abschnitt():
    cl = _load("changelog_lint")
    problems = "\n".join(cl.lint("## Unreleased\n\n## 1.0 (1 Mai 2026)\n\n## Irgendwas\n\nx\n", None))
    assert "leer" in problems
    assert "passt nicht" in problems
    assert cl.lint("", None) == ["keine Abschnitte (## ...) gefunden"]


def test_lint_echter_changelog_ist_in_ordnung():
    cl = _load("changelog_lint")
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    assert cl.lint(text, cl.project_version()) == []


# --- check_workflows ---------------------------------------------------------------------------------------------

GOOD_WF = textwrap.dedent("""\
    name: X
    on: push
    permissions:
      contents: read
    jobs:
      a:
        runs-on: ubuntu-latest
        timeout-minutes: 5
        steps:
          - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
          - uses: ./local-action
      b:
        uses: ./.github/workflows/other.yml
    """)


def test_workflows_gueltige_datei():
    cw = _load("check_workflows")
    assert cw.check_text("x.yml", GOOD_WF) == []


def test_workflows_findet_regelverstoesse():
    cw = _load("check_workflows")
    bad = textwrap.dedent("""\
        name: X
        on: pull_request_target
        jobs:
          a:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0
              - uses: actions/deploy-pages@3d3c42e5aac5ba805825da76410c181273ba90b1 # v4
        """)
    problems = "\n".join(cw.check_text("x.yml", bad))
    assert "permissions" in problems
    assert "pull_request_target" in problems
    assert "nicht auf einen Commit" in problems
    assert "Versionskommentar" in problems
    assert "timeout-minutes" in problems
    assert "deploy-pages" in problems


def test_workflows_kommentare_loesen_keine_verbote_aus():
    cw = _load("check_workflows")
    text = GOOD_WF.replace("name: X", "name: X  # kein deploy-pages, kein pull_request_target")
    assert cw.check_text("x.yml", text) == []


def test_workflows_jobs_parser():
    cw = _load("check_workflows")
    assert sorted(cw.jobs(GOOD_WF.splitlines())) == ["a", "b"]


def test_workflows_repo_ist_sauber():
    cw = _load("check_workflows")
    assert cw.check_dir() == []


def test_release_workflow_veroeffentlicht_nichts_von_allein():
    wf = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
    assert "--draft" in wf
    assert "changelog_extract.py" in wf
    assert len(re.findall(r"^\s+contents: write", wf, re.M)) == 1, "Schreibrecht nur im Bau-Job (Entwurf)"
    assert re.search(r"^permissions:\n  contents: read", wf, re.M)


def test_dependabot_deckt_alle_oekosysteme_ab():
    text = (ROOT / ".github/dependabot.yml").read_text(encoding="utf-8")
    for eco in ("github-actions", "pip", "npm", "devcontainers"):
        assert f"package-ecosystem: {eco}" in text
    assert text.count("cooldown:") >= 3


# --- check_docs_index --------------------------------------------------------------------------------------------

def test_docs_index_repo_ist_vollstaendig():
    ci = _load("check_docs_index")
    assert ci.check() == []


def test_docs_index_findet_fehlende_und_tote_eintraege(tmp_path):
    ci = _load("check_docs_index")
    docs = tmp_path / "docs"
    (docs / "sub").mkdir(parents=True)
    (docs / "README.md").write_text("[A](A.md) [X](GONE.md) [Ext](https://example.org)\n", encoding="utf-8")
    (docs / "A.md").write_text("a", encoding="utf-8")
    (docs / "B.md").write_text("b", encoding="utf-8")
    (docs / "sub" / "README.md").write_text("s", encoding="utf-8")
    (docs / "sub" / "C.md").write_text("c", encoding="utf-8")
    problems = "\n".join(ci.check(tmp_path))
    assert "docs/B.md fehlt" in problems
    assert "GONE.md" in problems
    assert "sub/README.md fehlt" in problems.replace("\\", "/")
    assert "C.md" not in problems     # Unterordner mit eigener README: nur die README muss verlinkt sein


def test_docs_index_ohne_readme(tmp_path):
    ci = _load("check_docs_index")
    (tmp_path / "docs").mkdir()
    assert ci.check(tmp_path) == ["docs/README.md fehlt"]


# --- check_version_sync ------------------------------------------------------------------------------------------

def test_versionen_repo_stimmt():
    cv = _load("check_version_sync")
    assert cv.check() == []


def test_versionen_tag_und_abweichung(tmp_path):
    cv = _load("check_version_sync")
    (tmp_path / "docs").mkdir()
    (tmp_path / "pyproject.toml").write_text('[project]\nversion = "2.0"\n', encoding="utf-8")
    vf = tmp_path / "docs" / "VERSIONEN.md"
    vf.write_text("| Mac-App und Engine | `pyproject.toml` | 1.9 |\n", encoding="utf-8")
    problems = "\n".join(cv.check(tmp_path, tag="v2.1"))
    assert "1.9" in problems and "Tag v2.1" in problems
    vf.write_text("| Mac-App und Engine | `pyproject.toml` | 2.0 |\n", encoding="utf-8")
    assert cv.check(tmp_path, tag="v2.0") == []


# --- Doku und Verdrahtung ----------------------------------------------------------------------------------------

def test_check_all_und_makefile_kennen_die_doku_pruefungen():
    sh = (ROOT / "tools/check_all.sh").read_text(encoding="utf-8")
    for tool in ("check_doc_links", "check_docs_index", "changelog_lint", "check_version_sync", "check_workflows"):
        assert f"tools/{tool}.py" in sh
    assert "--docs" in sh
    mk = (ROOT / "Makefile").read_text(encoding="utf-8")
    assert "docs-check:" in mk and "changelog-notes:" in mk


def test_ci_hat_doku_job_mit_zwischenspeicher():
    ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    assert "check_all.sh --docs" in ci
    assert ".ruff_cache" in ci
    assert "workflow_dispatch" in ci


def test_neue_doku_ist_verlinkt():
    readme = (ROOT / "docs/README.md").read_text(encoding="utf-8")
    contributing = (ROOT / "CONTRIBUTING.md").read_text(encoding="utf-8")
    for name in ("ENTWICKLUNG.md", "CI.md", "RELEASE.md"):
        assert name in readme
        assert (ROOT / "docs" / name).is_file()
    assert "docs/ENTWICKLUNG.md" in contributing
    assert "docs/CI.md" in contributing


def test_ci_doku_nennt_jeden_workflow():
    doc = (ROOT / "docs/CI.md").read_text(encoding="utf-8")
    for wf in sorted((ROOT / ".github/workflows").glob("*.yml")):
        assert f"`{wf.name}`" in doc, f"{wf.name} fehlt in docs/CI.md"
