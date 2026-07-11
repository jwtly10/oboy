package main

import "core:fmt"
import "core:os"

main :: proc() {
	file_path := "roms/Pokemon Red.gb"
	rom, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.println("Could not read file, aborting")
		return
	}
	defer delete(rom, context.allocator)


	header, ok := parse_rom_header(rom)
	if !ok {
		fmt.println("Header parsing failed")
		return
	}
	print_rom_header(&header)
}
