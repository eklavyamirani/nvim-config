.PHONY: deps test check-config test-config test-review test-lsp

NVIM ?= nvim
NVIM_HEADLESS = $(NVIM) --headless --cmd "set runtimepath^=$(CURDIR)"

test: check-config test-config test-review

# Language servers; on Windows run `nvim -l scripts/install_deps.lua` directly.
deps:
	$(NVIM) -l scripts/install_deps.lua

check-config:
	python3 scripts/check_config.py

test-config:
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/config.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/csharp_lsp.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/lsp_servers.lua')"

# Needs the servers from `make deps`.
test-lsp:
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/python_lsp.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/diffview_lsp.lua')"

test-review:
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_context.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_route.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_tree.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_group_tree.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_worktree.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/review_startup.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/review_reading.lua')"
