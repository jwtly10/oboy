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


// --- LD [imm16], SP opcode tests ---

@(test)
test_ld_imm16_sp_writes_sp_little_endian :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x08, 0x00, 0xC0})
	cpu := make_test_cpu()

	cpu.sp = 0x1234
	cpu.f = 0xB0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [imm16], SP to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC000) == 0x34,
		"Expected low byte of SP at address 0xC000",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC001) == 0x12,
		"Expected high byte of SP at address 0xC001",
	)
	testing.expect(t, cpu.sp == 0x1234, "Expected SP to remain unchanged")
	testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cycles == 5, "Expected LD [imm16], SP to take 5 cycles")
}

@(test)
test_ld_imm16_sp_handles_zero_low_byte :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x08, 0x10, 0xC0})
	cpu := make_test_cpu()

	cpu.sp = 0xFF00

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [imm16], SP to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC010) == 0x00,
		"Expected low byte 0x00 at the target address",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC011) == 0xFF,
		"Expected high byte 0xFF at the next address",
	)
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cycles == 5, "Expected LD [imm16], SP to take 5 cycles")
}

@(test)
test_ld_imm16_sp_handles_zero_high_byte :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x08, 0x20, 0xC0})
	cpu := make_test_cpu()

	cpu.sp = 0x00FF

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [imm16], SP to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC020) == 0xFF,
		"Expected low byte 0xFF at the target address",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC021) == 0x00,
		"Expected high byte 0x00 at the next address",
	)
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cycles == 5, "Expected LD [imm16], SP to take 5 cycles")
}

@(test)
test_ld_imm16_sp_writes_to_consecutive_addresses :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x08, 0xFF, 0xC0})
	cpu := make_test_cpu()

	cpu.sp = 0xABCD

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [imm16], SP to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC0FF) == 0xCD,
		"Expected low byte at the exact immediate address",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC100) == 0xAB,
		"Expected high byte at the following address",
	)
	testing.expect(t, cycles == 5, "Expected LD [imm16], SP to take 5 cycles")
}

@(test)
test_ld_imm16_sp_wraps_second_write_from_ffff_to_0000 :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x08, 0xFF, 0xFF})
	cpu := make_test_cpu()

	cpu.sp = 0x1234

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [imm16], SP to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0x34,
		"Expected low byte of SP at address 0xFFFF",
	)
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0x0000) == 0x12,
		"Expected high byte of SP to wrap to address 0x0000",
	)
	testing.expect(t, cpu.pc == 0x0103, "Expected PC to advance by 3")
	testing.expect(t, cycles == 5, "Expected LD [imm16], SP to take 5 cycles")
}

// --- inc r16, dec r16, and add hl, r16 opcode tests ---

get_r16 :: proc(cpu: ^gb.Cpu, reg: gb.R16) -> u16 {
	switch reg {
	case .BC:
		return gb.cpu_get_bc(cpu)
	case .DE:
		return gb.cpu_get_de(cpu)
	case .HL:
		return gb.cpu_get_hl(cpu)
	case .SP:
		return cpu.sp
	}
	return 0
}

expect_inc_r16 :: proc(t: ^testing.T, opcode: u8, reg: gb.R16, initial, expected: u16) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.f = 0xB0
	gb.cpu_set_r16(&cpu, reg, initial)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected INC r16 opcode to succeed")
	testing.expect(t, get_r16(&cpu, reg) == expected, "Expected INC r16 to increment its operand")
	testing.expect(t, cpu.f == 0xB0, "Expected INC r16 to leave flags unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected INC r16 to advance PC by 1")
	testing.expect(t, cycles == 2, "Expected INC r16 to take 2 cycles")
}

@(test)
test_inc_r16_all_operands :: proc(t: ^testing.T) {
	expect_inc_r16(t, 0x03, .BC, 0x1234, 0x1235)
	expect_inc_r16(t, 0x13, .DE, 0x2345, 0x2346)
	expect_inc_r16(t, 0x23, .HL, 0x3456, 0x3457)
	expect_inc_r16(t, 0x33, .SP, 0x4567, 0x4568)
}

@(test)
test_inc_r16_wraps_at_ffff :: proc(t: ^testing.T) {
	expect_inc_r16(t, 0x03, .BC, 0xFFFF, 0x0000)
}

expect_dec_r16 :: proc(t: ^testing.T, opcode: u8, reg: gb.R16, initial, expected: u16) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.f = 0xB0
	gb.cpu_set_r16(&cpu, reg, initial)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected DEC r16 opcode to succeed")
	testing.expect(t, get_r16(&cpu, reg) == expected, "Expected DEC r16 to decrement its operand")
	testing.expect(t, cpu.f == 0xB0, "Expected DEC r16 to leave flags unchanged")
	testing.expect(t, cpu.pc == 0x0101, "Expected DEC r16 to advance PC by 1")
	testing.expect(t, cycles == 2, "Expected DEC r16 to take 2 cycles")
}

@(test)
test_dec_r16_all_operands :: proc(t: ^testing.T) {
	expect_dec_r16(t, 0x0B, .BC, 0x1234, 0x1233)
	expect_dec_r16(t, 0x1B, .DE, 0x2345, 0x2344)
	expect_dec_r16(t, 0x2B, .HL, 0x3456, 0x3455)
	expect_dec_r16(t, 0x3B, .SP, 0x4567, 0x4566)
}

@(test)
test_dec_r16_wraps_at_0000 :: proc(t: ^testing.T) {
	expect_dec_r16(t, 0x3B, .SP, 0x0000, 0xFFFF)
}

expect_add_hl_r16 :: proc(
	t: ^testing.T,
	opcode: u8,
	reg: gb.R16,
	hl, operand, expected: u16,
	initial_flags, expected_flags: u8,
) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	gb.cpu_set_r16(&cpu, .HL, hl)
	if reg != .HL {
		gb.cpu_set_r16(&cpu, reg, operand)
	}
	cpu.f = initial_flags

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected ADD HL, r16 opcode to succeed")
	testing.expect(
		t,
		gb.cpu_get_hl(&cpu) == expected,
		"Expected ADD HL, r16 to store the 16-bit sum in HL",
	)
	testing.expect(
		t,
		cpu.f == expected_flags,
		"Expected ADD HL, r16 to preserve Z and set N, H, and C correctly",
	)
	testing.expect(t, cpu.pc == 0x0101, "Expected ADD HL, r16 to advance PC by 1")
	testing.expect(t, cycles == 2, "Expected ADD HL, r16 to take 2 cycles")
}

@(test)
test_add_hl_r16_all_operands :: proc(t: ^testing.T) {
	expect_add_hl_r16(t, 0x09, .BC, 0x1000, 0x0001, 0x1001, 0x80, 0x80)
	expect_add_hl_r16(t, 0x19, .DE, 0x2000, 0x0002, 0x2002, 0x80, 0x80)
	expect_add_hl_r16(t, 0x29, .HL, 0x3000, 0x3000, 0x6000, 0x80, 0x80)
	expect_add_hl_r16(t, 0x39, .SP, 0x4000, 0x0003, 0x4003, 0x80, 0x80)
}

@(test)
test_add_hl_r16_sets_half_carry_from_bit_11 :: proc(t: ^testing.T) {
	expect_add_hl_r16(t, 0x09, .BC, 0x0FFF, 0x0001, 0x1000, 0x00, 0x20)
}

@(test)
test_add_hl_r16_wraps_and_sets_carry :: proc(t: ^testing.T) {
	expect_add_hl_r16(t, 0x19, .DE, 0xFFFF, 0x0001, 0x0000, 0x00, 0x30)
}

@(test)
test_add_hl_r16_preserves_zero_and_clears_other_stale_flags :: proc(t: ^testing.T) {
	expect_add_hl_r16(t, 0x39, .SP, 0x1000, 0x0001, 0x1001, 0xF0, 0x80)
}

// --- inc r8 and dec r8 opcode tests ---

set_r8_operand :: proc(cpu: ^gb.Cpu, bus: ^gb.Bus, reg: gb.R8, value: u8) {
	switch reg {
	case .B:
		cpu.b = value
	case .C:
		cpu.c = value
	case .D:
		cpu.d = value
	case .E:
		cpu.e = value
	case .H:
		cpu.h = value
	case .L:
		cpu.l = value
	case .HL_INDIRECT:
		gb.bus_write_byte(bus, gb.cpu_get_hl(cpu), value)
	case .A:
		cpu.a = value
	}
}

get_r8_operand :: proc(cpu: ^gb.Cpu, bus: ^gb.Bus, reg: gb.R8) -> u8 {
	switch reg {
	case .B:
		return cpu.b
	case .C:
		return cpu.c
	case .D:
		return cpu.d
	case .E:
		return cpu.e
	case .H:
		return cpu.h
	case .L:
		return cpu.l
	case .HL_INDIRECT:
		return gb.bus_read_byte(bus, gb.cpu_get_hl(cpu))
	case .A:
		return cpu.a
	}
	return 0
}

expect_inc_r8 :: proc(
	t: ^testing.T,
	opcode: u8,
	reg: gb.R8,
	initial, expected, initial_flags, expected_flags: u8,
) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.a = 0xA1
	cpu.b = 0xB2
	cpu.c = 0xC3
	cpu.d = 0xD4
	cpu.e = 0xE5
	cpu.h = 0xC1
	cpu.l = 0x20
	cpu.sp = 0xFEDC
	cpu.f = initial_flags
	set_r8_operand(&cpu, &bus, reg, initial)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected INC r8 opcode to succeed")
	testing.expect(
		t,
		get_r8_operand(&cpu, &bus, reg) == expected,
		"Expected INC r8 to increment its operand",
	)
	testing.expect(t, cpu.f == expected_flags, "Expected INC r8 to set Z, N, and H and preserve C")
	testing.expect(t, cpu.pc == 0x0101, "Expected INC r8 to advance PC by 1")
	expected_cycles := 1
	if reg == .HL_INDIRECT {
		expected_cycles = 3
	}
	testing.expect(
		t,
		cycles == expected_cycles,
		"Expected INC r8 to use the operand-specific cycle count",
	)
	testing.expect(t, cpu.sp == 0xFEDC, "Expected INC r8 to leave SP unchanged")
	if reg != .HL_INDIRECT && reg != .H && reg != .L {
		testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC120, "Expected INC r8 to leave HL unchanged")
	}
}

@(test)
test_inc_r8_all_operands :: proc(t: ^testing.T) {
	expect_inc_r8(t, 0x04, .B, 0x21, 0x22, 0x10, 0x10)
	expect_inc_r8(t, 0x0C, .C, 0x32, 0x33, 0x10, 0x10)
	expect_inc_r8(t, 0x14, .D, 0x43, 0x44, 0x10, 0x10)
	expect_inc_r8(t, 0x1C, .E, 0x54, 0x55, 0x10, 0x10)
	expect_inc_r8(t, 0x24, .H, 0x65, 0x66, 0x10, 0x10)
	expect_inc_r8(t, 0x2C, .L, 0x76, 0x77, 0x10, 0x10)
	expect_inc_r8(t, 0x34, .HL_INDIRECT, 0x87, 0x88, 0x10, 0x10)
	expect_inc_r8(t, 0x3C, .A, 0x98, 0x99, 0x10, 0x10)
}

@(test)
test_inc_r8_wraps_sets_zero_and_half_carry_and_preserves_carry :: proc(t: ^testing.T) {
	expect_inc_r8(t, 0x04, .B, 0xFF, 0x00, 0x50, 0xB0)
}

@(test)
test_inc_r8_sets_half_carry_without_zero_and_preserves_clear_carry :: proc(t: ^testing.T) {
	expect_inc_r8(t, 0x04, .B, 0x0F, 0x10, 0xC0, 0x20)
}

@(test)
test_inc_r8_clears_stale_flags_and_lower_flag_nibble :: proc(t: ^testing.T) {
	expect_inc_r8(t, 0x04, .B, 0x01, 0x02, 0xEF, 0x00)
}

expect_dec_r8 :: proc(
	t: ^testing.T,
	opcode: u8,
	reg: gb.R8,
	initial, expected, initial_flags, expected_flags: u8,
) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.a = 0xA1
	cpu.b = 0xB2
	cpu.c = 0xC3
	cpu.d = 0xD4
	cpu.e = 0xE5
	cpu.h = 0xC1
	cpu.l = 0x20
	cpu.sp = 0xFEDC
	cpu.f = initial_flags
	set_r8_operand(&cpu, &bus, reg, initial)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected DEC r8 opcode to succeed")
	testing.expect(
		t,
		get_r8_operand(&cpu, &bus, reg) == expected,
		"Expected DEC r8 to decrement its operand",
	)
	testing.expect(t, cpu.f == expected_flags, "Expected DEC r8 to set Z, N, and H and preserve C")
	testing.expect(t, cpu.pc == 0x0101, "Expected DEC r8 to advance PC by 1")
	expected_cycles := 1
	if reg == .HL_INDIRECT {
		expected_cycles = 3
	}
	testing.expect(
		t,
		cycles == expected_cycles,
		"Expected DEC r8 to use the operand-specific cycle count",
	)
	testing.expect(t, cpu.sp == 0xFEDC, "Expected DEC r8 to leave SP unchanged")
	if reg != .HL_INDIRECT && reg != .H && reg != .L {
		testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC120, "Expected DEC r8 to leave HL unchanged")
	}
}

@(test)
test_dec_r8_all_operands :: proc(t: ^testing.T) {
	expect_dec_r8(t, 0x05, .B, 0x22, 0x21, 0x10, 0x50)
	expect_dec_r8(t, 0x0D, .C, 0x33, 0x32, 0x10, 0x50)
	expect_dec_r8(t, 0x15, .D, 0x44, 0x43, 0x10, 0x50)
	expect_dec_r8(t, 0x1D, .E, 0x55, 0x54, 0x10, 0x50)
	expect_dec_r8(t, 0x25, .H, 0x66, 0x65, 0x10, 0x50)
	expect_dec_r8(t, 0x2D, .L, 0x77, 0x76, 0x10, 0x50)
	expect_dec_r8(t, 0x35, .HL_INDIRECT, 0x88, 0x87, 0x10, 0x50)
	expect_dec_r8(t, 0x3D, .A, 0x99, 0x98, 0x10, 0x50)
}

@(test)
test_dec_r8_to_zero_sets_zero_without_half_carry_and_preserves_carry :: proc(t: ^testing.T) {
	expect_dec_r8(t, 0x05, .B, 0x01, 0x00, 0x10, 0xD0)
}

@(test)
test_dec_r8_wraps_and_sets_half_carry_with_clear_carry :: proc(t: ^testing.T) {
	expect_dec_r8(t, 0x05, .B, 0x00, 0xFF, 0x80, 0x60)
}

@(test)
test_dec_r8_borrows_from_bit_four_and_clears_stale_zero :: proc(t: ^testing.T) {
	expect_dec_r8(t, 0x05, .B, 0x10, 0x0F, 0x90, 0x70)
}

@(test)
test_dec_r8_clears_stale_half_carry_and_lower_flag_nibble :: proc(t: ^testing.T) {
	expect_dec_r8(t, 0x05, .B, 0x02, 0x01, 0xAF, 0x40)
}

// --- ld r8, imm8 opcode tests ---

expect_ld_r8_imm8 :: proc(t: ^testing.T, opcode: u8, reg: gb.R8, value: u8) {
	bus := make_test_bus([]u8{opcode, value})
	cpu := make_test_cpu()
	cpu.a = 0xA1
	cpu.b = 0xB2
	cpu.c = 0xC3
	cpu.d = 0xD4
	cpu.e = 0xE5
	cpu.h = 0xC1
	cpu.l = 0x20
	cpu.sp = 0xFEDC
	cpu.f = 0xB0
	gb.bus_write_byte(&bus, 0xC120, 0x6F)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD r8, imm8 opcode to succeed")
	testing.expect(
		t,
		get_r8_operand(&cpu, &bus, reg) == value,
		"Expected LD r8, imm8 to load its destination",
	)
	testing.expect(t, cpu.f == 0xB0, "Expected LD r8, imm8 to leave flags unchanged")
	testing.expect(t, cpu.pc == 0x0102, "Expected LD r8, imm8 to advance PC by 2")
	expected_cycles := 2
	if reg == .HL_INDIRECT {
		expected_cycles = 3
	}
	testing.expect(
		t,
		cycles == expected_cycles,
		"Expected LD r8, imm8 to use the destination-specific cycle count",
	)
	testing.expect(t, cpu.sp == 0xFEDC, "Expected LD r8, imm8 to leave SP unchanged")

	if reg != .A {
		testing.expect(t, cpu.a == 0xA1, "Expected LD r8, imm8 to leave A unchanged")
	}
	if reg != .B {
		testing.expect(t, cpu.b == 0xB2, "Expected LD r8, imm8 to leave B unchanged")
	}
	if reg != .C {
		testing.expect(t, cpu.c == 0xC3, "Expected LD r8, imm8 to leave C unchanged")
	}
	if reg != .D {
		testing.expect(t, cpu.d == 0xD4, "Expected LD r8, imm8 to leave D unchanged")
	}
	if reg != .E {
		testing.expect(t, cpu.e == 0xE5, "Expected LD r8, imm8 to leave E unchanged")
	}
	if reg != .H {
		testing.expect(t, cpu.h == 0xC1, "Expected LD r8, imm8 to leave H unchanged")
	}
	if reg != .L {
		testing.expect(t, cpu.l == 0x20, "Expected LD r8, imm8 to leave L unchanged")
	}
	if reg != .HL_INDIRECT {
		testing.expect(
			t,
			gb.bus_read_byte(&bus, 0xC120) == 0x6F,
			"Expected register LD r8, imm8 to leave memory unchanged",
		)
	}
}

@(test)
test_ld_r8_imm8_all_destinations :: proc(t: ^testing.T) {
	expect_ld_r8_imm8(t, 0x06, .B, 0x10)
	expect_ld_r8_imm8(t, 0x0E, .C, 0x21)
	expect_ld_r8_imm8(t, 0x16, .D, 0x32)
	expect_ld_r8_imm8(t, 0x1E, .E, 0x43)
	expect_ld_r8_imm8(t, 0x26, .H, 0x54)
	expect_ld_r8_imm8(t, 0x2E, .L, 0x65)
	expect_ld_r8_imm8(t, 0x36, .HL_INDIRECT, 0x76)
	expect_ld_r8_imm8(t, 0x3E, .A, 0x87)
}

@(test)
test_ld_r8_imm8_loads_byte_boundaries_and_preserves_clear_flags :: proc(t: ^testing.T) {
	expect_ld_r8_imm8(t, 0x06, .B, 0x00)
	expect_ld_r8_imm8(t, 0x3E, .A, 0xFF)
}

@(test)
test_ld_hl_indirect_imm8_writes_at_ffff_and_pc_wraps :: proc(t: ^testing.T) {
	bus: gb.Bus
	bus.memory[0xFFFE] = 0x36
	bus.memory[0xFFFF] = 0x5A
	cpu := make_test_cpu()
	cpu.pc = 0xFFFE
	cpu.h = 0xFF
	cpu.l = 0xFF
	cpu.f = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL], imm8 at the end of memory to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0x5A,
		"Expected LD [HL], imm8 to write at address FFFF",
	)
	testing.expect(
		t,
		gb.cpu_get_hl(&cpu) == 0xFFFF,
		"Expected LD [HL], imm8 to leave HL unchanged",
	)
	testing.expect(t, cpu.f == 0x10, "Expected LD [HL], imm8 to leave flags unchanged")
	testing.expect(t, cpu.pc == 0x0000, "Expected the two-byte instruction PC to wrap to 0000")
	testing.expect(t, cycles == 3, "Expected LD [HL], imm8 to take 3 cycles")
}

// --- accumulator rotate opcode tests ---

expect_accumulator_rotate :: proc(
	t: ^testing.T,
	opcode, initial_a, initial_flags, expected_a, expected_flags: u8,
) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.a = initial_a
	cpu.f = initial_flags
	cpu.b = 0x42
	cpu.sp = 0xCDEF

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected accumulator rotate opcode to succeed")
	testing.expect(t, cpu.a == expected_a, "Expected accumulator rotate to produce the correct A")
	testing.expect(t, cpu.f == expected_flags, "Expected accumulator rotate to set only C")
	testing.expect(t, cpu.pc == 0x0101, "Expected accumulator rotate to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected accumulator rotate to take 1 cycle")
	testing.expect(
		t,
		cpu.b == 0x42,
		"Expected accumulator rotate to leave other registers unchanged",
	)
	testing.expect(t, cpu.sp == 0xCDEF, "Expected accumulator rotate to leave SP unchanged")
}

@(test)
test_rlca_rotates_bit_seven_into_bit_zero_and_carry :: proc(t: ^testing.T) {
	expect_accumulator_rotate(t, 0x07, 0x85, 0xEF, 0x0B, 0x10)
	expect_accumulator_rotate(t, 0x07, 0x42, 0x1F, 0x84, 0x00)
}

@(test)
test_rrca_rotates_bit_zero_into_bit_seven_and_carry :: proc(t: ^testing.T) {
	expect_accumulator_rotate(t, 0x0F, 0x81, 0xEF, 0xC0, 0x10)
	expect_accumulator_rotate(t, 0x0F, 0x42, 0x1F, 0x21, 0x00)
}

@(test)
test_rla_rotates_through_both_carry_states :: proc(t: ^testing.T) {
	expect_accumulator_rotate(t, 0x17, 0x80, 0x0F, 0x00, 0x10)
	expect_accumulator_rotate(t, 0x17, 0x40, 0xFF, 0x81, 0x00)
}

@(test)
test_rra_rotates_through_both_carry_states :: proc(t: ^testing.T) {
	expect_accumulator_rotate(t, 0x1F, 0x01, 0x0F, 0x00, 0x10)
	expect_accumulator_rotate(t, 0x1F, 0x02, 0xFF, 0x81, 0x00)
}

// --- daa opcode tests ---

expect_daa :: proc(t: ^testing.T, initial_a, initial_flags, expected_a, expected_flags: u8) {
	bus := make_test_bus([]u8{0x27})
	cpu := make_test_cpu()
	cpu.a = initial_a
	cpu.f = initial_flags
	cpu.c = 0x55

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected DAA to succeed")
	testing.expect(t, cpu.a == expected_a, "Expected DAA to produce the correct packed BCD value")
	testing.expect(
		t,
		cpu.f == expected_flags,
		"Expected DAA to set Z and C, preserve N, and clear H",
	)
	testing.expect(t, cpu.pc == 0x0101, "Expected DAA to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected DAA to take 1 cycle")
	testing.expect(t, cpu.c == 0x55, "Expected DAA to leave other registers unchanged")
}

@(test)
test_daa_adjusts_addition_low_and_high_digits :: proc(t: ^testing.T) {
	expect_daa(t, 0x3C, 0x00, 0x42, 0x00)
	expect_daa(t, 0x32, 0x20, 0x38, 0x00)
	expect_daa(t, 0xA0, 0x00, 0x00, 0x90)
	expect_daa(t, 0x21, 0x10, 0x81, 0x10)
}

@(test)
test_daa_adjusts_subtraction_and_preserves_subtract_and_carry :: proc(t: ^testing.T) {
	expect_daa(t, 0x0F, 0x60, 0x09, 0x40)
	expect_daa(t, 0x73, 0x50, 0x13, 0x50)
	expect_daa(t, 0x66, 0x70, 0x00, 0xD0)
}

@(test)
test_daa_clears_stale_zero_half_carry_and_lower_flag_nibble :: proc(t: ^testing.T) {
	expect_daa(t, 0x12, 0xAF, 0x18, 0x00)
}

// --- accumulator flag opcode tests ---

expect_accumulator_flag_opcode :: proc(
	t: ^testing.T,
	opcode, initial_a, initial_flags, expected_a, expected_flags: u8,
) {
	bus := make_test_bus([]u8{opcode})
	cpu := make_test_cpu()
	cpu.a = initial_a
	cpu.f = initial_flags
	cpu.d = 0x77

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected accumulator flag opcode to succeed")
	testing.expect(
		t,
		cpu.a == expected_a,
		"Expected accumulator flag opcode to update A correctly",
	)
	testing.expect(
		t,
		cpu.f == expected_flags,
		"Expected accumulator flag opcode to update flags correctly",
	)
	testing.expect(t, cpu.pc == 0x0101, "Expected accumulator flag opcode to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected accumulator flag opcode to take 1 cycle")
	testing.expect(
		t,
		cpu.d == 0x77,
		"Expected accumulator flag opcode to leave other registers unchanged",
	)
}

@(test)
test_cpl_complements_a_sets_n_and_h_and_preserves_z_and_c :: proc(t: ^testing.T) {
	expect_accumulator_flag_opcode(t, 0x2F, 0x35, 0x9F, 0xCA, 0xF0)
	expect_accumulator_flag_opcode(t, 0x2F, 0xFF, 0x00, 0x00, 0x60)
}

@(test)
test_scf_sets_carry_clears_n_and_h_and_preserves_zero :: proc(t: ^testing.T) {
	expect_accumulator_flag_opcode(t, 0x37, 0x5A, 0xEF, 0x5A, 0x90)
	expect_accumulator_flag_opcode(t, 0x37, 0x5A, 0x00, 0x5A, 0x10)
}

@(test)
test_ccf_toggles_carry_clears_n_and_h_and_preserves_zero :: proc(t: ^testing.T) {
	expect_accumulator_flag_opcode(t, 0x3F, 0xA5, 0xFF, 0xA5, 0x80)
	expect_accumulator_flag_opcode(t, 0x3F, 0xA5, 0x8F, 0xA5, 0x90)
}

// --- jr opcode tests ---

expect_jr :: proc(t: ^testing.T, offset: u8, expected_pc: u16) {
	bus := make_test_bus([]u8{0x18, offset})
	cpu := make_test_cpu()
	cpu.a = 0x42
	cpu.sp = 0xCDEF
	cpu.f = 0xBF

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected JR imm8 to succeed")
	testing.expect(t, cpu.pc == expected_pc, "Expected JR imm8 to apply the signed offset")
	testing.expect(t, cycles == 3, "Expected JR imm8 to take 3 cycles")
	testing.expect(t, cpu.f == 0xBF, "Expected JR imm8 to leave flags unchanged")
	testing.expect(t, cpu.a == 0x42, "Expected JR imm8 to leave registers unchanged")
	testing.expect(t, cpu.sp == 0xCDEF, "Expected JR imm8 to leave SP unchanged")
}

@(test)
test_jr_applies_positive_zero_and_negative_offsets_from_end_of_instruction :: proc(t: ^testing.T) {
	expect_jr(t, 0x7F, 0x0181)
	expect_jr(t, 0x00, 0x0102)
	expect_jr(t, 0x80, 0x0082)
	expect_jr(t, 0xFE, 0x0100)
}

@(test)
test_jr_wraps_pc_across_both_ends_of_address_space :: proc(t: ^testing.T) {
	bus: gb.Bus
	bus.memory[0xFFFE] = 0x18
	bus.memory[0xFFFF] = 0x01
	cpu := make_test_cpu()
	cpu.pc = 0xFFFE
	cpu.f = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected forward wrapping JR to succeed")
	testing.expect(t, cpu.pc == 0x0001, "Expected JR to wrap forward through 0000")
	testing.expect(t, cpu.f == 0x10, "Expected wrapping JR to preserve flags")
	testing.expect(t, cycles == 3, "Expected wrapping JR to take 3 cycles")

	bus.memory[0x0000] = 0x18
	bus.memory[0x0001] = 0xFD
	cpu.pc = 0x0000
	cpu.f = 0xE0

	cycles, ok = gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected backward wrapping JR to succeed")
	testing.expect(t, cpu.pc == 0xFFFF, "Expected JR to wrap backward through FFFF")
	testing.expect(t, cpu.f == 0xE0, "Expected backward wrapping JR to preserve flags")
	testing.expect(t, cycles == 3, "Expected backward wrapping JR to take 3 cycles")
}

// --- jr conditional opcode tests ---

expect_jr_condition :: proc(t: ^testing.T, opcode, initial_flags: u8, should_jump: bool) {
	bus := make_test_bus([]u8{opcode, 0x05})
	cpu := make_test_cpu()
	cpu.a = 0x6A
	cpu.sp = 0xBEEF
	cpu.f = initial_flags

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	expected_pc := u16(0x0102)
	expected_cycles := 2
	if should_jump {
		expected_pc = 0x0107
		expected_cycles = 3
	}

	testing.expect(t, ok, "Expected conditional JR to succeed")
	testing.expect(t, cpu.pc == expected_pc, "Expected conditional JR to select the correct PC")
	testing.expect(
		t,
		cycles == expected_cycles,
		"Expected conditional JR timing to depend on whether the branch is taken",
	)
	testing.expect(t, cpu.f == initial_flags, "Expected conditional JR to preserve all flags")
	testing.expect(t, cpu.a == 0x6A, "Expected conditional JR to leave registers unchanged")
	testing.expect(t, cpu.sp == 0xBEEF, "Expected conditional JR to leave SP unchanged")
}

@(test)
test_jr_conditions_branch_for_both_flag_states :: proc(t: ^testing.T) {
	expect_jr_condition(t, 0x20, 0x0F, true) // JR NZ with Z clear.
	expect_jr_condition(t, 0x20, 0x8F, false) // JR NZ with Z set.
	expect_jr_condition(t, 0x28, 0x8F, true) // JR Z with Z set.
	expect_jr_condition(t, 0x28, 0x0F, false) // JR Z with Z clear.
	expect_jr_condition(t, 0x30, 0x8F, true) // JR NC with C clear.
	expect_jr_condition(t, 0x30, 0x9F, false) // JR NC with C set.
	expect_jr_condition(t, 0x38, 0x9F, true) // JR C with C set.
	expect_jr_condition(t, 0x38, 0x8F, false) // JR C with C clear.
}

@(test)
test_jr_condition_fetches_negative_offset_when_not_taken :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x28, 0x80})
	cpu := make_test_cpu()
	cpu.f = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected untaken JR Z to succeed")
	testing.expect(t, cpu.pc == 0x0102, "Expected untaken JR Z to skip its offset byte")
	testing.expect(t, cpu.f == 0x10, "Expected untaken JR Z to preserve flags")
	testing.expect(t, cycles == 2, "Expected untaken JR Z to take 2 cycles")
}

// --- stop opcode tests ---

@(test)
test_stop_consumes_padding_byte_and_enters_stopped_state :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x10, 0x00, 0x00})
	cpu := make_test_cpu()
	cpu.a = 0x35
	cpu.sp = 0xCAFE
	cpu.f = 0xAF

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected STOP to succeed")
	testing.expect(t, cycles == 1, "Expected STOP to take 1 cycle")
	testing.expect(t, cpu.pc == 0x0102, "Expected STOP to consume its padding byte")
	testing.expect(t, cpu.stopped, "Expected STOP to enter the stopped state")
	testing.expect(t, cpu.f == 0xAF, "Expected STOP to leave flags unchanged")
	testing.expect(t, cpu.a == 0x35, "Expected STOP to leave registers unchanged")
	testing.expect(t, cpu.sp == 0xCAFE, "Expected STOP to leave SP unchanged")
}

@(test)
test_stopped_cpu_does_not_fetch_or_execute_next_instruction :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x10, 0x00, 0x3E, 0x99})
	cpu := make_test_cpu()
	cpu.a = 0x12
	cpu.f = 0xB0

	_, first_ok := gb.Cpu_step(&cpu, &bus)
	cycles, second_ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, first_ok, "Expected STOP to succeed")
	testing.expect(t, second_ok, "Expected a stopped CPU step to succeed")
	testing.expect(t, cycles == 0, "Expected a stopped CPU not to execute an instruction cycle")
	testing.expect(t, cpu.pc == 0x0102, "Expected a stopped CPU not to fetch the next opcode")
	testing.expect(t, cpu.a == 0x12, "Expected a stopped CPU not to execute the next opcode")
	testing.expect(t, cpu.f == 0xB0, "Expected a stopped CPU to preserve flags")
	testing.expect(t, cpu.stopped, "Expected the CPU to remain stopped without a wake event")
}

// --- ld r8, r8 opcode tests ---

@(test)
test_ld_r8_r8_copies_register_and_preserves_state :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x41}) // LD B, C
	cpu := make_test_cpu()
	cpu.a = 0xA1
	cpu.b = 0xB2
	cpu.c = 0xC3
	cpu.sp = 0xFEDC
	cpu.f = 0xAF

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD B, C to succeed")
	testing.expect(t, cpu.b == 0xC3, "Expected LD B, C to copy C into B")
	testing.expect(t, cpu.c == 0xC3, "Expected LD B, C to leave C unchanged")
	testing.expect(t, cpu.a == 0xA1, "Expected LD B, C to leave other registers unchanged")
	testing.expect(t, cpu.sp == 0xFEDC, "Expected LD B, C to leave SP unchanged")
	testing.expect(t, cpu.f == 0xAF, "Expected LD B, C to preserve the entire F register")
	testing.expect(t, cpu.pc == 0x0101, "Expected LD B, C to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected LD B, C to take 1 cycle")
}

@(test)
test_ld_r8_r8_decodes_high_register_codes :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x7C}) // LD A, H
	cpu := make_test_cpu()
	cpu.a = 0x19
	cpu.b = 0xB2
	cpu.h = 0xE7
	cpu.f = 0x10

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, H to succeed")
	testing.expect(t, cpu.a == 0xE7, "Expected LD A, H to copy H into A")
	testing.expect(t, cpu.h == 0xE7, "Expected LD A, H to leave H unchanged")
	testing.expect(t, cpu.b == 0xB2, "Expected LD A, H to leave B unchanged")
	testing.expect(t, cpu.f == 0x10, "Expected LD A, H to preserve flags")
	testing.expect(t, cpu.pc == 0x0101, "Expected LD A, H to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected LD A, H to take 1 cycle")
}

@(test)
test_ld_hl_indirect_r8_writes_memory_at_ffff :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x77}) // LD [HL], A
	cpu := make_test_cpu()
	cpu.a = 0x5A
	cpu.h = 0xFF
	cpu.l = 0xFF
	cpu.f = 0xB0
	gb.bus_write_byte(&bus, 0xFFFF, 0x16)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD [HL], A to succeed")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xFFFF) == 0x5A,
		"Expected LD [HL], A to write A at HL",
	)
	testing.expect(t, cpu.a == 0x5A, "Expected LD [HL], A to leave A unchanged")
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xFFFF, "Expected LD [HL], A to leave HL unchanged")
	testing.expect(t, cpu.f == 0xB0, "Expected LD [HL], A to preserve flags")
	testing.expect(t, cpu.pc == 0x0101, "Expected LD [HL], A to advance PC by 1")
	testing.expect(t, cycles == 2, "Expected LD [HL], A to take 2 cycles")
}

@(test)
test_ld_r8_hl_indirect_reads_memory :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x56}) // LD D, [HL]
	cpu := make_test_cpu()
	cpu.d = 0x21
	cpu.h = 0xC1
	cpu.l = 0x23
	cpu.f = 0x00
	gb.bus_write_byte(&bus, 0xC123, 0x9D)

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD D, [HL] to succeed")
	testing.expect(t, cpu.d == 0x9D, "Expected LD D, [HL] to read the byte at HL")
	testing.expect(
		t,
		gb.bus_read_byte(&bus, 0xC123) == 0x9D,
		"Expected LD D, [HL] to leave memory unchanged",
	)
	testing.expect(t, gb.cpu_get_hl(&cpu) == 0xC123, "Expected LD D, [HL] to leave HL unchanged")
	testing.expect(t, cpu.f == 0x00, "Expected LD D, [HL] to preserve clear flags")
	testing.expect(t, cpu.pc == 0x0101, "Expected LD D, [HL] to advance PC by 1")
	testing.expect(t, cycles == 2, "Expected LD D, [HL] to take 2 cycles")
}

@(test)
test_ld_r8_r8_self_load_leaves_register_unchanged :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x7F}) // LD A, A
	cpu := make_test_cpu()
	cpu.a = 0xE4
	cpu.f = 0xF0

	cycles, ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, ok, "Expected LD A, A to succeed")
	testing.expect(t, cpu.a == 0xE4, "Expected LD A, A to leave A unchanged")
	testing.expect(t, cpu.f == 0xF0, "Expected LD A, A to preserve flags")
	testing.expect(t, cpu.pc == 0x0101, "Expected LD A, A to advance PC by 1")
	testing.expect(t, cycles == 1, "Expected LD A, A to take 1 cycle")
}

@(test)
test_halt_opcode_enters_halted_state_without_executing_next_opcode :: proc(t: ^testing.T) {
	bus := make_test_bus([]u8{0x76, 0x41}) // HALT; LD B, C
	cpu := make_test_cpu()
	cpu.b = 0x12
	cpu.c = 0x34
	cpu.f = 0x90

	first_cycles, first_ok := gb.Cpu_step(&cpu, &bus)
	second_cycles, second_ok := gb.Cpu_step(&cpu, &bus)

	testing.expect(t, first_ok, "Expected HALT to succeed")
	testing.expect(t, second_ok, "Expected a halted CPU step to succeed")
	testing.expect(t, cpu.halted, "Expected opcode 76 to enter the halted state")
	testing.expect(t, cpu.pc == 0x0101, "Expected a halted CPU not to fetch the next opcode")
	testing.expect(t, cpu.b == 0x12, "Expected a halted CPU not to execute the next opcode")
	testing.expect(t, cpu.c == 0x34, "Expected HALT to leave registers unchanged")
	testing.expect(t, cpu.f == 0x90, "Expected HALT to preserve flags")
	testing.expect(t, first_cycles == 1, "Expected HALT to take 1 cycle")
	testing.expect(t, second_cycles == 1, "Expected a halted CPU step to consume 1 cycle")
}
