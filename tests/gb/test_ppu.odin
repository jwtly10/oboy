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

// --- PPU background rendering tests ---

@(test)
test_ppu_renders_tile_pixels_through_background_palette :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x91) // LCD on, BG on, unsigned tile data.
	gb.bus_write_byte(&bus, 0xFF47, 0xE4) // Identity mapping for color IDs 0, 1, 2, 3.
	gb.bus_write_byte(&bus, 0x9800, 0)
	gb.bus_write_byte(&bus, 0x8000, 0x55)
	gb.bus_write_byte(&bus, 0x8001, 0x33)

	ppu_tick_many(&bus, 252)

	expected := [8]u8{0, 1, 2, 3, 0, 1, 2, 3}
	for pixel, screen_x in expected {
		testing.expectf(
			t,
			bus.ppu.frame_buffer[screen_x] == pixel,
			"Expected pixel %d of the first tile to have shade %d",
			screen_x,
			pixel,
		)
	}
	testing.expect(
		t,
		bus.ppu.frame_buffer[gb.SCREEN_WIDTH] == 0,
		"Expected rendering scanline 0 not to modify scanline 1",
	)
}

@(test)
test_ppu_uses_selected_tile_map_and_signed_tile_addressing :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x89) // LCD on, BG on, map 9C00, signed tile data.
	gb.bus_write_byte(&bus, 0xFF47, 0x1B) // Reverse color ID to shade mapping.
	gb.bus_write_byte(&bus, 0x9C00, 0xFF) // Signed tile -1 begins at 8FF0.
	gb.bus_write_byte(&bus, 0x8FF0, 0x80)
	gb.bus_write_byte(&bus, 0x8FF1, 0x80)

	ppu_tick_many(&bus, 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 0,
		"Expected color ID 3 from signed tile -1 to map to shade 0",
	)
	testing.expect(t, bus.ppu.frame_buffer[1] == 3, "Expected color ID 0 to map to shade 3")
}

@(test)
test_ppu_background_scroll_wraps_across_256_pixel_map :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x91)
	gb.bus_write_byte(&bus, 0xFF42, 0xFF)
	gb.bus_write_byte(&bus, 0xFF43, 0xFC)
	gb.bus_write_byte(&bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&bus, 0x9BFF, 1)
	gb.bus_write_byte(&bus, 0x9BE0, 2)
	gb.bus_write_byte(&bus, 0x801E, 0x08) // Tile 1, row 7, x=4 is color ID 1.
	gb.bus_write_byte(&bus, 0x802E, 0x80) // Tile 2, row 7, x=0 is color ID 1.

	ppu_tick_many(&bus, 252)

	testing.expect(t, bus.ppu.frame_buffer[0] == 1, "Expected SCX/SCY to select pixel (252, 255)")
	testing.expect(t, bus.ppu.frame_buffer[4] == 1, "Expected background X to wrap from 255 to 0")
}

@(test)
test_ppu_blanks_background_when_lcdc_background_enable_is_clear :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x90) // LCD on, BG off.
	gb.bus_write_byte(&bus, 0xFF47, 0xFF)
	gb.bus_write_byte(&bus, 0x8000, 0xFF)
	gb.bus_write_byte(&bus, 0x8001, 0xFF)

	ppu_tick_many(&bus, 252)

	for screen_x in 0 ..< gb.SCREEN_WIDTH {
		actual := bus.ppu.frame_buffer[screen_x]
		testing.expectf(
			t,
			actual == 0,
			"Expected disabled background pixel %d to be blank, got: %v",
			screen_x,
			actual,
		)
	}
}

// --- PPU window rendering tests ---

ppu_write_solid_test_tile :: proc(bus: ^gb.Bus, tile_number, colour_number: u8) {
	low_byte := u8(0xFF if colour_number & 1 != 0 else 0)
	high_byte := u8(0xFF if colour_number & 2 != 0 else 0)
	tile_address := u16(0x8000) + u16(tile_number) * 16
	for row in 0 ..< 8 {
		row_address := tile_address + u16(row * 2)
		gb.bus_write_byte(bus, row_address, low_byte)
		gb.bus_write_byte(bus, row_address + 1, high_byte)
	}
}

@(test)
test_ppu_window_overlays_background_from_wx_and_wy :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0xF1) // LCD, BG, and Window on; Window uses 9C00.
	gb.bus_write_byte(&bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&bus, 0xFF4A, 4)
	gb.bus_write_byte(&bus, 0xFF4B, 15) // Window begins at screen x=8.
	gb.bus_write_byte(&bus, 0x9800, 1)
	gb.bus_write_byte(&bus, 0x9801, 1)
	gb.bus_write_byte(&bus, 0x9C00, 2)
	ppu_write_solid_test_tile(&bus, 1, 1)
	ppu_write_solid_test_tile(&bus, 2, 2)

	ppu_tick_many(&bus, 4 * 456 + 252)

	previous_line := 3 * gb.SCREEN_WIDTH
	window_line := 4 * gb.SCREEN_WIDTH
	testing.expect(
		t,
		bus.ppu.frame_buffer[previous_line + 8] == 1,
		"Expected the background above WY to remain visible",
	)
	testing.expect(
		t,
		bus.ppu.frame_buffer[window_line + 7] == 1,
		"Expected the background immediately left of WX-7 to remain visible",
	)
	testing.expect(
		t,
		bus.ppu.frame_buffer[window_line + 8] == 2,
		"Expected the Window to begin at screen coordinate (WX-7, WY)",
	)
}

@(test)
test_ppu_window_starts_at_tile_row_zero_when_ly_reaches_wy :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0xF1)
	gb.bus_write_byte(&bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&bus, 0xFF4A, 9)
	gb.bus_write_byte(&bus, 0xFF4B, 7)
	gb.bus_write_byte(&bus, 0x9C00, 3)
	gb.bus_write_byte(&bus, 0x8030, 0xFF) // Tile 3 row 0 is color ID 1.
	gb.bus_write_byte(&bus, 0x8032, 0x00)
	gb.bus_write_byte(&bus, 0x8033, 0xFF) // Tile 3 row 1 is color ID 2.

	ppu_tick_many(&bus, 9 * 456 + 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[9 * gb.SCREEN_WIDTH] == 1,
		"Expected the first visible Window scanline to use tile row 0",
	)

	ppu_tick_many(&bus, 456)

	testing.expect(
		t,
		bus.ppu.frame_buffer[10 * gb.SCREEN_WIDTH] == 2,
		"Expected the next Window scanline to use tile row 1",
	)
}

@(test)
test_ppu_window_uses_its_selected_map_and_ignores_background_scroll :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0xF1) // BG uses 9800; Window uses 9C00.
	gb.bus_write_byte(&bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&bus, 0xFF42, 8)
	gb.bus_write_byte(&bus, 0xFF43, 8)
	gb.bus_write_byte(&bus, 0xFF4A, 0)
	gb.bus_write_byte(&bus, 0xFF4B, 7)
	gb.bus_write_byte(&bus, 0x9C00, 1)
	gb.bus_write_byte(&bus, 0x9821, 2) // Background pixel (8, 8) uses this entry.
	ppu_write_solid_test_tile(&bus, 1, 1)
	ppu_write_solid_test_tile(&bus, 2, 2)

	ppu_tick_many(&bus, 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 1,
		"Expected Window pixel (0, 0) not to use the scrolled Background coordinate",
	)
}

@(test)
test_ppu_window_enable_and_offscreen_wx :: proc(t: ^testing.T) {
	disabled_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&disabled_bus, 0xFF40, 0xD1) // Window map selected but Window disabled.
	gb.bus_write_byte(&disabled_bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&disabled_bus, 0xFF4B, 7)
	gb.bus_write_byte(&disabled_bus, 0x9800, 1)
	gb.bus_write_byte(&disabled_bus, 0x9C00, 2)
	ppu_write_solid_test_tile(&disabled_bus, 1, 1)
	ppu_write_solid_test_tile(&disabled_bus, 2, 2)
	ppu_tick_many(&disabled_bus, 252)
	testing.expect(
		t,
		disabled_bus.ppu.frame_buffer[0] == 1,
		"Expected a disabled Window to leave the Background visible",
	)

	offscreen_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&offscreen_bus, 0xFF40, 0xB9) // BG uses 9C00; Window uses 9800.
	gb.bus_write_byte(&offscreen_bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&offscreen_bus, 0xFF4B, 167)
	gb.bus_write_byte(&offscreen_bus, 0x9800, 1)
	gb.bus_write_byte(&offscreen_bus, 0x9C13, 2)
	ppu_write_solid_test_tile(&offscreen_bus, 1, 1)
	ppu_write_solid_test_tile(&offscreen_bus, 2, 2)
	ppu_tick_many(&offscreen_bus, 252)
	testing.expect(
		t,
		offscreen_bus.ppu.frame_buffer[159] == 2,
		"Expected WX=167 to keep the Window beyond the right edge",
	)
}

// --- PPU sprite rendering tests ---

ppu_write_test_sprite :: proc(
	bus: ^gb.Bus,
	oam_index: int,
	screen_x: int,
	screen_y: int,
	tile_number: u8,
	attributes: u8,
) {
	offset := oam_index * 4
	bus.oam[offset] = u8(screen_y + 16)
	bus.oam[offset + 1] = u8(screen_x + 8)
	bus.oam[offset + 2] = tile_number
	bus.oam[offset + 3] = attributes
}

ppu_write_test_tile_row :: proc(
	bus: ^gb.Bus,
	tile_number: u8,
	row: int,
	low_byte: u8,
	high_byte: u8,
) {
	address := u16(0x8000) + u16(tile_number) * 16 + u16(row * 2)
	gb.bus_write_byte(bus, address, low_byte)
	gb.bus_write_byte(bus, address + 1, high_byte)
}

@(test)
test_ppu_renders_sprite_pixels_through_obp0_and_skips_colour_zero :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x92) // LCD and OBJ on; BG off.
	gb.bus_write_byte(&bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bus, 0, 4, 0, 1, 0)
	ppu_write_test_tile_row(&bus, 1, 0, 0x55, 0x33)

	ppu_tick_many(&bus, 252)

	expected := [8]u8{0, 1, 2, 3, 0, 1, 2, 3}
	for shade, sprite_x in expected {
		screen_x := 4 + sprite_x
		testing.expectf(
			t,
			bus.ppu.frame_buffer[screen_x] == shade,
			"Expected sprite pixel %d to have shade %d",
			sprite_x,
			shade,
		)
	}
	testing.expect(
		t,
		bus.ppu.frame_buffer[3] == 0,
		"Expected the pixel left of the OBJ to remain blank",
	)
	testing.expect(
		t,
		bus.ppu.frame_buffer[gb.SCREEN_WIDTH + 4] == 0,
		"Expected rendering scanline 0 not to modify scanline 1",
	)
}

@(test)
test_ppu_obj_enable_and_palette_attribute_control_sprite_output :: proc(t: ^testing.T) {
	disabled_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&disabled_bus, 0xFF40, 0x90) // LCD on; OBJ off.
	gb.bus_write_byte(&disabled_bus, 0xFF48, 0x0C) // OBP0 maps colour 1 to shade 3.
	ppu_write_test_sprite(&disabled_bus, 0, 0, 0, 1, 0)
	ppu_write_solid_test_tile(&disabled_bus, 1, 1)
	ppu_tick_many(&disabled_bus, 252)
	testing.expect(
		t,
		disabled_bus.ppu.frame_buffer[0] == 0,
		"Expected a disabled OBJ layer not to render a sprite",
	)

	enabled_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&enabled_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&enabled_bus, 0xFF48, 0x0C) // OBP0 maps colour 1 to shade 3.
	gb.bus_write_byte(&enabled_bus, 0xFF49, 0x08) // OBP1 maps colour 1 to shade 2.
	ppu_write_test_sprite(&enabled_bus, 0, 0, 0, 1, 0)
	ppu_write_test_sprite(&enabled_bus, 1, 8, 0, 1, 1 << 4)
	ppu_write_solid_test_tile(&enabled_bus, 1, 1)
	ppu_tick_many(&enabled_bus, 252)
	testing.expect(
		t,
		enabled_bus.ppu.frame_buffer[0] == 3,
		"Expected attribute bit 4 clear to select OBP0",
	)
	testing.expect(
		t,
		enabled_bus.ppu.frame_buffer[8] == 2,
		"Expected attribute bit 4 set to select OBP1",
	)
}

@(test)
test_ppu_sprite_x_and_y_flip_mirror_tile_pixels :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x92)
	gb.bus_write_byte(&bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bus, 0, 0, 0, 1, (1 << 6) | (1 << 5))
	// The bottom-right source pixel is colour 2 and should move to the top-left.
	ppu_write_test_tile_row(&bus, 1, 7, 0x00, 0x01)

	ppu_tick_many(&bus, 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 2,
		"Expected X/Y flip to mirror the bottom-right pixel to top-left",
	)
	testing.expect(
		t,
		bus.ppu.frame_buffer[1] == 0,
		"Expected the adjacent transparent source pixel to remain transparent",
	)
}

@(test)
test_ppu_8x16_sprite_ignores_tile_bit_zero_and_selects_both_halves :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x96) // LCD and OBJ on; 8x16 OBJ size.
	gb.bus_write_byte(&bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bus, 0, 0, 0, 5, 0)
	ppu_write_test_tile_row(&bus, 4, 0, 0x80, 0x00)
	ppu_write_test_tile_row(&bus, 5, 7, 0x00, 0x80)

	ppu_tick_many(&bus, 252)
	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 1,
		"Expected an odd 8x16 tile number to use the preceding even tile for its top half",
	)

	ppu_tick_many(&bus, 15 * 456)
	testing.expect(
		t,
		bus.ppu.frame_buffer[15 * gb.SCREEN_WIDTH] == 2,
		"Expected the bottom scanline of an 8x16 OBJ to use the odd tile's final row",
	)

	flipped_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&flipped_bus, 0xFF40, 0x96)
	gb.bus_write_byte(&flipped_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&flipped_bus, 0, 0, 0, 5, 1 << 6)
	ppu_write_test_tile_row(&flipped_bus, 5, 7, 0x00, 0x80)
	ppu_tick_many(&flipped_bus, 252)
	testing.expect(
		t,
		flipped_bus.ppu.frame_buffer[0] == 2,
		"Expected Y flip to mirror the complete 16-pixel OBJ rather than each tile separately",
	)
}

@(test)
test_ppu_sprite_bg_priority_uses_background_colour_id :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x93) // LCD, BG, and OBJ on.
	gb.bus_write_byte(&bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bus, 0, 0, 0, 1, 1 << 7)
	ppu_write_solid_test_tile(&bus, 1, 2)
	// BG x=0 is colour 0; BG x=1 is colour 1.
	ppu_write_test_tile_row(&bus, 0, 0, 0x40, 0x00)

	ppu_tick_many(&bus, 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 2,
		"Expected an OBJ behind the BG to remain visible over BG colour 0",
	)
	testing.expect(
		t,
		bus.ppu.frame_buffer[1] == 1,
		"Expected BG colour 1 to cover an OBJ whose priority attribute is set",
	)

	bg_disabled_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bg_disabled_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&bg_disabled_bus, 0xFF47, 0xFF)
	gb.bus_write_byte(&bg_disabled_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bg_disabled_bus, 0, 0, 0, 1, 1 << 7)
	ppu_write_solid_test_tile(&bg_disabled_bus, 1, 2)
	ppu_tick_many(&bg_disabled_bus, 252)
	testing.expect(
		t,
		bg_disabled_bus.ppu.frame_buffer[0] == 2,
		"Expected LCDC.0 clear to blank the BG without hiding a behind-BG OBJ",
	)
}

@(test)
test_ppu_sprite_overlap_uses_dmg_x_then_oam_priority :: proc(t: ^testing.T) {
	lower_x_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&lower_x_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&lower_x_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&lower_x_bus, 0, 4, 0, 1, 0)
	ppu_write_test_sprite(&lower_x_bus, 1, 3, 0, 2, 0)
	ppu_write_solid_test_tile(&lower_x_bus, 1, 1)
	ppu_write_solid_test_tile(&lower_x_bus, 2, 2)
	ppu_tick_many(&lower_x_bus, 252)
	testing.expect(
		t,
		lower_x_bus.ppu.frame_buffer[4] == 2,
		"Expected the OBJ with the lower X coordinate to win despite its later OAM index",
	)

	equal_x_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&equal_x_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&equal_x_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&equal_x_bus, 0, 4, 0, 1, 0)
	ppu_write_test_sprite(&equal_x_bus, 1, 4, 0, 2, 0)
	ppu_write_solid_test_tile(&equal_x_bus, 1, 1)
	ppu_write_solid_test_tile(&equal_x_bus, 2, 2)
	ppu_tick_many(&equal_x_bus, 252)
	testing.expect(
		t,
		equal_x_bus.ppu.frame_buffer[4] == 1,
		"Expected the earlier OAM entry to win when overlapping OBJs have equal X",
	)
}

@(test)
test_ppu_transparent_and_bg_hidden_obj_pixels_do_not_reorder_sprites :: proc(t: ^testing.T) {
	transparent_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&transparent_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&transparent_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&transparent_bus, 0, 0, 0, 1, 0)
	ppu_write_test_sprite(&transparent_bus, 1, 0, 0, 2, 0)
	ppu_write_test_tile_row(&transparent_bus, 2, 0, 0x80, 0x00)
	ppu_tick_many(&transparent_bus, 252)
	testing.expect(
		t,
		transparent_bus.ppu.frame_buffer[0] == 1,
		"Expected a lower-priority opaque OBJ pixel through a transparent higher-priority pixel",
	)

	masked_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&masked_bus, 0xFF40, 0x93)
	gb.bus_write_byte(&masked_bus, 0xFF47, 0xE4)
	gb.bus_write_byte(&masked_bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&masked_bus, 0, 0, 0, 1, 1 << 7)
	ppu_write_test_sprite(&masked_bus, 1, 0, 0, 2, 0)
	ppu_write_solid_test_tile(&masked_bus, 0, 3)
	ppu_write_solid_test_tile(&masked_bus, 1, 1)
	ppu_write_solid_test_tile(&masked_bus, 2, 2)
	ppu_tick_many(&masked_bus, 252)
	testing.expect(
		t,
		masked_bus.ppu.frame_buffer[0] == 3,
		"Expected a BG-hidden higher-priority OBJ to mask a lower-priority OBJ",
	)
}

@(test)
test_ppu_scanline_sprite_limit_counts_horizontally_hidden_objects :: proc(t: ^testing.T) {
	limited_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&limited_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&limited_bus, 0xFF48, 0xE4)
	for oam_index in 0 ..< 10 {
		ppu_write_test_sprite(&limited_bus, oam_index, -8, 0, 1, 0)
	}
	ppu_write_test_sprite(&limited_bus, 10, 0, 0, 1, 0)
	ppu_write_solid_test_tile(&limited_bus, 1, 1)
	ppu_tick_many(&limited_bus, 252)
	testing.expect(
		t,
		limited_bus.ppu.frame_buffer[0] == 0,
		"Expected ten X-hidden OBJs to consume the scanline limit before OAM entry 10",
	)

	within_limit_bus := make_test_bus([]u8{})
	gb.bus_write_byte(&within_limit_bus, 0xFF40, 0x92)
	gb.bus_write_byte(&within_limit_bus, 0xFF48, 0xE4)
	for oam_index in 0 ..< 9 {
		ppu_write_test_sprite(&within_limit_bus, oam_index, -8, 0, 1, 0)
	}
	ppu_write_test_sprite(&within_limit_bus, 9, 0, 0, 1, 0)
	ppu_write_solid_test_tile(&within_limit_bus, 1, 1)
	ppu_tick_many(&within_limit_bus, 252)
	testing.expect(
		t,
		within_limit_bus.ppu.frame_buffer[0] == 1,
		"Expected the tenth selected OBJ to remain visible",
	)
}

@(test)
test_ppu_renders_visible_portion_of_sprite_above_and_left_of_screen :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{})
	gb.bus_write_byte(&bus, 0xFF40, 0x92)
	gb.bus_write_byte(&bus, 0xFF48, 0xE4)
	ppu_write_test_sprite(&bus, 0, -4, -2, 1, 0)
	// At screen (0, 0), the partially hidden OBJ contributes source pixel (4, 2).
	ppu_write_test_tile_row(&bus, 1, 2, 0x08, 0x00)

	ppu_tick_many(&bus, 252)

	testing.expect(
		t,
		bus.ppu.frame_buffer[0] == 1,
		"Expected the visible portion of an OBJ above and left of the screen to render",
	)
}
