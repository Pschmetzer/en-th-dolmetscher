"""Contract between the Mac app (app/*.swift) and the engine: every command-line flag the app passes
must exist in dolmetscher.py, and the --profile-stdin request keys the app sends must be read."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift"))
ENGINE = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")


def engine_flags():
    flags = set(re.findall(r'add_argument\(\s*"(--[a-z0-9-]+)"', ENGINE))
    # BooleanOptionalAction also accepts --no-<name>
    flags |= {"--no-" + f[2:] for f in re.findall(
        r'add_argument\(\s*"(--[a-z0-9-]+)"[^)]*BooleanOptionalAction', ENGINE)}
    return flags


def test_app_flags_exist_in_engine():
    used = set(re.findall(r'"(--[a-z][a-z0-9-]+)"', SWIFT))
    assert {"--json", "--idle", "--profile-stdin", "--history", "--history-export"} <= used
    missing = sorted(used - engine_flags())
    assert not missing, f"Flags used by the app but unknown to the engine: {missing}"


def test_model_choices_known_to_engine():
    tags = set(re.findall(r'\.tag\("(small|medium|best|auto)"\)', SWIFT))
    assert tags == {"small", "medium", "best", "auto"}
    assert 'model == "auto"' in ENGINE


def test_profile_stdin_keys_are_read():
    for key in ("enroll", "enroll_lang", "delete_profile", "vocab"):
        assert f'"{key}"' in SWIFT, key
        assert f'req.get("{key}")' in ENGINE, key


def test_history_export_formats_supported():
    m = re.search(r'formats = \[([^\]]*)\]', SWIFT)
    assert m, "HistorySection.formats not found"
    app_formats = set(re.findall(r'"([a-z]+)"', m.group(1)))
    choices = re.search(r'"--history-export".*?choices=\[([^\]]*)\]', ENGINE)
    assert choices
    assert app_formats <= set(re.findall(r'"([a-z]+)"', choices.group(1)))


def test_app_handles_events_it_relies_on():
    # Events the engine emits and the app must react to (others may be ignored).
    for ev in ("ready", "mic", "utt", "heard", "roles", "preset", "hwprofile", "error", "dropped",
               "speak_done", "pong"):
        assert f'emit("{ev}"' in ENGINE, ev
        assert f'case "{ev}"' in SWIFT, ev


DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


def _swift_dict(name):
    m = re.search(r"static let " + name + r": \[String: String\] = \[(.*?)\n    \]", SWIFT, re.S)
    assert m, name
    return dict(re.findall(r'"([a-z_]+)": "([a-z_]+)"', m.group(1)))


def _doc_codes(heading):
    sec = DOCS.split(heading, 1)[1].split("\n### ", 1)[0].split("\n## ", 1)[0]
    codes = set()
    for line in sec.splitlines():
        if line.startswith("| `") and not line.startswith("| `code`"):
            codes |= set(re.findall(r"`([a-z_]+)`", line.split("|")[1]))
    assert codes, heading
    return codes


def test_every_documented_code_is_localized():
    """PROTOKOLL.md tables vs. app: each dropped/error code has its own text (or a deliberate rule)."""
    from test_l10n_keys import parse_table
    rows, _ = parse_table()
    errs, drops = _swift_dict("errorKeys"), _swift_dict("droppedKeys")
    missing = sorted(_doc_codes("### `error.code`") - set(errs))
    assert not missing, f"error codes without app text: {missing}"
    # command: answer comes as `command`; translate_failed: an `error` follows -> status unchanged
    missing = sorted(_doc_codes("### `dropped.code`") - set(drops) - {"command", "translate_failed"})
    assert not missing, f"dropped codes without app text: {missing}"
    bad = sorted(k for k in list(errs.values()) + list(drops.values()) if k not in rows)
    assert not bad, f"L10n keys missing: {bad}"


def test_engine_codes_known_to_app():
    errs = _swift_dict("errorKeys")
    emitted = set(re.findall(r'emit\("error", code="([a-z_]+)"', ENGINE))
    assert emitted and not sorted(emitted - set(errs)), sorted(emitted - set(errs))


def test_speaker_model_error_has_code():
    # Die App erkennt den Stimmprofil-Fehler am Code (früher: Textanfang der Meldung).
    assert re.search(r'emit\("error", code="profiles_failed",\s*msg="Stimmprofile nicht nutzbar', ENGINE)


def test_speak_done_partial_and_delete_all():
    assert 'done["partial"] = True' in ENGINE and 'o["partial"] as? Bool == true' in SWIFT
    assert 'emit("profiles_deleted_all"' in ENGINE and '"profiles_deleted_all"' in SWIFT
    assert '"--delete-all-profiles"' in SWIFT
    assert 'emit("pong"' in ENGINE and '["ping": ' in SWIFT


def test_engine_app_nacharbeiten_contract():
    """speak_text: App sendet, Engine liest, Doku nennt es; Profil-Fehler über Code statt Textanfang;
    unsure-dropped liefert text/lang, die App liest sie für „Trotzdem übersetzen“ (retranslate)."""
    assert '"speak_text"' in SWIFT and 'd.get("speak_text")' in ENGINE and "`speak_text`" in DOCS
    assert 'code="profiles_failed"' in ENGINE and '"profiles_failed": "err_speaker_model"' in SWIFT
    assert "speakerErrorPrefix" not in SWIFT
    assert 'unsure = {"text": text, "lang": lang' in ENGINE
    assert 'o["code"] as? String == "unsure"' in SWIFT and 'o["text"] as? String' in SWIFT
    assert 'send(["retranslate": ["id": d.id, "text": d.text, "lang": d.lang]])' in SWIFT
