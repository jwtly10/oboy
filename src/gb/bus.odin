package gb

KIB_128 :: 0x20000 // 128 KiB
KIB_64 :: 0x10000 // 64 KiB
KIB_32 :: 0x8000 // 32 KiB
KIB_16 :: 0x4000 // 16 KiB
KIB_8 :: 0x2000 // 8 KiB

// Memory Map

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

// Interrupt Addresses

IE_ADDRESS :: u16(0xFFFF)
INTERRUPT_FLAG_ADDRESS :: u16(0xFF0F)

// Timer Address

DIV_ADDRESS :: u16(0xFF04)
TIMA_ADDRESS :: u16(0xFF05)
TMA_ADDRESS :: u16(0xFF06)
TAC_ADDRESS :: u16(0xFF07)

// PPU Addresses

// LCD Control
LCDC_ADDRESS :: u16(0xFF40)
// LCD Status
STAT_ADDRESS :: u16(0xFF41)
SCY_ADDRESS :: u16(0xFF42)
SCX_ADDRESS :: u16(0xFF43)
// Stores no. scanlines ppu currently processing
LY_ADDRESS :: u16(0xFF44)
LYC_ADDRESS :: u16(0xFF45)
BGP_ADDRESS :: u16(0xFF47)
OBP0_ADDRESS :: u16(0xFF48)
OBP1_ADDRESS :: u16(0xFF49)
WY_ADDRESS :: u16(0xFF4A)
WX_ADDRESS :: u16(0xFF4B)

PPU :: struct {
	lcdc:                u8,
	stat:                u8,
	scy:                 u8,
	scx:                 u8,
	ly:                  u8,
	lyc:                 u8,
	// Background palette data
	bgp:                 u8,
	obp0:                u8,
	obp1:                u8,
	wy:                  u8,
	wx:                  u8,
	dot:                 int,
	mode:                PPU_mode,
	// Representing colors for each pixel
	frame_buffer:        [160 * 144]u8,
	stat_interrupt_line: bool,
	// Flag for triggering drawing
	frame_ready:         bool,
}

PPU_mode :: enum u8 {
	HBLANK  = 0,
	VBLANK  = 1,
	OAM     = 2,
	DRAWING = 3,
}

Timer_Registers :: struct {
	system_counter: u16,
	tima:           u8,
	tma:            u8,
	tac:            u8,
	overflow_phase: timer_overflow_cycle,
	overflow_delay: u8,
}

timer_overflow_cycle :: enum {
	NONE,
	CYCLE_A,
	CYCLE_B,
}

// https://gbdev.io/pandocs/Memory_MapiW.html#memory-map
// Bus handled the memory mapping of the emulator
Bus :: struct {
	cartridge:  Cartridge,
	vram:       [0x2000]u8, // 8 KiB Video RAM
	wram:       [0x2000]u8, // 8 KiB Work RAM
	oam:        [0xA0]u8, // 160 bytes
	io:         [0x80]u8, // 128 bytes
	hram:       [0x7F]u8, // 127 bytes
	// Interrupt Enabled register
	ie:         u8,
	timer_regs: Timer_Registers,
	ppu:        PPU,
	dma:        DMA,
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

// CPU Bus Accessor (CPU restrictions)
cpu_bus_read_byte :: proc(bus: ^Bus, address: u16) -> u8 {
	if bus.dma.locked && !bus_address_is_hram(address) {
		// During DMA, the CPU cannot read real ROM/RAM values
		return bus.dma.current_value
	}

	return bus_read_byte(bus, address)
}

// Internal Accessor (no restrictions)
bus_read_byte :: proc(bus: ^Bus, address: u16) -> u8 {
	return bus_read_byte_internal(bus, address)
}

// CPU Bus Writer (CPU restrictions)
cpu_bus_write_byte :: proc(bus: ^Bus, address: u16, value: u8) {
	if bus.dma.locked && !bus_address_is_hram(address) && address != DMA_ADDRESS {
		// During DMA, the CPU cannot write to ROM/RAM
		return
	}

	bus_write_byte_internal(bus, address, value)
}

// Internal Writer (no restrictions)
bus_write_byte :: proc(bus: ^Bus, address: u16, value: u8) {
	bus_write_byte_internal(bus, address, value)
}

bus_read_byte_internal :: proc(bus: ^Bus, address: u16) -> u8 {
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
	case DIV_ADDRESS:
		// After 256 ticks, upper byte of s_c increases from 0 to 1
		// So this produces an increment every 256 ticks
		return u8(bus.timer_regs.system_counter >> 8)
	case TIMA_ADDRESS:
		return bus.timer_regs.tima
	case TMA_ADDRESS:
		return bus.timer_regs.tma
	case TAC_ADDRESS:
		// Only the lowest 3 bits are used
		// the rest are treated as 1
		// Bitwise OR 1111_1000
		return bus.timer_regs.tac | 0xF8
	case LCDC_ADDRESS:
		return bus.ppu.lcdc
	case STAT_ADDRESS:
		return bus.ppu.stat
	case SCY_ADDRESS:
		return bus.ppu.scy
	case SCX_ADDRESS:
		return bus.ppu.scx
	case LY_ADDRESS:
		return bus.ppu.ly
	case LYC_ADDRESS:
		return bus.ppu.lyc
	case BGP_ADDRESS:
		return bus.ppu.bgp
	case OBP0_ADDRESS:
		return bus.ppu.obp0
	case OBP1_ADDRESS:
		return bus.ppu.obp1
	case WY_ADDRESS:
		return bus.ppu.wy
	case WX_ADDRESS:
		return bus.ppu.wx
	case DMA_ADDRESS:
		return bus.dma.reg
	case IO_START ..= IO_END:
		return bus.io[address - IO_START]
	case HRAM_START ..= HRAM_END:
		return bus.hram[address - HRAM_START]
	case IE_ADDRESS:
		return bus.ie
	}

	unreachable()
}

bus_write_byte_internal :: proc(bus: ^Bus, address: u16, value: u8) {
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
	case DIV_ADDRESS:
		timer_write_div(bus, value)
	case TIMA_ADDRESS:
		timer_write_tima(bus, value)
	case TMA_ADDRESS:
		timer_write_tma(bus, value)
	case TAC_ADDRESS:
		timer_write_tac(bus, value)
	case LCDC_ADDRESS:
		bus.ppu.lcdc = value
	case STAT_ADDRESS:
		// CPU can only write bits 3..6, 0..2 are controlled by PPU
		bus.ppu.stat = (bus.ppu.stat & 0b0000_0111) | (value & 0b0111_1000)
		ppu_update_stat_interrupt_line(bus)
	case SCY_ADDRESS:
		bus.ppu.scy = value
	case SCX_ADDRESS:
		bus.ppu.scx = value
	case LY_ADDRESS:
	// Read-only - noop
	case LYC_ADDRESS:
		bus.ppu.lyc = value
		// If this value changes we have to ensure PPU state
		// is recalculated for the STAT interrupt
		ppu_update_lyc_coincidence(bus)
		ppu_update_stat_interrupt_line(bus)
	case BGP_ADDRESS:
		bus.ppu.bgp = value
	case OBP0_ADDRESS:
		bus.ppu.obp0 = value
	case OBP1_ADDRESS:
		bus.ppu.obp1 = value
	case WY_ADDRESS:
		bus.ppu.wy = value
	case WX_ADDRESS:
		bus.ppu.wx = value
	case DMA_ADDRESS:
		dma_write(bus, value)
	case IO_START ..= IO_END:
		bus.io[address - IO_START] = value
	case HRAM_START ..= HRAM_END:
		bus.hram[address - HRAM_START] = value
	case IE_ADDRESS:
		bus.ie = value
	}
}

// Bypases DMA restrictions to access DMA byte
bus_read_byte_dma :: proc(bus: ^Bus, address: u16) -> u8 {
	return bus_read_byte_internal(bus, address)
}

cpu_bus_write_u16 :: proc(bus: ^Bus, address: u16, value: u16) {
	cpu_bus_write_byte(bus, address, u8(value)) // u8 cast is lower byte
	cpu_bus_write_byte(bus, address + 1, u8(value >> 8)) // Move upper byte to lower (and as above)
}

bus_read_u16_le :: proc(bus: ^Bus, address: u16) -> u16 {
	low := u16(bus_read_byte(bus, address))
	high := u16(bus_read_byte(bus, address + 1))

	return low | high << 8
}

bus_address_is_hram :: proc(address: u16) -> bool {
	return address >= HRAM_START && address <= HRAM_END
}
