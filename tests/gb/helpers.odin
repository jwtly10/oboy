package gb_tests

import gb "../../src/gb"

make_test_bus :: proc(program: []u8) -> gb.Bus {
	bus: gb.Bus
	start := 0x0100

	copy(bus.memory[start:start + len(program)], program)
	return bus
}

make_test_cpu :: proc() -> gb.Cpu {
	return gb.Cpu{pc = 0x0100, sp = 0xFFFE}
}
