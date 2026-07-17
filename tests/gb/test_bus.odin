package gb_tests

import "../../src/gb"
import "core:fmt"
import "core:testing"

// --- Bus 16-bit write helper tests ---

@(test)
test_cpu_bus_write_u16_writes_little_endian :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.cpu_bus_write_u16(&bus, 0xC000, 0x1234)

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
test_cpu_bus_write_u16_wraps_at_end_of_address_space :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.cpu_bus_write_u16(&bus, 0xFFFF, 0xABCD)

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
		0xFF01,
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

	gb.bus_write_byte(&bus, 0xFF00, 0x20)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF00) == 0xEF,
		"Expected JOYP to expose writable selection bits and released buttons",
	)

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

// --- OAM DMA tests ---

dma_tick_many :: proc(bus: ^gb.Bus, t_cycles: int) {
	for _ in 0 ..< t_cycles {
		gb.dma_tick(bus)
	}
}

@(test)
test_dma_register_write_starts_transfer_from_selected_page :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})

	gb.bus_write_byte(&bus, 0xFF46, 0xC1)

	testing.expect(t, bus.dma.active, "Expected a DMA register write to start a transfer")
	testing.expect(t, !bus.dma.locked, "Expected the CPU bus to remain unlocked during startup")
	testing.expect(t, bus.dma.startup_delay == 4, "Expected one M-cycle of startup delay")
	testing.expect(t, bus.dma.reg == 0xC1, "Expected DMA to retain the written register value")
	testing.expect(t, bus.dma.source_start == 0xC100, "Expected DMA source to begin at XX00")
	testing.expect(t, bus.dma.byte_index == 0, "Expected a new DMA transfer to begin at byte zero")
	testing.expect(t, bus.dma.cycle_count == 0, "Expected no transfer cycle to have elapsed")
}

@(test)
test_dma_copies_selected_page_to_all_of_oam_after_startup_and_160_m_cycles :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	for index in 0 ..< 0xA0 {
		gb.bus_write_byte(&bus, 0xC100 + u16(index), u8(index ~ 0x5A))
	}

	gb.bus_write_byte(&bus, 0xFF46, 0xC1)
	dma_tick_many(&bus, 161 * 4)

	testing.expect(
		t,
		!bus.dma.active,
		"Expected DMA to finish after startup and 160 copy M-cycles",
	)
	testing.expect(t, bus.dma.byte_index == 0xA0, "Expected DMA to copy exactly 160 bytes")
	for index in 0 ..< 0xA0 {
		testing.expectf(
			t,
			bus.oam[index] == u8(index ~ 0x5A),
			"Expected DMA byte %d to be copied from the selected source page",
			index,
		)
	}
}

@(test)
test_dma_register_reads_back_last_written_source_after_transfer :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF46, 0x80)

	dma_tick_many(&bus, 161 * 4)

	got := gb.bus_read_byte(&bus, 0xFF46)
	testing.expect(
		t,
		got == 0x80,
		fmt.tprintf(
			"Expected FF46 to read back the most recently written DMA source page got: %v",
			got,
		),
	)
}

@(test)
test_dma_allows_hram_access_and_blocks_other_cpu_writes :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC000, 0x11)
	gb.bus_write_byte(&bus, 0xFF80, 0x22)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)
	dma_tick_many(&bus, 4)

	gb.cpu_bus_write_byte(&bus, 0xC000, 0x33)
	gb.cpu_bus_write_byte(&bus, 0xFF80, 0x44)

	testing.expect(
		t,
		bus.wram[0] == 0x11,
		"Expected a CPU write outside HRAM to be blocked during DMG DMA",
	)
	testing.expect(
		t,
		gb.cpu_bus_read_byte(&bus, 0xFF80) == 0x44,
		"Expected HRAM to remain readable and writable during DMG DMA",
	)
}

@(test)
test_dma_does_not_block_cpu_bus_during_startup_delay :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC000, 0x11)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)

	gb.cpu_bus_write_byte(&bus, 0xC000, 0x22)

	testing.expect(
		t,
		bus.wram[0] == 0x22,
		"Expected the CPU bus to remain available during the DMA startup M-cycle",
	)
}

@(test)
test_dma_write_during_transfer_restarts_immediately_from_new_source_page :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	for index in 0 ..< 0xA0 {
		gb.bus_write_byte(&bus, 0xC000 + u16(index), 0x11)
		gb.bus_write_byte(&bus, 0xD000 + u16(index), u8(index))
	}

	gb.bus_write_byte(&bus, 0xFF46, 0xC0)
	dma_tick_many(&bus, 3 * 4)
	gb.bus_write_byte(&bus, 0xFF46, 0xD0)
	dma_tick_many(&bus, 4)

	testing.expect(
		t,
		bus.oam[2] == 0,
		"Expected the simplified restart model to stop the old transfer immediately",
	)
	testing.expect(t, bus.dma.source_start == 0xD000, "Expected DMA to use the new source page")
	testing.expect(
		t,
		bus.dma.byte_index == 0,
		"Expected the restarted transfer to begin at byte zero",
	)
	testing.expect(t, bus.dma.locked, "Expected the CPU bus to lock after restart startup")

	dma_tick_many(&bus, 160 * 4)

	testing.expect(t, !bus.dma.active, "Expected the restarted DMA transfer to finish")
	for index in 0 ..< 0xA0 {
		testing.expectf(
			t,
			bus.oam[index] == u8(index),
			"Expected restarted DMA byte %d to come from the new source page",
			index,
		)
	}
}

// --- CPU bus accessor and OAM DMA timing tests ---

@(test)
test_cpu_bus_accessors_block_non_hram_while_internal_access_bypasses_dma :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC000, 0x11)
	gb.bus_write_byte(&bus, 0xFF80, 0x22)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)
	dma_tick_many(&bus, 4)
	bus.dma.current_value = 0xA5

	gb.cpu_bus_write_byte(&bus, 0xC000, 0x33)
	gb.cpu_bus_write_byte(&bus, 0xFF80, 0x44)

	testing.expect(
		t,
		gb.cpu_bus_read_byte(&bus, 0xC000) == 0xA5,
		"Expected a blocked CPU read to observe the current DMA bus value",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC000) == 0x11,
		"Expected the blocked CPU write not to change WRAM",
	)
	testing.expect(
		t,
		gb.cpu_bus_read_byte(&bus, 0xFF80) == 0x44,
		"Expected CPU HRAM reads and writes to remain available during DMA",
	)

	gb.bus_write_byte(&bus, 0xC000, 0x55)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC000) == 0x55,
		"Expected unrestricted internal bus access to bypass CPU DMA contention",
	)
}

@(test)
test_cpu_bus_access_remains_available_during_dma_startup_cycle :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC000, 0x11)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)

	gb.cpu_bus_write_byte(&bus, 0xC000, 0x22)

	testing.expect(
		t,
		gb.cpu_bus_read_byte(&bus, 0xC000) == 0x22,
		"Expected CPU bus access to remain available during the DMA startup M-cycle",
	)
}

@(test)
test_dma_copies_first_byte_after_one_m_cycle_startup :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC000, 0x5A)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)

	dma_tick_many(&bus, 4)
	testing.expect(t, bus.oam[0] == 0, "Expected DMA not to copy during its startup M-cycle")
	testing.expect(t, bus.dma.byte_index == 0, "Expected no byte to be copied during startup")

	dma_tick_many(&bus, 3)
	testing.expect(
		t,
		bus.oam[0] == 0,
		"Expected DMA not to copy before its first full transfer cycle",
	)

	gb.dma_tick(&bus)
	testing.expect(t, bus.oam[0] == 0x5A, "Expected DMA to copy its first byte after startup")
	testing.expect(
		t,
		bus.dma.byte_index == 1,
		fmt.tprintf(
			"Expected exactly one byte to be copied but was: %v ",
			int(bus.dma.byte_index),
		),
	)
}

@(test)
test_dma_finishes_after_startup_and_exactly_160_transfer_m_cycles :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xC09F, 0xA5)
	gb.bus_write_byte(&bus, 0xFF46, 0xC0)

	dma_tick_many(&bus, 161 * 4 - 1)
	testing.expect(
		t,
		bus.dma.active,
		"Expected DMA to remain active before its final transfer dot",
	)
	testing.expect(t, bus.dma.byte_index == 0x9F, "Expected 159 bytes before the final dot")

	gb.dma_tick(&bus)
	testing.expect(t, !bus.dma.active, "Expected DMA to finish after startup and 160 copy cycles")
	testing.expect(t, bus.dma.byte_index == 0xA0, "Expected DMA to copy all 160 bytes")
	testing.expect(t, bus.oam[0x9F] == 0xA5, "Expected the final OAM byte to be copied")
}
