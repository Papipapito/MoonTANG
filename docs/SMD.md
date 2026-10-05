# MoonTANG on the MSXhdmi_tn20k_smd cartridge (rev B)

Not yet run on hardware. Sound over **HDMI**, with a VU meter on screen.

![VU meter](img/vu_screen.png)

The MSXhdmi_tn20k_smd is an SMD re‑layout of jabadiagm's MSXhdmi / Asgard video
cartridge: a Tang Nano 20K with the MSX bus wired straight to the FPGA through four
74LVC245 buffers. It has no path from the FPGA to the slot's `SOUNDIN` pin, so this
variant sends the MoonSound to the Tang's HDMI connector instead — in stereo — and
uses the picture to show what is playing.

## What you see

- Six bars: **FM** left/right, **WAVE** (the PCM wavetable) left/right, and **OUT**,
  the mix that goes to the HDMI audio. 28 segments of 1.5 dB; the top one is full
  scale. The bright segment is the peak, held for about a second.
- `YRW801 OK` / `...` (still copying it from flash, about 2 s after power‑up) /
  `NO VALIDA` (copied, but the image in the flash is not the YRW801: a blank flash
  or another firmware's data at `0x200000`) / `ERROR` (the copy did not finish:
  flash or SDRAM not answering). `mt4yrw` in [`tools/msx/`](../tools/msx/) checks
  what the MSX reads.
- `MSX OK` when the slot clock is running, `--` when it is not.
- The build date, bottom left.

The picture is 720×480 at 60 Hz, flagged as 16:9, with colours in limited range
(16–235), which is what a TV expects for that format. The audio is 48 kHz stereo PCM.
A DVI‑only monitor will not take it: it needs a display that accepts HDMI with
audio.

## What to flash

| Step | File | Address | Gowin Programmer operation |
|---|---|---|---|
| 1 | `bitstream/moontang_smd_YYYYMMDD.fs` | `0x000000` | External Flash mode |
| 2 | `yrw801.bin` (2 MB, not included) | `0x200000` | exFlash C Bin Erase, Program thru GAO‑Bridge |

- **Never plug the USB cable while the cartridge is in a powered MSX.** This board
  has no diode on the 5 V rail: the MSX's 5 V and the PC's would be tied together.
  Flash it on the bench, out of the MSX.
- Do **not** flash `moontang_wondertang*.fs` here, nor this file on a WonderTANG.
- The Tang's BL616 must keep its factory firmware: three of its pins share lines
  with the bus buffers.

## What this board cannot do

Checked on the KiCad PCB: the following slot lines end at the edge connector and
never reach the FPGA.

| Line | Consequence |
|---|---|
| `/INT` | The OPL4 cannot interrupt the MSX. The timer flags can still be read at `C4h`. |
| `/BUSDIR` | On machines (or slot expanders) with a buffered slot data bus, I/O reads from the cartridge do not reach the CPU: the MoonSound is not detected. Writes still work. |
| `/WAIT` | A read cannot be stretched. See *Reads without /WAIT* below. |
| `/M1` | None: an interrupt‑acknowledge cycle has `/RD` and `/WR` inactive. |
| `SOUNDIN` | No sound through the MSX: HDMI only. |

### What that means for software

From reading the source or disassembly of each program — nothing below has been
run on this board.

| Program | Without `/INT` |
|---|---|
| VGMPlay 1.3 / 1.4 on a Z80 MSX | **Plays at about 5 % of the speed.** It times playback with the OPL4 timer interrupt, for any VGM, as soon as it detects the chip. |
| VGMPlay on a turbo R, VGMPlay 1.2 | Fine: they do not use the OPL4 timer. |
| MoonBlaster Wave 1.1 and later | Plays, locked to the display interrupt: a 60 Hz song on a 50 Hz machine runs at 83 % unless the screen is switched to 60 Hz. |
| RoboPlay, SymbOS (SymAmp, Sound Daemon), MoonDriver, MWMPLAY, MMP | Fine: they use the display interrupt or poll the status. |
| Meridian, NMP, MBFM / MBPlay, games | Not checked. |

Detection of the MoonSound does not depend on `/INT` in any of the programs above.

### Reads without /WAIT

On a real MoonSound, and on the WonderTANG variant, reading the wave data port
(`7Fh`) can hold the Z80 for a moment while the PCM engine answers. This board
cannot do that, so the two registers software actually reads — the device ID and
the wave memory data register — are answered directly from the bus side, where the
engine has already left the next byte ready. In simulation this reads correctly at
3.58 MHz and with turbo timings (7.16 MHz), also while notes are playing.

The other wave registers still take the trip to the engine, so reading them back
needs 3.58 MHz; at that speed the bench reads the slot registers back correctly on
the first read.

## The two spare pins

Two FPGA pins reach the ESP‑01S socket: **pin 75 → J2.1** and **pin 79 → J2.8**.
Inside the Tang both have a pull‑down (and pin 79 also feeds the WS2812 LED), so
they cannot pull a slot line directly: each needs a transistor — gate or base on
the pin, open drain or collector on the slot line — exactly like the WonderTANG
does for `/WAIT` and `/INT`.

The firmware is ready for it: `EXT_A` (pin 75) and `EXT_B` (pin 79) in
`moontang_smd_top.sv` select what each pin outputs, **active high**:
`0` nothing (default), `1` `/INT`, `2` `/BUSDIR`, `3` `/WAIT`.

On the rev B PCB the only copper of those slot lines is the gold finger itself, so
this is a board‑revision job more than a bodge: two transistors from J2.1 and J2.8
to `/INT` (finger 8) and `/BUSDIR` (finger 10) would lift the two limits that
matter. Until then the default build leaves both pins low.

## Notes

- Use the MSX at 3.58 MHz.
- LED3 on the Tang lights while the cartridge is answering a read. The other Tang
  LEDs are on bus lines and just flicker.
- Like the original MSXhdmi firmware, some bus lines share pins with the HDMI
  connector's DDC, CEC and hot‑plug lines; the FPGA does not use them.
- Resource use on the GW2AR‑18: about 54 % of the logic, 16 of 46 block RAMs, both
  PLLs. The PCM engine runs from the HDMI PLL (135 MHz ÷ 3.5 = 38.57 MHz).
