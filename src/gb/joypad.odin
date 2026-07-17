package gb

joypad :: struct {
	select_bits: u8,
	right:       bool,
	left:        bool,
	up:          bool,
	down:        bool,
	a:           bool,
	b:           bool,
	start:       bool,
	select:      bool,
}

joypad_write :: proc(bus: ^Bus, value: u8) {
	// 0b110000 -  since we ignore upper 2 bits
	bus.joypad.select_bits = value & 0x30
}

joypad_read :: proc(bus: ^Bus) -> u8 {
	// The byte layout looks like this:
	// +--------------------------------------------------------------------+
	// | 7  6 |    5      |      4     |    3     |    2    |    1   |  0   |
	// =--------------------------------------------------------------------+
	// |      |  Select   |  Select d- |  Start/  |  Select/ |  B/   |  A/  |
	// |      |  buttons  |     pad    |   Up     |   Left   | Left | Right |
	// +--------------------------------------------------------------------+
	// Bit 5 = Select buttons
	// - If this bit is 0 then buttons (SsBA) can be read from lower nibble
	// Bit 4 = Select d-pad
	// - If this bit is 0 then directional keys can be read from lower nibble
	//

	joypad := &bus.joypad

	// Bits 6 and 7 read high
	// Bits 0–3 default high because released buttons are 1.
	result := u8(0xC0) | joypad.select_bits | 0x0F

	// Bit 4 low selects direction buttons.
	if joypad.select_bits & (1 << 4) == 0 {
		if joypad.right {
			result &= ~u8(1 << 0)
		}
		if joypad.left {
			result &= ~u8(1 << 1)
		}
		if joypad.up {
			result &= ~u8(1 << 2)
		}
		if joypad.down {
			result &= ~u8(1 << 3)
		}
	}

	// Bit 5 low selects action buttons.
	if joypad.select_bits & (1 << 5) == 0 {
		if joypad.a {
			result &= ~u8(1 << 0)
		}
		if joypad.b {
			result &= ~u8(1 << 1)
		}
		if joypad.select {
			result &= ~u8(1 << 2)
		}
		if joypad.start {
			result &= ~u8(1 << 3)
		}
	}

	return result
}

// --- Frontend callers

jpad_btn :: enum {
	RIGHT,
	LEFT,
	UP,
	DOWN,
	A,
	B,
	SELECT,
	START,
}

joypad_set_button :: proc(bus: ^Bus, button: jpad_btn, pressed: bool) {
	switch button {
	case .RIGHT:
		bus.joypad.right = pressed
	case .LEFT:
		bus.joypad.left = pressed
	case .UP:
		bus.joypad.up = pressed
	case .DOWN:
		bus.joypad.down = pressed
	case .A:
		bus.joypad.a = pressed
	case .B:
		bus.joypad.b = pressed
	case .SELECT:
		bus.joypad.select = pressed
	case .START:
		bus.joypad.start = pressed
	}
}
