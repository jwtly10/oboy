.PHONY: run test build

run:
	odin run src -- "roms/Pokemon Red.gb"

build:
	odin build src -o:speed -out:oboy

test:
	odin test tests/ -vet -all-packages