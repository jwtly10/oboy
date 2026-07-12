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
	a:       u8,
	b:       u8,
	c:       u8,
	d:       u8,
	e:       u8,
	f:       u8,
	h:       u8,
	l:       u8,
	sp:      u16,
	pc:      u16,
	stopped: bool,
	halted:  bool,
	trace:   bool,
	ime:     bool,
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
	if (cpu.stopped) {
		// No CPU cycles consumed
		return 0, true
	}

	if (cpu.halted) {
		// Consume cycle, but no instruction execution
		return 1, true
	}

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
	case 0xC2, 0xCA, 0xD2, 0xDA:
		// jp cond, imm16
		address := cpu_fetch_u16(cpu, bus)
		if cpu_condition_met(cpu, (opcode >> 3) & 0b11) {
			cpu.pc = address
			cycles = 4
		} else {
			cycles = 3
		}
		ok = true
	case 0xE9:
		// jp hl
		cpu.pc = cpu_get_hl(cpu)
		cycles = 1
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
		dest := R8((opcode >> 3) & 0b111)
		value := cpu_read_r8(cpu, bus, dest)
		result := cpu_inc_r8(cpu, value)
		cpu_write_r8(cpu, bus, dest, result)

		cycles = 1
		if dest == .HL_INDIRECT {
			cycles = 3
		}
		ok = true
	case 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D:
		// dec r8
		dest := R8((opcode >> 3) & 0b111)
		value := cpu_read_r8(cpu, bus, dest)
		value = cpu_dec_r8(cpu, value)
		cpu_write_r8(cpu, bus, dest, value)

		cycles = 1
		if dest == .HL_INDIRECT {
			cycles = 3
		}
		ok = true
	case 0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E:
		// ld r8, imm8
		dest := R8((opcode >> 3) & 0b111)
		value := cpu_fetch_u8(cpu, bus)
		cpu_write_r8(cpu, bus, dest, value)

		cycles = 2
		if dest == .HL_INDIRECT {
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
	case 0x07:
		// rlca
		cpu_rlca(cpu)
		cycles = 1
		ok = true
	case 0x0F:
		// rrca
		cpu_rrca(cpu)
		cycles = 1
		ok = true
	case 0x17:
		// rla
		cpu_rla(cpu)
		cycles = 1
		ok = true
	case 0x1F:
		// rra
		cpu_rra(cpu)
		cycles = 1
		ok = true
	case 0x27:
		// daa
		cpu_daa(cpu)
		cycles = 1
		ok = true
	case 0x2F:
		// cpl
		cpu_cpl(cpu)
		cycles = 1
		ok = true
	case 0x37:
		// scf
		cpu_scf(cpu)
		cycles = 1
		ok = true
	case 0x3F:
		// ccf
		cpu_ccf(cpu)
		cycles = 1
		ok = true
	case 0x18:
		// jr imm8
		offset := i8(cpu_fetch_u8(cpu, bus))
		cpu.pc = u16(i32(cpu.pc) + i32(offset))
		cycles = 3
		ok = true
	case 0x20, 0x28, 0x30, 0x38:
		// jr cond, imm8
		condition := (opcode >> 3) & 0b11
		offset := i8(cpu_fetch_u8(cpu, bus))

		if cpu_condition_met(cpu, condition) {
			cpu.pc = u16(i32(cpu.pc) + i32(offset))
			cycles = 3
		} else {
			cycles = 2
		}

		ok = true
	case 0x10:
		// stop
		// TODO: https://gist.github.com/SonoSooS/c0055300670d678b5ae8433e20bea595#nop-and-stop may not always be ignored
		_ = cpu_fetch_u8(cpu, bus)
		cpu.stopped = true
		cycles = 1
		ok = true
	case 0x40 ..= 0x7F:
		// ld r8, r8
		cycles = 1
		if opcode == 0x76 {
			// LD HL, HL Exception
			cpu.halted = true
			cycles = 1
			ok = true
			break
		}

		//dest bits 5-4-3
		dest := R8((opcode >> 3) & 0b111)
		// src bits 2-1-0
		src := R8((opcode) & 0b111)

		value := cpu_read_r8(cpu, bus, src)
		cpu_write_r8(cpu, bus, dest, value)

		cycles = 1
		if dest == .HL_INDIRECT || src == .HL_INDIRECT {
			cycles = 2
		}

		ok = true
	case 0x80 ..= 0xBF:
		operation := (opcode >> 3) & 0b111
		src := R8(opcode & 0b111)
		value := cpu_read_r8(cpu, bus, src)

		cpu_execute_alu(cpu, operation, value)

		cycles = 1
		if src == .HL_INDIRECT {
			cycles = 2
		}

		ok = true
	case 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE:
		operation := (opcode >> 3) & 0b111
		value := cpu_fetch_u8(cpu, bus)

		cpu_execute_alu(cpu, operation, value)

		cycles = 2
		ok = true
	case 0xC0, 0xC8, 0xD0, 0xD8:
		// ret cond
		if cpu_condition_met(cpu, (opcode >> 3) & 0b11) {
			cpu.pc = cpu_pop_u16(cpu, bus)
			cycles = 5
		} else {
			cycles = 2
		}

		ok = true
	case 0xC9:
		// ret
		cpu.pc = cpu_pop_u16(cpu, bus)
		cycles = 4
		ok = true
	case 0xD9:
		// reti
		cpu.pc = cpu_pop_u16(cpu, bus)
		cpu.ime = true
		cycles = 4
		ok = true
	case 0xC4, 0xCC, 0xD4, 0xDC:
		// call cond, imm16
		address := cpu_fetch_u16(cpu, bus)
		if cpu_condition_met(cpu, (opcode >> 3) & 0b11) {
			cpu_push_u16(cpu, bus, cpu.pc)
			cpu.pc = address
			cycles = 6
		} else {
			cycles = 3
		}
		ok = true
	case 0xCD:
		// call imm16
		address := cpu_fetch_u16(cpu, bus)
		cpu_push_u16(cpu, bus, cpu.pc)
		cpu.pc = address
		cycles = 6
		ok = true
	case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF:
		// rst tgt3
		cpu_push_u16(cpu, bus, cpu.pc)
		cpu.pc = u16(opcode & 0x38)
		cycles = 4
		ok = true
	case 0xC1:
		// POP BC
		cpu_set_r16(cpu, .BC, cpu_pop_u16(cpu, bus))
		cycles = 3
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

cpu_rlca :: proc(cpu: ^Cpu) {
	carry := (cpu.a & 0x80) != 0
	cpu.a = (cpu.a << 1) | (cpu.a >> 7)
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_C, carry)
}

cpu_rrca :: proc(cpu: ^Cpu) {
	carry := (cpu.a & 0x01) != 0
	cpu.a = (cpu.a >> 1) | (cpu.a << 7)
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_C, carry)
}

cpu_rla :: proc(cpu: ^Cpu) {
	old_carry := u8(0)
	if (cpu.f & FLAG_C) != 0 {
		old_carry = 1
	}
	carry := (cpu.a & 0x80) != 0
	cpu.a = (cpu.a << 1) | old_carry
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_C, carry)
}

cpu_rra :: proc(cpu: ^Cpu) {
	old_carry := u8(0)
	if (cpu.f & FLAG_C) != 0 {
		old_carry = 0x80
	}
	carry := (cpu.a & 0x01) != 0
	cpu.a = (cpu.a >> 1) | old_carry
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_C, carry)
}

cpu_daa :: proc(cpu: ^Cpu) {
	adjust := u8(0)
	carry := (cpu.f & FLAG_C) != 0

	if (cpu.f & FLAG_N) == 0 {
		if carry || cpu.a > 0x99 {
			adjust |= 0x60
			carry = true
		}
		if (cpu.f & FLAG_H) != 0 || (cpu.a & 0x0F) > 0x09 {
			adjust |= 0x06
		}
		cpu.a += adjust
	} else {
		if carry {
			adjust |= 0x60
		}
		if (cpu.f & FLAG_H) != 0 {
			adjust |= 0x06
		}
		cpu.a -= adjust
	}

	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
	cpu_set_flag(cpu, FLAG_H, false)
	cpu_set_flag(cpu, FLAG_C, carry)
}

cpu_cpl :: proc(cpu: ^Cpu) {
	cpu.a = ~cpu.a
	cpu_set_flag(cpu, FLAG_N, true)
	cpu_set_flag(cpu, FLAG_H, true)
}

cpu_scf :: proc(cpu: ^Cpu) {
	cpu_set_flag(cpu, FLAG_N, false)
	cpu_set_flag(cpu, FLAG_H, false)
	cpu_set_flag(cpu, FLAG_C, true)
}

cpu_ccf :: proc(cpu: ^Cpu) {
	carry := (cpu.f & FLAG_C) == 0
	cpu_set_flag(cpu, FLAG_N, false)
	cpu_set_flag(cpu, FLAG_H, false)
	cpu_set_flag(cpu, FLAG_C, carry)
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

cpu_read_r8 :: proc(cpu: ^Cpu, bus: ^Bus, dest: R8) -> u8 {
	switch dest {
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

cpu_write_r8 :: proc(cpu: ^Cpu, bus: ^Bus, dest: R8, value: u8) {
	switch dest {
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

// Increments by 1, and sets flags
cpu_inc_r8 :: proc(cpu: ^Cpu, value: u8) -> u8 {
	result := value + 1

	cpu_set_flag(cpu, FLAG_Z, result == 0)
	cpu_set_flag(cpu, FLAG_N, false)
	cpu_set_flag(cpu, FLAG_H, (value & 0x0F) == 0x0F)
	// C is unchanged.

	return result
}

// Decrements by 1 and sets flags
cpu_dec_r8 :: proc(cpu: ^Cpu, value: u8) -> u8 {
	result := value - 1

	cpu_set_flag(cpu, FLAG_Z, result == 0)
	cpu_set_flag(cpu, FLAG_N, true)
	cpu_set_flag(cpu, FLAG_H, (value & 0x0F) == 0x00)
	// C is unchanged.

	return result
}

// Increments the contents of register pair R16 by 1.
cpu_inc_r16 :: proc(cpu: ^Cpu, dest: R16) {
	switch dest {
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
cpu_dec_r16 :: proc(cpu: ^Cpu, dest: R16) {
	switch dest {
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
cpu_add_hl_r16 :: proc(cpu: ^Cpu, dest: R16) {
	hl := cpu_get_hl(cpu)
	value: u16

	switch dest {
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
cpu_set_r16 :: proc(cpu: ^Cpu, dest: R16, value: u16) {
	switch dest {
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
cpu_ld_r16mem_a :: proc(cpu: ^Cpu, bus: ^Bus, dest: R16_mem) {
	switch dest {
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
cpu_ld_a_r16mem :: proc(cpu: ^Cpu, bus: ^Bus, dest: R16_mem) {
	switch dest {
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

cpu_execute_alu :: proc(cpu: ^Cpu, operation: u8, value: u8) {
	switch operation {
	case 0:
		// add a, r8
		cpu_add_a(cpu, value)
	case 1:
		// adc a, r8
		cpu_adc_a(cpu, value)
	case 2:
		// sub a, r8
		cpu_sub_a(cpu, value)
	case 3:
		// sbc a, r8
		cpu_sbc_a(cpu, value)
	case 4:
		// and a, r8
		cpu_and_a(cpu, value)
	case 5:
		// xor a, r8
		cpu_xor_a(cpu, value)
	case 6:
		// or a, r8
		cpu_or_a(cpu, value)
	case 7:
		// cp a, r8
		cpu_cp_a(cpu, value)
	}
}

cpu_add_a :: proc(cpu: ^Cpu, value: u8) {
	a := cpu.a
	result := u16(a) + u16(value)
	cpu.a = u8(result)

	cpu.f = 0
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
	cpu_set_flag(cpu, FLAG_H, u16(a & 0x0F) + u16(value & 0x0F) > 0x0F)
	cpu_set_flag(cpu, FLAG_C, result > 0xFF)
}

cpu_adc_a :: proc(cpu: ^Cpu, value: u8) {
	a := cpu.a
	carry := u16(0)
	if (cpu.f & FLAG_C) != 0 {
		carry = 1
	}
	result := u16(a) + u16(value) + carry
	cpu.a = u8(result)

	cpu.f = 0
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
	cpu_set_flag(cpu, FLAG_H, u16(a & 0x0F) + u16(value & 0x0F) + carry > 0x0F)
	cpu_set_flag(cpu, FLAG_C, result > 0xFF)
}

cpu_sub_a :: proc(cpu: ^Cpu, value: u8) {
	a := cpu.a
	cpu.a = a - value

	cpu.f = FLAG_N
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
	cpu_set_flag(cpu, FLAG_H, (a & 0x0F) < (value & 0x0F))
	cpu_set_flag(cpu, FLAG_C, a < value)
}

cpu_sbc_a :: proc(cpu: ^Cpu, value: u8) {
	a := cpu.a
	carry := u16(0)
	if (cpu.f & FLAG_C) != 0 {
		carry = 1
	}
	subtrahend := u16(value) + carry
	cpu.a = u8(u16(a) - subtrahend)

	cpu.f = FLAG_N
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
	cpu_set_flag(cpu, FLAG_H, u16(a & 0x0F) < u16(value & 0x0F) + carry)
	cpu_set_flag(cpu, FLAG_C, u16(a) < subtrahend)
}

cpu_and_a :: proc(cpu: ^Cpu, value: u8) {
	cpu.a = cpu.a & value
	cpu.f = FLAG_H
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
}

cpu_xor_a :: proc(cpu: ^Cpu, value: u8) {
	cpu.a = cpu.a ~ value
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
}

cpu_or_a :: proc(cpu: ^Cpu, value: u8) {
	cpu.a = cpu.a | value
	cpu.f = 0
	cpu_set_flag(cpu, FLAG_Z, cpu.a == 0)
}

cpu_cp_a :: proc(cpu: ^Cpu, value: u8) {
	a := cpu.a
	cpu.f = FLAG_N
	cpu_set_flag(cpu, FLAG_Z, a == value)
	cpu_set_flag(cpu, FLAG_H, (a & 0x0F) < (value & 0x0F))
	cpu_set_flag(cpu, FLAG_C, a < value)
}

// The contents of the address specified by the stack pointer SP are loaded in the lower-order byte of PC,
// and the contents of SP are incremented by 1. The contents of the address specified by the new SP value
// are then loaded in the higher-order byte of PC, and the contents of SP are incremented by 1 again.
// (The value of SP is 2 larger than before instruction execution.) The next instruction is fetched from
// the address specified by the content of PC (as usual).
cpu_pop_u16 :: proc(cpu: ^Cpu, bus: ^Bus) -> u16 {
	low := u16(bus_read_byte(bus, cpu.sp))
	cpu.sp += 1

	high := u16(bus_read_byte(bus, cpu.sp))
	cpu.sp += 1

	return (high << 8) | low
}

cpu_push_u16 :: proc(cpu: ^Cpu, bus: ^Bus, value: u16) {
	cpu.sp -= 1
	bus_write_byte(bus, cpu.sp, u8(value >> 8))
	cpu.sp -= 1
	bus_write_byte(bus, cpu.sp, u8(value))
}

cpu_condition_met :: proc(cpu: ^Cpu, condition: u8) -> bool {
	switch condition {
	case 0:
		return (cpu.f & FLAG_Z) == 0 // NZ
	case 1:
		return (cpu.f & FLAG_Z) != 0 // Z
	case 2:
		return (cpu.f & FLAG_C) == 0 // NC
	case 3:
		return (cpu.f & FLAG_C) != 0 // C
	}

	unreachable()
}
