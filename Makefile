clean_test:
	rm -rf ./test_playground/*

run-all-dry:
	./run-all.sh --dry-run all

tree:
	tree ./test_playground/

run_test: clean_test run-all-dry tree

check_script:
	shellcheck --shell=sh ./run.sh

lint:
	golangci-lint run ./...

generate:
	python3 update_dashboard.py
