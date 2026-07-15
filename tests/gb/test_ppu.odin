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
test_ppu_updates_lyc_coincidence_at_scanline_boundary :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x80)
	gb.bus_write_byte(&bus, 0xFF45, 1)

	ppu_tick_many(&bus, 456)

	testing.expect(t, bus.ppu.ly == 1, "Expected LY to reach the comparison line")
	testing.expect(
		t,
		bus.ppu.stat & 0b100 != 0,
		"Expected STAT coincidence flag when LY equals LYC",
	)
}
