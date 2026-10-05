# What has been verified, and how

Nothing here replaces a test on a real MSX. This is what the simulations do and do
not cover, so a failure on hardware can be narrowed down quickly.

## The board‑level benches

`tools/sim/board/` (WonderTANG) and `tools/sim/board_smd/` (HDMI board) simulate the
**real top level** of each variant — converted to plain Verilog with sv2v and run
with Icarus Verilog — together with:

- Gowin's own simulation models of the rPLL, CLKDIV, BUFG and OSER10 primitives, so
  the clock frequencies and the SDRAM clock phase are the ones the parameters give;
- a model of the carrier board, connected to the FPGA **by pin number**;
- a model of the SPI flash holding a synthetic YRW801;
- a model of the embedded SDRAM that drives its data bus only during the valid
  window of a real read (clock‑out delay + access time + input delay) and X outside
  it, and that flags illegal command sequences;
- a Z80 that performs opcode fetch, refresh and I/O cycles with Z80A timings at
  3.58 MHz, samples data and `/WAIT` where the real CPU does, and checks that
  neither changes inside its setup window.

### Where the pin numbers come from

A wrong pin assignment is invisible to an RTL simulation, and it is what broke the
first WonderTANG bitstream of this project. So the two sides of the connection come
from different sources:

| | FPGA side | Board side |
|---|---|---|
| WonderTANG | wrapper generated from `fpga/constraints/moontang.cst` | pin table generated from the official firmware's `top.cst`; bus multiplexing as the official `top.v` does it |
| HDMI board | wrapper generated from `fpga/constraints/moontang_smd.cst` | pin table generated from the board's KiCad PCB, following the copper through the 74LVC245 buffers |

### What the WonderTANG bench checks (75 checks; 84 with HDMI)

The same bench runs both WonderTANG bitstreams. With HDMI it also checks the
38.57 MHz engine clock and, with the HDMI receiver model described below, that
every pixel and audio sample on the cable is the one that was sent while the sound
into the MSX keeps working.


Clock frequencies; YRW801 copy (exact byte count, no retries, checksum); no bus activity with
the MSX off or in reset; FM register write and read‑back on both banks; wavetable
device ID; silence on other ports, on memory cycles and on interrupt‑acknowledge
cycles; OPL3 timer → `/INT` on the slot and its release; wave ROM read through the
memory registers with `/WAIT`, and how early `/WAIT` reaches the slot; sample RAM
write and read‑back; slot register read‑back through `7Fh`, on the first read; a PCM note from key‑on to the I2S frames at the amplifier; an
FM note panned left, then right, and its presence in the mono mix; survival of the
wave memory across an MSX reset, also with the memory chain's completion toggle
left at 1 by the last operation before the reset (96 reads of the first bytes of
the wave ROM must all be right); and, all along, that the cartridge only drives the
data bus during one of its own reads.

### Negative controls

A test that cannot fail proves nothing, so the bench is also run against known‑bad
inputs and has to fail:

| Control | Result |
|---|---|
| The pin file of the first bitstream (address selectors swapped) | fails: no answer at `C4h`, and an answer when `C4h` is on A8–A15 |
| The original SDRAM read‑capture point, against the worst‑case data window | fails: wave memory reads return undefined data |
| FM shadow‑register writes that miss their strobe (the read‑back copy is never written) | fails: `C5h` and `C7h` do not read back what was written |
| The PCM engine before the reset fix (memory‑chain completion seen right after an MSX reset) | fails: 5 of 192 reads of the wave ROM's first bytes wrong after the reset |

And one case that has to be reported, not passed: a **blank flash** where the
wave ROM should be. The copy finishes, but the checksum does not match, and the
HDMI screen has to say `YRW801 NO VALIDA` (`run_board.sh todo`, `blank`).

Checked once by hand (it needs a file that is no longer in the tree): the PCM engine
from before the slot read‑back fix fails the read‑back phase on both boards, with 7
of 12 single read‑backs wrong on the WonderTANG and 4 of 12 on the HDMI board.

A sweep of the FPGA clock‑to‑pad delay in the multiplexed‑bus loop passes up to
18.5 ns of total loop delay (the scanner samples 18.5 ns after switching a group,
the same settling time the official firmware allows).

**`/WAIT` and the Z80 setup window.** The Z80 samples `/WAIT` on a falling clock edge
and needs it stable 70 ns before. `/WAIT` being asserted inside that window would be
an error (the Z80 might not wait), and the bench fails on it. Releasing it inside
the window is allowed: `/WAIT` is released when the engine answers, which has no
fixed phase with the MSX clock, and the release goes through an NPN and the MSX
pull‑up, whose delay depends on the computer. The Z80 then takes one wait state
more or one less. The bench follows the shorter path and checks the data there; the
longer path only adds time. In the current run, 1 of 50 releases lands inside the
window, 0.6 ns in.

### What the HDMI‑board bench checks

The same bus, memory and reset checks with the Z80 **ignoring `/WAIT`** (that board
has none), plus: the data‑buffer direction sequence (the FPGA never drives against
the buffer); timer flags by polling; slot register read‑back at 3.58 MHz; a burst of
wave‑memory reads at `INIR` pace;
the PCM engine's rate on its 38.57 MHz clock; stereo separation of the audio handed
to the HDMI transmitter; the VU levels; and one video frame dumped to an image.

`tools/sim/hdmi/` holds an independent HDMI receiver model (TMDS and TERC4 decoding,
packet ECC, audio sample packets, InfoFrames). Besides its own bench, it is attached
to the whole HDMI‑board design (`tools/sim/board_smd/hdmi_rx_hookup.vh`), on the
symbols before the serialiser. There, every pixel on the link has to be the one the
VU screen produced, and every audio sample the one the transmitter took, in order
and in its channel. There has to be no protocol error (BCH, checksums, parity, TMDS
codes), and the geometry, clock regeneration, channel status and InfoFrames have to
be right. The four known deviations of this copy of hdl‑util/hdmi from CEA‑861 and
HDMI 1.4 (`tools/sim/hdmi/hdmi_cea861.patch`) are accepted there knowingly. The
CTS is allowed ±2: in simulation the pixel and audio clocks come from models rounded
to picoseconds and give 27001.7; on the board both come from the same crystal and
it is exactly 27000.

## Smaller benches

| Bench | Covers |
|---|---|
| `tools/sim/tb_loader_real.v` | the YRW801 loader against the real SPI flash reader, and its checksum (right and wrong expected sum) |
| `tools/sim/opl3_timer/` | an OPL3 timer stopped in the exact cycle where its prescaler wraps, in five different ways: flags and `/INT` must clear, and the normal periods must not change. Negative control: the timer before the fix fails 5 of 9 (`run.sh negativo`) |
| `tools/sim/tb_i2s.v` | I2S channel order, bit alignment, and that samples are stable when the transmitter loads them |
| `tools/sim/vu/tb_vu_meter.v` | level‑to‑segment conversion against a logarithmic reference, and the meter ballistics |
| `tools/sim/vu/` | the VU screen: renders frames to PNG and counts lit segments |

## What simulation cannot tell

- Electrical behaviour: levels, the 5 V rail, the NPN stages, the J3 audio path.
- Whether a given TV accepts the HDMI signal.
- How it sounds. The OPL4 core itself is the one validated by ear on the MSXimus;
  what is new here is everything around it.
