.PHONY: bootstrap start stop smoke clean harness

bootstrap:
	bash scripts/bootstrap_all.sh

start:
	bash scripts/run_local.sh

stop:
	bash scripts/stop_all.sh

smoke:
	bash scripts/smoke_test.sh

clean:
	bash scripts/clean_workspace.sh

harness:
	python3 scripts/tool_harness.py
