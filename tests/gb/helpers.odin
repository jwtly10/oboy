package gb_tests

import gb "../../src/gb"

make_test_bus :: proc(program: []u8) -> gb.Bus {
	rom := make([]u8, 0x8000, context.temp_allocator)
	copy(rom[0x0100:], program)
	return gb.Bus_init(rom)
}

make_test_cpu :: proc() -> gb.Cpu {
	return gb.Cpu{pc = 0x0100, sp = 0xFFFE, trace = true}
}
