package gb

import "core:fmt"
import "core:os"

dump_ppu_test_frame :: proc() {
	bus := Bus{}
	bus_write_byte(&bus, LCDC_ADDRESS, 0x91)
	bus_write_byte(&bus, BGP_ADDRESS, 0xE4)

	for tile_y in 0 ..< 32 {
		for tile_x in 0 ..< 32 {
			tile_number := u8((tile_x + tile_y) % 4)
			bus_write_byte(&bus, 0x9800 + u16(tile_y * 32 + tile_x), tile_number)
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
