.PHONY: bootstrap start stop smoke clean harness

bootstrap:
	bash scripts/bootstrap.sh

start:
	bash scripts/start_all.sh

stop:
	bash scripts/stop_all.sh

smoke:
	bash scripts/smoke_test.sh

clean:
	bash scripts/clean_workspace.sh

harness:
	python3 scripts/tool_harness.py
