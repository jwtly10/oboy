package gb_tests

import "../../src/gb"
import "core:testing"

// --- Bus 16-bit write helper tests ---

@(test)
test_bus_write_u16_writes_little_endian :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.bus_write_u16(&bus, 0xC000, 0x1234)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC000) == 0x34,
		"Expected low byte at the starting address",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC001) == 0x12,
		"Expected high byte at the next address",
	)
}

@(test)
test_bus_write_u16_wraps_at_end_of_address_space :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.bus_write_u16(&bus, 0xFFFF, 0xABCD)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0xCD,
		"Expected low byte at address 0xFFFF",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0xAB,
		"Expected high byte to wrap to address 0x0000",
	)
}

