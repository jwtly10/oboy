package gb_tests

import "../../src/gb"
import "core:testing"

// --- PPU state machine tests ---

ppu_tick_many :: proc(bus: ^gb.Bus, t_cycles: int) {
	for _ in 0 ..< t_cycles {
		gb.ppu_tick(bus)
	}
}

@(test)
test_ppu_disabled_resets_timing_and_enters_hblank :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	bus.ppu.dot = 123
	bus.ppu.ly = 42
	bus.ppu.stat = 0b0111_1011
	bus.ppu.mode = .DRAWING

	gb.ppu_tick(&bus)

	testing.expect(t, bus.ppu.dot == 0, "Expected a disabled LCD to reset the dot counter")
	testing.expect(t, bus.ppu.ly == 0, "Expected a disabled LCD to reset LY")
	testing.expect(t, bus.ppu.mode == .HBLANK, "Expected a disabled LCD to remain in mode 0")
	testing.expect(t, bus.ppu.stat & 0b11 == 0, "Expected STAT mode bits to report HBlank")
}

@(test)
test_ppu_visible_scanline_enters_modes_at_dot_boundaries :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	ppu_tick_many(&bus, 1)
	testing.expect(t, bus.ppu.dot == 1, "Expected one PPU dot to elapse")
	testing.expect(t, bus.ppu.mode == .OAM, "Expected visible scanline to begin in OAM mode")
	testing.expect(t, bus.ppu.stat & 0b11 == 2, "Expected STAT to report OAM mode")

	ppu_tick_many(&bus, 79)
	testing.expect(t, bus.ppu.dot == 80, "Expected OAM scan to last 80 dots")
	testing.expect(t, bus.ppu.mode == .DRAWING, "Expected drawing mode to begin at dot 80")
	testing.expect(t, bus.ppu.stat & 0b11 == 3, "Expected STAT to report drawing mode")

	ppu_tick_many(&bus, 172)
	testing.expect(t, bus.ppu.dot == 252, "Expected baseline drawing to end at dot 252")
	testing.expect(t, bus.ppu.mode == .HBLANK, "Expected HBlank to begin after drawing")
	testing.expect(t, bus.ppu.stat & 0b11 == 0, "Expected STAT to report HBlank mode")
}

@(test)
test_ppu_scanline_wrap_enters_oam_for_next_visible_line :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	ppu_tick_many(&bus, 456)

	testing.expect(t, bus.ppu.dot == 0, "Expected dot counter to wrap after 456 dots")
	testing.expect(t, bus.ppu.ly == 1, "Expected LY to increment after one scanline")
	testing.expect(t, bus.ppu.mode == .OAM, "Expected the next visible line to begin in OAM mode")
	testing.expect(t, bus.ppu.stat & 0b11 == 2, "Expected STAT to report OAM at dot 0")
}

@(test)
test_ppu_enters_vblank_and_requests_interrupt_at_line_144 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.bus_write_byte(&bus, 0xFF0F, 0x10)

	ppu_tick_many(&bus, 144 * 456)

	testing.expect(t, bus.ppu.dot == 0, "Expected VBlank to begin at dot 0")
	testing.expect(t, bus.ppu.ly == 144, "Expected VBlank to begin on line 144")
	testing.expect(t, bus.ppu.mode == .VBLANK, "Expected line 144 to begin in VBlank mode")
	testing.expect(t, bus.ppu.stat & 0b11 == 1, "Expected STAT to report VBlank mode")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) == 0x11,
		"Expected VBlank to set IF bit 0 without changing other interrupt requests",
	)
}

@(test)
test_ppu_lyc_coincidence_flag_tracks_equal_and_unequal_values :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	gb.ppu_tick(&bus)
	testing.expect(t, bus.ppu.ly == 0, "Expected PPU to begin on line 0")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF41) & 0b100 != 0,
		"Expected coincidence flag to set when LY and LYC are both 0",
	)

	gb.bus_write_byte(&bus, 0xFF45, 1)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF41) & 0b100 == 0,
		"Expected coincidence flag to clear immediately when LYC differs from LY",
	)

	ppu_tick_many(&bus, 455)

	testing.expect(t, bus.ppu.ly == 1, "Expected LY to reach the comparison line")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF41) & 0b100 != 0,
		"Expected coincidence flag to set when LY advances to LYC",
	)

	ppu_tick_many(&bus, 456)
	testing.expect(t, bus.ppu.ly == 2, "Expected LY to advance beyond the comparison line")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF41) & 0b100 == 0,
		"Expected coincidence flag to clear when LY advances beyond LYC",
	)

	gb.bus_write_byte(&bus, 0xFF45, 2)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF41) & 0b100 != 0,
		"Expected coincidence flag to set immediately when LYC changes to equal LY",
	)
}

// --- STAT interrupt opcode tests ---

@(test)
test_stat_lyc_interrupt_requests_on_rising_edge_and_preserves_if :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.bus_write_byte(&bus, 0xFF0F, 0x15)
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF41, 0x40)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) == 0x15,
		"Expected an unequal LYC value not to request STAT",
	)

	ppu_tick_many(&bus, 456)

	testing.expect(t, bus.ppu.ly == 1, "Expected LY to reach LYC")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) == 0x17,
		"Expected LYC equality to set IF bit 1 without changing other requests",
	)
}

@(test)
test_stat_lyc_interrupt_does_not_repeat_until_source_goes_low :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.ppu_tick(&bus)
	gb.bus_write_byte(&bus, 0xFF41, 0x40)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected enabling LYC while equal to request STAT",
	)

	gb.bus_write_byte(&bus, 0xFF0F, 0)
	ppu_tick_many(&bus, 8)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 == 0,
		"Expected a high STAT line not to request another interrupt",
	)

	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF45, 0)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected a new LYC low-to-high transition to request STAT again",
	)
}

@(test)
test_stat_mode_2_interrupt_requests_when_oam_begins :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF41, 0x20)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	gb.ppu_tick(&bus)

	testing.expect(t, bus.ppu.mode == .OAM, "Expected the visible line to be in OAM mode")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected entry into enabled mode 2 to request STAT",
	)
}

@(test)
test_stat_mode_0_interrupt_requests_when_hblank_begins :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF41, 0x08)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	ppu_tick_many(&bus, 252)

	testing.expect(t, bus.ppu.dot == 252, "Expected the PPU to reach the HBlank boundary")
	testing.expect(t, bus.ppu.mode == .HBLANK, "Expected mode 0 to begin at dot 252")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected entry into enabled mode 0 to request STAT",
	)
}

@(test)
test_stat_mode_1_interrupt_requests_when_vblank_begins :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF41, 0x10)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	ppu_tick_many(&bus, 144 * 456)

	testing.expect(t, bus.ppu.mode == .VBLANK, "Expected mode 1 to begin on line 144")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x03 == 0x03,
		"Expected VBlank entry to request both VBlank and enabled mode 1 STAT interrupts",
	)
}

@(test)
test_stat_sources_share_one_interrupt_line :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.ppu_tick(&bus)
	gb.bus_write_byte(&bus, 0xFF41, 0x60)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected the first enabled STAT source to request an interrupt",
	)

	gb.bus_write_byte(&bus, 0xFF0F, 0)
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF45, 0)

	testing.expect(t, bus.ppu.mode == .OAM, "Expected mode 2 to keep the shared STAT line high")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 == 0,
		"Expected STAT blocking while another enabled source keeps the line high",
	)
}

// --- STAT interrupt edge-case opcode tests ---

@(test)
test_stat_mode_0_interrupt_rearms_for_each_visible_scanline :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 0xFF)
	gb.bus_write_byte(&bus, 0xFF41, 0x08)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)

	ppu_tick_many(&bus, 252)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected the first HBlank to request STAT",
	)

	gb.bus_write_byte(&bus, 0xFF0F, 0)
	ppu_tick_many(&bus, 456)

	testing.expect(t, bus.ppu.ly == 1, "Expected the PPU to reach the next visible line")
	testing.expect(t, bus.ppu.dot == 252, "Expected the next visible line to reach HBlank")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected mode 0 to rearm and request STAT on the next scanline",
	)
}

@(test)
test_stat_consecutive_modes_keep_shared_line_high :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 0xFF)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	ppu_tick_many(&bus, 80)
	gb.bus_write_byte(&bus, 0xFF41, 0x28)

	ppu_tick_many(&bus, 172)
	testing.expect(t, bus.ppu.mode == .HBLANK, "Expected mode 0 to begin at dot 252")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected enabled mode 0 to request STAT",
	)

	gb.bus_write_byte(&bus, 0xFF0F, 0)
	ppu_tick_many(&bus, 204)

	testing.expect(t, bus.ppu.mode == .OAM, "Expected mode 2 to follow mode 0")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 == 0,
		"Expected mode 2 to be blocked because mode 0 kept the shared line high",
	)
}

@(test)
test_dmg_stat_write_during_oam_requests_spurious_interrupt :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF45, 1)
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.ppu_tick(&bus)

	testing.expect(t, bus.ppu.mode == .OAM, "Expected the PPU to be in OAM mode")
	gb.bus_write_byte(&bus, 0xFF41, 0x00)

	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFF0F) & 0x02 != 0,
		"Expected the DMG STAT write quirk to request an interrupt during OAM",
	)
}
