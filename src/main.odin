package main

import "core:fmt"
import "core:os"
import "gb"

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "--display-test" {
		gb.dump_ppu_test_frame()
		return
	}

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

	machine, m_ok := gb.Machine_init(rom, &header, context.allocator)
	if !m_ok {
		fmt.println("Could not initialise machine")
		return
	}
	defer gb.Machine_destroy(&machine)

	count := 0
	for i := 0; i < 10_000_000; i += 1 {
		count += 1
		ok := gb.Machine_step(&machine)
		if !ok {
			fmt.println("Could not step machine")
			break
		}
	}

	fmt.printfln("Executed %v instructions", count)
}
