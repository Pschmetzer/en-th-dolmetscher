# Hilfen fuer Beitragende ohne Mac (Presets, Web, Doku). Die Engine-Tests brauchen requirements-dev.txt (siehe CONTRIBUTING.md).
PY ?= python3
IGNORE_ENV = --ignore=tests/test_env_logic_swift.py --ignore=tests/test_setup_env.py

.PHONY: test test-web lint web presets-index

test:            ## alle Tests
	$(PY) -m pytest -q tests

test-web:        ## nur Web, Pakete, Sprachen (schnell, braucht node)
	$(PY) -m pytest -q tests -k "web or preset or l10n or languages or index_html or runde7"

lint:            ## ruff wie in der CI, dazu Syntaxpruefung der Skripte
	ruff check ./*.py bench/ tests/
	bash -n build.sh
	for f in build-support/*.sh; do bash -n "$$f"; done

web:             ## Web-Version lokal: http://localhost:8000
	$(PY) -m http.server 8000

presets-index:   ## presets-index.json nach Aenderungen an presets/ neu erzeugen
	$(PY) tools/make_presets_index.py
