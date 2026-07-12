package gb_tests

import "../../src/gb"
import "core:testing"

@(test)
test_nop :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x00})
	cpu := make_test_cpu()

	_, ok := gb.Cpu_step(&cpu, &bus)
	testing.expect(t, ok, "Expected NOP to not error")
	testing.expect(t, cpu.pc == 0x0101, "Expected to bump PC to bump to 0x0101")
}
