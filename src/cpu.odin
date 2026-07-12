package main

import "core:fmt"

CPU :: struct {
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

cpu_init :: proc() -> CPU {
	return CPU{pc = 0x0100}
}

cpu_step :: proc(cpu: ^CPU, bus: ^Bus) -> bool {
	instruction_address := cpu.pc
	opcode := bus_read_byte(bus, instruction_address)

	cpu.pc += 1

	switch opcode {
	case 0x00:
		fmt.println("NOP")
		return true
	case:
		fmt.printf("Unimplemented opcode 0x%02X at 0x%04X\n", opcode, instruction_address)
		return false
	}
}
