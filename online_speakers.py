"""Gruppenmodus (Runde 25): stabile Sprechernummern ohne Stimmprofil.

`profiles.cluster_speakers` ist eine Stapelfunktion: bei jedem Aufruf werden die Labels nach Gruppengröße neu
vergeben und Einzelsätze der größten ähnlichen Gruppe zugeschlagen. Pro Äußerung aufgerufen würde sich die Nummer
einer Person also verschieben und die erste Äußerung einer neuen Person verschluckt werden. `OnlineSpeakers`
legt deshalb eine stabile Schicht darüber: eine neue Äußerung bekommt sofort die Nummer des ähnlichsten Zentroids
(oder eine neue), vergebene Nummern werden nie umnummeriert; `cluster_speakers` dient nur dazu, zwei Nummern, die
sich als dieselbe Person herausstellen, zusammenzulegen (Alias für künftige Äußerungen). Reine Funktionen/Klasse,
kein Stimmmodell: Eingabe sind fertige Stimmabdrücke."""
import threading

import numpy as np

import profiles

REFINE_EVERY = 6          # nach so vielen neuen Äußerungen prüft cluster_speakers, ob zwei Nummern dieselbe Person sind
KEEP = 120                # so viele Abdrücke bleiben für die Prüfung im Speicher (die ältesten fallen heraus)
MERGE_VETO = 0.1          # Zusammenlegen nur, wenn die Zentroide höchstens so weit unter der Gruppenschwelle liegen


def label(n):
    """Anzeigename im Protokoll: 'Sprecher 3'."""
    return f"Sprecher {int(n)}"


def _unit(emb):
    try:
        v = np.asarray(emb, dtype=np.float32).ravel()
    except (TypeError, ValueError):
        return None
    if v.size == 0 or not np.isfinite(v).all():
        return None
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-6 else None


class OnlineSpeakers:
    def __init__(self, min_sim=profiles.CLUSTER_MIN_SIM, max_k=profiles.CLUSTER_MAX, keep=KEEP,
                 refine_every=REFINE_EVERY):
        self.min_sim, self.max_k, self.keep, self.refine_every = min_sim, max(1, int(max_k)), max(4, int(keep)), \
            max(2, int(refine_every))
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        """Alles vergessen (Gespräch löschen): die Nummerierung beginnt wieder bei 1."""
        with self.lock:
            self.embs, self.nums = [], []        # parallel: Abdruck, vergebene (Roh-)Nummer
            self.sums = {}                       # Nummer -> Summe der Abdrücke
            self.alias = {}                      # zusammengelegte Nummer -> bleibende Nummer
            self.next, self.count, self.dim = 1, 0, None

    def _canon(self, n):
        seen = 0
        while n in self.alias and seen < 64:
            n, seen = self.alias[n], seen + 1
        return n

    def speakers(self):
        """Aktuell gültige Nummern (aufsteigend)."""
        with self.lock:
            return sorted(self.sums)

    def _cent(self, n):
        s = self.sums[n]
        return s / (float(np.linalg.norm(s)) + 1e-9)

    def assign(self, emb):
        """Stimmabdruck -> Sprechernummer (1, 2, …) oder None (kein/ungültiger Abdruck, anderes Modell)."""
        v = _unit(emb)
        if v is None:
            return None
        with self.lock:
            if self.dim is not None and v.size != self.dim:
                return None                      # anderes Stimmmodell mitten im Gespräch: nicht mischen
            self.dim = v.size
            best, sim = None, -1.0
            for n in self.sums:
                s = float(self._cent(n) @ v)
                if s > sim:
                    best, sim = n, s
            if best is None or sim < self.min_sim:
                if len(self.sums) < self.max_k:
                    best = self.next
                    self.next += 1
                    self.sums[best] = np.zeros_like(v)
                # sonst: der ähnlichste Sprecher (Obergrenze erreicht)
            self.sums[best] = self.sums[best] + v
            self.embs.append(v)
            self.nums.append(best)
            if len(self.embs) > self.keep:
                del self.embs[0], self.nums[0]
            self.count += 1
            if self.count % self.refine_every == 0 and len(self.sums) > 1:
                self._refine()
            return self._canon(best)

    def _refine(self):
        """cluster_speakers über die gemerkten Abdrücke: Nummern, deren Äußerungen in dieselbe Gruppe fallen UND
        deren Zentroide nahe genug liegen, werden zusammengelegt. Nie umnummeriert, nur Alias für künftige."""
        try:
            lab = profiles.cluster_speakers(self.embs, self.min_sim, self.max_k)
        except Exception:
            return
        if len(lab) != len(self.embs):
            return
        votes = {}
        for n, c in zip(self.nums, lab):
            votes.setdefault(n, {}).setdefault(c, 0)
            votes[n][c] += 1
        group = {}
        for n in sorted(votes):
            if n in self.alias:
                continue
            c = max(votes[n], key=lambda k: (votes[n][k], -k))
            group.setdefault(c, []).append(n)
        for members in group.values():
            keep = members[0]
            for other in members[1:]:
                if float(self._cent(keep) @ self._cent(other)) >= self.min_sim - MERGE_VETO:
                    self.sums[keep] = self.sums[keep] + self.sums.pop(other)
                    self.alias[other] = keep
                    for k, v in list(self.alias.items()):
                        if v == other:
                            self.alias[k] = keep
                    self.nums = [keep if x == other else x for x in self.nums]
