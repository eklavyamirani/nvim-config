.PHONY: test check-config test-config test-review

NVIM ?= nvim
NVIM_HEADLESS = $(NVIM) --headless --cmd "set runtimepath^=$(CURDIR)"

test: check-config test-config test-review

check-config:
	python3 scripts/check_config.py

test-config:
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/config.lua')"

test-review:
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_context.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_route.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_tree.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_group_tree.lua')"
	$(NVIM_HEADLESS) -u NONE -c "lua dofile('tests/review_worktree.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/review_startup.lua')"
	$(NVIM_HEADLESS) -u init.lua -c "lua dofile('tests/review_reading.lua')"
