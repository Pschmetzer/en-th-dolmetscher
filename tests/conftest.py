import pytest


@pytest.fixture(autouse=True)
def _reset_net_backoff():
    """Anbieter-Backoff/Offline-Schalter (Modulzustand) darf nicht zwischen Tests lecken."""
    import dolmetscher as d
    d.reset_net_backoff()
    yield
    d.reset_net_backoff()
