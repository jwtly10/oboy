.PHONY: run test display-test

run:
	odin run src

test:
	odin test tests/  -vet -all-packages

display-test:
	odin run src -- --display-test
