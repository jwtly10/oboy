package gb

timer_tick :: proc(bus: ^Bus) {
	timer_overflow_check(bus)

	regs := &bus.timer_regs

	tac := regs.tac
	old_input := timer_input(regs.system_counter, tac)

	regs.system_counter += 1

	new_input := timer_input(regs.system_counter, tac)

	// Falling edge detection:
	// Based on the DIV & Tac, we check if the required bit is HIGH
	// before and after incrementing system counter
	// Inputs are true if high
	// so we are basically saying, if was high, but now not high (1->0)
	// so triggers TIMA increment
	if old_input && !new_input {
		timer_increment_tima(bus)
	}
}

timer_write_div :: proc(bus: ^Bus, value: u8) {
	regs := &bus.timer_regs
	tac := regs.tac

	old_input := timer_input(regs.system_counter, tac)

	// Writing to div resets internal divider counter
	regs.system_counter = 0

	new_input := timer_input(regs.system_counter, tac)

	// FED
	if old_input && !new_input {
		timer_increment_tima(bus)
	}
}

timer_write_tac :: proc(bus: ^Bus, value: u8) {
	regs := &bus.timer_regs

	old_input := timer_input(regs.system_counter, regs.tac)

	// the only bits we care about are 0,1,2
	regs.tac = value & 0x07

	new_input := timer_input(regs.system_counter, regs.tac)

	if old_input && !new_input {
		timer_increment_tima(bus)
	}
}

// Helper for writing to TIMA
// https://gbdev.io/pandocs/Timer_Obscure_Behaviour.html#timer-overflow-behavior
timer_write_tima :: proc(bus: ^Bus, value: u8) {
	regs := &bus.timer_regs

	switch regs.overflow_phase {
	case .CYCLE_A:
		regs.overflow_phase = .NONE
		regs.overflow_delay = 0
		regs.tima = value

	case .CYCLE_B:
	// Ignored. TMA wins during reload.

	case .NONE:
		regs.tima = value
	}
}

timer_write_tma :: proc(bus: ^Bus, value: u8) {
	regs := &bus.timer_regs

	regs.tma = value

	if regs.overflow_phase == .CYCLE_B {
		// During cycle B, the written TMA value is also loaded into TIMA.
		regs.tima = value
	}
}

timer_increment_tima :: proc(bus: ^Bus) {
	regs := &bus.timer_regs

	if regs.tima == 0xFF {
		// https://gbdev.io/pandocs/Timer_Obscure_Behaviour.html#timer-overflow-behavior
		// We allow overflow
		regs.tima = 0x00
		regs.overflow_phase = .CYCLE_A
		regs.overflow_delay = 4 // 1 M-Cycle -> 4 T-Cycle
		// We trigger overflow interrupt (.TIMER) on the NEXT cycle
		return
	}

	regs.tima += 1
}

// Checks Timer reg state to trigger overflow
timer_overflow_check :: proc(bus: ^Bus) {
	regs := &bus.timer_regs

	switch regs.overflow_phase {
	case .NONE:
		return
	case .CYCLE_A:
		// Timer is ticking in T-Ticks
		// so we have to wait for the full M-Cycle to complete first
		regs.overflow_delay -= 1

		if regs.overflow_delay == 0 {
			regs.overflow_phase = .CYCLE_B
			regs.overflow_delay = 4

			regs.tima = regs.tma
			interrupt_request(bus, .TIMER)
		}
	case .CYCLE_B:
		// The reload signal remains active for the whole M-cycle.
		regs.tima = regs.tma
		regs.overflow_delay -= 1

		if regs.overflow_delay == 0 {
			regs.overflow_phase = .NONE
		}
	}
}

// https://github.com/Ashiepaws/GBEDG/blob/master/timers/index.md
// Generates a signal based on CPU clock and tac
// 1. Tac must have enabled bit
// 2. Bit 0-1 of TAC decides which counter bit we care about
// 3. Counter & mask are ANDed to see if required bit is high (and tac enabled implicitly)
// Returns if signal is high
timer_input :: proc(counter: u16, tac: u8) -> bool {
	// 'Enabled' bit
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
