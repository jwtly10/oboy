package gb

import "core:fmt"

@private
FLAG_Z:: u8(1 << 7) // Zero flag
FLAG_N:: u8(1 << 6) // Subtraction Flag (BCD)
FLAG_H:: u8(1 << 5) // Half Carry flag (BCD)
FLAG_C:: u8(1 << 4) // Carry flag

// https://gbdev.io/pandocs/CPU_Instruction_Set.html#cpu-instruction-set
Cpu :: struct {
	a:  u8,
	b:  u8,
	c:  u8,
	d:  u8,
	e:  u8,
	f:  u8,
	h:  u8,
	l:  u8,
	sp: u16,
	pc: u16,
}

R16 :: enum {
    BC,
    DE,
    HL,
    SP
}

R16_stk :: enum {
    BC,
    DE,
    HL,
    AF
}

Cpu_init :: proc() -> Cpu {
	return Cpu{pc = 0x0100}
}

Cpu_step :: proc(cpu: ^Cpu, bus: ^Bus) -> (int, bool) {
	instruction_address := cpu.pc
	opcode := cpu_fetch_u8(cpu, bus)
	switch opcode {
	case 0x00: // NOP
		fmt.println("NOP")
        cpu_dbg_state(cpu, opcode)
		return 1, true
    case 0xC3: // JP a16
        fmt.println("JP a16")
        address := cpu_fetch_u16(cpu, bus)
        cpu.pc = address
        cpu_dbg_state(cpu, opcode)
        return 4, true
    case 0xFE: // CP d8
        fmt.println("CP d8")
        cpu_cp(cpu, cpu_fetch_u8(cpu, bus))
        cpu_dbg_state(cpu, opcode)
        return 2, true
	case:
		fmt.printf("Unimplemented opcode 0x%02X at 0x%04X\n", opcode, instruction_address)
		return 0, false
	}
}

cpu_cp :: proc(cpu: ^Cpu, value: u8) {
    cpu_set_flag(cpu, FLAG_Z, cpu.a == value)
    cpu_set_flag(cpu, FLAG_N, true)
    cpu_set_flag(cpu, FLAG_C, cpu.a < value)
    cpu_set_flag(cpu, FLAG_H, (cpu.a & 0x0F) < (value & 0x0F))
}

cpu_fetch_u8 :: proc(cpu: ^Cpu, bus: ^Bus) -> u8 {
    value := bus_read_byte(bus, cpu.pc)
    cpu.pc += 1
    return value
}

cpu_fetch_u16 :: proc(cpu: ^Cpu, bus: ^Bus) -> u16 {
    low := u16(cpu_fetch_u8(cpu, bus))
    high := u16(cpu_fetch_u8(cpu, bus))
    return low | (high << 8)
}

cpu_set_flag::proc(cpu: ^Cpu, flag: u8, set: bool) {
    if set {
        cpu.f |= flag
    } else {
        cpu.f &= ~flag
    }

    // Ensures lower nibble is never set
    cpu.f &= 0xF0

}

cpu_dbg_state :: proc(cpu: ^Cpu, opcode: u8) {
    fmt.printf(
    "PC=%04X OP=%02X A=%02X F=%02X BC=%04X DE=%04X HL=%04X SP=%04X\n",
    cpu.pc,
    opcode,
    cpu.a,
    cpu.f,
    cpu_get_bc(cpu),
    cpu_get_de(cpu),
    cpu_get_hl(cpu),
    cpu.sp,
    )
}

cpu_get_bc ::proc (cpu: ^ Cpu) -> u16 {
    return u16(cpu.b) << 8 | u16(cpu.c)
}

cpu_get_de ::proc (cpu: ^ Cpu) -> u16 {
    return u16(cpu.d) << 8 | u16(cpu.e)
}

cpu_get_hl ::proc (cpu: ^ Cpu) -> u16 {
    return u16(cpu.h) << 8 | u16(cpu.l)
}
