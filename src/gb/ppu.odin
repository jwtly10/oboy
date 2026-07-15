package gb


VISIBLE_SCANLINE_END :: 144
TOTAL_SCANLINES :: 154

END_OF_SCANLINE_D :: 456

OAM_MODE_END_D :: 80
DRAWING_MODE_END_D :: 252 // TODO: this is actually variable https://github.com/Ashiepaws/GBEDG/blob/master/ppu/index.md#the-concept-of-ppu-modes

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
		return
	}

	// How PPU mode is derived:
	// - Screen is 144 pixels high so there are 0..143 visible scanlines
	// - There are 154 scanlines total (10 hidden are VBLANK)
	// - Each scanline lasts 456 T-Cycles
	// - OAM scan lasts 80 T-Cycles
	// - HBLANK fills remainder of the 456 cycle
	// - Mode 3 (DRAWING) is variable
	if ppu.ly >= VISIBLE_SCANLINE_END {
		ppu_set_mode(bus, .VBLANK)
	} else if ppu.dot < OAM_MODE_END_D {
		ppu_set_mode(bus, .OAM)
	} else if ppu.dot < DRAWING_MODE_END_D {
		ppu_set_mode(bus, .DRAWING)
	} else {
		ppu_set_mode(bus, .HBLANK)
	}

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
