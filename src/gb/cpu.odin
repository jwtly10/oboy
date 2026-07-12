package gb

import "core:fmt"

@(private)
FLAG_Z :: u8(1 << 7) // Zero flag
FLAG_N :: u8(1 << 6) // Subtraction Flag (BCD)
FLAG_H :: u8(1 << 5) // Half Carry flag (BCD)
FLAG_C :: u8(1 << 4) // Carry flag

// https://gbdev.io/pandocs/CPU_Instruction_Set.html#cpu-instruction-set
Cpu :: struct {
	// The r8 registers
	a:     u8,
	b:     u8,
	c:     u8,
	d:     u8,
	e:     u8,
	f:     u8,
	h:     u8,
	l:     u8,
	sp:    u16,
	pc:    u16,
	trace: bool,
}

R8 :: enum {
	B,
	C,
	D,
	E,
	H,
	L,
	HL_INDIRECT,
	A,
}

R16 :: enum {
	BC,
	DE,
	HL,
	SP,
}

R16_mem :: enum {
	BC,
	DE,
	HLI, // HL+
	HLD, // HL-
}

R16_stk :: enum {
	BC,
	DE,
	HL,
	AF,
}

Cpu_init :: proc() -> Cpu {
	return Cpu{pc = 0x0100}
}

Cpu_step :: proc(cpu: ^Cpu, bus: ^Bus) -> (cycles: int, ok: bool) {
	instruction_address := cpu.pc
	opcode := cpu_fetch_u8(cpu, bus)

	switch opcode {
	case 0x00:
		// nop
		cycles = 1
		ok = true
	case 0xC3:
		// jp imm16
		address := cpu_fetch_u16(cpu, bus)
		cpu.pc = address
		cycles = 4
		ok = true
	case 0xFE:
		// cp a, imm8
		cpu_cp_a_imm8(cpu, cpu_fetch_u8(cpu, bus))
		cycles = 2
		ok = true
	case 0x01, 0x11, 0x21, 0x31:
		// ld r16, imm16
		value := cpu_fetch_u16(cpu, bus)
		// pulling the index of the r16 opcode where 5/4 are the fixed dest bits
		// we move to pos - 1 - 0 so we can create index
		// eg. ....0001 (0x01) >> 4 = ....0000 & ....0011 == 0b00 (index 0)
		//     00110001 (0x31) >> 4 = 00000011 & 0b11 == 0b3 (index 3)
		dest := R16((opcode >> 4) & 0b11)
		cpu_set_r16(cpu, dest, value)
		cycles = 3
		ok = true
	case 0x02, 0x12, 0x22, 0x32:
		// ld [r16mem], a
		dest := R16_mem((opcode >> 4) & 0b11)
		cpu_ld_r16mem_a(cpu, bus, dest)
		cycles = 2
		ok = true
	case 0x03, 0x13, 0x23, 0x33:
		// inc r16
		dest := R16((opcode >> 4) & 0b11)
		cpu_inc_r16(cpu, dest)
		cycles = 2
		ok = true
	case 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C:
		// inc r8
		r_idx := R8((opcode >> 3) & 0b111)
		value := cpu_read_r8(cpu, bus, r_idx)
		value = cpu_inc_r8(cpu, value)
		cpu_write_r8(cpu, bus, r_idx, value)

		cycles = 1
		if r_idx == .HL_INDIRECT {
			cycles = 3
		}
		ok = true
	case 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D:
		// dec r8
		r_idx := R8((opcode >> 3) & 0b111)
		value := cpu_read_r8(cpu, bus, r_idx)
		value = cpu_dec_r8(cpu, value)
		cpu_write_r8(cpu, bus, r_idx, value)

		cycles = 1
		if r_idx == .HL_INDIRECT {
			cycles = 3
		}
		ok = true
	case 0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E:
		// ld r8, imm8
		r_idx := R8((opcode >> 3) & 0b111)
		value := cpu_fetch_u8(cpu, bus)
		cpu_write_r8(cpu, bus, r_idx, value)

		cycles = 2
		if r_idx == .HL_INDIRECT {
			cycles = 3
		}
		ok = true
	case 0x0B, 0x1B, 0x2B, 0x3B:
		// dec r16
		dest := R16((opcode >> 4) & 0b11)
		cpu_dec_r16(cpu, dest)
		cycles = 2
		ok = true
	case 0x0A, 0x1A, 0x2A, 0x3A:
		// ld a, [r16mem]
		dest := R16_mem((opcode >> 4) & 0b11)
		cpu_ld_a_r16mem(cpu, bus, dest)
		cycles = 2
		ok = true
	case 0x08:
		// ld [imm16], sp
		address := cpu_fetch_u16(cpu, bus)
		bus_write_u16(bus, address, cpu.sp)
		cycles = 5
		ok = true
	case 0x09, 0x19, 0x29, 0x39:
		// add hl, r16
		dest := R16((opcode >> 4) & 0b11)
		cpu_add_hl_r16(cpu, dest)
		cycles = 2
		ok = true
	case:
		fmt.printf("Unimplemented opcode 0x%02X at 0x%04X\n", opcode, instruction_address)
		cycles = 0
		ok = false
	}

	if cpu.trace {
		cpu_dbg_state(cpu, instruction_address, opcode)
	}

	return cycles, ok
}

cpu_cp_a_imm8 :: proc(cpu: ^Cpu, value: u8) {
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

cpu_read_r8 :: proc(cpu: ^Cpu, bus: ^Bus, r_idx: R8) -> u8 {
	switch r_idx {
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
		return bus_read_byte(bus, cpu_get_hl(cpu))
	case .A:
		return cpu.a
	}

	unreachable()
}

cpu_write_r8 :: proc(cpu: ^Cpu, bus: ^Bus, r_idx: R8, value: u8) {
	switch r_idx {
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
		bus_write_byte(bus, cpu_get_hl(cpu), value)
	case .A:
		cpu.a = value
	}
}

cpu_set_flag :: proc(cpu: ^Cpu, flag: u8, set: bool) {
	if set {
		cpu.f |= flag
	} else {
		cpu.f &= ~flag
	}

	// Ensures lower nibble is never set
	cpu.f &= 0xF0

}

cpu_dbg_state :: proc(cpu: ^Cpu, instruction_address: u16, opcode: u8) {
	fmt.printf(
		"PC=%04X OP=%02X A=%02X F=%02X BC=%04X DE=%04X HL=%04X SP=%04X\n",
		instruction_address,
		opcode,
		cpu.a,
		cpu.f,
		cpu_get_bc(cpu),
		cpu_get_de(cpu),
		cpu_get_hl(cpu),
		cpu.sp,
	)
}

cpu_get_bc :: proc(cpu: ^Cpu) -> u16 {
	return (u16(cpu.b) << 8) | u16(cpu.c)
}

cpu_get_de :: proc(cpu: ^Cpu) -> u16 {
	return (u16(cpu.d) << 8) | u16(cpu.e)
}

cpu_get_hl :: proc(cpu: ^Cpu) -> u16 {
	return (u16(cpu.h) << 8) | u16(cpu.l)
}

// Increments the contents of register R8 by 1.
cpu_inc_r8 :: proc(cpu: ^Cpu, value: u8) -> u8 {
	result := value + 1

	cpu_set_flag(cpu, FLAG_Z, result == 0)
	cpu_set_flag(cpu, FLAG_N, false)
	cpu_set_flag(cpu, FLAG_H, (value & 0x0F) == 0x0F)
	// C is unchanged.

	return result
}

// Decrements the contents of register R8 by 1.
cpu_dec_r8 :: proc(cpu: ^Cpu, value: u8) -> u8 {
	result := value - 1

	cpu_set_flag(cpu, FLAG_Z, result == 0)
	cpu_set_flag(cpu, FLAG_N, true)
	cpu_set_flag(cpu, FLAG_H, (value & 0x0F) == 0x00)
	// C is unchanged.

	return result
}

// Increments the contents of register pair R16 by 1.
cpu_inc_r16 :: proc(cpu: ^Cpu, r_idx: R16) {
	switch r_idx {
	case .BC:
		cpu_set_r16(cpu, .BC, cpu_get_bc(cpu) + 1)
	case .DE:
		cpu_set_r16(cpu, .DE, cpu_get_de(cpu) + 1)
	case .HL:
		cpu_set_r16(cpu, .HL, cpu_get_hl(cpu) + 1)
	case .SP:
		cpu_set_r16(cpu, .SP, cpu.sp + 1)
	}
}

// Decrements the contents of register pair R16 by 1.
cpu_dec_r16 :: proc(cpu: ^Cpu, r_idx: R16) {
	switch r_idx {
	case .BC:
		cpu_set_r16(cpu, .BC, cpu_get_bc(cpu) - 1)
	case .DE:
		cpu_set_r16(cpu, .DE, cpu_get_de(cpu) - 1)
	case .HL:
		cpu_set_r16(cpu, .HL, cpu_get_hl(cpu) - 1)
	case .SP:
		cpu_set_r16(cpu, .SP, cpu.sp - 1)
	}
}

// Adds the contents of register pair R16 to the contents of register pair HL,
// and store the results in register pair HL.
cpu_add_hl_r16 :: proc(cpu: ^Cpu, r_idx: R16) {
	hl := cpu_get_hl(cpu)
	value: u16

	switch r_idx {
	case .BC:
		value = cpu_get_bc(cpu)
	case .DE:
		value = cpu_get_de(cpu)
	case .HL:
		value = cpu_get_hl(cpu)
	case .SP:
		value = cpu.sp
	}

	// We need to track if the op carries, so cast to 32 before downcasting on store
	result := u32(hl) + u32(value)

	cpu_set_r16(cpu, .HL, u16(result))

	// Does not modify Z
	cpu_set_flag(cpu, FLAG_N, false) // is not sub
	cpu_set_flag(cpu, FLAG_H, (hl & 0x0FFF) + (value & 0x0FFF) > 0x0FFF) // carry from bit 11 intto 12
	cpu_set_flag(cpu, FLAG_C, result > 0xFFFF) // carry past bit 15
}

// Set R16 reg specified value
cpu_set_r16 :: proc(cpu: ^Cpu, r_idx: R16, value: u16) {
	switch r_idx {
	case .BC:
		cpu.b = u8((value >> 8)) // Shifts bits right to move hi > low & casts
		cpu.c = u8(value) // Cast takes the low byte
	case .DE:
		cpu.d = u8((value >> 8)) // Shifts bits right to move hi > low & casts
		cpu.e = u8(value) // Cast takes the low byte
	case .HL:
		cpu.h = u8((value >> 8)) // Shifts bits right to move hi > low & casts
		cpu.l = u8(value) // Cast takes the low byte
	case .SP:
		cpu.sp = value
	}
}

// Stores the contents of register A in the memory location specified by register pair R16_mem.
// If HL reg, increment or decrement.
cpu_ld_r16mem_a :: proc(cpu: ^Cpu, bus: ^Bus, r_idx: R16_mem) {
	switch r_idx {
	case .BC:
		bus_write_byte(bus, cpu_get_bc(cpu), cpu.a)
	case .DE:
		bus_write_byte(bus, cpu_get_de(cpu), cpu.a)
	case .HLI:
		address := cpu_get_hl(cpu)
		bus_write_byte(bus, address, cpu.a)
		cpu_set_r16(cpu, .HL, address + 1)
	case .HLD:
		address := cpu_get_hl(cpu)
		bus_write_byte(bus, address, cpu.a)
		cpu_set_r16(cpu, .HL, address - 1)
	}
}

// Loads the 8-bit contents of memory specified by register pair R16_mem into register A.
cpu_ld_a_r16mem :: proc(cpu: ^Cpu, bus: ^Bus, r_idx: R16_mem) {
	switch r_idx {
	case .BC:
		cpu.a = bus_read_byte(bus, cpu_get_bc(cpu))
	case .DE:
		cpu.a = bus_read_byte(bus, cpu_get_de(cpu))
	case .HLI:
		address := cpu_get_hl(cpu)
		cpu.a = bus_read_byte(bus, address)
		cpu_set_r16(cpu, .HL, address + 1)
	case .HLD:
		address := cpu_get_hl(cpu)
		cpu.a = bus_read_byte(bus, address)
		cpu_set_r16(cpu, .HL, address - 1)
	}
}

