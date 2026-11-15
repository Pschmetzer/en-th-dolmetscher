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
    for ev in ("ready", "mic", "utt", "heard", "roles", "preset", "hwprofile", "error"):
        assert f'emit("{ev}"' in ENGINE, ev
        assert f'case "{ev}"' in SWIFT, ev
