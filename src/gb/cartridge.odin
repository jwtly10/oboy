package gb

import "core:fmt"

@(private)
ROM_BANK_0_START :: 0x0000
ROM_BANK_0_END :: 0x3FFF
ROM_BANK_N_START :: 0x4000
ROM_BANK_N_END :: 0x7FFF

// May support Memory Bank Controllers (MBCs)
// https://gbdev.io/pandocs/MBCs.html
Cartridge :: struct {
	rom:               []u8, // Rom data (may be banked)
	ram:               []u8, // External cartridge RAM (banked)
	cartridge_type:    Cartridge_Type,
	rom_bank:          u16,
	ram_timer_enabled: bool,
	ram_rtc_select:    u8, // MBC3 Real Time Clock https://gbdev.io/pandocs/MBC3.html#a000-bfff---ram-bank-00-07-or-rtc-register-readwrite
}

// https://gbdev.io/pandocs/The_Cartridge_Header.html#0147--cartridge-type
// TODO: Not all implemented
Cartridge_Type :: enum u8 {
	ROM_ONLY               = 0x00,
	MBC1                   = 0x01,
	MBC1_RAM               = 0x02,
	MBC1_RAM_BATTERY       = 0x03,
	MBC3_TIMER_BATTERY     = 0x0F,
	MBC3_TIMER_RAM_BATTERY = 0x10,
	MBC3                   = 0x11,
	MBC3_RAM               = 0x12,
	MBC3_RAM_BATTERY       = 0x13,
	MBC5                   = 0x19,
	MBC5_RAM               = 0x1A,
	MBC5_RAM_BATTERY       = 0x1B,
}

Cartridge_init :: proc(
	rom: []u8,
	header: ^ROM_Header,
	alloc := context.allocator,
) -> (
	Cartridge,
	bool,
) {
	cart_type := Cartridge_Type(header.cartridge_type)
	if !cartridge_type_supported(cart_type) {
		fmt.printfln("Unsupported cartridge type: 0x%02X", header.cartridge_type)
		return {}, false
	}

	if len(rom) < KIB_32 {
		fmt.println("ROM is too small")
		return {}, false
	}

	expected_rom_size := cartridge_rom_size(header.rom_size_code)
	if expected_rom_size == 0 {
		fmt.printfln("Unsupported ROM size code: 0x%02X", header.rom_size_code)
		return {}, false
	}

	if len(rom) != expected_rom_size {
		fmt.printfln(
			"ROM size mismatch: header expects %d bytes, file contains %d bytes",
			expected_rom_size,
			len(rom),
		)
		return {}, false
	}

	ram_size, ram_size_ok := cartridge_ram_size(header.ram_size_code)
	if !ram_size_ok {
		fmt.printfln("Unsupported RAM size code: 0x%02X", header.ram_size_code)
		return {}, false
	}

	ram, ram_err := make([]u8, ram_size, alloc)
	if ram_err != nil {
		return {}, false
	}

	return Cartridge {
			rom = rom,
			ram = ram,
			cartridge_type = cart_type,
			rom_bank = 1,
			ram_timer_enabled = false,
			ram_rtc_select = 0,
		},
		true
}

Cartridge_destroy :: proc(cartridge: ^Cartridge, allocator := context.allocator) {
	delete(cartridge.ram, allocator)
}

cartridge_read :: proc(cart: ^Cartridge, address: u16) -> u8 {
	offset: int // since it starts from 0x0000

	switch address {
	case ROM_BANK_0_START ..= ROM_BANK_0_END:
		// Reach into static slice
		offset = int(address)
	case ROM_BANK_N_START ..= ROM_BANK_N_END:
		rom_bank_count := len(cart.rom) / KIB_16
		if rom_bank_count == 0 {
			return 0xFF
		}

		// We wrap any OOB bank accessing to replicate hardware lines
		// which would automatically ignore higher bits
		// FIXME: Just a fallback for invalid access, not 100%
		effective_bank := int(cart.rom_bank) % rom_bank_count
		offset = effective_bank * KIB_16 + int(address - ROM_BANK_N_START)
	case:
		return 0xFF // Not addressable
	}

	if offset < 0 || offset >= len(cart.rom) {
		// Not addressable
		return 0xFF
	}

	return cart.rom[offset]
}

cartridge_write :: proc(cart: ^Cartridge, address: u16, value: u8) {
	#partial switch cart.cartridge_type {
	case .ROM_ONLY:
		// ROM-only cartridge. Writes are ignored.
		return
	case .MBC3, .MBC3_RAM, .MBC3_RAM_BATTERY, .MBC3_TIMER_BATTERY, .MBC3_TIMER_RAM_BATTERY:
		cartridge_write_mbc3(cart, address, value)
	case:
		// Already rejected on init
		unreachable()
	}
}


cartridge_read_ram :: proc(cart: ^Cartridge, address: u16) -> u8 {
	if !cart.ram_timer_enabled {
		return 0xFF
	}

	selector := cart.ram_rtc_select

	if selector <= 0x07 {
		ram_bank_count := len(cart.ram) / KIB_8
		if ram_bank_count == 0 {
			return 0xFF
		}

		// Wrapping OOB ram access
		effective_bank := int(selector) % ram_bank_count
		offset := effective_bank * KIB_8 + int(address - EXTERNAL_RAM_START)

		return cart.ram[offset]
	}

	if selector >= 0x08 && selector <= 0x0C {
		return 0xFF // RTC not implemented
	}

	return 0xFF
}

cartridge_write_ram :: proc(cart: ^Cartridge, address: u16, value: u8) {
	if !cart.ram_timer_enabled {
		return
	}

	selector := cart.ram_rtc_select

	if selector <= 0x07 {
		ram_bank_count := len(cart.ram) / KIB_8
		if ram_bank_count == 0 {
			return
		}

		// Wrapping OOB ram access
		effective_bank := int(selector) % ram_bank_count

		offset := effective_bank * KIB_8 + int(address - EXTERNAL_RAM_START)

		cart.ram[offset] = value
		return
	}

	if selector >= 0x08 && selector <= 0x0C {
		return // RTC not implemented
	}
}

cartridge_write_mbc3 :: proc(cartridge: ^Cartridge, address: u16, value: u8) {
	switch address {
	// https://gbdev.io/pandocs/MBC3.html#0000-1fff---ram-and-timer-enable-write-only
	case 0x0000 ..= 0x1FFF:
		cartridge.ram_timer_enabled = (value & 0x0F) == 0x0A

	// https://gbdev.io/pandocs/MBC3.html#2000-3fff---rom-bank-number-write-only
	case 0x2000 ..= 0x3FFF:
		bank := value & 0x7F

		if bank == 0 {
			bank = 1
		}

		cartridge.rom_bank = u16(bank)

	// https://gbdev.io/pandocs/MBC3.html#4000-5fff---ram-bank-number---or---rtc-register-select-write-only
	case 0x4000 ..= 0x5FFF:
		cartridge.ram_rtc_select = value

	case 0x6000 ..= 0x7FFF:
	// RTC latching not implemented yet.
	}
}

cartridge_type_supported :: proc(cartridge_type: Cartridge_Type) -> bool {
	#partial switch cartridge_type {
	case .ROM_ONLY,
	     .MBC3,
	     .MBC3_RAM,
	     .MBC3_RAM_BATTERY,
	     .MBC3_TIMER_BATTERY,
	     .MBC3_TIMER_RAM_BATTERY:
		return true
	}

	return false
}

cartridge_ram_size :: proc(code: u8) -> (int, bool) {
	switch code {
	case 0x00:
		return 0, true
	// https://gbdev.io/pandocs/The_Cartridge_Header.html#0149--ram-size
	case 0x01:
		// Recognized but unused.
		return 0, true
	case 0x02:
		return KIB_8, true
	case 0x03:
		return KIB_32, true
	case 0x04:
		return KIB_128, true
	case 0x05:
		return KIB_64, true
	}

	return 0, false
}

cartridge_rom_size :: proc(code: u8) -> int {
	switch code {
	case 0x00:
		return 32 * 1024
	case 0x01:
		return 64 * 1024
	case 0x02:
		return 128 * 1024
	case 0x03:
		return 256 * 1024
	case 0x04:
		return 512 * 1024
	case 0x05:
		return 1 * 1024 * 1024
	case 0x06:
		return 2 * 1024 * 1024
	case 0x07:
		return 4 * 1024 * 1024
	case 0x08:
		return 8 * 1024 * 1024
	case 0x52:
		return 72 * KIB_16
	case 0x53:
		return 80 * KIB_16
	case 0x54:
		return 96 * KIB_16
	}

	return 0
}
