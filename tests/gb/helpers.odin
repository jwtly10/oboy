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
	rom_size_code: u8
	switch len(rom) {
	case 32 * 1024:
		rom_size_code = 0x00
	case 64 * 1024:
		rom_size_code = 0x01
	case 128 * 1024:
		rom_size_code = 0x02
	case 256 * 1024:
		rom_size_code = 0x03
	case 512 * 1024:
		rom_size_code = 0x04
	case 1024 * 1024:
		rom_size_code = 0x05
	case 2 * 1024 * 1024:
		rom_size_code = 0x06
	case 4 * 1024 * 1024:
		rom_size_code = 0x07
	case 8 * 1024 * 1024:
		rom_size_code = 0x08
	case 72 * 0x4000:
		rom_size_code = 0x52
	case 80 * 0x4000:
		rom_size_code = 0x53
	case 96 * 0x4000:
		rom_size_code = 0x54
	case:
		assert(false, "Test ROM must have a valid Game Boy ROM size")
	}

	header := gb.ROM_Header {
		cartridge_type = cartridge_type,
		rom_size_code  = rom_size_code,
		ram_size_code  = ram_size_code,
	}
	bus, ok := gb.Bus_init(rom, &header, context.temp_allocator)
	assert(ok, "Failed to initialize test bus")
	return bus
}

make_test_cpu :: proc() -> gb.Cpu {
	return gb.Cpu{pc = 0x0100, sp = 0xFFFE, trace = true}
}
