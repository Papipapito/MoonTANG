# First tests on a real MSX

MSX‑BASIC programs for the first session with the cartridge. Each one prints what
it read and a verdict (`OK` / `FALLO`). Load them with `LOAD "MT1DET.ASC",R`.

Run them at **3.58 MHz**, once the LED is on (or the HDMI screen says
`YRW801 OK`), in this order:

| Program | Checks |
|---|---|
| `mt1det` | Detection: the four FM ports answer, FM registers read back, NEW2, wave ID (register 02h = 20h) |
| `mt2fm` | An FM sine at 440 Hz (check it with a tuner), a scale, and left/right panning (heard on HDMI only) |
| `mt3tmr` | OPL3 timers by polling, with interrupts off |
| `mt3int` | The timer 1 interrupt through `/INT` (WonderTANG only). Run it only if `mt3tmr` passed |
| `mt4yrw` | The YRW801 in SDRAM: header of wave 0, a text block and the version at the end. **Run it again after every flash** |
| `mt5ram` | Write and read back the sample RAM (200000h–3FFFFFh) |
| `mt6pcm` | A PCM note with wave 0 of the YRW801 |

The expected values were checked against openMSX with a real MoonSound
(`moonsound` extension, YRW801 ROM).

Not to be used: the test programs of other OPL4 FPGA projects that start a timer
without masking it and without a handler hang the MSX through `/INT`, exactly
as a real MoonSound would; and those that access the wave memory without setting
register 02h bit 0 (memory mode) read nothing.

Then real software: VGMPlay twice in a row, leaving to DOS without a reset;
MoonBlaster Wave; a reset of the MSX followed by `mt4yrw` again.
