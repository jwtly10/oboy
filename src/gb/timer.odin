package gb

// Timer :: struct {}

// init_timer :: proc() -> Timer {

// 	return Timer{}
// }

timer_tick :: proc(bus: ^Bus) {
	tac := bus.timer_regs.tac

	old_input := timer_input(bus.timer_regs.system_counter, tac)

	bus.timer_regs.system_counter += 1

	new_input := timer_input(bus.timer_regs.system_counter, tac)

	if old_input && !new_input {
		timer_increment_tima(bus)
	}
}

timer_input :: proc(counter: u16, tac: u8) -> bool {
	if tac & 0x04 == 0 {
		return false
	}

	bit: u16

	switch tac & 0x03 {
	case 0x00:
		bit = 9
	case 0x01:
		bit = 3
	case 0x02:
		bit = 5
	case 0x03:
		bit = 7
	}

	return counter & (u16(1) << bit) != 0
}

timer_increment_tima :: proc(bus: ^Bus) {
	if bus.timer_regs.tima == 0xFF {
		bus.timer_regs.tima = bus.timer_regs.tma
		interrupt_request(bus, .TIMER)
		return
	}

	bus.timer_regs.tima += 1
}
