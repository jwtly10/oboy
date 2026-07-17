package gb_tests

import gb "../../src/gb"
import "core:testing"

make_test_machine :: proc(program: []u8) -> gb.Machine {
	return gb.Machine{cpu = make_test_cpu(), bus = make_test_bus(program)}
}

// --- Machine interrupt handling tests ---

@(test)
test_machine_vblank_interrupt_enters_vector_and_saves_return_address :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.pc = 0x1234
	machine.cpu.sp = 0xD002
	machine.cpu.ime = true
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected VBlank interrupt service to succeed")
	testing.expect(t, machine.cpu.pc == 0x0040, "Expected VBlank handler vector 0x0040")
	testing.expect(
		t,
		machine.cpu.sp == 0xD000,
		"Expected interrupt service to decrement SP by two",
	)
	testing.expect(
		t,
		gb.bus_read_u16_le(&machine.bus, 0xD000) == 0x1234,
		"Expected current PC to be pushed in little-endian order",
	)
	testing.expect(t, !machine.cpu.ime, "Expected interrupt service to clear IME")
}

@(test)
test_machine_timer_interrupt_enters_timer_vector :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.ime = true
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x04)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x04)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected Timer interrupt service to succeed")
	testing.expect(t, machine.cpu.pc == 0x0050, "Expected Timer handler vector 0x0050")
}

@(test)
test_machine_interrupt_clears_only_serviced_if_bit :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.ime = true
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0xFF)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected enabled VBlank interrupt service to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0xFE,
		"Expected only the serviced VBlank IF bit to be cleared",
	)
}

@(test)
test_machine_vblank_has_priority_over_timer :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.ime = true
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x05)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x05)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected highest-priority interrupt service to succeed")
	testing.expect(t, machine.cpu.pc == 0x0040, "Expected VBlank to win over Timer")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x04,
		"Expected Timer request to remain pending after VBlank service",
	)
}

@(test)
test_machine_does_not_service_interrupt_when_ime_is_clear :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.ime = false
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected normal instruction execution to succeed")
	testing.expect(t, machine.cpu.pc == 0x0101, "Expected NOP to execute instead of the handler")
	testing.expect(t, machine.cpu.sp == 0xFFFE, "Expected SP to remain unchanged")
	testing.expect(t, !machine.cpu.ime, "Expected IME to remain clear")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x01,
		"Expected unserviced interrupt request to remain pending",
	)
}

@(test)
test_machine_pending_interrupt_releases_halt_when_ime_is_clear :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	machine.cpu.halted = true
	machine.cpu.ime = false
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x04)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x04)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected CPU execution to resume")
	testing.expect(t, !machine.cpu.halted, "Expected a pending interrupt to release HALT")
	testing.expect(t, machine.cpu.pc == 0x0101, "Expected execution to resume without servicing")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x04,
		"Expected Timer request to remain pending while IME is clear",
	)
}

@(test)
test_machine_halt_with_pending_interrupt_and_clear_ime_exits_immediately :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x76, 0x00})
	machine.cpu.ime = false
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected HALT execution to succeed")
	testing.expect(
		t,
		!machine.cpu.halted,
		"Expected pending interrupt with clear IME to trigger the HALT bug instead of halting",
	)
	testing.expect(t, machine.cpu.pc == 0x0101, "Expected HALT opcode fetch to advance PC")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x01,
		"Expected interrupt request to remain pending while IME is clear",
	)
}

@(test)
test_machine_halt_bug_executes_following_opcode_twice :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x76, 0x04, 0x00}) // HALT; INC B; NOP
	machine.cpu.ime = false
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	halt_ok := gb.Machine_step(&machine)
	first_inc_ok := gb.Machine_step(&machine)
	first_inc_pc := machine.cpu.pc
	first_inc_b := machine.cpu.b
	second_inc_ok := gb.Machine_step(&machine)

	testing.expect(
		t,
		halt_ok && first_inc_ok && second_inc_ok,
		"Expected HALT and both INC executions",
	)
	testing.expect(t, first_inc_b == 1, "Expected the opcode after HALT to execute once")
	testing.expect(
		t,
		first_inc_pc == 0x0101,
		"Expected the first bugged opcode fetch not to advance PC",
	)
	testing.expect(
		t,
		machine.cpu.b == 2,
		"Expected the opcode after HALT to execute a second time",
	)
	testing.expect(
		t,
		machine.cpu.pc == 0x0102,
		"Expected the repeated opcode fetch to advance PC normally",
	)
}

@(test)
test_machine_halt_bug_makes_rst_push_its_own_address :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x76, 0xC7}) // HALT; RST 00H
	machine.cpu.sp = 0xD002
	machine.cpu.ime = false
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	halt_ok := gb.Machine_step(&machine)
	rst_ok := gb.Machine_step(&machine)

	testing.expect(t, halt_ok && rst_ok, "Expected HALT and RST executions to succeed")
	testing.expect(t, machine.cpu.pc == 0x0000, "Expected RST 00H to enter vector 0x0000")
	testing.expect(t, machine.cpu.sp == 0xD000, "Expected RST to decrement SP by two")
	testing.expect(
		t,
		gb.bus_read_u16_le(&machine.bus, 0xD000) == 0x0101,
		"Expected RST return address to point to the RST opcode",
	)
}

@(test)
test_machine_ei_then_halt_interrupt_returns_to_halt :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0xFB, 0x76}) // EI; HALT
	machine.cpu.sp = 0xD002
	gb.bus_write_byte(&machine.bus, 0xFFFF, 0x01)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x01)

	ei_ok := gb.Machine_step(&machine)
	halt_ok := gb.Machine_step(&machine)
	interrupt_ok := gb.Machine_step(&machine)

	testing.expect(t, ei_ok && halt_ok && interrupt_ok, "Expected EI, HALT, and interrupt service")
	testing.expect(t, machine.cpu.pc == 0x0040, "Expected VBlank interrupt vector")
	testing.expect(
		t,
		machine.cpu.sp == 0xD000,
		"Expected interrupt service to decrement SP by two",
	)
	testing.expect(
		t,
		gb.bus_read_u16_le(&machine.bus, 0xD000) == 0x0101,
		"Expected interrupt return address to point to HALT",
	)
	testing.expect(
		t,
		!machine.cpu.halt_bug,
		"Expected interrupt service to consume the HALT bug state",
	)
}

// -- Timer tests --

@(test)
test_div_increments_after_64_m_cycles :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.machine_tick(&machine, 63)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF04) == 0,
		"Expected DIV to remain zero before 256 T-cycles",
	)

	gb.machine_tick(&machine, 1)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF04) == 1,
		"Expected DIV to increment after 256 T-cycles",
	)
}

@(test)
test_writing_div_resets_system_counter :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.machine_tick(&machine, 64)
	gb.bus_write_byte(&machine.bus, 0xFF04, 0x99)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF04) == 0,
		"Expected any write to DIV to reset it",
	)
}

@(test)
test_disabled_timer_does_not_increment_tima :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.bus_write_byte(&machine.bus, 0xFF07, 0x01)
	gb.machine_tick(&machine, 4)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0,
		"Expected TIMA not to increment while timer is disabled",
	)
}

@(test)
test_timer_frequency_01_increments_after_4_m_cycles :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)
	gb.machine_tick(&machine, 4)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 1,
		"Expected TIMA to increment after 4 M-cycles",
	)
}

@(test)
test_tima_overflow_reloads_tma_and_requests_interrupt :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x42)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 4)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x00,
		"Expected TIMA to remain zero during the overflow delay",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 == 0,
		"Expected Timer interrupt to remain clear during the overflow delay",
	)

	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x42,
		"Expected TIMA to reload from TMA one M-cycle after overflow",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 != 0,
		"Expected TIMA reload to request Timer interrupt",
	)
}

// --- Timer core tests ---

@(test)
test_all_timer_frequencies_increment_on_their_selected_period :: proc(t: ^testing.T) {
	cases := [?]struct {
		tac:             u8,
		period_m_cycles: int,
	}{{0x04, 256}, {0x05, 4}, {0x06, 16}, {0x07, 64}}

	for test_case in cases {
		machine := make_test_machine([]u8{0x00})
		gb.bus_write_byte(&machine.bus, 0xFF07, test_case.tac)

		gb.machine_tick(&machine, test_case.period_m_cycles - 1)
		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF05) == 0,
			"Expected TAC 0x%02X not to increment TIMA before %d M-cycles",
			test_case.tac,
			test_case.period_m_cycles,
		)

		gb.machine_tick(&machine, 1)
		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF05) == 1,
			"Expected TAC 0x%02X to increment TIMA after %d M-cycles",
			test_case.tac,
			test_case.period_m_cycles,
		)
	}
}

@(test)
test_timer_increments_tima_across_multiple_periods :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 12)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 3,
		"Expected TIMA to increment once for each elapsed timer period",
	)
}

@(test)
test_div_continues_while_tima_is_disabled :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x01)

	gb.machine_tick(&machine, 64)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF04) == 1,
		"Expected DIV to continue incrementing while the timer is disabled",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0,
		"Expected disabled TIMA to remain unchanged while DIV increments",
	)
}

@(test)
test_tima_overflow_preserves_unrelated_interrupt_flags :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x11)
	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x42)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 4)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x11,
		"Expected interrupt flags to remain unchanged during the overflow delay",
	)

	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) == 0x15,
		"Expected timer overflow to set only the Timer interrupt flag",
	)
}

// --- Timer overflow write tests ---

@(test)
test_writing_tima_during_overflow_delay_cancels_reload_and_interrupt :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x42)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 4)
	gb.bus_write_byte(&machine.bus, 0xFF05, 0x77)
	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x77,
		"Expected TIMA write to replace zero and cancel the pending reload",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 == 0,
		"Expected TIMA write to cancel the pending Timer interrupt",
	)
}

@(test)
test_writing_tma_during_overflow_delay_changes_pending_reload_value :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x42)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 4)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x66)
	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF06) == 0x66,
		"Expected TMA write to update the modulo register",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x66,
		"Expected pending reload to use the updated TMA value",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 != 0,
		"Expected pending reload to request Timer interrupt",
	)
}

@(test)
test_timer_can_overflow_again_after_reload_phase_completes :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.machine_tick(&machine, 5)
	gb.bus_write_byte(&machine.bus, 0xFF0F, 0x00)
	gb.machine_tick(&machine, 2)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0xFF,
		"Expected TIMA to remain at TMA before the next timer period",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 == 0,
		"Expected no second Timer interrupt before another overflow",
	)

	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x00,
		"Expected the next timer increment to overflow TIMA again",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 == 0,
		"Expected the second Timer interrupt to wait for the reload",
	)

	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0xFF,
		"Expected the second overflow to reload TMA",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 != 0,
		"Expected the second reload to request Timer interrupt",
	)
}

// --- DIV and TAC write-edge tests ---

@(test)
test_writing_div_increments_tima_when_selected_input_is_high :: proc(t: ^testing.T) {
	cases := [?]struct {
		tac:           u8,
		high_m_cycles: int,
	}{{0x04, 128}, {0x05, 2}, {0x06, 8}, {0x07, 32}}

	for test_case in cases {
		machine := make_test_machine([]u8{0x00})
		gb.bus_write_byte(&machine.bus, 0xFF07, test_case.tac)
		gb.machine_tick(&machine, test_case.high_m_cycles)

		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF05) == 0,
			"Expected TAC 0x%02X not to increment before its falling edge",
			test_case.tac,
		)

		gb.bus_write_byte(&machine.bus, 0xFF04, 0x99)

		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF04) == 0,
			"Expected DIV write to reset the counter for TAC 0x%02X",
			test_case.tac,
		)
		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF05) == 1,
			"Expected DIV write to create a falling edge for TAC 0x%02X",
			test_case.tac,
		)
	}
}

@(test)
test_writing_div_does_not_increment_tima_when_input_is_low_or_disabled :: proc(t: ^testing.T) {
	low_machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&low_machine.bus, 0xFF07, 0x05)
	gb.bus_write_byte(&low_machine.bus, 0xFF04, 0x00)

	testing.expect(
		t,
		gb.bus_read_byte(&low_machine.bus, 0xFF05) == 0,
		"Expected DIV write not to increment TIMA when the selected input is low",
	)

	disabled_machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&disabled_machine.bus, 0xFF07, 0x01)
	gb.machine_tick(&disabled_machine, 2)
	gb.bus_write_byte(&disabled_machine.bus, 0xFF04, 0x00)

	testing.expect(
		t,
		gb.bus_read_byte(&disabled_machine.bus, 0xFF05) == 0,
		"Expected DIV write not to increment TIMA while the timer is disabled",
	)
}

@(test)
test_writing_tac_increments_tima_only_on_falling_input_transitions :: proc(t: ^testing.T) {
	cases := [?]struct {
		old_tac:          u8,
		new_tac:          u8,
		advance_m_cycles: int,
		expected_tima:    u8,
	} {
		{0x05, 0x06, 2, 1}, // Selected input changes from bit 3 high to bit 5 low.
		{0x06, 0x05, 2, 0}, // Selected input changes from bit 5 low to bit 3 high.
		{0x05, 0x06, 10, 0}, // Both selected inputs are high.
		{0x05, 0x06, 0, 0}, // Both selected inputs are low.
		{0x05, 0x01, 2, 1}, // DMG disabling while the selected input is high.
		{0x05, 0x01, 0, 0}, // Disabling while the selected input is low.
		{0x05, 0x05, 2, 0}, // Rewriting the same high input creates no edge.
	}

	for test_case in cases {
		machine := make_test_machine([]u8{0x00})
		gb.machine_tick(&machine, test_case.advance_m_cycles)
		gb.bus_write_byte(&machine.bus, 0xFF07, test_case.old_tac)
		gb.bus_write_byte(&machine.bus, 0xFF07, test_case.new_tac)

		testing.expectf(
			t,
			gb.bus_read_byte(&machine.bus, 0xFF05) == test_case.expected_tima,
			"Expected TAC change 0x%02X -> 0x%02X to leave TIMA at 0x%02X",
			test_case.old_tac,
			test_case.new_tac,
			test_case.expected_tima,
		)
	}
}

@(test)
test_writing_tac_masks_unused_bits :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})

	gb.bus_write_byte(&machine.bus, 0xFF07, 0xFF)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF07) == 0xFF,
		"Expected TAC unused bits to read high after writing all bits",
	)
}

@(test)
test_tac_write_falling_edge_uses_delayed_overflow_reload :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.machine_tick(&machine, 2)
	gb.bus_write_byte(&machine.bus, 0xFF05, 0xFF)
	gb.bus_write_byte(&machine.bus, 0xFF06, 0x42)
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	gb.bus_write_byte(&machine.bus, 0xFF07, 0x01)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x00,
		"Expected TAC write falling edge to overflow TIMA to zero",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 == 0,
		"Expected TAC write overflow not to request Timer interrupt immediately",
	)

	gb.machine_tick(&machine, 1)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x42,
		"Expected TAC write overflow to reload TMA after one M-cycle",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 != 0,
		"Expected TAC write overflow reload to request Timer interrupt",
	)
}

@(test)
test_timer_advances_while_cpu_is_halted :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x76})
	gb.bus_write_byte(&machine.bus, 0xFF07, 0x05)

	halt_ok := gb.Machine_step(&machine)
	wait_one_ok := gb.Machine_step(&machine)
	wait_two_ok := gb.Machine_step(&machine)
	wait_three_ok := gb.Machine_step(&machine)

	testing.expect(
		t,
		halt_ok && wait_one_ok && wait_two_ok && wait_three_ok,
		"Expected HALT and halted wait cycles to succeed",
	)
	testing.expect(t, machine.cpu.halted, "Expected CPU to remain halted")
	testing.expect(t, machine.cpu.pc == 0x0101, "Expected halted CPU not to fetch another opcode")
	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF05) == 1,
		"Expected the timer to advance during four halted M-cycles",
	)
}

// --- PPU clock integration tests ---

@(test)
test_machine_tick_advances_ppu_once_per_t_cycle :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	gb.bus_write_byte(&machine.bus, 0xFF40, 0x80)

	gb.machine_tick(&machine, 20)

	testing.expect(
		t,
		machine.bus.ppu.dot == 80,
		"Expected 20 M-cycles to advance the PPU by 80 dots",
	)
	testing.expect(
		t,
		machine.bus.ppu.mode == .DRAWING,
		"Expected machine clock to reach drawing mode",
	)
	testing.expect(
		t,
		machine.bus.ppu.stat & 0b11 == 3,
		"Expected STAT mode to follow machine time",
	)
}

// --- OAM DMA clock integration tests ---

@(test)
test_machine_tick_advances_dma_once_per_t_cycle :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0x00})
	for index in 0 ..< 0xA0 {
		gb.bus_write_byte(&machine.bus, 0xC000 + u16(index), u8(index + 1))
	}
	gb.bus_write_byte(&machine.bus, 0xFF46, 0xC0)

	gb.machine_tick(&machine, 161)

	testing.expect(
		t,
		!machine.bus.dma.active,
		"Expected one startup cycle and 160 copy cycles to complete OAM DMA",
	)
	testing.expect(
		t,
		machine.bus.oam[0] == 1 && machine.bus.oam[0x9F] == 0xA0,
		"Expected machine time to copy the first and last OAM bytes",
	)
}

@(test)
test_machine_dma_uses_instruction_at_once_timing :: proc(t: ^testing.T) {
	machine := make_test_machine([]u8{0xE0, 0x46}) // LDH [$FF46], A
	machine.cpu.a = 0xC0
	gb.bus_write_byte(&machine.bus, 0xC000, 0x5A)

	ok := gb.Machine_step(&machine)

	testing.expect(t, ok, "Expected the DMA-triggering instruction to succeed")
	testing.expect(t, machine.bus.dma.active, "Expected the instruction to request OAM DMA")
	testing.expect(
		t,
		machine.bus.dma.byte_index == 2,
		"Expected bulk instruction timing to advance DMA for all three LDH M-cycles",
	)
	testing.expect(
		t,
		machine.bus.oam[0] == 0x5A && machine.bus.oam[1] == 0,
		"Expected the first two DMA bytes to be copied during bulk instruction timing",
	)
	testing.expect(t, machine.bus.dma.locked, "Expected DMA to lock the CPU bus after startup")
}
