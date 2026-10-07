# What has been verified, and how

Nothing here replaces a test on a real MSX. This is what the simulations do and do
not cover, so a failure on hardware can be narrowed down quickly.

## On hardware

The OPL4 has played on a WonderTANG 2.02b with an earlier build of the HDMI
bitstream (the morning of 5 October, before the latest fixes). Not tried on
hardware yet: any of the bitstreams delivered now (the four in `bitstream/` and the
experimental HDMI + MSX‑Audio one); the MSX‑Audio and the MSXhdmi_tn20k_smd board
have never been. The MSX‑BASIC tests of [`tools/msx/`](../tools/msx/)
were checked against openMSX.

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
  3.58 MHz (and, in the MSX‑Audio phases, at 5.37, 7.16 and 10.74 MHz), samples
  data and `/WAIT` where the real CPU does, and checks that neither changes inside
  its setup window.

```sh
# WSL / Linux with Icarus Verilog and sv2v
bash tools/sim/board/run_board.sh          # WonderTANG without HDMI (about 6 minutes)
bash tools/sim/board/run_board.sh hdmi     # with HDMI, and the HDMI receiver model (about 20 minutes)
bash tools/sim/board/run_board.sh audio    # with the MSX-Audio: phases L and M
bash tools/sim/board/run_board.sh todo     # all three, negative controls, blank flash, sweeps
bash tools/sim/board/run_board.sh hdmi_audio  # the EXPERIMENTAL HDMI + MSX-Audio bitstream and its negative control (about 60 minutes; not in "todo")
bash tools/sim/board_smd/run_smd.sh        # MSXhdmi_tn20k_smd
```

### Where the pin numbers come from

A wrong pin assignment is invisible to an RTL simulation, and it is what broke the
first WonderTANG bitstream of this project. So the two sides of the connection come
from different sources:

| | FPGA side | Board side |
|---|---|---|
| WonderTANG | wrapper generated from `fpga/constraints/moontang.cst` | pin table generated from the official firmware's `top.cst`; bus multiplexing as the official `top.v` does it |
| HDMI board | wrapper generated from `fpga/constraints/moontang_smd.cst` | pin table generated from the board's KiCad PCB, following the copper through the 74LVC245 buffers |

### What the WonderTANG bench checks (75 checks; 84 with HDMI; 120 with the MSX‑Audio)

The same bench runs the three WonderTANG bitstreams. With HDMI it also checks the
38.57 MHz engine clock and, with the HDMI receiver model described below, that
every pixel and audio sample on the cable is the one that was sent while the sound
into the MSX keeps working. With the MSX‑Audio it adds the checks described in the
next section.

Clock frequencies; YRW801 copy (exact byte count, no retries, checksum); no bus activity with
the MSX off or in reset; FM register write and read‑back on both banks; wavetable
device ID; silence on other ports (`C0h` included, in the bitstreams without the
MSX‑Audio), on memory cycles and on interrupt‑acknowledge
cycles; OPL3 timer → `/INT` on the slot and its release; wave ROM read through the
memory registers with `/WAIT`, and how early `/WAIT` reaches the slot; sample RAM
write and read‑back; slot register read‑back through `7Fh`, on the first read; a PCM note from key‑on to the I2S frames at the amplifier; an
FM note panned left, then right, and its presence in the mono mix; survival of the
wave memory across an MSX reset, also with the memory chain's completion toggle
left at 1 by the last operation before the reset (96 reads of the first bytes of
the wave ROM must all be right); and, all along, that the cartridge only drives the
data bus during one of its own reads.

### What the MSX‑Audio phases check

`bash tools/sim/board/run_board.sh audio` builds the MSX‑Audio top against the same
`moontang.cst` and runs two simulations side by side: the main bench with phase L
added (120 checks), and phase M (`-Ptb_board.BUSV=1`, 84 checks), which after the
port checks replaces the rest of the main bench. `run_board.sh todo` runs both.

Phase L:

- status `06h` after a reset; decoding on A0–A7 only, with garbage on A8–A15;
  `C2h` and `C3h` silent;
- timer 1 → `/INT` on the slot (the Y8950's, not the OPL3's), status `C6h`, and the
  release after stopping the timer and resetting the flags;
- sample RAM: bytes written at `0A000h` (above 32 KB) and `3FFF8h` (the last 8 of
  256 KB) land in SDRAM bank 2 and read back through `C1h`, with the two dummy
  reads; `02000h` and `1FFF8h` keep their own (no aliasing);
- the OPL4 FM note left sounding by the earlier phases is silenced at the start
  of phase L, and L3 and L4 check that it stays silent (maximum and minimum within
  ±16 LSB: with its envelope at the bottom the OPL3 still leaves a few LSB, −9 at
  most here), so that what reaches the amplifier is the Y8950 alone;
- a short ADPCM sample reaches the amplifier over I2S at its weight in the mix,
  `(ADPCM/8) × 5` (±20 400 for a full‑scale sample), and raises end of sample,
  with its IRQ on `/INT`;
- an FM note of the Y8950 reaches the amplifier (about ±20 500) without touching
  the OPL4's FM; key off gives silence;
- phase L4b: one write of an FM register (index and data) in each of the 105
  phases of the Z80 clock against the FPGA's — the MSX clock and the 108 MHz meet
  again every 35 Z80 cycles, the 9‑state scanner of the multiplexed bus every
  105 — and `jtopl` has to hold the right index and data after every one of them;
- the Y8950 and the OPL4 do not step on each other: registers, status and sample
  RAMs (`0A000h` of the ADPCM in bank 2, `20A000h` of the OPL4 in bank 1);
- with Z80 timing at 7.16 and 10.74 MHz: reads of `C0h`/`C1h` and of `C4h`/`C5h`,
  none asking for `/WAIT`, and fast `OUT`s to both chips without a lost write.

Phase M:

- reads at 3.58, 5.37, 7.16 and 10.74 MHz: every read of `C0h`/`C1h` returns the
  right value and the Y8950's data settles no later than the OPL4's (+5 ns; the
  check is one‑sided, see below), and fast `OUT`s reach both chips;
- `/WR` pulses from 300 ns down in steps of 20 ns: both chips write down to 80 ns
  and both miss at 60 ns; an `OUT` whose data changes just as `/WR` rises is written
  with the right value;
- bus noise (interrupt acknowledge, memory cycles, M1, refresh, other ports) does
  not move the ADPCM RAM pointer or touch the selected register: exactly one strobe
  per real `C0h`/`C1h` cycle;
- the OPL3 and Y8950 interrupts ANDed on `/INT`, served in both orders;
- an MSX `/RESET` in the middle of an `IN`/`OUT` of `C1h`, with ADPCM and FM
  playing: `/INT` released, status `06h`, both silent, the bridge and
  `adpcm_sdram` idle, the sample RAM keeps its contents and works again.

What the settle time measures: for each fast read, the last moment D0–D7 changed
before the Z80 samples, counted from `/IORQ`, and the worst of 16 reads per port.
It is the read path of the multiplexed front‑end (the same for both chips) unless
the value itself changes during the read. At 5.37, 7.16 and 10.74 MHz both chips
read at 158–161 ns. At 3.58 MHz in phase M the Y8950 is at 161 ns and the OPL4 at
502 ns, and those 502 ns are not the read path: phase C sets NEW2 (register 105h,
bit 1), which raises LD (bit 1 of the status) in the wavetable engine until the
next status read, and the first `IN C4h` of phase M is that read. It starts with
`02h` on the bus; the read is passed on to the PCM engine, which clears LD, and the
cleared flag comes back through the clock crossing and turns the bus to `00h`
about 500 ns after `/IORQ` — still before the Z80 samples (615 ns), so the read
returns `00h`. At 3.58 MHz the comparison therefore only shows that the Y8950 is
not later than that; the faster speeds, where LD is already clear, are the ones
that compare the read paths.

Up to 7.16 MHz no read of either chip changes inside the Z80's setup window. At
10.74 MHz both are at the limit, and equally so: the data settles about 159 ns
after `/IORQ` (phase M: `C0h`/`C1h` at 159.4 ns, `C4h`/`C5h` at 158.8 ns) and some
reads of each chip change inside the 50 ns setup window — 8 of each chip in phase
M, 8 of the OPL4 and 10 of the Y8950 in phase L. The sampled value is right in all
of them.

### Negative controls

A test that cannot fail proves nothing, so the bench is also run against known‑bad
inputs and has to fail (the first five in `run_board.sh todo`, the sixth in
`run_board.sh hdmi_audio`):

| Control | Result |
|---|---|
| The pin file of the first bitstream (address selectors swapped) | fails 8 of 36 checks: no answer at `C4h`, and an answer when `C4h` is on A8–A15 |
| The original SDRAM read‑capture point, against the worst‑case data window | fails 13 of 56: wave memory reads return undefined data |
| FM shadow‑register writes that miss their strobe (the read‑back copy is never written) | fails 4 of 36: `C5h` and `C7h` do not read back what was written |
| The PCM engine before the reset fix (memory‑chain completion seen right after an MSX reset) | fails 2 of 75: 5 of 192 reads of the wave ROM's first bytes wrong after the reset |
| The Y8950 FM given the whole bus cycle, as `jtopl` gets it in the MSXimus (`cs_n` for as long as the write is seen, with the live data and A0 instead of the 2‑cycle pulse with the first cycle's), MSX‑Audio bitstream | fails 1 of 120, phase L4b: `jtopl` keeps `FFh` (the released bus) as the index or as the data in 16 of the 105 phases. Whether the FM note of phase L4 sounds depends on the phases its writes land on: in an earlier version of the bench it did not sound, now it does |
| The seventh VU bar fed with the mix (OUT R) instead of the Y8950's share, experimental HDMI + MSX‑Audio bitstream (`run_board.sh hdmi_audio`) | fails 1 of 133: the bar moves while only the OPL4 plays |

And one case that has to be reported, not passed: a **blank flash** where the
wave ROM should be. The copy finishes, but the checksum does not match, and the
HDMI screen has to say `YRW801 NO VALIDA` (`run_board.sh todo`, `blank`).

Checked once by hand (it needs a file that is no longer in the tree): the PCM engine
from before the slot read‑back fix fails the read‑back phase on both boards, with 7
of 12 single read‑backs wrong on the WonderTANG and 4 of 12 on the HDMI board.

A sweep of the FPGA clock‑to‑pad delay in the multiplexed‑bus loop passes up to
18.5 ns of total loop delay (the scanner samples 18.5 ns after switching a group,
the same settling time the official firmware allows), with and without the
MSX‑Audio; at 19.5 ns both fail.

**`/WAIT` and the Z80 setup window.** The Z80 samples `/WAIT` on a falling clock edge
and needs it stable 70 ns before. `/WAIT` being asserted inside that window would be
an error (the Z80 might not wait), and the bench fails on it. Releasing it inside
the window is allowed: `/WAIT` is released when the engine answers, which has no
fixed phase with the MSX clock, and the release goes through an NPN and the MSX
pull‑up, whose delay depends on the computer. The Z80 then takes one wait state
more or one less. The bench follows the shorter path and checks the data there; the
longer path only adds time. In the current runs the releases that land inside the
window are all on reads of `7Fh`: 19 without HDMI, 22 with the MSX‑Audio, none
with HDMI.

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
be right. `fpga/hdmi/hdmi.sv` includes the CEA‑861/HDMI 1.4 timing corrections
recorded in `tools/sim/hdmi/hdmi_cea861.patch`; the normal test is strict. The CTS
is allowed ±2: in simulation the pixel and audio clocks come from models rounded
to picoseconds and give 27001.7; on the board both come from the same crystal and
it is exactly 27000.

### The experimental HDMI + MSX‑Audio bitstream

`run_board.sh hdmi_audio` builds `moontang_wt_hdmi_audio_top` (the HDMI top with the
Y8950 on) against `moontang_wt_hdmi.cst` and runs, in one simulation, everything of
the HDMI bench and phase L of the MSX‑Audio bench (133 checks): every pixel and
every audio sample on the cable, the Y8950 FM and ADPCM in the mix, the shared
`/INT`. Phase M (bus timing) is not repeated: the bus front‑end and the Y8950
interface are the ones of the MSX‑Audio bitstream. Plus phase V, the seventh bar of
the VU meter (MSX‑AUDIO), against a model of the bar written apart from
`vu_screen`: each of its pixels (24 rows, 28 segments of 16 px and the 2 px gaps;
48 192 pixels over 4 frames) has the colour the level, the peak mark and the zone
give; the bar stays at 0 while only the OPL4 plays (OUT reaches 24 segments) and
reaches 26 with the Y8950 FM note of phase L4. The frame on the cable is left in
`build/hdmi_audio_cuadro.png`.

Its negative control (the bar fed with the mix) runs alongside, in the same mode;
see the table above.

Gowin closes timing on it, but see [WONDERTANG.md](WONDERTANG.md#experimental-hdmi-and-msx-audio-together)
for the one risk that timing analysis does not cover (the embedded SDRAM interface
is not constrained).

## Smaller benches

| Bench | Covers |
|---|---|
| `tools/sim/tb_loader_real.v` | the YRW801 loader against the real SPI flash reader, and its checksum (right and wrong expected sum) |
| `tools/sim/opl3_timer/` | an OPL3 timer stopped in the exact cycle where its prescaler wraps, in five different ways: flags and `/INT` must clear, and the normal periods must not change. Negative control: the timer before the fix fails 5 of 9 (`run.sh negativo`) |
| `tools/sim/tb_i2s.v` | I2S channel order, bit alignment, and that samples are stable when the transmitter loads them |
| `tools/sim/vu/tb_vu_meter.v` | level‑to‑segment conversion against a logarithmic reference, and the meter ballistics |
| `tools/sim/vu/` | the VU screen: renders frames to PNG and counts lit segments |
| `tools/sim/wv_to_sdram/` (`run.sh`) | the SDRAM bridge with its two clients, against a fake controller that can be stalled at will (94 checks): the watchdog firing during a refresh with requests pending, which are served when the controller comes back; firing in each wait state for each client, with the `done` and the `FFFFh` data going only to the owner; the priorities, and the second client never starved (at most 46 cycles, 426 ns, with the first one saturated); the bank mapping, without aliasing and with the right byte lane; 4000 + 4000 random operations with refresh running; an operation dropped by its client in the middle (no `done` for it; the next request gets its own); a 5000‑cycle controller init that does not trip the watchdog. Negative controls (`run.sh negativo`), which have to fail: the single‑client bridge without the handling of a watchdog during a refresh (6 of 26), the current bridge without the handling of a dropped operation (5 of 94), and with the watchdog counting while idle (1 of 94) |
| `tools/sim/y8950/` (`run.sh`) | the SDRAM shared by the PCM engine and the ADPCM, on the real chain (`wave_sdram` and `adpcm_sdram` → `wv_to_sdram` → `ip_sdram` → the SDRAM model of the board bench). A synthetic engine, saturated (one cache miss after another), at 38.57 and 37.125 MHz against no ADPCM (reference) and an ADPCM that writes a block and reads it back with pauses of 30, 5.9, 3 and 1 µs, or none: 12 runs, no wrong data, no protocol error, no watchdog, and every run with ADPCM has to read back and check data (blocks of 2048 bytes; of 256 bytes with 30 µs pauses, so that the 15 ms simulated reach the read‑back: 128 words checked; 392 to 16 384 in the others). The engine keeps at least 99.7 % of its rate with pauses of 3 µs or more (anything a Z80 can do), and 96.8 % in the worst case (1 µs pauses at 37.125 MHz). Also `tb_rst.v`: MSX resets in the middle of ADPCM operations with the engine saturated (2000, 2000 and 6000 resets of 1–40 or 1–3 cycles): no `done` of an aborted operation reaches a new request, no wrong read, nothing hangs |
| `tools/sim/y8950/` (`run.sh mix`) | the mixer of the MSX‑Audio bitstream (`tb_mix.v`, 10 checks): the limiter exhaustively over its 2^20 inputs (identity below the knee, slope 1/2 and ceiling above, monotonic, symmetric); a full FM carrier of `jtopl` (±20 500) passes untouched; loud chords — 3 carriers at full level (TL = 0): 60.9 % of the samples would clip without the limiter, 44.3 % sit at the ceiling with it; 6 channels at TL = 8: 15.3 % and 7.2 % |

In Icarus, `jtopl` only leaves X after a long reset (100 µs or more; an MSX `/RESET`
is that long), even with the `MOONTANG_SIM` initial values: a new bench with short
resets would see the Y8950 FM at X. On the FPGA every register starts at 0.
The ADPCM interpolator (`jt10_adpcmb_interpol`) has data registers without reset:
the board bench sets them to 0 at time 0, as the FPGA does at power‑up. Without
that, the first ADPCM sample played after power‑up puts two X samples into the mix
(the HDMI bench catches them; the MSX‑Audio bench, which only measures levels, does
not).

## What simulation cannot tell

- Electrical behaviour: levels, the 5 V rail, the NPN stages, the J3 audio path.
- Whether a given TV accepts the HDMI signal.
- How it sounds. The OPL4 core itself is the one validated by ear on the MSXimus;
  what is new here is everything around it.
- How the MSX‑Audio sounds next to the MoonSound. The Y8950 is the one validated by
  ear on the MSXimus; the balance and the limiter have to be judged here by ear,
  with loud MSX‑Audio music.

## Seen in simulation, not checked on hardware

- An OPL4 FM note released with RR = 0 is still heard after an MSX `/RESET`.
- If the SDRAM controller stayed forever with `bus_ready` low, no request would be
  served: the bridge's watchdog covers operations in progress, not the idle state.
- The Y8950 FM needs about 23 µs between data writes to registers 20h and up, as
  the real chip does; the board bench waits 25 µs.
