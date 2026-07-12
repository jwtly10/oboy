package gb

// May support Memory Bank Controllers (MBCs)
// https://gbdev.io/pandocs/MBCs.html
Cartridge :: struct {
	rom:            []u8, // Rom data (may be banked)
	ram:            []u8, // External cartridge RAM (banked)
	cartridge_type: u8,
	rom_bank:       u8,
	ram_bank:       u8,
	ram_enabled:    bool,
	rtc_register:   u8, // MBC3 Real Time Clock
}

Cartridge_init :: proc(
	rom: []u8,
	header: ^ROM_Header,
	alloc := context.allocator,
) -> (
	Cartridge,
	bool,
) {
	ram_size := cartridge_ram_size(header.ram_size_code)
	ram, ram_err := make([]u8, ram_size, alloc)
	if ram_err != nil {
		return {}, false
	}

	return Cartridge {
			rom = rom,
			ram = ram,
			cartridge_type = header.cartridge_type,
			rom_bank = 1,
			ram_bank = 0,
			ram_enabled = false,
			rtc_register = 0,
		},
		true
}

Cartridge_destroy :: proc(cartridge: ^Cartridge, allocator := context.allocator) {
	delete(cartridge.ram, allocator)
}

cartridge_ram_size :: proc(code: u8) -> int {
	switch code {
	case 0x00:
		return 0
	case 0x01:
		return 0x0800 // 2 KiB
	case 0x02:
		return 0x2000 // 8 KiB
	case 0x03:
		return 0x8000 // 32 KiB
	case 0x04:
		return 0x20000 // 128 KiB
	case 0x05:
		return 0x10000 // 64 KiB
	}

	return 0
}

cartridge_read :: proc(cartridge: ^Cartridge, address: u16) -> u8 {
	offset: int // since it starts from 0x0000

	switch address {
	case 0x0000 ..= 0x3FFF:
		// Reach into static slice
		offset = int(address)
	case 0x4000 ..= 0x7FFF:
		// Depending on which bank is active, we need to reach
		// into the rom by each 16 Kib Slice (0x4000)
		offset = int(cartridge.rom_bank) * 0x4000 + int(address - 0x4000)
	case:
		return 0xFF // Not addressable
	}

	if offset < 0 || offset >= len(cartridge.rom) {
		// Not addressable
		return 0xFF
	}

	return cartridge.rom[offset]
}

cartridge_read_ram :: proc(cartridge: ^Cartridge, address: u16) -> u8 {
	if !cartridge.ram_enabled {
		return 0xFF
	}

	if cartridge.rtc_register != 0 {
		return 0xFF // not implemented yet.
	}

	offset := int(cartridge.ram_bank) * 0x2000 + int(address - 0xA000)

	if offset < 0 || offset >= len(cartridge.ram) {
		return 0xFF
	}

	return cartridge.ram[offset]
}

cartridge_write :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	switch cartridge.cartridge_type {
	case 0x00:
		// ROM-only cartridge. Writes are ignored.
		return

	case 0x0F, 0x10, 0x11, 0x12, 0x13:
		// MBC3 cartridge
		cartridge_write_mbc3(cartridge, address, value)

	case:
		// Unsupported cartridge controller.
		return
	}
}

cartridge_write_mbc3 :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	switch address {
	// https://gbdev.io/pandocs/MBC3.html#2000-3fff---rom-bank-number-write-only
	case 0x0000 ..= 0x1FFF:
		cartridge.ram_enabled = (value & 0x0F) == 0x0A

	// https://gbdev.io/pandocs/MBC3.html#2000-3fff---rom-bank-number-write-only
	case 0x2000 ..= 0x3FFF:
		bank := value & 0x7F

		if bank == 0 {
			bank = 1
		}

		cartridge.rom_bank = bank

	// https://gbdev.io/pandocs/MBC3.html#4000-5fff---ram-bank-number---or---rtc-register-select-write-only
	case 0x4000 ..= 0x5FFF:
		if value <= 0x07 {
			cartridge.ram_bank = value
			cartridge.rtc_register = 0
		} else if value >= 0x08 && value <= 0x0C {
			cartridge.rtc_register = value
		}

	case 0x6000 ..= 0x7FFF:
	// RTC latching not implemented yet.
	}
}

cartridge_write_ram :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	if !cartridge.ram_enabled {
		return
	}

	if cartridge.rtc_register != 0 {
		return // RTC not implemented yet.
	}

	offset := int(cartridge.ram_bank) * 0x2000 + int(address - 0xA000)

	if offset < 0 || offset >= len(cartridge.ram) {
		return
	}

	cartridge.ram[offset] = value
}
