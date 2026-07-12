package main

import "core:fmt"
import "core:os"
import "gb"

main :: proc() {
	file_path := "roms/Pokemon Red.gb"
	rom, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.println("Could not read file, aborting")
		return
	}
	defer delete(rom, context.allocator)


	header, ok := gb.Parse_rom_header(rom)
	if !ok {
		fmt.println("Header parsing failed")
		return
	}
	gb.Print_rom_header(&header)

	bus := gb.Bus_init(rom)
	cpu := gb.Cpu_init_post_boot()

	for i := 0; i < 3; i += 1 {
		_, ok := gb.Cpu_step(&cpu, &bus)
		if !ok {
			break
		}
	}
}
