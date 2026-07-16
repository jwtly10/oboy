package gb

import "core:fmt"
import "core:os"

dump_ppu_test_frame :: proc() {
	bus := Bus{}
	bus_write_byte(&bus, LCDC_ADDRESS, 0xF1) // LCD, BG, and Window on; Window uses 9C00.
	bus_write_byte(&bus, BGP_ADDRESS, 0xE4)
	bus_write_byte(&bus, WY_ADDRESS, 24)
	bus_write_byte(&bus, WX_ADDRESS, 39) // Window begins at screen x=32.

	for tile_y in 0 ..< 32 {
		for tile_x in 0 ..< 32 {
			tile_number := u8(1 + (tile_x + tile_y) % 2)
			bus_write_byte(&bus, 0x9800 + u16(tile_y * 32 + tile_x), tile_number)
		}
	}

	window_width_tiles := (SCREEN_WIDTH - 32) / 8
	window_height_tiles := (SCREEN_HEIGHT - 24) / 8
	for tile_y in 0 ..< 32 {
		for tile_x in 0 ..< 32 {
			tile_number: u8
			if tile_x == 0 ||
			   tile_x == window_width_tiles - 1 ||
			   tile_y == 0 ||
			   tile_y == window_height_tiles - 1 {
				tile_number = 3
			} else if tile_y == 2 {
				tile_number = 2
			} else {
				tile_number = 0
			}
			bus_write_byte(&bus, 0x9C00 + u16(tile_y * 32 + tile_x), tile_number)
		}
	}

	for tile_number in 0 ..< 4 {
		low_byte := u8(0xFF if tile_number & 1 != 0 else 0)
		high_byte := u8(0xFF if tile_number & 2 != 0 else 0)
		for row in 0 ..< 8 {
			address := u16(0x8000 + tile_number * 16 + row * 2)
			bus_write_byte(&bus, address, low_byte)
			bus_write_byte(&bus, address + 1, high_byte)
		}
	}

	for _ in 0 ..< TOTAL_SCANLINES * END_OF_SCANLINE_D {
		ppu_tick(&bus)
	}

	header := "P5\n160 144\n255\n"
	output := make([]u8, len(header) + SCREEN_WIDTH * SCREEN_HEIGHT)
	defer delete(output)
	copy(output, transmute([]u8)header)
	for shade, pixel_index in bus.ppu.frame_buffer {
		output[len(header) + pixel_index] = 255 - shade * 85
	}

	file_path := "/tmp/oboy-ppu-test-frame.pgm"
	if err := os.write_entire_file(file_path, output); err != nil {
		fmt.println("Could not write PPU test frame")
		return
	}

	fmt.printfln("Wrote known PPU test frame to %s", file_path)
}
