package gb

import "core:fmt"

// https://gbdev.io/pandocs/Interrupts.html#ff0f--if-interrupt-flag
Interrupt :: enum u8 {
	VBLANK = 0,
	LCD    = 1,
	TIMER  = 2,
	SERIAL = 3,
	JOYPAD = 4,
}

Machine :: struct {
	cpu: Cpu,
	bus: Bus,
}

Machine_init :: proc(
	rom: []u8,
	header: ^ROM_Header,
	alloc := context.allocator,
) -> (
	Machine,
	bool,
) {
	bus, ok := Bus_init(rom, header, alloc)
	if (!ok) {
		fmt.println("Error initialising bus")
		return {}, false
	}

	return Machine{cpu = Cpu_init_post_boot(), bus = bus}, true
}

Machine_destroy :: proc(machine: ^Machine, alloc := context.allocator) {
	Bus_destroy(&machine.bus, alloc)
}

Machine_step :: proc(machine: ^Machine) -> bool {
	cpu := &machine.cpu
	bus := &machine.bus

	pending := interrupt_pending(bus)
	if (pending != 0) {
		// https://gbdev.io/pandocs/halt.html
		// Cpu wakes up if bitwise AND of IE and IF is non-zero
		cpu.halted = false
	}

	if (cpu.ime && pending != 0) {
		// Servicing an interrupt consumes 5 M-Cycles https://gbdev.io/pandocs/Interrupts.html#interrupt-handling
		cpu_service_interrupt(cpu, bus, pending)
		machine_tick(machine, 5)
		// We return and let CPU continue
		return true
	}

	cycles, ok := Cpu_step(cpu, bus)
	if !ok {
		return false
	}

	machine_tick(machine, cycles)
	return true
}

machine_tick :: proc(machine: ^Machine, m_cycles: int) {
	// We are tracking CPU op cycles in M Cycles
	// so when talking to timer we use T Cycles
	for _ in 0 ..< m_cycles * 4 {
		timer_tick(&machine.bus)
	}
}

// Checks IF register for interrupt
interrupt_pending :: proc(bus: ^Bus) -> u8 {
	iflags := bus_read_byte(bus, INTERRUPT_FLAG_ADDRESS)

	// Keep interupts that are
	// 1. requested in INTERRUPT_FLAG_ADDRESS
	// 2. enabled in IE
	// 3. valid interupt bits in pos 0-4
	return iflags & bus.ie & 0x1F
}

interrupt_request :: proc(bus: ^Bus, interrupt: Interrupt) {
	iflags := bus_read_byte(bus, INTERRUPT_FLAG_ADDRESS)
	iflags |= u8(1 << u8(interrupt))
	bus_write_byte(bus, INTERRUPT_FLAG_ADDRESS, iflags)
}

// https://gbdev.io/pandocs/Interrupts.html#interrupt-handling
//
// 1. The IF bit corresponding to this interrupt and the IME flag are reset by the CPU.
// The former “acknowledges” the interrupt, while the latter prevents any further interrupts
// from being handled until the program re-enables them, typically by using the reti instruction.
// 2. The corresponding interrupt handler (see the IE and IF register descriptions above) is called by the CPU.
// This is a regular call, exactly like what would be performed by a call <address> instruction
// (the current PC is pushed onto the stack and then set to the address of the interrupt handler).
// The following interrupt service routine is executed when control is being transferred to an interrupt handler:
//
// 1. Two wait states are executed (2 M-cycles pass while nothing happens; presumably the CPU is executing nops during this time).
// 2. The current value of the PC register is pushed onto the stack, consuming 2 more M-cycles.
// 3. The PC register is set to the address of the handler (one of: $40, $48, $50, $58, $60). This consumes one last M-cycle.
//
// The entire process lasts 5 M-cycles.
cpu_service_interrupt :: proc(cpu: ^Cpu, bus: ^Bus, pending: u8) {
	bit: u8
	vector: u16

	// bits 0..4 checked in priority order (low bit +)
	if pending & (1 << 0) != 0 {
		bit = 0
		vector = 0x0040
	} else if pending & (1 << 1) != 0 {
		bit = 1
		vector = 0x0048
	} else if pending & (1 << 2) != 0 {
		bit = 2
		vector = 0x0050
	} else if pending & (1 << 3) != 0 {
		bit = 3
		vector = 0x0058
	} else {
		bit = 4
		vector = 0x0060
	}

	cpu.ime = false

	// Unset the requested bit
	iflags := bus_read_byte(bus, INTERRUPT_FLAG_ADDRESS)
	iflags &= ~u8(1 << bit)
	bus_write_byte(bus, INTERRUPT_FLAG_ADDRESS, iflags)

	return_address := cpu.pc
	if cpu.halt_bug {
		// EI followed by a bugged HALT returns to the HALT instruction.
		return_address -= 1
		cpu.halt_bug = false
	}

	// 2 8 bit decrements to handle 16 bit pc
	cpu.sp -= 2
	bus_write_u16(bus, cpu.sp, return_address)

	cpu.pc = vector
}
