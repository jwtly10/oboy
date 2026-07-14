package gb

timer_tick :: proc(bus: ^Bus) {
	timer_overflow_check(bus)

	regs := &bus.timer_regs

	tac := regs.tac
	old_input := timer_input(regs.system_counter, tac)

	regs.system_counter += 1

	new_input := timer_input(regs.system_counter, tac)

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
