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
		gb.bus_read_byte(&machine.bus, 0xFF05) == 0x42,
		"Expected TIMA to reload from TMA after overflow",
	)

	testing.expect(
		t,
		gb.bus_read_byte(&machine.bus, 0xFF0F) & 0x04 != 0,
		"Expected TIMA overflow to request Timer interrupt",
	)
}
