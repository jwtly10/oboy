

# oboy

`oboy` is a WIP Odin Game Boy emulator.

Can currently boot and run Pokémon Red.

https://github.com/user-attachments/assets/3e2b281f-57cd-4657-bd0b-4e086385cc35

## Known accuracy issues

- Timing is not cycle-accurate. The timer, PPU and DMA are all updated after each instruction.
- The PPU renders a scanline at a time and uses a fixed drawing period. Some games rely on exact PPU timing.
- DMA timing and bus conflicts are not hardware accurate
- The boot ROM is skipped. CPU starts from post-boot state.
- Only ROM-only and MBC3 cartridges are supported. No MBC3 Clock or battery-backed save file support.
- Not all interrupts are implemented (STOP/JP)
- Some hardware rules, like PPU memory access restrictions are not implemented yet.
- No audio, serial/link cable, Game Boy Color or Super Game Boy support.
- No Third-party test ROMs suites run yet - no hardware accuracy guarantees.

## Controls
| Controller | Keyboard   |
| ---------- | ---------- |
| D-pad      | WASD       |
| A          | J          |
| B          | K          |
| Start      | Enter      |
| Select     | Backspace  |


## Running

Can run with:

```sh
odin run src -o:speed -- <path-to-rom>
```

Can build with:
```sh
odin build src -o:speed -out:oboy
./oboy <path-to-rom>
```

## TODO

- [ ] Build up 3rd Party Rom Test suite
- [ ] Add battery-backed save files
- [ ] Improve cycle-level CPU, timer, PPU, and DMA synchronization
- [ ] Replace fixed scanline rendering timings with more accurate PPU/FIFO behavior
- [ ] Finish joypad interrupt behavior
- [ ] Add audio through the APU
- [ ] Add serial and link-cable register behavior
- [ ] Add MBC3 real-time clock
- [ ] Support MBC1 and MBC5
- [ ] Better UX/UI / COngifu
- [ ] Boot ROM Support
