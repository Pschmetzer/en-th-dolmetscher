import types

import hwprofile


def fake_run(values):
    def run(cmd, **kw):
        v = values.get(cmd[-1])
        return types.SimpleNamespace(returncode=0 if v is not None else 1, stdout=v or "")
    return run


def info(chip, gb, machine="arm64"):
    run = fake_run({"hw.memsize": str(gb * 2 ** 30), "machdep.cpu.brand_string": chip})
    return hwprofile.auto_choice(run, machine)


def test_detect_values():
    d = hwprofile.detect(fake_run({"hw.memsize": str(16 * 2 ** 30), "machdep.cpu.brand_string": "Apple M2"}), "arm64")
    assert d == {"chip": "Apple M2", "ram_gb": 16.0, "arm64": True}


def test_detect_sysctl_failure():
    def boom(*a, **k):
        raise OSError
    d = hwprofile.detect(boom, "x86_64")
    assert d == {"chip": "", "ram_gb": 0.0, "arm64": False}
    assert hwprofile.recommend(d)["model"] == "small"


def test_tiers():
    assert info("Apple M1", 8)["model"] == "medium" and info("Apple M1", 8)["beam"] == 1
    assert info("Apple M2", 16)["model"] == "medium" and info("Apple M2", 16)["beam"] == 3
    assert info("Apple M4 Pro", 24)["model"] == "best"
    assert info("Apple M4 Max", 64)["beam"] == 5
    assert info("Apple M3", 24)["model"] == "medium"          # Basis-Chip, nicht Pro/Max
    assert info("Apple M1", 4)["model"] == "small"
    assert info("Intel(R) Core(TM) i7", 32, "x86_64")["model"] == "small"


def test_model_values_valid():
    for gb in (4, 8, 16, 32):
        assert info("Apple M4 Pro", gb)["model"] in hwprofile.TIERS
