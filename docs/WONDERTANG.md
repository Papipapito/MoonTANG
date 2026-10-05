# MoonTANG on the WonderTANG 2.0b / 2.02b

Not yet run on hardware. This is the bring‑up guide.

## What you need

- A WonderTANG **2.0b or 2.02b** with its Tang Nano 20K.
- **Jumper J3 soldered** to the Tang's speaker pads. On these boards the sound goes
  through the Tang's own I2S amplifier and J3 into the slot's `SOUNDIN` pin: the
  MoonSound is heard through the MSX's audio output, **in mono** (left + right
  mixed). Without J3 there is no sound.
- The Yamaha **YRW801** wave ROM as `yrw801.bin` (2 MB, not included).

## What to flash

| Step | File | Address | Gowin Programmer operation |
|---|---|---|---|
| 1 | **one** of the two bitstreams below | `0x000000` | External Flash mode |
| 2 | `yrw801.bin` | `0x200000` | exFlash C Bin Erase, Program thru GAO‑Bridge |

| Bitstream | What it does |
|---|---|
| `bitstream/moontang_wondertang202b_hdmi_YYYYMMDD.fs` | Sound to the MSX **and**, at the same time, stereo sound and a VU meter on the Tang's HDMI connector. |
| `bitstream/moontang_wondertang202b_YYYYMMDD.fs` | Sound to the MSX only. |

For the MSX the two are the same cartridge. The HDMI one is the better choice for a
first test: the screen shows whether the wave ROM loaded, whether the MSX clock is
there, and whether the chip is producing sound — even if nothing is heard through
the MSX yet (J3 not soldered, for instance).

Do **not** flash `moontang_smd_*.fs` on this board, and never flash this one on the
HDMI board.

For a first try you can load the `.fs` into **SRAM** instead (it is lost at power
off): if something is wrong the board is back to its previous firmware after a
power cycle. Do it with the MSX off (the Tang powered from USB), or reset the MSX
afterwards. On the 2.0b the core reuses the JTAG pins: to flash it again, the
official README says to hold **S1** while plugging the USB cable and during the
whole flashing.

- **Check the wave ROM after every flash.** With some tools, erasing the flash for
  a new bitstream also wipes the area after it (mangOPL4 lost another image that
  way twice on this board). `0x200000` is also where tnCart keeps a megaROM and
  where the MSXnano keeps its BIOS pack: after using the Tang with another
  firmware, flash `yrw801.bin` again. The HDMI screen (`YRW801 NO VALIDA`) and
  the LED say so if the image is not the YRW801; `mt4yrw` (see
  [`tools/msx/`](../tools/msx/)) checks it from the MSX.
- With openFPGALoader: `openFPGALoader -b tangnano20k --external-flash -o 2097152 yrw801.bin`.

## The HDMI output

Plug a TV or an HDMI monitor with speakers into the Tang's HDMI connector. It is
optional: with nothing connected the cartridge behaves exactly the same.

![VU meter](img/vu_screen.png)

- Six bars: **FM** left/right, **WAVE** (the PCM wavetable) left/right, and **OUT**,
  the mix. 28 segments of 1.5 dB; the bright segment is the peak.
- `YRW801 OK` / `...` (still copying) / `NO VALIDA` (the copy finished, but the
  image in the flash is not the YRW801: a blank flash, a megaROM left there by
  another firmware, a truncated file) / `ERROR` (the copy did not finish: flash or
  SDRAM not answering). And `MSX OK` / `--`. The check is a sum of the 2 MB copied,
  compared with the sum of the real YRW801; `mt4yrw` checks what the MSX reads.
- The HDMI sound is **stereo**, 48 kHz; the sound that goes into the MSX is the
  same mix in mono.
- 720×480 at 60 Hz, flagged 16:9. A DVI‑only monitor will not take it.

## LED (pin 75)

| LED | Meaning |
|---|---|
| off | a PLL did not lock |
| fast blink | SDRAM initialising |
| slow blink | copying the YRW801 from flash to SDRAM (about 2 s) |
| double flash | the copy did not finish (flash or SDRAM not answering) |
| bursts of fast blinking every 0.6 s | copied, but the image in the flash is not the YRW801 |
| short flash every 0.6 s | ready, but no clock from the MSX (cartridge out, or MSX off) |
| steady on | ready and the MSX is running |

FM does not depend on the YRW801: **FM plays but the wavetable is silent** points at
the flash/SDRAM chain; **nothing at all** points at the bus or the power.

## Things to know before powering it

- **Power.** The WonderTANG feeds the Tang through a Schottky diode. On our board
  the Tang saw 4.59 V from a 5.0 V slot, which is marginal; if the Tang does not
  start reliably, check the 5 V rail first.
- **MSX off, USB plugged.** With the Tang powered from USB and the MSX off, the slot
  lines float. The cartridge does not touch the data bus, `/WAIT` or `/INT` until it
  sees the slot clock running and `/RESET` released.
- **`/WAIT` and `/INT` during configuration.** The FPGA takes about 3 s to load
  its configuration from flash. During that time the board's own pull‑up holds
  `/WAIT` asserted, so the MSX waits (a black screen for ~3 s is expected), and
  `/INT` is undefined. If the MSX does not boot with the cartridge in, look at
  those two lines with a scope at power‑up.
- **Speed.** At 3.58 MHz `/WAIT` reaches the Z80 with about 70 ns to spare. From
  5.37 MHz on it may arrive too late: reading the wave memory (not playing it)
  can fail in turbo modes.
- **Detection right after power‑up.** For the ~2 s the wave ROM is being copied the
  PCM engine is held in reset: a program that looks for the MoonSound in that
  window will not see the wavetable. Wait for the LED to stay on.
- **Level.** The mix is the MSXimus one: FM at its native level, wavetable 6 dB
  down. There is no volume control on the cartridge.

## Telemetry

The PCM engine sends a status line over the Tang's USB serial port (115200 8N1)
once it is running. `tools/dbg_reader.py` decodes it. It is silent until the YRW801
copy has finished.

## If the wave memory misbehaves

The embedded SDRAM runs at 108 MHz. Read data is captured half a cycle later than
in the original controller (which was tuned for 85.9 MHz), at the point the official
WonderTANG firmware and tnCart use at this frequency. The original capture point is
still available as a parameter (`SDRAM_RD_CAPTURE_CLK = 0` in `moontang_top.sv`) in
case a board prefers it.
