> ⚠️ **SUPERSEDED IN PART (2026‑08‑05).** This document was written for the first
> attempt, which targeted hra1129's V9968 carrier with a *flat, non‑multiplexed*
> slot bus and a 1‑bit sigma‑delta DAC. MoonTANG now targets the **WonderTANG
> 2.0b**, whose bus is **multiplexed** (`mp[7:0]` + `msel_n[2:0]`) and whose audio
> goes out through an **I2S DAC**. Sections 1, 5, 6 and 7 still describe the wave
> memory path, the loader and the mixer accurately; sections 2, 4 and 9 (block
> diagram, bus interface, open questions) are superseded by `README.md` and
> `BRINGUP_PLAN.md`. Kept for the reasoning it records.

# MoonTANG — Technical Architecture

**MoonSound (OPL4 / YMF278B) MSX cartridge on a Tang Nano 20K (Gowin GW2AR-18C).**

> Status: **EXPERIMENTAL / pre-hardware.** The RTL is written and builds, but the
> pin mapping is inherited from t.hara's (hra1129) V9968 carrier and has not yet
> been validated against real WonderTANG hardware. See section 9.

This document describes the FPGA design under `fpga/`. It reflects what the RTL
actually does (as wired in `src/moontang_top.v`), not the target datasheet.

---

## 1. Overview

MoonTANG reimplements a **MoonSound** cartridge as a pure MSX **I/O-slot
peripheral**. The MoonSound's audio chip, the Yamaha **YMF278B (OPL4)**, is two
engines in one: an **OPL3 FM synthesizer** (18 channels), exposed on I/O ports
**C4h–C7h**, and a **24-slot PCM wavetable** engine, exposed on I/O ports
**7Eh–7Fh**, which plays instrument samples from the **YRW801** 2 MB GM sample
ROM. MoonTANG maps both of these onto the MSX I/O bus and provides the YRW801
samples from the board's SPI flash, staged into the Tang Nano 20K's embedded
SDRAM. Because it is a peripheral chip and not a ROM/RAM device, the cartridge
decodes **only I/O cycles** — it never uses `/SLTSL` or the memory address space.
The FM path is handled by `opl4fm` (a wrapper around the gtaylormb/opl3_fpga
core), the PCM wavetable by `opl4_pcm` (a wrapper around srg320's YMF278B motor),
and the two engines' outputs are mixed and streamed out through two 1-bit
sigma-delta DACs.

---

## 2. Block diagram

Module hierarchy and dataflow inside `moontang_top`:

```
                         MSX slot bus  (async, ~1 us/cycle, via carrier transceivers)
    slot_reset_n  slot_iorq_n  slot_rd_n  slot_wr_n  slot_a[7:0]  slot_d[7:0]  slot_wait  slot_intr
         |             |           |          |           |           | ^          ^          ^
         v             v           v          v           v           v |          |          |
 ============================================================================================ moontang_top
   2FF bus synchronizer @ clk_54m  -> s_iorq_n / s_rd_n / s_wr_n / s_addr / s_din  (s_m1_n = 1)
         |
         +--- raw synchronized bus ----+--------------------------+
                                        |                          |
                                        v                          v
                                 +--------------+           +--------------+
                                 |   opl4fm     |           |  opl4_pcm    |
                                 | decode C4-C7 |           | decode 7E-7F |
                                 | OPL3 FM core |           | YMF278B PCM  |
                                 | (clk_opl3)   |           |  motor       |
                                 +------+-------+           +---+------+---+
                              dout/int_n|  pcm_out          dout|      | mem_* (clk_eng motor port)
                                        |  (FM wav)  pcm_l/pcm_r|      |
              read mux (FM priority) <--+----------------------+      v
              tristate slot_d  <--------+                       +-----------+
              slot_intr = ~int_n                                | wave_sdram|  arbiter
                                                                | host + eng|  (clk_54m / clk_eng / clk_108m)
   yrw801_loader  --- wl_* host write port ----------------------+     |
        ^  wl_done -> releases motor (eng_rst_n)                       | wv_*  (byte port, 16-bit word return)
        |                                                              v
     flash (flash_rw, SPI)                                      +-------------+
        |  flash_sclk/cs/mosi/miso                              | wv_to_sdram |  byte<->32b bridge + auto-refresh
        v                                                       +------+------+
     SPI flash (YRW801 image @ FLASH_BASE)                             | bus_* (32-bit word)
                                                                       v
                                                                +-------------+
                                                                |  ip_sdram   |  t.hara 32-bit controller
                                                                +------+------+
                                                                       | (implicit embedded-SDRAM pins)
                                                                       v
                                                              embedded SDRAM (GW2AR-18)

   Audio: fm_term (attenuated FM) + pcm_l/pcm_r  --> sat16 saturating mix @ clk_54m
          --> 2x sigma_delta_dac @ clk_108m --> audio_l / audio_r
```

Key point: the FM engine (`opl4fm`) and the PCM engine (`opl4_pcm`) each receive
the **raw synchronized bus** and decode their own ports internally. Only the PCM
engine touches wave memory; the loader shares that memory subsystem through
`wave_sdram`'s host port.

---

## 3. Clocking

Everything is derived from the single **27 MHz** onboard crystal. Two PLLs
(`pll_main`, `pll_eng`) generate the internal clocks; the FM core runs straight
off the crystal.

| Clock       | Frequency              | Source                | Domain / use                                                              |
|-------------|------------------------|-----------------------|---------------------------------------------------------------------------|
| `clk_opl3`  | 27 MHz                 | crystal (direct)      | OPL3 FM core inside `opl4fm`; core divides it (`CLK_DIV_COUNT=545` → fs ≈ 49.5 kHz) |
| `clk_54m`   | 54 MHz                 | `pll_main` CLKOUTD    | MSX bus host domain: 2FF bus sync, decode, read mux, audio mix            |
| `clk_108m`  | 108 MHz                | `pll_main` CLKOUT     | SDRAM controller + wave arbiter (`wv_to_sdram`, host side of `wave_sdram`) + both DACs |
| `clk_sdram` | 108 MHz, phase-shifted | `pll_main` CLKOUTP    | clock driven *to* the SDRAM chip (`PSDA_SEL≈180°`, tune on HW)            |
| `clk_eng`   | 37.125 MHz             | `pll_eng` CLKOUT      | OPL4 PCM motor; fractional CE `6272/6875` averages 33.8688 MHz → fs 44.1 kHz |

**`pll_main`** (from 27 MHz): IDIV /1 → PFD 27 MHz, FBDIV ×4 → 108 MHz, ODIV ×8 →
VCO 864 MHz (in the valid 400–1200 MHz range). It yields **108 MHz** (CLKOUT),
**108 MHz phase-shifted** (CLKOUTP, the SDRAM chip clock) and **54 MHz** (CLKOUTD
= 108/2).

**`pll_eng`** (from 27 MHz): IDIV /8 → PFD 3.375 MHz, FBDIV ×11 → 37.125 MHz
(= 27 × 11/8), ODIV ×16 → VCO 594 MHz. It yields the single **37.125 MHz** motor
clock.

**Why 37.125 MHz and not 37.5 MHz?** The motor would ideally like ~37.5 MHz, but
that ratio (37.5 = 27 × 25/18) forces IDIV = 18, giving a phase-frequency
detector rate of 27/18 = **1.5 MHz — below the rPLL's minimum valid PFD**.
37.125 MHz (27 × 11/8) uses IDIV = 8, a PFD of **3.375 MHz**, which is in range.
The small frequency difference is absorbed by the motor's fractional
clock-enable accumulator (`6272/6875`), which produces an average of exactly
33.8688 MHz — the YMF278B's nominal master rate, giving fs = 44.1 kHz.

*Note on inline comments:* some source comments carry MSXimus-era names for the
motor clock (e.g. "clk_eng36 = 108/3"). In MoonTANG the motor clock is the
independent `pll_eng` output at 37.125 MHz. Because `pll_eng` is a **separate
PLL** from `pll_main`, the motor domain is genuinely asynchronous to the
108/54 MHz domains, so the toggle + 3-flop synchronizers in `wave_sdram`
(section 5) are real CDC, not just defensive style.

`moontang.sdc` declares the 27 MHz `clk27` and the (unused) 14.318 MHz `clk14m`
base clocks; the PLL-derived clocks are inferred from the rPLL primitives. All
slot-bus ports are declared `set_false_path` (async, handled by the 2FF
synchronizer).

---

## 4. The MSX bus interface

`moontang_top` owns the bus-facing glue; the two engines decode their own ports.

**Synchronization (2FF).** The slot bus is asynchronous and slow relative to the
54 MHz host clock. Every control and data line is passed through two flip-flops
in the `clk_54m` domain before use:

```
iorq_s <= {iorq_s[0], slot_iorq_n};   // and likewise rd, wr
a_s0 <= slot_a; a_s1 <= a_s0;          // address: 2 stages
d_s0 <= slot_d; d_s1 <= d_s0;          // write data: 2 stages
```

The synchronized bus (`s_iorq_n`, `s_rd_n`, `s_wr_n`, `s_addr`, `s_din`) is fed
**raw** to both `opl4fm` and `opl4_pcm`, which register it once more and then
decode:

- `opl4fm` decodes **C4h–C7h** (`addr[7:2] == 6'b110001`) for the OPL3 FM core,
  plus an internal 7Fh stub returning `0x20` (YMF278B device ID).
- `opl4_pcm` decodes **7Eh–7Fh** (`addr[7:1] == 7'b0111111`) and maps the MSX
  port to the YMF278B's internal `A[2:0]` (C4→0, C5→1, C6→2, C7→3, 7E→4, 7F→5).
  It also observes FM writes to track internal state.

**`/M1` is tied to `1`** (`s_m1_n = 1'b1`): the WonderTANG-style carrier does not
route the Z80 `/M1` line, so a genuine I/O cycle can never be mistaken for an M1
(interrupt-ack) cycle — the decoders simply require `m1 == 1`.

**Read-data mux (FM priority, then wave).** A read is in progress when either
engine asserts its read strobe; FM wins the mux:

```
any_rd  = opl4fm_rd | opl4pcm_rd;
rd_data = opl4fm_rd ? opl4fm_dout : opl4pcm_dout;   // FM C4-C7 else wave 7E-7F
```

The real 7Eh/7Fh reads come from `opl4_pcm` (the actual PCM engine); `opl4fm`'s
own 7Fh stub is present but not selected by the top-level mux.

**Data tristate & direction.** `any_rd`/`rd_data` are registered one `clk_54m`
cycle (`drive_r`, `drive_data`) and drive the bidirectional data port:

```
slot_d        = drive_r ? drive_data : 8'hZZ;   // cart drives only during a read
slot_data_dir = drive_r;                        // 1 = cart -> MSX, 0 = MSX -> cart
oe_n          = 1'b0;                            // data transceiver always enabled
```

**Interrupt.** `slot_intr = ~opl4fm_int_n` — the FM timer IRQ (active-high to the
carrier). The PCM engine does not raise interrupts.

**Wait.** `/WAIT` (active-high stall to the Z80) is asserted for two reasons:

```
slot_wait = sdram_init_busy | ~opl4pcm_wait_n;
```

`sdram_init_busy` stalls the bus while the SDRAM controller performs its
power-on init; `~wave_wait_n` (from `opl4_pcm`) stalls a wave read (`IN 7Fh`)
until the fetched sample byte is ready.

---

## 5. The wave memory path

The YRW801 samples and the PCM engine's fetches share the embedded SDRAM through
a three-stage chain. Byte-oriented request handshakes on the left, a 32-bit
word-oriented SDRAM controller on the right:

```
opl4_pcm.mem_* (clk_eng)  ─┐
                           ├─►  wave_sdram  ──►  wv_to_sdram  ──►  ip_sdram  ──►  SDRAM
yrw801_loader.wl_* (clk_54m)┘   (arbiter)        (bridge+refresh)   (32-bit)
```

### 5.1 `wave_sdram` — arbiter (two client ports)

`wave_sdram` presents two clients and arbitrates them onto one internal request
port (`wv_*`, in `clk_108m`):

- **Host port** (`clk_54m`): used by `yrw801_loader` (and, historically, a debug
  port). Request via a **toggle** (`req_toggle` flips to start), `we`/`addr`/
  `wdata` payload, completion via `done_toggle`.
- **Motor port** (`clk_eng`): used by `opl4_pcm` for sample fetches. Request via
  a 1-cycle pulse (`eng_req`) that is converted to a toggle internally;
  completion via `eng_done_t` (toggle).

Both requests cross into the `clk_108m` arbiter FSM through **3-flop
synchronizers** with the payload travelling alongside the toggle (consumed one
cycle after the toggle is seen). The arbiter (`ST_IDLE → ST_REQ → ST_DROP`) gives
the **motor priority** (it has a hard sample deadline), then the host. It drives
one `wv_*` transaction, waits for `wv_done`, latches the returned data **per
client** (`dout_e` / `dout_h`, so the two clients never clobber each other), and
flips that client's done-toggle. Completions are synchronized back with another
3-flop stage into each client's clock.

The port returns a **16-bit word** (the requested byte plus its neighbour) —
this feeds `opl4_pcm`'s word cache. `wave_sdram` also extracts the single byte
for each client: `rdata = addr[0] ? word[15:8] : word[7:0]`.

### 5.2 `wv_to_sdram` — byte port ↔ 32-bit word bridge + refresh

`wave_sdram`'s `wv_*` port speaks a byte address and a 16-bit return; `ip_sdram`
is a **32-bit** controller addressed by 32-bit word. `wv_to_sdram` bridges them
and injects auto-refresh:

- **Address:** byte address `wv_addr[21:0]` (4 MB) → word address
  `bus_address = {1'b0, wv_addr[21:2]}`. `wv_addr[1]` (`half`) selects which
  16-bit half of the 32-bit word to return; `wv_addr[1:0]` selects the byte lane
  for writes.
- **Byte-lane / half-word mapping:** the 32-bit word is four byte lanes 0..3.
  - *Read:* the controller returns 32 bits; the bridge forwards the 16-bit
    half-word containing the requested byte — `wv_dout = half ? bus_rdata[31:16]
    : bus_rdata[15:0]` (i.e. `{odd byte, even byte}`). `wave_sdram` later picks
    the final byte with `addr[0]`.
  - *Write:* the byte is **replicated to all four lanes** (`{b,b,b,b}`) and
    `bus_wdata_mask = ~(4'b0001 << wv_addr[1:0])` masks all lanes except the
    target one (DQM convention: `0` = write, `1` = mask), so only the addressed
    byte is written.
- **Auto-refresh:** a `REFRESH_CYCLES` (780-cycle, ~7 µs at 108 MHz) counter sets
  `ref_pending`; the FSM issues a refresh command in preference to a queued
  wave access. As the *only* SDRAM client (unlike MSXimus, where the wave stole
  spare CPU turns), arbitration is trivial and the bridge only has to interleave
  this periodic refresh.

**`ip_sdram` handshake — the `ST_ACCEPT` wait-for-accept detail.** `bus_valid`
and `bus_refresh` are only sampled when `bus_ready == 1`, and — because
`bus_valid` is **registered** — after issuing a command you cannot simply watch
`bus_ready`, since it still reads high on the issue cycle. The FSM therefore:

```
ST_IDLE   : if bus_ready, issue refresh (if pending) or the wave access; -> ST_ACCEPT
ST_ACCEPT : wait for bus_ready to FALL (controller has taken the command)
            -> ST_REF (refresh) | ST_WR (write) | ST_RD (read)
ST_RD     : wait for bus_rdata_en, latch half-word, pulse wv_done            -> ST_DONE
ST_WR     : wait for bus_ready to RISE again (write done), pulse wv_done      -> ST_DONE
ST_REF    : wait for bus_ready to RISE again (refresh done, no wv_done)       -> ST_IDLE
ST_DONE   : wait for wv_req to drop (wave_sdram releases the request)         -> ST_IDLE
```

That is: issue, wait for **ready to fall** (accepted), then wait for the
completion signal (`bus_rdata_en` on reads, `bus_ready` rising on writes/
refresh).

### 5.3 `ip_sdram` — t.hara's controller

`ip_sdram` (from hra1129, proven on this same GW2AR-18C in the V9968 cartridge)
is the actual SDRAM controller: 32-bit datapath, word-addressed. Its SDRAM chip
pins are the **implicit embedded-SDRAM pins** of the GW2AR-18 package — they are
declared on the `moontang_top` port list (`O_sdram_*`, `IO_sdram_dq`) but are not
listed in the `.cst`; the toolchain binds them implicitly (the V9968 builds the
same way). It exposes `sdram_init_busy` (used for `/WAIT` and to gate the loader)
and takes the phase-shifted `clk_sdram` as the chip clock.

### 5.4 Two reset domains

The memory subsystem and the chip logic are reset independently, on purpose:

- **`por_reset_n`** (power-on): a 4-stage sync off the PLL lock, in `clk_54m`.
  It resets the **memory subsystem** — `wave_sdram`, `wv_to_sdram`, `ip_sdram`,
  `yrw801_loader`, `flash`, and the DACs. It is asserted **once**, at PLL lock,
  and is **not** disturbed by MSX resets. This is what lets the loaded YRW801
  wave survive a soft reset of the MSX (no need to reload 2 MB from flash on
  every reset).
- **`bus_reset_n`** (MSX reset): a 3-stage sync of `slot_reset_n` (gated by
  `por_reset_n`), also in `clk_54m`. It resets the **chip logic** — `opl4fm` and
  `opl4_pcm` — so those follow the MSX reset line as a real MoonSound would.

The PCM motor sits at the boundary: `eng_rst_n = bus_reset_n & wl_done`, so it
follows the MSX reset **and** stays held until the wave load has completed.

---

## 6. The YRW801 loader

The YMF278B needs the **YRW801**: 2 MB of PCM samples for the General-MIDI
instruments. On a real MoonSound this is a mask ROM inside the chip; on MoonTANG
it lives in the board's SPI flash and is copied into SDRAM at boot. Like the BIOS
packs, **the ROM image is user-supplied for copyright reasons** and is flashed at
`FLASH_BASE` (default `0x100000`).

`yrw801_loader` (in `clk_54m`, the host domain) runs a simple FSM
(`S_WAIT → S_RDISS → S_RDWAIT → S_WRISS → S_WRWAIT → … → S_DONE`):

1. After `start` (asserted as `por_reset_n & ~sdram_init_busy`, i.e. once SDRAM
   init finishes) and a short flash warm-up margin, it pulses `flash_rd` to the
   `flash` (`flash_rw`) SPI reader, which streams bytes via continuous read
   (opcode `0x03`).
2. Each byte is written into SDRAM through `wave_sdram`'s **host port**
   (`wl_req_toggle` / `wl_we` / `wl_addr = cnt` / `wl_wdata`), waiting for
   `wl_done_toggle` to flip.
3. After `WAVE_SIZE` (2 MB) bytes it asserts `flash_terminate` and enters
   `S_DONE`, raising **`wl_done`**.

While loading, the motor is held in reset (`eng_rst_n = bus_reset_n & wl_done`,
`wl_done = 0`) so it never reads half-written samples. `wl_done` going high
releases the motor. `wave_sdram` arbitrates the loader's writes against the
motor's reads, so once the MSX is up and the motor is running, they coexist.

---

## 7. Audio

The final mix happens in `moontang_top` (host domain), fed by the FM sample
(`opl4fm.pcm_out`) and the stereo PCM (`opl4_pcm.pcm_l/pcm_r`).

**FM attenuation.** The OPL4's FM level register (F8h, surfaced as
`opl4_mixfm[5:0]` from `opl4_pcm`) scales the FM before mixing, mirroring the
real chip (as done in MSXimus):

```
o4fm_base = mixfm[0] ? (fm>>>1)+(fm>>>2) : fm;   // optional x0.75
o4fm_att  = o4fm_base >>> mixfm[2:1];            // >> 0..3
fm_term   = (mixfm[2:0] == 7) ? 0 : o4fm_att;    // code 7 = mute FM
```

**Saturating mix.** FM and PCM are sign-extended to 18 bits, summed per channel,
and clamped to 16-bit signed range by `sat16()`:

```
mixL = sext(fm_term) + sext(pcm_l);   mixR = sext(fm_term) + sext(pcm_r);
sampL = sat16(mixL);  sampR = sat16(mixR);   // registered @ clk_54m
```

**Output DACs.** Each channel drives a `sigma_delta_dac`: a **2nd-order, 1-bit
sigma-delta** modulator clocked at **108 MHz**. It offset-binary-shifts the
signed sample (`+0x8000`), runs two 19-bit integrators with 1-bit feedback
(`±32768`), and outputs `~acc2[18]`. Running the modulator as fast as possible
(108 MHz) pushes quantization noise well out of the audio band; an external RC
low-pass reconstructs the analog signal to the jack / slot `SOUND` pin.

---

## 8. Build & resource usage

Build with the Gowin command-line flow:

```
cd fpga && gw_sh build.tcl
```

`build.tcl` targets `GW2AR-18C` / `GW2AR-LV18QN88C8/I7`, adds sources in
dependency order — the OPL3 core (`opl3/*.sv`) and `opl4fm.v`; the PCM motor
(`opl4wave/ymf278b_gowin.v`, `opl4_pcm.v`) and `wave_sdram.v`; the memory
subsystem (`wv_to_sdram.v`, `ip_sdram_tangnano20k_c.v`); the loader
(`yrw801_loader.v`, `flash_rw.v`); `sigma_delta_dac.v`; the PLLs; and the top —
then the constraints (`moontang.cst`, `moontang.sdc`). It frees the dedicated
config pins as GPIO (`-use_mspi_as_gpio` for the loader's flash, plus SSPI / JTAG
/ CPU / DONE / READY for audio and spare pins), sets `-top_module moontang_top`
with SystemVerilog 2017, and runs `syn` then `pnr`.

Measured build results (GW2AR-18C):

| Resource | Utilization |
|----------|-------------|
| Logic    | 52 %        |
| CLS      | 60 %        |
| BSRAM    | 7 %         |
| DSP      | 7 %         |

Timing closure — all clocks meet their constraints (achieved Fmax):

| Clock domain        | Achieved Fmax |
|---------------------|---------------|
| FM core (clk_opl3)  | 73 MHz        |
| Bus host (clk_54m)  | 114 MHz       |
| SDRAM (clk_108m)    | 162 MHz       |
| PCM motor (clk_eng) | 47.7 MHz      |

Each figure is comfortably above the clock it serves (27 / 54 / 108 / 37.125 MHz
respectively), so the design closes timing with margin in simulation/synthesis.

---

## 9. Open hardware questions

MoonTANG has **not** been brought up on real hardware. The following must be
validated / tuned on a physical WonderTANG-style board before flashing:

- **WonderTANG pin mapping.** `constraints/moontang.cst` is carried over from
  t.hara's V9968 carrier (same Tang Nano 20K + level transceivers to the MSX
  slot). Every slot/bus pin assignment must be checked against the **real
  WonderTANG schematic** before programming — the current file is a coherent
  first guess, not a verified mapping.
- **Audio pin routing.** `audio_l` (pin 52) / `audio_r` (pin 53) and their
  path to an RC filter / the slot `SOUND` pin are a starting choice and need to
  be confirmed against the actual board wiring.
- **SDRAM CAS latency / `clk_sdram` phase.** `pll_main`'s `PSDA_SEL` (SDRAM chip
  clock phase, currently ~180°) and the controller's CAS-latency timing set the
  setup/hold margin at the SDRAM; these are per-board and must be tuned on real
  silicon (the Tang Nano 20K SDRAM part varies across board revisions).
- **Flash `FLASH_BASE` offset.** The YRW801 image offset in SPI flash
  (`FLASH_BASE`, default `0x100000`) must match wherever the user actually
  writes the 2 MB ROM image; verify against the real flash layout.
