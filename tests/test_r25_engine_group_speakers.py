"""Runde 25: Gruppenmodus – stabile Sprechernummern über cluster_speakers (synthetische Stimmabdrücke)."""
import numpy as np
import pytest

import online_speakers as osp
import profiles

DIM = 64


def voice(k, seed, noise=0.08):
    """Stimme k: feste Richtung plus kleines Rauschen je Äußerung."""
    base = np.zeros(DIM, dtype=np.float32)
    base[k * 5:k * 5 + 5] = 1.0
    r = np.random.default_rng(seed).normal(0, noise, DIM).astype(np.float32)
    return base + r


def test_label_format():
    assert osp.label(3) == "Sprecher 3"


def test_same_voice_keeps_number_and_new_voices_get_next_numbers():
    s = osp.OnlineSpeakers()
    seq = [0, 0, 1, 0, 2, 1, 2, 2, 0, 1]
    got = [s.assign(voice(k, i)) for i, k in enumerate(seq)]
    first = {}
    for k, n in zip(seq, got):
        assert first.setdefault(k, n) == n                  # dieselbe Person -> immer dieselbe Nummer
    assert got[0] == 1 and first[1] == 2 and first[2] == 3  # Reihenfolge des ersten Auftretens
    assert s.speakers() == [1, 2, 3]


def test_first_utterance_of_new_person_is_not_folded_into_big_group():
    s = osp.OnlineSpeakers()
    for i in range(8):
        s.assign(voice(0, i))
    assert s.assign(voice(3, 99)) == 2                      # cluster_speakers allein würde den Einzelsatz schlucken


def test_batch_cluster_function_would_fold_singleton_documentation():
    embs = [voice(0, i) for i in range(8)] + [voice(3, 99)]
    labels = profiles.cluster_speakers(embs)
    assert len(set(labels)) == 1                            # Grund für die stabile Schicht


def test_numbers_never_renumber_past_when_more_speakers_join():
    s = osp.OnlineSpeakers()
    a = [s.assign(voice(0, i)) for i in range(5)]
    s.assign(voice(1, 50))
    s.assign(voice(2, 51))
    assert a == [1] * 5
    assert s.assign(voice(0, 60)) == 1


def test_invalid_embeddings_return_none():
    s = osp.OnlineSpeakers()
    assert s.assign(None) is None
    assert s.assign(np.zeros(DIM)) is None
    assert s.assign(np.full(DIM, np.nan)) is None
    assert s.assign([]) is None
    assert s.assign("x") is None
    assert s.speakers() == []


def test_dimension_change_is_rejected_not_mixed():
    s = osp.OnlineSpeakers()
    assert s.assign(voice(0, 1)) == 1
    assert s.assign(np.ones(DIM + 3)) is None
    assert s.assign(voice(0, 2)) == 1


def test_max_speakers_caps_and_uses_nearest():
    s = osp.OnlineSpeakers(max_k=2)
    assert s.assign(voice(0, 1)) == 1
    assert s.assign(voice(1, 2)) == 2
    n = s.assign(voice(2, 3))
    assert n in (1, 2) and s.speakers() == [1, 2]


def test_reset_restarts_numbering():
    s = osp.OnlineSpeakers()
    s.assign(voice(0, 1))
    s.assign(voice(1, 2))
    s.reset()
    assert s.speakers() == [] and s.assign(voice(4, 3)) == 1


def test_refinement_merges_two_numbers_of_one_voice_via_alias():
    s = osp.OnlineSpeakers(refine_every=1000)
    for i in range(4):                                      # dieselbe Stimme, von Hand auf zwei Nummern verteilt
        v = osp._unit(voice(0, i))
        s.embs.append(v)
        s.nums.append(1 if i < 2 else 2)
        s.sums[1 if i < 2 else 2] = s.sums.get(1 if i < 2 else 2, np.zeros_like(v)) + v
    s.next, s.dim = 3, DIM
    s._refine()
    assert s.alias == {2: 1} and s.speakers() == [1]
    assert s.assign(voice(0, 77)) == 1                      # künftige Äußerungen: bleibende Nummer
    assert s.nums[:4] == [1, 1, 1, 1]


def test_refinement_veto_blocks_merge_when_centroids_far_apart():
    s = osp.OnlineSpeakers(refine_every=1000)
    for k in (0, 0, 1):
        v = osp._unit(voice(k, k + 1))
        s.embs.append(v)
        n = 1 if k == 0 else 2
        s.nums.append(n)
        s.sums[n] = s.sums.get(n, np.zeros_like(v)) + v
    s.next, s.dim = 3, DIM
    s._refine()
    assert s.alias == {} and s.speakers() == [1, 2]


def test_veto_keeps_distinct_voices_apart_after_refinement():
    s = osp.OnlineSpeakers(refine_every=3)
    seq = [0, 1, 0, 1, 2, 2, 0, 1, 2, 0, 1, 2]
    got = [s.assign(voice(k, 10 + i)) for i, k in enumerate(seq)]
    assert s.speakers() == [1, 2, 3]
    assert [got[i] for i in range(len(seq)) if seq[i] == 2] == [3] * 4


def test_keep_limit_bounds_memory():
    s = osp.OnlineSpeakers(keep=10)
    for i in range(50):
        s.assign(voice(i % 2, i))
    assert len(s.embs) == 10 == len(s.nums)


def test_assign_is_thread_safe():
    import threading
    s = osp.OnlineSpeakers()
    out = []

    def go(i):
        out.append(s.assign(voice(i % 3, i)))
    ts = [threading.Thread(target=go, args=(i,)) for i in range(30)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    assert None not in out and set(s.speakers()) <= {1, 2, 3, 4, 5, 6, 7, 8}


@pytest.mark.parametrize("bad", [0, -3])
def test_max_k_floor(bad):
    assert osp.OnlineSpeakers(max_k=bad).max_k == 1
