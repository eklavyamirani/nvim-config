.PHONY: test test-config test-review customizations check-customizations

NVIM ?= nvim
NVIM_HEADLESS = $(NVIM) --headless --cmd "set runtimepath^=$(CURDIR)"

test: check-customizations test-config test-review

test-config:
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/config.lua')"

test-review:
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_context.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_route.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_tree.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_worktree.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/review_startup.lua')"

customizations:
	python3 scripts/customizations.py

check-customizations:
	python3 scripts/customizations.py --check
