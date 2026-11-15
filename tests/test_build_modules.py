"""build.sh muss jedes lokale Modul, das die Engine importiert, ins App-Bundle kopieren."""
import ast
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _local_imports(path, seen):
    local = {p.stem for p in ROOT.glob("*.py")}
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name.split(".")[0] for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names = [node.module.split(".")[0]]
        for n in names:
            if n in local and n not in seen:
                seen.add(n)
                _local_imports(ROOT / f"{n}.py", seen)
    return seen


def test_build_copies_all_engine_modules():
    needed = _local_imports(ROOT / "dolmetscher.py", {"dolmetscher"})
    line = next(l for l in (ROOT / "build.sh").read_text().splitlines()
                if re.match(r"\s*cp dolmetscher\.py ", l))
    copied = {pathlib.Path(w).stem for w in line.split() if w.endswith(".py")}
    assert needed <= copied, f"build.sh kopiert nicht: {sorted(needed - copied)}"
