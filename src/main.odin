package main

import "core:fmt"
import "core:os"
import "gb"
import rl "vendor:raylib"

SCREEN_SCALE :: 4

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("Usage: oboy <path-to-rom>")
		return
	}

	file_path := os.args[1]

	rom, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.println("Could not read file, aborting")
		return
	}
	defer delete(rom, context.allocator)

	header, ok := gb.Parse_rom_header(rom)
	if !ok {
		fmt.println("Header parsing failed")
		return
	}
	gb.Print_rom_header(&header)

	machine, m_ok := gb.Machine_init(rom, &header, context.allocator)
	if !m_ok {
		fmt.println("Could not initialise machine")
		return
	}
	defer gb.Machine_destroy(&machine)

	rl.InitWindow(gb.SCREEN_WIDTH * SCREEN_SCALE, gb.SCREEN_HEIGHT * SCREEN_SCALE, "Oboy - GB Emu")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	image := rl.GenImageColor(gb.SCREEN_WIDTH, gb.SCREEN_HEIGHT, rl.WHITE)
	texture := rl.LoadTextureFromImage(image)
	rl.UnloadImage(image)
	defer rl.UnloadTexture(texture)

	rl.SetTextureFilter(texture, .POINT)

	display_pixels: [gb.SCREEN_WIDTH * gb.SCREEN_HEIGHT]rl.Color

	for !rl.WindowShouldClose() {

		// Keyboard inputs
		gb.joypad_set_button(&machine.bus, .RIGHT, rl.IsKeyDown(.D))
		gb.joypad_set_button(&machine.bus, .LEFT, rl.IsKeyDown(.A))
		gb.joypad_set_button(&machine.bus, .UP, rl.IsKeyDown(.W))
		gb.joypad_set_button(&machine.bus, .DOWN, rl.IsKeyDown(.S))

		gb.joypad_set_button(&machine.bus, .A, rl.IsKeyDown(.J))
		gb.joypad_set_button(&machine.bus, .B, rl.IsKeyDown(.K))
		gb.joypad_set_button(&machine.bus, .SELECT, rl.IsKeyDown(.BACKSPACE))
		gb.joypad_set_button(&machine.bus, .START, rl.IsKeyDown(.ENTER))

		if !gb.Machine_run_frame(&machine) {
			break
		}

		for shade, index in machine.bus.ppu.frame_buffer {
			switch shade {
			case 0:
				display_pixels[index] = rl.Color{224, 248, 208, 255}
			case 1:
				display_pixels[index] = rl.Color{136, 192, 112, 255}
			case 2:
				display_pixels[index] = rl.Color{52, 104, 86, 255}
			case:
				display_pixels[index] = rl.Color{8, 24, 32, 255}
			}
		}

		rl.UpdateTexture(texture, raw_data(display_pixels[:]))

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		rl.DrawTexturePro(
			texture,
			rl.Rectangle {
				x = 0,
				y = 0,
				width = f32(gb.SCREEN_WIDTH),
				height = f32(gb.SCREEN_HEIGHT),
			},
			rl.Rectangle {
				x = 0,
				y = 0,
				width = f32(gb.SCREEN_WIDTH * SCREEN_SCALE),
				height = f32(gb.SCREEN_HEIGHT * SCREEN_SCALE),
			},
			{},
			0,
			rl.WHITE,
		)

		rl.EndDrawing()
	}
}
