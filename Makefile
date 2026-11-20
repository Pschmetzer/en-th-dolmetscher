# Hilfen fuer Beitragende ohne Mac (Presets, Web, Doku). Die Engine-Tests brauchen requirements-dev.txt (siehe CONTRIBUTING.md).
PY ?= python3
# Bekannte Umgebungsfehler ohne Apple-Silicon-Mac (say, swiftc, uv): tests/test_env_logic_swift.py und tests/test_setup_env.py.
# Dort ausschliessen: make test PYTEST_ARGS="$(IGNORE_ENV)"
PYTEST_ARGS ?=
IGNORE_ENV = --ignore=tests/test_env_logic_swift.py --ignore=tests/test_setup_env.py

.PHONY: test test-mac test-web web-test lint check web presets-index audit cov lock stats

test:            ## alle Tests wie die CI-Linux-Jobs (ohne Marker macos)
	$(PY) -m pytest -q -m "not macos" $(PYTEST_ARGS) tests

test-mac:        ## nur Tests mit Marker macos (say, swiftc, setup-env.sh; nur auf dem Mac)
	$(PY) -m pytest -q -m macos tests

test-web:        ## nur Web, Pakete, Sprachen (schnell, braucht node)
	$(PY) -m pytest -q $(PYTEST_ARGS) tests -k "web or preset or l10n or languages or index_html or runde7"

web-test: test-web  ## Alias fuer test-web

lint:            ## ruff wie in der CI, dazu Syntaxpruefung der Skripte
	ruff check ./*.py bench/ tests/ tools/
	bash -n build.sh
	for f in build-support/*.sh; do bash -n "$$f"; done

check:           ## alles wie in der CI: ruff + pytest (tools/check_all.sh)
	bash tools/check_all.sh

web:             ## Web-Version lokal: http://localhost:8000
	$(PY) -m http.server 8000

presets-index:   ## presets-index.json nach Aenderungen an presets/ neu erzeugen
	$(PY) tools/make_presets_index.py

stats:           ## Phrasenpakete: Abdeckung je Kategorie und je Paket
	$(PY) tools/preset_stats.py --by-category
	$(PY) tools/preset_stats.py

cov:             ## Tests mit Abdeckung (wie der CI-Job, braucht requirements-dev.txt)
	$(PY) -m pytest -q -m "not macos" $(PYTEST_ARGS) --cov --cov-report=term tests

audit:           ## bekannte Schwachstellen in den Lock-Dateien (pip-audit, braucht Netz)
	$(PY) -m pip_audit --disable-pip --require-hashes -r requirements.txt
	$(PY) -m pip_audit --disable-pip --require-hashes -r requirements-dev.txt

lock:            ## Lock-Dateien aus den .in-Dateien neu erzeugen (braucht uv; Befehle stehen in den .in-Dateien)
	uv pip compile requirements.in --universal --python-version 3.12 --generate-hashes -o requirements.txt
	uv pip compile requirements-dev.in -c requirements.txt --universal --python-version 3.12 --generate-hashes -o requirements-dev.txt
