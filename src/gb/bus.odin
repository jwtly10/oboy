package gb

// https://gbdev.io/pandocs/Memory_Map.html#memory-map
@(private)
KIB_128 :: 0x20000 // 128 KiB
KIB_64 :: 0x10000 // 64 KiB
KIB_32 :: 0x8000 // 32 KiB
KIB_16 :: 0x4000 // 16 KiB
KIB_8 :: 0x2000 // 8 KiB

ROM_START :: u16(0x0000)
ROM_END :: u16(0x7FFF)

VRAM_START :: u16(0x8000)
VRAM_END :: u16(0x9FFF)

EXTERNAL_RAM_START :: u16(0xA000)
EXTERNAL_RAM_END :: u16(0xBFFF)

WRAM_START :: u16(0xC000)
WRAM_END :: u16(0xDFFF)

ECHO_RAM_START :: u16(0xE000)
ECHO_RAM_END :: u16(0xFDFF)

OAM_START :: u16(0xFE00)
OAM_END :: u16(0xFE9F)

UNUSABLE_START :: u16(0xFEA0)
UNUSABLE_END :: u16(0xFEFF)

IO_START :: u16(0xFF00)
IO_END :: u16(0xFF7F)

HRAM_START :: u16(0xFF80)
HRAM_END :: u16(0xFFFE)

IE_ADDRESS :: u16(0xFFFF)

Bus :: struct {
	cartridge: Cartridge,
	vram:      [0x2000]u8, // 8 KiB Video RAM
	wram:      [0x2000]u8, // 8 KiB Work RAM
	oam:       [0xA0]u8, // 160 bytes
	io:        [0x80]u8, // 128 bytes
	hram:      [0x7F]u8, // 127 bytes
	ie:        u8, // Interrupt Enable register
}

Bus_init :: proc(rom: []u8, header: ^ROM_Header, allocator := context.allocator) -> (Bus, bool) {
	cartridge, ok := Cartridge_init(rom, header, allocator)
	if !ok {
		return {}, false
	}

	return Bus{cartridge = cartridge}, true
}

Bus_destroy :: proc(bus: ^Bus, allocator := context.allocator) {
	Cartridge_destroy(&bus.cartridge, allocator)
}

bus_read_byte :: proc(bus: ^Bus, address: u16) -> u8 {
	switch address {
	case ROM_START ..= ROM_END:
		return cartridge_read(&bus.cartridge, address)
	case VRAM_START ..= VRAM_END:
		return bus.vram[address - VRAM_START]
	case EXTERNAL_RAM_START ..= EXTERNAL_RAM_END:
		return cartridge_read_ram(&bus.cartridge, address)
	case WRAM_START ..= WRAM_END:
		return bus.wram[address - WRAM_START]
	case ECHO_RAM_START ..= ECHO_RAM_END:
		return bus.wram[address - ECHO_RAM_START] // Mirror of wram
	case OAM_START ..= OAM_END:
		return bus.oam[address - OAM_START]
	case UNUSABLE_START ..= UNUSABLE_END:
		return 0xFF // Not usable
	case IO_START ..= IO_END:
		return bus.io[address - IO_START]
	case HRAM_START ..= HRAM_END:
		return bus.hram[address - HRAM_START]
	case IE_ADDRESS:
		return bus.ie
	}
	unreachable()
}

bus_write_byte :: proc(bus: ^Bus, address: u16, value: u8) {
	switch address {
	case ROM_START ..= ROM_END:
		cartridge_write(&bus.cartridge, address, value)
	case VRAM_START ..= VRAM_END:
		bus.vram[address - VRAM_START] = value
	case EXTERNAL_RAM_START ..= EXTERNAL_RAM_END:
		cartridge_write_ram(&bus.cartridge, address, value)
	case WRAM_START ..= WRAM_END:
		bus.wram[address - WRAM_START] = value
	case ECHO_RAM_START ..= ECHO_RAM_END:
		bus.wram[address - ECHO_RAM_START] = value
	case OAM_START ..= OAM_END:
		bus.oam[address - OAM_START] = value
	case UNUSABLE_START ..= UNUSABLE_END:
	// ignored
	case IO_START ..= IO_END:
		bus.io[address - IO_START] = value
	case HRAM_START ..= HRAM_END:
		bus.hram[address - HRAM_START] = value
	case IE_ADDRESS:
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
