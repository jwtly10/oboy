package gb_tests

import "../../src/gb"
import "core:testing"

// --- Internal CPU getters tests ---

@(test)
test_fetch_u16_little_endian :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0x50, 0x01 })
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

// --- Opcode instruction state test ---

@(test)
test_nop :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0x00 })
    cpu := make_test_cpu()

    _, ok := gb.Cpu_step(&cpu, &bus)
    testing.expect(t, ok, "Expected NOP to not error")
    testing.expect(t, cpu.pc == 0x0101, "Expected to bump PC to bump to 0x0101")
}

@(test)
test_jp_a16 :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xC3, 0x50, 0x01 })
    cpu := make_test_cpu()

    cpu.f = 0xB0 // some arbitrary flag state to confirm JP does not change flags

    cycles, ok := gb.Cpu_step(&cpu, &bus)

    testing.expect(t, ok, "Expected JP a16 to succeed")
    testing.expect(t, cpu.pc == 0x0150, "Expected PC to jump to 0x0150")
    testing.expect(t, cpu.f == 0xB0, "Expected flags to remain unchanged")
    testing.expect(t, cycles == 4, "Expected JP a16 to take 4 cycles")
}

@(test)
test_cp_d8_equal_sets_zero_and_subtract :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x42 })
    cpu := make_test_cpu()
    cpu.a = 0x42

    cycles, ok := gb.Cpu_step(&cpu, &bus)

    // 66 - 66 = 0, so Z is set.
    // CP is a subtraction operation, so N is always set.
    // The lower nibble is 2 - 2, so no half-borrow is needed and H is clear.
    // 66 is not less than 66, so no full borrow is needed and C is clear.
    // Flags: Z=1, N=1, H=0, C=0 -> 1100_0000 -> 0xC0.
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x42, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0xC0, "Expected Z=1, N=1, H=0, C=0")
}

@(test)
test_cp_d8_sets_half_carry :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x01 })
    cpu := make_test_cpu()
    cpu.a = 0x10

    cycles, ok := gb.Cpu_step(&cpu, &bus)

    // 16 - 1 = 15, so the result is not zero and Z is clear.
    // CP is a subtraction operation, so N is set.
    // The lower nibble must calculate 0 - 1, so it borrows from bit 4 and H is set.
    // 16 is greater than 1, so no full 8-bit borrow is needed and C is clear.
    // Flags: Z=0, N=1, H=1, C=0 -> 0110_0000 -> 0x60.
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x10, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0x60, "Expected Z=0, N=1, H=1, C=0")
}

@(test)
test_cp_d8_sets_carry_and_half_carry :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x05 })
    cpu := make_test_cpu()
    cpu.a = 0x03

    cycles, ok := gb.Cpu_step(&cpu, &bus)

    // 3 - 5 is not zero, so Z is clear.
    // CP is a subtraction operation, so N is set.
    // The lower nibble must calculate 3 - 5, so a half-borrow is needed and H is set.
    // 3 is less than 5, so a full 8-bit borrow is needed and C is set.
    // Flags: Z=0, N=1, H=1, C=1 -> 0111_0000 -> 0x70.
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x03, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0x70, "Expected Z=0, N=1, H=1, C=1")
}

@(test)
test_cp_d8_sets_carry_without_half_carry :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x20 })
    cpu := make_test_cpu()
    cpu.a = 0x10

    cycles, ok := gb.Cpu_step(&cpu, &bus)

    // 16 - 32 is not zero, so Z is clear.
    // CP is a subtraction operation, so N is set.
    // The lower nibbles calculate 0 - 0, so no half-borrow is needed and H is clear.
    // 16 is less than 32, so a full 8-bit borrow is needed and C is set.
    // Flags: Z=0, N=1, H=0, C=1 -> 0101_0000 -> 0x50.
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x10, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0x50, "Expected Z=0, N=1, H=0, C=1")
}

@(test)
test_cp_d8_clears_previous_flags :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x01 })
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
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x02, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0x40, "Expected Z=0, N=1, H=0, C=0")
}

@(test)
test_cp_d8_keeps_lower_flag_nibble_zero :: proc(t: ^testing.T) {
    bus := make_test_bus([]u8{ 0xFE, 0x00 })
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
    testing.expect(t, ok, "Expected CP d8 to succeed")
    testing.expect(t, cycles == 2, "Expected CP d8 to take 2 cycles")
    testing.expect(t, cpu.pc == 0x0102, "Expected PC to advance by 2")
    testing.expect(t, cpu.a == 0x01, "Expected CP to leave A unchanged")
    testing.expect(t, cpu.f == 0x40, "Expected lower four bits of F to be zero")
}