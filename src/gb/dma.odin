package gb

DMA_ADDRESS :: u16(0xFF46)
DMA_LENGTH :: u16(0x00A0) // 160 Bytes

// Direct Memory Access
// https://gbdev.io/pandocs/OAM_DMA_Transfer.html
//
// Note:
// The DMA timing is NOT hardware accurate, at this point it's just enough to
// write memory to the correct place, in a relatively timely fashion so sprites
// can be loaded
DMA :: struct {
	reg:           u8,

	// Write triggered
	active:        bool,
	// Encodes when the CPU can access memory during DMA
	locked:        bool,
	// Ticks until initialisation complete
	startup_delay: u8,

	// DMA reg source start
	source_start:  u16,
	// Next byte to copy
	byte_index:    u16,
	// T-cycles since last byte copy
	cycle_count:   u8,
	// Exposes the byte currently being transfer
	// to handle the case of restricted CPU reads during DMA
	current_value: u8,
}

// Writing to this register starts a DMA transfer from ROM or RAM to OAM
// Transfer takes 160 M-cycles plus initial 1 M-Cycle (4 T-Cycle) delay
// After writing to the register a delay of 4 T-cycles occurs before the DMA transfer actually begins.
dma_write :: proc(bus: ^Bus, value: u8) {
	dma := &bus.dma

	dma.reg = value
	dma.active = true
	dma.startup_delay = 4
	dma.locked = false
	dma.byte_index = 0
	dma.cycle_count = 0
	// The written value becomes the high byte of the source address - where the to-copy data starts
	// https://github.com/Ashiepaws/GBEDG/blob/master/dma/index.md#dma-control-register-dma--ff46
	dma.source_start = u16(value) << 8
}

// Once started, the transfer copies one byte every 4 T-cycles, adding up to a total duration
// of 644 T-cycles (including the initialization delay).
dma_tick :: proc(bus: ^Bus) {
	dma := &bus.dma

	if !dma.active {
		// Hasn't been written too, no need to tick
		return
	}

	if dma.startup_delay > 0 {
		// Decrement initialization delay
		dma.startup_delay -= 1

		// During the same tick that ends the startup delay
		// we lock the CPU from accessing memory
		if dma.startup_delay == 0 {
			dma.locked = true
		}
		return
	}

	// We copy byte every 4 T-cycles
	dma.cycle_count += 1
	if dma.cycle_count < 4 {
		return
	}

	// Reset the count to allow work on next 4th tick
	dma.cycle_count = 0

	source_address := dma.source_start + dma.byte_index
	value := bus_read_byte_dma(bus, source_address)

	// Write the value from DMA source
	dma.current_value = value
	bus.oam[dma.byte_index] = value
	dma.byte_index += 1

	if dma.byte_index == DMA_LENGTH {
		// All written
		dma.active = false
		dma.locked = false
	}
}
