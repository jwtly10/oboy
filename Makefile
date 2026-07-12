.PHONY: run test

run:
	odin run src

test:
	odin test tests/  -vet -all-packages