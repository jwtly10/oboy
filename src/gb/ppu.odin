package gb


VISIBLE_SCANLINE_END :: 144
TOTAL_SCANLINES :: 154

END_OF_SCANLINE_D :: 456

OAM_MODE_END_D :: 80
DRAWING_MODE_END_D :: 252 // TODO: this is actually variable https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#the-concept-of-ppu-modes

SCREEN_WIDTH :: 160
SCREEN_HEIGHT :: 144

TILE_MAP_1 :: 0x9800 // -> 0x9BFF
TILE_MAP_2 :: 0x9C00 // -> 0x9FFF

TILE_DATA_1 :: 0x8000 //-┐
TILE_DATA_2 :: 0x9000 //-┴-> -> 0x97FF

ppu_tick :: proc(bus: ^Bus) {
	ppu := &bus.ppu

	// 7th bit of reg enables/disables PPU
	if ppu.lcdc & 0x80 == 0 {
		// Disabled PPU
		ppu.dot = 0
		// Rests processing scanline
		ppu.ly = 0
		// Sets mode
		ppu_set_mode(bus, .HBLANK)
		// Update LYC triggers
		ppu_update_lyc_coincidence(bus)
		// We don't trigger interrupt while disabled
		// we just reset line
		ppu.stat_interrupt_line = false
		return
	}

	old_mode := ppu.mode
	// The dot essentially represents the horizontal timing within 1 scanline
	// whereas LY is the vertical scanline position within a frame
	ppu.dot += 1

	if ppu.dot == END_OF_SCANLINE_D {
		ppu.dot = 0
		ppu.ly += 1

		// https://gbdev.io/pandocs/Interrupt_Sources.html#int-40--vblank-interrupt
		if ppu.ly == VISIBLE_SCANLINE_END {
			request_interrupt(bus, .VBLANK)
		}

		if ppu.ly == TOTAL_SCANLINES {
			ppu.ly = 0
		}
	}

	ppu_update_mode(bus)

	if old_mode == .DRAWING && ppu.mode == .HBLANK {
		ppu_render_scanline(bus)
	}

	ppu_update_lyc_coincidence(bus)
	ppu_update_stat_interrupt_line(bus)
}

ppu_render_scanline :: proc(bus: ^Bus) {
	ppu := &bus.ppu
	line_start := int(ppu.ly) * SCREEN_WIDTH

	if ppu.lcdc & 1 == 0 {
		for screen_x in 0 ..< SCREEN_WIDTH {
			ppu.frame_buffer[line_start + screen_x] = 0
		}
		return
	}

	for screen_x in 0 ..< SCREEN_WIDTH {

		// https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#the-wx-and-wy-registers
		// 7 is a bit of a magic number... setting 7 is left hand edge
		window_x := int(ppu.wx) - 7

		// We use the window when 3 conditions are met:
		// 1. Bit 5 is set (enables window rendering)
		// 2. Current screen row has reached window top edge
		// 3. Current screen pixel has reached windows left edge
		use_window :=
			ppu.lcdc & (1 << 5) != 0 && int(ppu.ly) >= int(ppu.wy) && screen_x >= window_x

		pixel_x: u8
		pixel_y: u8
		map_location: u16

		if use_window {
			// See background condition explantion
			// Window is essentially the same rendering process, it's just
			// reference different areas of memory
			pixel_x = u8(screen_x - window_x) // Raw left edge
			pixel_y = ppu.ly - ppu.wy // Raw top

			// See https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#lcd-control-register-lcdc--ff40
			// This bit picks which tile map to use
			if ppu.lcdc & (1 << 6) != 0 {
				map_location = TILE_MAP_2
			} else {
				map_location = TILE_MAP_1
			}
		} else {
			// SCX and SCY hold values which show how many pixels the viewport
			// is off from the left & top
			//
			// Since the background is 256x256 (can be represented by u8) and the
			// viewport is a slice of this background for any given  position (screen_x, ppu.ly)
			// we need to know what that background pixel is
			//
			// Backgrounds are made up of various 8x8 tiles, so given some background_x/y value
			// we need to divide by 8, to figure out which tile this background value sits
			// inside, and eventually resolve the specific pixel data.
			//
			// https://gbdev.io/pandocs/LCDC.html?highlight=LCDC#ff40--lcdc-lcd-control
			// Once we have that, we now know (based on LCDC bit 3) which tile map to use (we have 2)
			// which contains tile numbers. LCDC bit 4 tells us how to use said tile number to find
			// the actual pixel data

			// u16 > u8 to safely overflow
			pixel_x = u8(u16(ppu.scx) + u16(screen_x))
			pixel_y = u8(u16(ppu.scy) + u16(ppu.ly))

			// Bit 3 picks which tile map to use when rendering background
			if (ppu.lcdc & (1 << 3) != 0) {
				// Bit is 1
				map_location = TILE_MAP_2
			} else {
				map_location = TILE_MAP_1
			}
		}

		shade := ppu_resolve_pixel(bus, map_location, pixel_x, pixel_y)
		// Set this pixel position the GB shade
		ppu.frame_buffer[int(ppu.ly) * SCREEN_WIDTH + screen_x] = shade
	}
}

// Given bus, map location and pixel coords, resolve the color of the given pixel
ppu_resolve_pixel :: proc(bus: ^Bus, map_location: u16, pixel_x: u8, pixel_y: u8) -> u8 {
	ppu := &bus.ppu
	tile_x := u16(pixel_x / 8)
	tile_y := u16(pixel_y / 8)

	// https://gbdev.io/pandocs/Tile_Maps.html#vram-tile-maps
	// The tile map is 32 tiles wide, so we need to find our row & index
	tile_map_address := map_location + tile_y * 32 + tile_x
	tile_number := bus_read_byte(bus, tile_map_address)

	// https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#tile-data
	// There are two different modes to accessing tile data
	tile_data_address: u16
	if (ppu.lcdc & (1 << 4) != 0) {
		tile_data_address = TILE_DATA_1 + u16(tile_number) * 16
	} else {
		//                                          ↓ Widen to i32 so we can multiply
		tile_data_address = u16(i32(TILE_DATA_2) + i32(i8(tile_number)) * 16)
	}

	// Each tile has 8x8 pixels with color depth of 2 bits pp (16 bytes)
	// Now we have the address of the first byte
	// We need to decide which row, and since 2 bytes, reference the second byte of said row
	tile_row := u16(pixel_y % 8)
	row_address := tile_data_address + tile_row * 2

	// We now have both bytes of the pixel data
	low_byte := bus_read_byte(bus, row_address)
	high_byte := bus_read_byte(bus, row_address + 1)

	tile_column := u16(pixel_x % 8)
	bit_index := 7 - tile_column

	low_bit := (low_byte >> bit_index) & 1
	high_bit := (high_byte >> bit_index) & 1

	// 0, 1, 2 or 3
	colour_number := (high_bit << 1) | low_bit

	// Mapping color to a displayed shade
	shade := (ppu.bgp >> (colour_number * 2)) & 0b11
	return shade
}

// How PPU mode is derived:
// - Screen is 144 pixels high so there are 0..143 visible scanlines
// - There are 154 scanlines total (10 hidden are VBLANK)
// - Each scanline lasts 456 T-Cycles
// - OAM scan lasts 80 T-Cycles
// - HBLANK fills remainder of the 456 cycle
// - Mode 3 (DRAWING) is variable
ppu_update_mode :: proc(bus: ^Bus) {
	ppu := &bus.ppu

	if ppu.ly >= VISIBLE_SCANLINE_END {
		ppu_set_mode(bus, .VBLANK)
	} else if ppu.dot < OAM_MODE_END_D {
		ppu_set_mode(bus, .OAM)
	} else if ppu.dot < DRAWING_MODE_END_D {
		ppu_set_mode(bus, .DRAWING)
	} else {
		ppu_set_mode(bus, .HBLANK)
	}
}

// https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#stat6---lycly-stat-interrupt-enable
//
// This interrupt is ONLY triggered on the rising edge of this condition
// Essentially one of these conditions must be met to trigger a STAT interrupt
// And it will only happen once, until they all 'reset' again
ppu_update_stat_interrupt_line :: proc(bus: ^Bus) {
	ppu := &bus.ppu

	// https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#lcd-status-register-stat--ff41
	// A number of bits trigger the interrupt behaviour
	lyc_src := (ppu.stat & (1 << 6)) != 0 && ppu.ly == ppu.lyc
	oam_src := (ppu.stat & (1 << 5)) != 0 && ppu.mode == .OAM
	vblank_src := (ppu.stat & (1 << 4)) != 0 && ppu.mode == .VBLANK
	hblank_src := (ppu.stat & (1 << 3)) != 0 && ppu.mode == .HBLANK

	src_high := lyc_src || hblank_src || vblank_src || oam_src

	// line is not set yet - but a src_high is true -> We can interrupt
	if !ppu.stat_interrupt_line && src_high {
		request_interrupt(bus, .STAT)
	}

	// Set to true, and it won't run again until
	ppu.stat_interrupt_line = src_high
}

// https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#lcd-status-register-stat--ff41
// Bit 2   Coincidence Flag
//     This bit is set by the PPU if the value of the LY register is equal to that of the LYC register.
ppu_update_lyc_coincidence :: proc(bus: ^Bus) {
	ppu := &bus.ppu

	if ppu.ly == ppu.lyc {
		// Setting bit 2, if not already
		ppu.stat |= 1 << 2
	} else {
		// Clearing bit 2
		ppu.stat &= ~u8(1 << 2)
	}
}

// Sets PPU mode based on STAT register
// Bit 1-0 PPU Mode
// These two bits are set by the PPU depending on which mode it is in.
// * 0 : H-Blank
// * 1 : V-Blank
// * 2 : OAM Scan
// * 3 : Drawing
ppu_set_mode :: proc(bus: ^Bus, mode: PPU_mode) {
	ppu := &bus.ppu

	ppu.mode = mode
	// unsets mode bits (0,1) and set it to the mode (casting to u8 to get 0b1..0b11 based on mode)
	ppu.stat = (ppu.stat & ~u8(0b011)) | u8(mode)
}
