package gb

Bus :: struct {
	// 16-bit address bus
	memory: [0x10000]u8,
}

Bus_init :: proc(rom: []u8) -> Bus {
	bus: Bus

	// Init 32kib of rom data to memory
	rom_len := min(len(rom), 0x8000)
	copy(bus.memory[0:rom_len], rom[0:rom_len])

	return bus
}

bus_read_byte :: proc(bus: ^Bus, address: u16) -> u8 {
	return bus.memory[int(address)]
}

bus_write_byte :: proc(bus: ^Bus, address: u16, value: u8) {
	bus.memory[int(address)] = value
}

bus_write_u16 :: proc(bus: ^Bus, address: u16, value: u16) {
	bus_write_byte(bus, address, u8(value)) // u8 cast is lower byte
	bus_write_byte(bus, address + 1, u8(value >> 8))
}

bus_read_u16_le :: proc(bus: ^Bus, address: u16) -> u16 {
	low := u16(bus_read_byte(bus, address))
	high := u16(bus_read_byte(bus, address + 1))

	return low | high << 8
}

