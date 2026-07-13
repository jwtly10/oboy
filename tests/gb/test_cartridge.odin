package gb_tests

import "../../src/gb"
import "core:mem"
import "core:testing"

// --- Cartridge ROM and RAM mapping tests ---

@(test)
test_cartridge_maps_loaded_rom_data :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	rom[0x0000] = 0x12
	rom[0x0001] = 0x34
	bus := make_test_bus_from_rom(rom)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0x12,
		"Expected the first ROM byte at 0x0000",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0001) == 0x34,
		"Expected the second ROM byte at 0x0001",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0002) == 0x00,
		"Expected zero-filled ROM data to remain mapped",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x7FFF) == 0x00,
		"Expected the final byte of ROM to remain mapped",
	)
}

@(test)
test_cartridge_ignores_rom_writes_and_disabled_ram_writes :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	rom[0x0000] = 0x42
	bus := make_test_bus_from_rom(rom)

	gb.bus_write_byte(&bus, 0x0000, 0x99)
	gb.bus_write_byte(&bus, 0xA000, 0x77)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0x42,
		"Expected writes not to modify cartridge ROM",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected disabled cartridge RAM to read as 0xFF",
	)
}

// --- MBC3 cartridge banking tests ---

@(test)
test_mbc3_initial_rom_mapping_uses_banks_zero_and_one :: proc(t: ^testing.T) {
	rom := make([]u8, 2 * 0x4000, context.temp_allocator)
	rom[0x0000] = 0x10
	rom[0x3FFF] = 0x1F
	rom[0x4000] = 0x20
	rom[0x7FFF] = 0x2F
	bus := make_test_bus_from_rom(rom, 0x13)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0x10,
		"Expected 0x0000 to read from the start of ROM bank zero",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x3FFF) == 0x1F,
		"Expected 0x3FFF to read from the end of ROM bank zero",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x20,
		"Expected 0x4000 to read from the start of ROM bank one",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x7FFF) == 0x2F,
		"Expected 0x7FFF to read from the end of ROM bank one",
	)
}

@(test)
test_mbc3_switches_rom_banks_in_4000_to_7fff :: proc(t: ^testing.T) {
	rom := make([]u8, 4 * 0x4000, context.temp_allocator)
	rom[0x0000] = 0x00
	rom[0x4000] = 0x11
	rom[0x8000] = 0x22
	rom[0xC000] = 0x33
	bus := make_test_bus_from_rom(rom, 0x13)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x11,
		"Expected ROM bank one to be selected initially",
	)
	gb.bus_write_byte(&bus, 0x2000, 0x02)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x22,
		"Expected ROM bank two after selecting bank two",
	)
	gb.bus_write_byte(&bus, 0x2000, 0x03)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x33,
		"Expected ROM bank three after selecting bank three",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0x00,
		"Expected the fixed ROM bank to remain bank zero",
	)
}

@(test)
test_mbc3_rom_bank_zero_selection_maps_bank_one :: proc(t: ^testing.T) {
	rom := make([]u8, 2 * 0x4000, context.temp_allocator)
	rom[0x4000] = 0x11
	bus := make_test_bus_from_rom(rom, 0x13)

	gb.bus_write_byte(&bus, 0x2000, 0x00)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x11,
		"Expected MBC3 ROM bank zero selection to map bank one",
	)
}

@(test)
test_mbc3_ram_is_disabled_by_default_and_enable_value_controls_access :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x03)

	gb.bus_write_byte(&bus, 0xA000, 0x12)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected cartridge RAM to be disabled initially",
	)
	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	gb.bus_write_byte(&bus, 0xA000, 0x34)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0x34,
		"Expected 0x0A in the RAM-enable range to enable cartridge RAM",
	)
	gb.bus_write_byte(&bus, 0x1FFF, 0x00)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected any value other than 0x0A to disable cartridge RAM",
	)
	gb.bus_write_byte(&bus, 0x1FFF, 0x0A)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0x34,
		"Expected re-enabled cartridge RAM to retain its value",
	)
}

@(test)
test_mbc3_ram_banks_retain_independent_values :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x03)
	values := [4]u8{0x10, 0x21, 0x32, 0x43}

	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	for value, bank in values {
		gb.bus_write_byte(&bus, 0x4000, u8(bank))
		gb.bus_write_byte(&bus, 0xA000, value)
	}

	for value, bank in values {
		gb.bus_write_byte(&bus, 0x4000, u8(bank))
		testing.expect(
			t,
			gb.bus_read_byte(&bus, 0xA000) == value,
			"Expected each MBC3 RAM bank to retain its own value",
		)
	}
}

// --- Cartridge RAM size tests ---

@(test)
test_cartridge_ram_size_codes_limit_addressable_ram :: proc(t: ^testing.T) {
	cases := [?]struct {
		code:             u8,
		last_address:     u16,
		outside_address:  u16,
		has_outside_byte: bool,
	}{{0x02, 0xBFFF, 0x0000, false}}

	for test_case in cases {
		rom := make([]u8, 0x8000, context.temp_allocator)
		bus := make_test_bus_from_rom(rom, 0x13, test_case.code)
		gb.bus_write_byte(&bus, 0x0000, 0x0A)
		gb.bus_write_byte(&bus, test_case.last_address, 0x5A)

		testing.expect(
			t,
			gb.bus_read_byte(&bus, test_case.last_address) == 0x5A,
			"Expected the final byte provided by the RAM size code to be addressable",
		)
		if test_case.has_outside_byte {
			gb.bus_write_byte(&bus, test_case.outside_address, 0xA5)
			testing.expect(
				t,
				gb.bus_read_byte(&bus, test_case.outside_address) == 0xFF,
				"Expected an address beyond allocated cartridge RAM to read as 0xFF",
			)
		}
	}
}

@(test)
test_cartridge_without_ram_always_reads_ff :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x00)

	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	gb.bus_write_byte(&bus, 0xA000, 0x42)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected a cartridge with no RAM to read 0xFF",
	)
}

// --- MBC3 register boundary and masking tests ---

@(test)
test_mbc3_ram_enable_uses_low_nibble_at_both_register_boundaries :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x02)

	gb.bus_write_byte(&bus, 0x0000, 0x1A)
	gb.bus_write_byte(&bus, 0xA000, 0x37)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0x37,
		"Expected a low nibble of 0xA to enable RAM",
	)

	gb.bus_write_byte(&bus, 0x1FFF, 0x1B)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected a low nibble other than 0xA to disable RAM",
	)
}

@(test)
test_mbc3_rom_bank_register_masks_bit_seven_at_both_boundaries :: proc(t: ^testing.T) {
	rom := make([]u8, 4 * 0x4000, context.temp_allocator)
	rom[0x4000] = 0x11
	rom[0x8000] = 0x22
	bus := make_test_bus_from_rom(rom, 0x13)

	gb.bus_write_byte(&bus, 0x2000, 0x82)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x22,
		"Expected bit seven of the ROM bank value to be ignored",
	)

	gb.bus_write_byte(&bus, 0x3FFF, 0x80)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x4000) == 0x11,
		"Expected masked bank zero to remap to bank one",
	)
}

@(test)
test_mbc3_rtc_selection_blocks_ram_and_ram_selection_restores_it :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x10, 0x03)

	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	gb.bus_write_byte(&bus, 0x4000, 0x02)
	gb.bus_write_byte(&bus, 0xA000, 0x52)
	gb.bus_write_byte(&bus, 0x5FFF, 0x08)

	gb.bus_write_byte(&bus, 0xA000, 0x99)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected selected unimplemented RTC register to read as 0xFF",
	)

	gb.bus_write_byte(&bus, 0x4000, 0x02)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0x52,
		"Expected selecting RAM again to restore access to the prior bank",
	)
}

@(test)
test_all_mbc3_cartridge_types_dispatch_bank_control_writes :: proc(t: ^testing.T) {
	cartridge_types := [5]u8{0x0F, 0x10, 0x11, 0x12, 0x13}

	for cartridge_type in cartridge_types {
		rom := make([]u8, 4 * 0x4000, context.temp_allocator)
		rom[0x8000] = 0x22
		bus := make_test_bus_from_rom(rom, cartridge_type)

		gb.bus_write_byte(&bus, 0x2000, 0x02)
		testing.expect(
			t,
			gb.bus_read_byte(&bus, 0x4000) == 0x22,
			"Expected every MBC3 cartridge type to dispatch ROM bank writes",
		)
	}
}

// --- Cartridge type validation tests ---

@(test)
test_supported_cartridge_types_initialize :: proc(t: ^testing.T) {
	cartridge_types := [6]u8{0x00, 0x0F, 0x10, 0x11, 0x12, 0x13}
	rom := make([]u8, 0x8000, context.temp_allocator)

	for cartridge_type in cartridge_types {
		header := gb.ROM_Header {
			cartridge_type = cartridge_type,
		}
		bus, ok := gb.Bus_init(rom, &header)

		testing.expect(t, ok, "Expected every implemented cartridge type to initialize")
		if ok {
			gb.Bus_destroy(&bus)
		}
	}
}

@(test)
test_unimplemented_and_unknown_cartridge_types_fail_initialization_without_leaking :: proc(
	t: ^testing.T,
) {
	cartridge_types := [7]u8{0x01, 0x02, 0x03, 0x19, 0x1A, 0x1B, 0xFF}
	rom := make([]u8, 0x8000, context.temp_allocator)
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.temp_allocator, context.temp_allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	allocator := mem.tracking_allocator(&tracker)

	for cartridge_type in cartridge_types {
		header := gb.ROM_Header {
			cartridge_type = cartridge_type,
			ram_size_code  = 0x03,
		}
		_, ok := gb.Bus_init(rom, &header, allocator)

		testing.expect(
			t,
			!ok,
			"Expected unimplemented and unknown cartridge types to fail initialization",
		)
	}

	testing.expect(
		t,
		len(tracker.allocation_map) == 0,
		"Expected failed cartridge initialization to release allocated RAM",
	)
}

@(test)
test_unused_ram_size_code_does_not_provide_cartridge_ram :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x01)

	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	gb.bus_write_byte(&bus, 0xA000, 0x5A)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0xFF,
		"Expected unused RAM size code 0x01 not to provide cartridge RAM",
	)
}

@(test)
test_mbc3_unmapped_ram_bank_wraps_to_installed_ram :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	bus := make_test_bus_from_rom(rom, 0x13, 0x02)

	gb.bus_write_byte(&bus, 0x0000, 0x0A)
	gb.bus_write_byte(&bus, 0x4000, 0x00)
	gb.bus_write_byte(&bus, 0xA000, 0x37)
	gb.bus_write_byte(&bus, 0x4000, 0x01)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xA000) == 0x37,
		"Expected an unmapped MBC3 RAM bank to wrap to installed RAM",
	)
}

@(test)
test_unknown_ram_size_code_fails_initialization :: proc(t: ^testing.T) {
	rom := make([]u8, 0x8000, context.temp_allocator)
	header := gb.ROM_Header {
		cartridge_type = 0x13,
		rom_size_code  = 0x00,
		ram_size_code  = 0x06,
	}

	_, ok := gb.Bus_init(rom, &header, context.temp_allocator)

	testing.expect(t, !ok, "Expected an unknown RAM size code to fail initialization")
}
