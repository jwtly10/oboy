package gb

// https://gbdev.io/pandocs/Memory_Map.html#memory-map
Bus :: struct {
	cartridge: Cartridge,
	vram:      [0x2000]u8, // 8 KiB Video RAM
	wram:      [0x2000]u8, // 8 KiB Work RAM
	oam:       [0xA0]u8, // 160 bytes
	io:        [0x80]u8, // 128 bytes
	hram:      [0x7F]u8, // 127 bytes
	ie:        u8, // Interrupt Enable register
}

Cartridge :: struct {
	rom: []u8,
	ram: []u8, // External cartridge RAM
	// TODO: split banks
}

Bus_init :: proc(rom: []u8) -> Bus {
	bus: Bus
	bus.cartridge.rom = rom
	return bus
}

bus_read_byte :: proc(bus: ^Bus, address: u16) -> u8 {
	switch address {
	case 0x0000 ..= 0x7FFF:
		return cartridge_read(&bus.cartridge, address)
	case 0x8000 ..= 0x9FFF:
		return bus.vram[address - 0x8000]
	case 0xA000 ..= 0xBFFF:
		return cartridge_read_ram(&bus.cartridge, address)
	case 0xC000 ..= 0xDFFF:
		return bus.wram[address - 0xC000]
	case 0xE000 ..= 0xFDFF:
		return bus.wram[address - 0xE000] // Mirror of wram
	case 0xFE00 ..= 0xFE9F:
		return bus.oam[address - 0xFE00]
	case 0xFEA0 ..= 0xFEFF:
		return 0xFF // Not usable
	case 0xFF00 ..= 0xFF7F:
		return bus.io[address - 0xFF00]
	case 0xFF80 ..= 0xFFFE:
		return bus.hram[address - 0xFF80]
	case 0xFFFF:
		return bus.ie
	}

	unreachable()
}

bus_write_byte :: proc(bus: ^Bus, address: u16, value: u8) {
	switch address {
	case 0x0000 ..= 0x7FFF:
		cartridge_write(&bus.cartridge, address, value)
	case 0x8000 ..= 0x9FFF:
		bus.vram[address - 0x8000] = value
	case 0xA000 ..= 0xBFFF:
		cartridge_write_ram(&bus.cartridge, address, value)
	case 0xC000 ..= 0xDFFF:
		bus.wram[address - 0xC000] = value
	case 0xE000 ..= 0xFDFF:
		bus.wram[address - 0xE000] = value
	case 0xFE00 ..= 0xFE9F:
		bus.oam[address - 0xFE00] = value
	case 0xFEA0 ..= 0xFEFF:
	// ignored
	case 0xFF00 ..= 0xFF7F:
		bus.io[address - 0xFF00] = value
	case 0xFF80 ..= 0xFFFE:
		bus.hram[address - 0xFF80] = value
	case 0xFFFF:
		bus.ie = value
	}
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

cartridge_read :: proc(cartridge: ^Cartridge, address: u16) -> u8 {
	index := int(address)

	if index >= len(cartridge.rom) {
		return 0xFF
	}

	return cartridge.rom[index]
}

cartridge_read_ram :: proc(cartridge: ^Cartridge, address: u16) -> u8 {
	// TODO
	return 0xFF
}

cartridge_write :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	// Writes can't modify ROM
	// MBC cartridges will interpret writes as controller cmds
}

cartridge_write_ram :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	// Not implemented yet
}
