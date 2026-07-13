package gb

import "core:fmt"

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
	cycles, ok := Cpu_step(&machine.cpu, &machine.bus)
	if !ok {
		return false
	}

	_ = cycles
	return true
}
