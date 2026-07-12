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
		gb.bus_read_byte(&bus, 0x0000) == 0x00,
		"Expected the wrapped high-byte write to cartridge ROM to be ignored",
	)
}

// --- Bus memory map tests ---

@(test)
test_bus_read_write_regions_cover_boundaries :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	addresses := [10]u16 {
		0x8000,
		0x9FFF,
		0xC000,
		0xDFFF,
		0xFE00,
		0xFE9F,
		0xFF00,
		0xFF7F,
		0xFF80,
		0xFFFE,
	}

	for address, index in addresses {
		value := u8(index + 1)
		gb.bus_write_byte(&bus, address, value)
		testing.expect(
			t,
			gb.bus_read_byte(&bus, address) == value,
			"Expected mapped memory boundary to retain its byte",
		)
	}

	gb.bus_write_byte(&bus, 0xFFFF, 0xA5)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0xA5,
		"Expected interrupt-enable register to retain its byte",
	)
}

@(test)
test_bus_echo_ram_mirrors_work_ram_in_both_directions :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.bus_write_byte(&bus, 0xC000, 0x12)
	gb.bus_write_byte(&bus, 0xFDFF, 0x34)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xE000) == 0x12,
		"Expected echo RAM to mirror the start of work RAM",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xDDFF) == 0x34,
		"Expected a write at the end of echo RAM to update work RAM",
	)
}

@(test)
test_bus_unusable_oam_area_reads_ff_and_ignores_writes :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.bus_write_byte(&bus, 0xFEA0, 0x12)
	gb.bus_write_byte(&bus, 0xFEFF, 0x34)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFEA0) == 0xFF,
		"Expected the start of unusable memory to read as 0xFF",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFEFF) == 0xFF,
		"Expected the end of unusable memory to read as 0xFF",
	)
}

@(test)
test_bus_read_u16_reads_little_endian_and_wraps_address_space :: proc(t: ^testing.T) {
	bus := make_test_bus_with_rom([]u8{}, []Test_Rom_Byte{{0x0000, 0xAB}})
	gb.bus_write_byte(&bus, 0xC000, 0x34)
	gb.bus_write_byte(&bus, 0xC001, 0x12)
	gb.bus_write_byte(&bus, 0xFFFF, 0xCD)

	testing.expect(
		t,
		gb.bus_read_u16_le(&bus, 0xC000) == 0x1234,
		"Expected a little-endian 16-bit read",
	)
	testing.expect(
		t,
		gb.bus_read_u16_le(&bus, 0xFFFF) == 0xABCD,
		"Expected a 16-bit read to wrap from 0xFFFF to ROM",
	)
}
