package gb_tests

import "../../src/gb"
import "core:testing"

// --- Internal CPU getters tests ---

@(test)
test_can_fetch_u16_little_endian :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x50, 0x01})
	cpu := make_test_cpu()

	value := gb.cpu_fetch_u16(&cpu, &bus)

	testing.expect(t, value == 0x0150, "Expected little-endian 16-bit value 0x0150")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
}

@(test)
test_cpu_get_bc_combines_b_and_c :: proc(t: ^testing.T) {
	cpu := make_test_cpu()
	cpu.b = 0x12
	cpu.c = 0x34

	value := gb.cpu_get_bc(&cpu)

	testing.expect(t, value == 0x1234, "Expected BC to equal 0x1234")
}

@(test)
test_cpu_get_de_combines_d_and_e :: proc(t: ^testing.T) {
	cpu := make_test_cpu()
	cpu.d = 0xAB
	cpu.e = 0xCD

	value := gb.cpu_get_de(&cpu)

	testing.expect(t, value == 0xABCD, "Expected DE to equal 0xABCD")
}

@(test)
test_cpu_get_hl_combines_h_and_l :: proc(t: ^testing.T) {
	cpu := make_test_cpu()
	cpu.h = 0x01
	cpu.l = 0x50

	value := gb.cpu_get_hl(&cpu)

	testing.expect(t, value == 0x0150, "Expected HL to equal 0x0150")
}

@(test)
test_cpu_get_register_pairs_with_zero_bytes :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	cpu.b = 0xFF
	cpu.c = 0x00
	testing.expect(t, gb.cpu_get_bc(&cpu) == 0xFF00, "Expected BC to equal 0xFF00")

	cpu.d = 0x00
	cpu.e = 0xFF
	testing.expect(t, gb.cpu_get_de(&cpu) == 0x00FF, "Expected DE to equal 0x00FF")

	cpu.h = 0xFF
	cpu.l = 0xFF
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xFFFF, "Expected HL to equal 0xFFFF")
}

// --- Internal CPU setter tests ---

@(test)
test_cpu_set_r16_imm16_bc_splits_value_into_b_and_c :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	gb.cpu_set_r16(&cpu, .BC, 0x1234)

	// The high byte, 0x12, is stored in B.
	// The low byte, 0x34, is stored in C.
	testing.expect(t, cpu.b == 0x12, "Expected B to equal the high byte 0x12")
	testing.expect(t, cpu.c == 0x34, "Expected C to equal the low byte 0x34")
}

@(test)
test_cpu_set_r16_imm16_de_splits_value_into_d_and_e :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	gb.cpu_set_r16(&cpu, .DE, 0xABCD)

	// The high byte, 0xAB, is stored in D.
	// The low byte, 0xCD, is stored in E.
	testing.expect(t, cpu.d == 0xAB, "Expected D to equal the high byte 0xAB")
	testing.expect(t, cpu.e == 0xCD, "Expected E to equal the low byte 0xCD")
}

@(test)
test_cpu_set_r16_imm16_hl_splits_value_into_h_and_l :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	gb.cpu_set_r16(&cpu, .HL, 0x0150)

	// The high byte, 0x01, is stored in H.
	// The low byte, 0x50, is stored in L.
	testing.expect(t, cpu.h == 0x01, "Expected H to equal the high byte 0x01")
	testing.expect(t, cpu.l == 0x50, "Expected L to equal the low byte 0x50")
}

@(test)
test_cpu_set_r16_imm16_sp_sets_full_16_bit_value :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	gb.cpu_set_r16(&cpu, .SP, 0xFFFE)

	testing.expect(t, cpu.sp == 0xFFFE, "Expected SP to equal 0xFFFE")
}

@(test)
test_cpu_set_r16_imm16_handles_zero_bytes :: proc(t: ^testing.T) {
	cpu := make_test_cpu()

	gb.cpu_set_r16(&cpu, .BC, 0xFF00)
	testing.expect(t, cpu.b == 0xFF, "Expected B to equal 0xFF")
	testing.expect(t, cpu.c == 0x00, "Expected C to equal 0x00")

	gb.cpu_set_r16(&cpu, .DE, 0x00FF)
	testing.expect(t, cpu.d == 0x00, "Expected D to equal 0x00")
	testing.expect(t, cpu.e == 0xFF, "Expected E to equal 0xFF")
}

// --- Opcode instruction state test ---

// --- nop opcode tests ---

@(test)
test_nop :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x00})
	cpu := make_test_cpu()

	_, ok := gb.Cpu_step(&cpu, &bus)
	testing.expect(t, ok, "Expected NOP to not error")
	testing.expect(t, cpu.pc == 0x0101, "Expected to bump PC to bump to 0x0101")
}

// --- jp imm16 opcode tests ---

@(test)
test_jp_imm16_sets_pc :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xC3, 0x50, 0x01})
	cpu := make_test_cpu()

	cpu.f = 0xB0 // some arbitrary flag state to confirm JP does not change flags

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected JP imm16 to succeed")
	testing.expect(t, cpu.pc == 0x0150, "Expected PC to jump to 0x0150")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 4, "Expected JP imm16 to take 4 cycles")
}

// --- cp a, imm8 opcode tests ---

@(test)
test_cp_a_imm8_equal_sets_zero_and_subtract :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x42})
	cpu := make_test_cpu()
	cpu.a = 0x42

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 66 - 66 = 0, so Z is set.
	// CP is a subtraction operation, so N is always set.
	// The lower nibble is 2 - 2, so no half-borrow is needed and H is clear.
	// 66 is not less than 66, so no full borrow is needed and C is clear.
	// Flags: Z=1, N=1, H=0, C=0 -> 1100_0000 -> 0xC0.
	testing.expect(t, ok, "Expected CP a, imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP a, imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x42, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0xC0, "Expected Z=1, N=1, H=0, C=0")
}

@(test)
test_cp_imm8_sets_half_carry :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x01})
	cpu := make_test_cpu()
	cpu.a = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 16 - 1 = 15, so the result is not zero and Z is clear.
	// CP is a subtraction operation, so N is set.
	// The lower nibble must calculate 0 - 1, so it borrows from bit 4 and H is set.
	// 16 is greater than 1, so no full 8-bit borrow is needed and C is clear.
	// Flags: Z=0, N=1, H=1, C=0 -> 0110_0000 -> 0x60.
	testing.expect(t, ok, "Expected CP imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x10, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0x60, "Expected Z=0, N=1, H=1, C=0")
}

@(test)
test_cp_imm8_sets_carry_and_half_carry :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x05})
	cpu := make_test_cpu()
	cpu.a = 0x03

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 3 - 5 is not zero, so Z is clear.
	// CP is a subtraction operation, so N is set.
	// The lower nibble must calculate 3 - 5, so a half-borrow is needed and H is set.
	// 3 is less than 5, so a full 8-bit borrow is needed and C is set.
	// Flags: Z=0, N=1, H=1, C=1 -> 0111_0000 -> 0x70.
	testing.expect(t, ok, "Expected CP imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x03, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0x70, "Expected Z=0, N=1, H=1, C=1")
}

@(test)
test_cp_imm8_sets_carry_without_half_carry :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x20})
	cpu := make_test_cpu()
	cpu.a = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 16 - 32 is not zero, so Z is clear.
	// CP is a subtraction operation, so N is set.
	// The lower nibbles calculate 0 - 0, so no half-borrow is needed and H is clear.
	// 16 is less than 32, so a full 8-bit borrow is needed and C is set.
	// Flags: Z=0, N=1, H=0, C=1 -> 0101_0000 -> 0x50.
	testing.expect(t, ok, "Expected CP imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x10, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0x50, "Expected Z=0, N=1, H=0, C=1")
}

@(test)
test_cp_imm8_clears_previous_flags :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x01})
	cpu := make_test_cpu()
	cpu.a = 0x02

	// Begin with every flag set to prove CP replaces the previous flag state.
	cpu.f = 0xF0 // 11110000

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 2 - 1 = 1, so Z is clear.
	// CP is a subtraction operation, so N is set.
	// The lower nibble calculates 2 - 1 without borrowing, so H is clear.
	// 2 is greater than 1, so no full borrow is needed and C is clear.
	// Flags: Z=0, N=1, H=0, C=0 -> 0100_0000 -> 0x40.
	testing.expect(t, ok, "Expected CP imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x02, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0x40, "Expected Z=0, N=1, H=0, C=0")
}

@(test)
test_cp_imm8_keeps_lower_flag_nibble_zero :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0xFE, 0x00})
	cpu := make_test_cpu()
	cpu.a = 0x01

	// Deliberately place invalid bits in the lower nibble of F.
	// A valid Game Boy F register must always have bits 0-3 cleared.
	cpu.f = 0x0F

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// 1 - 0 = 1, so Z is clear.
	// CP is a subtraction operation, so N is set.
	// Neither a half-borrow nor a full borrow is needed.
	// cpu_set_flag also clears the invalid lower four bits.
	// Flags: Z=0, N=1, H=0, C=0 -> 0100_0000 -> 0x40.
	testing.expect(t, ok, "Expected CP imm8 to succeed")
	testing.expect(t, cycles == 2, "Expected CP imm8 to take 2 cycles")
	testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
	testing.expect(t, cpu.a == 0x01, "Expected CP to leave A unchanged")
	testing.expect(t, cpu.f == 0x40, "Expected lower four bits of F to be zero")
}


// --- ld r16, imm16 opcode tests ---

@(test)
test_ld_bc_loads_imm16 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x01, 0x34, 0x12})
	cpu := make_test_cpu()
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	// The immediate bytes are stored little-endian:
	// 0x34 is the low byte and 0x12 is the high byte.
	testing.expect(t, ok, "Expected LD BC, imm16 to succeed")
	testing.expect(t, gb.cpu_get_bc(&cpu) == 0x1234, "Expected BC to equal 0x1234")
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 3, "Expected LD BC, imm16 to take 3 cycles")
}

@(test)
test_ld_de_loads_imm16 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x11, 0xCD, 0xAB})
	cpu := make_test_cpu()
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD DE, imm16 to succeed")
	testing.expect(t, gb.cpu_get_de(&cpu) == 0xABCD, "Expected DE to equal 0xABCD")
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 3, "Expected LD DE, imm16 to take 3 cycles")
}

@(test)
test_ld_hl_loads_imm16 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x21, 0x50, 0x01})
	cpu := make_test_cpu()
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD HL, imm16 to succeed")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0x0150, "Expected HL to equal 0x0150")
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 3, "Expected LD HL, imm16 to take 3 cycles")
}

@(test)
test_ld_sp_loads_imm16 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x31, 0xFE, 0xFF})
	cpu := make_test_cpu()
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD SP, imm16 to succeed")
	testing.expect(t, cpu.sp == 0xFFFE, "Expected SP to equal 0xFFFE")
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 3, "Expected LD SP, imm16 to take 3 cycles")
}

// --- ld [r16mem], a opcode tests ---

@(test)
test_ld_bc_a_writes_a_to_address_in_bc :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x02})
	cpu := make_test_cpu()
	cpu.a = 0x42
	cpu.b = 0xC1
	cpu.c = 0x23

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [BC], A to succeed")
	testing.expect(t, gb.bus_read_byte(&bus, 0xC123) == 0x42, "Expected memory at BC to contain A")
	testing.expect(t, gb.cpu_get_bc(&cpu) == 0xC123, "Expected BC to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD [BC], A to take 2 cycles")
}


@(test)
test_ld_de_a_writes_a_to_address_in_de :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x12})
	cpu := make_test_cpu()

	cpu.a = 0x99
	cpu.d = 0xC2
	cpu.e = 0x34

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [DE], A to succeed")
	testing.expect(t, gb.bus_read_byte(&bus, 0xC234) == 0x99, "Expected memory at DE to contain A")
	testing.expect(t, gb.cpu_get_de(&cpu) == 0xC234, "Expected DE to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD [DE], A to take 2 cycles")
}

@(test)
test_ld_hli_a_writes_a_then_increments_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x22})
	cpu := make_test_cpu()

	cpu.a = 0x77
	cpu.h = 0xC3
	cpu.l = 0x45

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL+], A to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC345) == 0x77,
		"Expected memory at original HL to contain A",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC346, "Expected HL to increment after the write")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD [HL+], A to take 2 cycles")
}

@(test)
test_ld_hld_a_writes_a_then_decrements_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x32})
	cpu := make_test_cpu()

	cpu.a = 0x55
	cpu.h = 0xC4
	cpu.l = 0x56

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL-], A to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC456) == 0x55,
		"Expected memory at original HL to contain A",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC455, "Expected HL to decrement after the write")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD [HL-], A to take 2 cycles")
}

@(test)
test_ld_r16mem_a_does_not_change_flags :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x02})
	cpu := make_test_cpu()

	cpu.a = 0x42
	cpu.b = 0xC0
	cpu.c = 0x00
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [BC], A to succeed")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cycles == 2, "Expected LD [BC], A to take 2 cycles")
}

@(test)
test_ld_hli_a_wraps_hl_from_ffff_to_0000 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x22})
	cpu := make_test_cpu()

	cpu.a = 0xAA
	cpu.h = 0xFF
	cpu.l = 0xFF

	_, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL+], A to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0xAA,
		"Expected memory at 0xFFFF to contain A",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0x0000, "Expected HL to wrap to 0x0000")
}

@(test)
test_ld_hld_a_wraps_hl_from_0000_to_ffff :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x32})
	cpu := make_test_cpu()

	cpu.a = 0xBB
	cpu.h = 0x00
	cpu.l = 0x00

	_, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL-], A to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0xBB,
		"Expected memory at 0x0000 to contain A",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xFFFF, "Expected HL to wrap to 0xFFFF")
}


// --- ld a, [r16mem] opcode tests ---

@(test)
test_ld_a_bc_reads_memory_at_bc_into_a :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x0A})
	cpu := make_test_cpu()
	cpu.a = 0x00
	cpu.b = 0xC1
	cpu.c = 0x23

	// Writing 0x42 to BC
	gb.bus_write_byte(&bus, 0xC123, 0x42)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD a, [BC] to succeed")
	testing.expect(t, cpu.a == 0x42, "Expected memory at A to contain BC")
	testing.expect(t, gb.cpu_get_bc(&cpu) == 0xC123, "Expected BC to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [BC] to take 2 cycles")
}

@(test)
test_ld_a_de_reads_memory_at_de_into_a :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x1A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.d = 0xC2
	cpu.e = 0x34
	cpu.f = 0xB0

	gb.bus_write_byte(&bus, 0xC234, 0x99)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [DE] to succeed")
	testing.expect(t, cpu.a == 0x99, "Expected A to contain the byte read from memory at DE")
	testing.expect(t, gb.cpu_get_de(&cpu) == 0xC234, "Expected DE to remain unchanged")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [DE] to take 2 cycles")
}

@(test)
test_ld_a_hli_reads_memory_at_hl_into_a_then_increments_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x2A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.h = 0xC3
	cpu.l = 0x45
	cpu.f = 0xB0

	gb.bus_write_byte(&bus, 0xC345, 0x77)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL+] to succeed")
	testing.expect(
		t,
		cpu.a == 0x77,
		"Expected A to contain the byte read from the original HL address",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC346, "Expected HL to increment after the read")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [HL+] to take 2 cycles")
}

@(test)
test_ld_a_hld_reads_memory_at_hl_into_a_then_decrements_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x3A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.h = 0xC4
	cpu.l = 0x56
	cpu.f = 0xB0

	gb.bus_write_byte(&bus, 0xC456, 0x55)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL-] to succeed")
	testing.expect(
		t,
		cpu.a == 0x55,
		"Expected A to contain the byte read from the original HL address",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC455, "Expected HL to decrement after the read")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [HL-] to take 2 cycles")
}

@(test)
test_ld_a_bc_can_load_zero :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x0A})
	cpu := make_test_cpu()

	cpu.a = 0xFF
	cpu.b = 0xC0
	cpu.c = 0x10

	gb.bus_write_byte(&bus, 0xC010, 0x00)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [BC] to succeed")
	testing.expect(t, cpu.a == 0x00, "Expected A to load 0x00 from memory")
	testing.expect(t, gb.cpu_get_bc(&cpu) == 0xC010, "Expected BC to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [BC] to take 2 cycles")
}

@(test)
test_ld_a_de_can_load_ff :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x1A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.d = 0xC0
	cpu.e = 0x20

	gb.bus_write_byte(&bus, 0xC020, 0xFF)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [DE] to succeed")
	testing.expect(t, cpu.a == 0xFF, "Expected A to load 0xFF from memory")
	testing.expect(t, gb.cpu_get_de(&cpu) == 0xC020, "Expected DE to remain unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [DE] to take 2 cycles")
}

@(test)
test_ld_a_hli_wraps_hl_from_ffff_to_0000 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x2A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.h = 0xFF
	cpu.l = 0xFF

	gb.bus_write_byte(&bus, 0xFFFF, 0xAA)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL+] to succeed")
	testing.expect(t, cpu.a == 0xAA, "Expected A to contain the byte read from address 0xFFFF")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0x0000, "Expected HL to wrap from 0xFFFF to 0x0000")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [HL+] to take 2 cycles")
}

@(test)
test_ld_a_hld_wraps_hl_from_0000_to_ffff :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x3A})
	cpu := make_test_cpu()

	cpu.a = 0x00
	cpu.h = 0x00
	cpu.l = 0x00

	gb.bus_write_byte(&bus, 0x0000, 0xBB)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL-] to succeed")
	testing.expect(t, cpu.a == 0xBB, "Expected A to contain the byte read from address 0x0000")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xFFFF, "Expected HL to wrap from 0x0000 to 0xFFFF")
	testing.expect(t, cpu.pc == 0x0101, "Expected PC to advance by 1")
	testing.expect(t, cycles == 2, "Expected LD A, [HL-] to take 2 cycles")
}

@(test)
test_ld_a_hli_reads_before_incrementing_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x2A})
	cpu := make_test_cpu()

	cpu.h = 0xC5
	cpu.l = 0x00

	gb.bus_write_byte(&bus, 0xC500, 0x12)
	gb.bus_write_byte(&bus, 0xC501, 0x34)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL+] to succeed")
	testing.expect(t, cpu.a == 0x12, "Expected A to read from HL before HL increments")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC501, "Expected HL to increment after the read")
	testing.expect(t, cycles == 2, "Expected LD A, [HL+] to take 2 cycles")
}

@(test)
test_ld_a_hld_reads_before_decrementing_hl :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x3A})
	cpu := make_test_cpu()

	cpu.h = 0xC5
	cpu.l = 0x01

	gb.bus_write_byte(&bus, 0xC501, 0x12)
	gb.bus_write_byte(&bus, 0xC500, 0x34)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, [HL-] to succeed")
	testing.expect(t, cpu.a == 0x12, "Expected A to read from HL before HL decrements")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC500, "Expected HL to decrement after the read")
	testing.expect(t, cycles == 2, "Expected LD A, [HL-] to take 2 cycles")
}


