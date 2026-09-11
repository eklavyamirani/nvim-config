.PHONY: deps test check-config test-config test-review test-lsp

# Thin wrappers over the cross-platform scripts; on Windows run them with `nvim -l` directly.
NVIM ?= nvim
RUN_TESTS = $(NVIM) -l scripts/run_tests.lua

test:
	$(RUN_TESTS) check config review

deps:
	$(NVIM) -l scripts/install_deps.lua

check-config:
	$(RUN_TESTS) check

test-config:
	$(RUN_TESTS) config

test-review:
	$(RUN_TESTS) review

# Needs the servers from `make deps`.
test-lsp:
	$(RUN_TESTS) lsp
