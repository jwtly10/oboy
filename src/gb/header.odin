package gb

import "core:encoding/endian"
import "core:fmt"

ROM_Header :: struct {
	title:             string,
	cgb_flag:          u8,
	sgb_flag:          u8,
	cartridge_type:    u8,
	rom_size_code:     u8,
	ram_size_code:     u8,
	destination_code:  u8,
	old_licensee_code: u8,
	version:           u8,
	header_checksum:   u8,
	global_checksum:   u16,
}

// An implementation of header spec https://gbdev.gg8.se/wiki/articles/The_Cartridge_Header
Parse_rom_header :: proc(rom: []u8) -> (ROM_Header, bool) {
	HEADER_END := 0x014F
	TITLE_START := 0x0134
	TITLE_END := 0x0144
	// Note: last title byte is the CFG Flag
	CGB_FLAG := 0x0143
	// These are the indexes, but we don't need to capture
	// NEW_LICENSEE_START := 0x0144
	// NEW_LICENSEE_END := 0x0146
	SGB_FEATURES := 0x0146
	CARTRIDGE_TYPE := 0x0147
	ROM_SIZE := 0x0148
	SAVE_RAM_SIZE := 0x0149
	DESTINATION_CODE := 0x014A
	OLD_LICENSEE := 0x014B
	ROM_VERSION := 0x014C
	HEADER_CHECK := 0x014D
	GLOBAL_CHECK_START := 0x014E
	// GLOBAL_CHECK_END := 0x014F

	if (len(rom) <= HEADER_END) {
		fmt.println("ROM is too small to contain a valid cartridge header")
		return {}, false
	}

	// The CGB flag *may* be the last byte of title section if GBC rom
	cgb_flag := rom[CGB_FLAG]
	title_end := TITLE_END
	if cgb_flag == 0x80 || cgb_flag == 0xC0 {
		title_end = CGB_FLAG
	}

    // Title may end with null bytes
    title_bytes := rom[TITLE_START:title_end]
    title_len:=0
    for byte in title_bytes {
        if byte != 0 {
            title_len += 1
        }
    }

	header := ROM_Header {
		title             = string(title_bytes[0:title_len]),
		cgb_flag          = cgb_flag,
		sgb_flag          = rom[SGB_FEATURES],
		cartridge_type    = rom[CARTRIDGE_TYPE],
		rom_size_code     = rom[ROM_SIZE],
		ram_size_code     = rom[SAVE_RAM_SIZE],
		destination_code  = rom[DESTINATION_CODE],
		old_licensee_code = rom[OLD_LICENSEE],
		version           = rom[ROM_VERSION],
		header_checksum   = rom[HEADER_CHECK],
		global_checksum   = endian.unchecked_get_u16be(
			rom[GLOBAL_CHECK_START:GLOBAL_CHECK_START + 2],
		),
	}

	calculated_header := calculate_header_checksum(rom)
	if header.header_checksum != calculated_header {
		fmt.println(
			"Invalid header checksum: expected '%h', calculated '%h'",
			header.header_checksum,
			calculated_header,
		)
		return {}, false
	}

	return header, true
}

Print_rom_header :: proc(header: ^ROM_Header) {
	fmt.println("=========ROM Header Start=========")

	fmt.printf("TITLE: %s\n", header.title)
	switch header.cgb_flag {
	case 0x80:
		fmt.println("CGB Support: Compatible with Game Boy Color")
	case 0xC0:
		fmt.println("CGB Support: Game Boy Color only")
	case:
		fmt.println("CGB Support: None")
	}
	fmt.printf("SGB_FLAG: 0x%02X\n", header.sgb_flag)
	fmt.printf("CARTRIDGE_TYPE: 0x%02X\n", header.cartridge_type)
	fmt.printf("ROM_SIZE_CODE: 0x%02X\n", header.rom_size_code)
	fmt.printf("RAM_SIZE_CODE: 0x%02X\n", header.ram_size_code)
	fmt.printf("DESTINATION_CODE: 0x%02X\n", header.destination_code)
	fmt.printf("OLD_LICENSEE_CODE: 0x%02X\n", header.old_licensee_code)
	fmt.printf("VERSION: 0x%02X\n", header.version)
	fmt.printf("HEADER_CHECKSUM: 0x%02X\n", header.header_checksum)
	fmt.printf("GLOBAL_CHECKSUM: 0x%04X\n", header.global_checksum)

	fmt.println("=========ROM Header End==========")
}

// Calculates an 8 bit checksum across the cartridge header bytes 0134-014C.
// The checksum is calculated as follows:
//
// `x=0:FOR i=0134h TO 014Ch:x=x-MEM[i]-1:NEXT`
//
// The lower 8 bits of the result must be the same than the value in this entry. The GAME WON'T WORK if this checksum is incorrect.
//
// https://gbdev.gg8.se/wiki/articles/The_Cartridge_Header#:~:text=014D%20%2D-,Header%20Checksum,-Contains%20an%208
calculate_header_checksum :: proc(rom: []u8) -> u8 {
	checksum: u8 = 0

	for byte in rom[0x0134:0x014D] {
		checksum = checksum - byte - 1
	}

	return checksum
}
