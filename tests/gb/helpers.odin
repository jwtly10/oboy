package gb_tests

import gb "../../src/gb"

Test_Rom_Byte :: struct {
	address: u16,
	value:   u8,
}

make_test_bus :: proc(program: []u8) -> gb.Bus {
	return make_test_bus_with_rom(program, nil)
}

make_test_bus_with_rom :: proc(program: []u8, rom_bytes: []Test_Rom_Byte) -> gb.Bus {
	rom := make([]u8, 0x8000, context.temp_allocator)
	copy(rom[0x0100:], program)
	for rom_byte in rom_bytes {
		rom[rom_byte.address] = rom_byte.value
	}
	return make_test_bus_from_rom(rom)
}

make_test_bus_from_rom :: proc(
	rom: []u8,
	cartridge_type: u8 = 0x00,
	ram_size_code: u8 = 0x00,
) -> gb.Bus {
	header := gb.ROM_Header {
		cartridge_type = cartridge_type,
		ram_size_code  = ram_size_code,
	}
	bus, _ := gb.Bus_init(rom, &header, context.temp_allocator)
	return bus
}

make_test_cpu :: proc() -> gb.Cpu {
	return gb.Cpu{pc = 0x0100, sp = 0xFFFE, trace = true}
}
