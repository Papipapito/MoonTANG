# MoonTANG — architecture

MoonTANG is a MoonSound cartridge as a pure **I/O peripheral**: OPL3 FM on ports
`C4h–C7h` and the 24‑voice PCM wavetable on `7Eh–7Fh`. One WonderTANG bitstream
adds an MSX‑Audio (Y8950) on `C0h–C1h`. It never uses `/SLTSL` or the memory space.

The design is one **core** — the MoonSound itself — inside the WonderTANG shell.

```
                    ┌───────────────────────── moontang_core ─────────────────────────┐
  bus (in clk_54m)  │  opl4fm ── OPL3 FM core (gtaylormb)                    27 MHz   │
  iorq/rd/wr/addr ─▶│     │                                                           │
  din / rd_data     │  opl4_pcm ── YMF278B PCM engine (srg320)              clk_eng   │
  wait_n / int_n  ◀─│     │                                                           │
                    │  wave_sdram ─▶ wv_to_sdram ─▶ ip_sdram ─▶ embedded SDRAM 108 MHz│
                    │     ▲            ▲ 2nd client (SDRAM banks 2-3)                 │
                    │     │       adpcm_sdram ◀── moontang_y8950 (Y8950 = 1, C0h-C1h) │
                    │     │                       jtopl2 FM + ADPCM-B, CE 3.58 MHz    │
                    │  yrw801_loader ◀─ flash_rw ◀─ SPI flash (YRW801 at 0x200000)    │
                    │                                                                 │
                    │  mixer: FM (register F8h attenuation) + wave [+ Y8950, limiter] │
                    │                                                 ─▶ L, R, mono   │
                    └─────────────────────────────────────────────────────────────────┘
        ▲                                                         │
        │                                                         ▼
  ┌─────┴──────────────────────────┐          ┌───────────────────────────────────────┐
  │ WonderTANG shell               │          │ WonderTANG: i2s_feed ▶ I2S ▶ Tang amp │
  │   WT200B_BUS (tnCart): scans   │          │   ▶ J3 ▶ SOUNDIN (mono)               │
  │   the multiplexed bus          │          ├───────────────────────────────────────┤
  │                                │          │ moontang_av (HDMI builds):             │
  │                                │          │   48 kHz stereo ▶ hdl‑util/hdmi       │
  │                                │          │   vu_meter ▶ vu_screen ▶ 720x480p     │
  │                                │          └───────────────────────────────────────┘
  └────────────────────────────────┘
```

| File | Role |
|---|---|
| `src/moontang_core.sv` | the MoonSound: FM, PCM, wave memory chain, loader, mixer, bus‑alive guard; with `Y8950 = 1`, also the MSX‑Audio |
| `src/moontang_wt_shell.sv` | WonderTANG 2.02b shell: bus scanner, core, I2S; the PCM engine clock comes from the top |
| `src/moontang_wt_hdmi_top.sv` | WonderTANG top **with** HDMI: shell + `moontang_av` |
| `src/moontang_top.sv` | WonderTANG top **without** HDMI: shell + a PLL for the PCM engine |
| `src/moontang_wt_audio_top.sv` | WonderTANG top **without** HDMI and **with** the MSX‑Audio: `moontang_top.sv` with `Y8950 = 1`; same ports and instance names, so it uses the same `moontang.cst` and `moontang.sdc` |
| `src/moontang_wt_hdmi_audio_top.sv` | **experimental**: WonderTANG top **with** HDMI **and** the MSX‑Audio: `moontang_wt_hdmi_top.sv` with `Y8950 = 1` and the seventh VU bar; same ports and instance names, so it uses `moontang_wt_hdmi.cst` and `.sdc` |
| `src/moontang_y8950.sv` | the MSX‑Audio: bus decoding of `C0h–C1h`, write strobes, 3.58 MHz clock enable, IRQ; instantiates the parts below |
| `y8950/jtopl/*`, `y8950/jt10/*`, `y8950/y8950_adpcm.v`, `y8950/adpcm_sdram.v` | Y8950 FM (`jtopl2`), ADPCM‑B decoder, ADPCM registers and sample RAM interface |
| `src/moontang_mix_y8950.v` | mixer of the MSX‑Audio bitstream: OPL4 + Y8950 and the limiter |
| `src/moontang_av.sv` | the WonderTANG HDMI output: stereo sound, VU meter, and the PCM engine clock |
| `src/opl4fm.v`, `opl3/*` | FM half; register shadow for read‑back; timer IRQ |
| `src/opl4_pcm.v`, `opl4wave/ymf278b_gowin.v` | PCM half: bus glue, fractional clock enable, sample cache, engine |
| `src/wave_sdram.v`, `wv_to_sdram.v`, `ip_sdram_tangnano20k_c.v` | wave memory: arbiter, byte‑to‑word bridge for two clients with refresh and watchdog, SDRAM controller |
| `src/yrw801_loader.v`, `flash_rw.v` | copy of the YRW801 from SPI flash to SDRAM at power‑up |
| `wondertang/*` | tnCart multiplexed bus front‑end and I2S transmitter; `src/i2s_feed.v` hands samples to it |
| `src/vu_meter.v`, `vu_screen.v`, `font8x8.v`, `hdmi/*` | level meters, their screen, HDMI transmitter (all inside `moontang_av`) |

The OPL4 files are the ones of the MSXimus (Zynq branch) and are kept in sync with
it. MoonTANG's own differences are confined to parameters of `opl4_pcm.v`: the
clock‑enable fraction of the PCM engine, the telemetry baud divisor, and the
optional read mirror (`RD_MIRROR`, off by default).

The Y8950 files under `y8950/` are those of the MSXimus 60K (V3.8 branch), which
are the same in every MSXimus core. JTOPL comes with the MSXimus change to it (the
shift registers of `jtopl_sh` and `jtopl_sh_rst` kept in flip‑flops with
`syn_srlstyle`). MoonTANG only adds a few `initial` blocks in four `jtopl` files
(`jtopl_div`, `jtopl_slot_cnt`, `jtopl_sh`, `jtopl_reg_ch`) behind
`` `ifdef MOONTANG_SIM ``: a macro that only the simulation scripts define, so that
Icarus does not start those registers at X. Synthesis does not see them.

## Clocks

Everything derives from the Tang's 27 MHz crystal. The GW2AR‑18 has two PLLs.

| Clock | Without HDMI | With HDMI | Used by |
|---|---|---|---|
| 108 MHz + shifted copy | PLL 1 | PLL 1 | SDRAM, wave arbiter, (WonderTANG) bus scanner |
| 54 MHz | PLL 1 ÷ 2 | PLL 1 ÷ 2 | host side of the OPL4, bus |
| 27 MHz (FM) | 108 ÷ 4 (`CLKDIV`) | 108 ÷ 4 (`CLKDIV`) | OPL3 core (49.5 kHz sample rate) |
| PCM engine | PLL 2: 37.125 MHz | 135 ÷ 3.5 (`CLKDIV`): 38.57 MHz | PCM engine |
| 135 MHz | — | PLL 2 | TMDS serialisers |
| pixel 27 MHz | — | crystal through `BUFG` | video, HDMI |
| HDMI audio | — | 48 kHz = 54 MHz ÷ 1125 | HDMI sample rate |
| I2S (WonderTANG) | 1.543 MHz bit clock | 1.543 MHz bit clock | sound into the MSX |

With HDMI the second PLL makes the 135 MHz the transmitter needs, so the PCM
engine takes its clock from there instead of having a PLL of its own. That is the
only internal difference between the WonderTANG bitstreams with and without HDMI.

The MSX‑Audio bitstream has the clocks of the one without HDMI, and the
experimental HDMI + MSX‑Audio one those of the HDMI bitstream. The Y8950 runs on
the 54 MHz clock with a clock enable of 35/528, 3.579545 MHz on average (315/88 MHz,
the MSX clock); it adds no clock net.

The PCM engine needs an average of 33.8688 MHz (44.1 kHz × 768). It gets it from a
fractional clock enable: 6272/6875 of 37.125 MHz, or 2744/3125 of 38.57 MHz.
The FM clock is derived from the PLL and not taken from the crystal pad: from the
pad its skew against the 54 MHz domain produced hold violations.

## Resets

- **Power‑on reset** follows the system PLL lock only. It covers the SDRAM, the
  loader and the wave memory chain, so the wave ROM **survives an MSX reset**.
  On HDMI builds, a loss of the 135 MHz HDMI PLL resets the pixel/PCM-engine
  domain only; it must not restart the loader or disturb the slot bus.
- **Bus reset** follows the slot's `/RESET` and resets the chip logic, the Y8950
  included. The ADPCM sample RAM is in the SDRAM, so its contents also survive an
  MSX reset.
- The PCM engine is also held in reset until the YRW801 copy has finished.

## Bus‑alive guard

With the Tang powered from USB and the MSX off, the slot lines float and can look
like a read of one of our ports. The core only lets the shell drive the data bus,
`/WAIT` or `/INT` when it has counted slot‑clock edges in the last 2.4 ms and
`/RESET` is released.

## Wave memory

`wave_sdram` arbitrates two clients — the loader at power‑up, the PCM engine
afterwards — onto one byte port. `wv_to_sdram` turns byte accesses into 32‑bit word
accesses of the embedded SDRAM, inserts refresh cycles, and has a watchdog so that a
stuck SDRAM cannot wedge the arbiter. The 2 MB YRW801 occupies the first half of the
4 MB wave address space; the second half is sample RAM.

On HDMI builds the on-screen `SAMPLE RAM` bar is a 28-segment high-water mark of
that second half.  The PCM engine retains the maximum custom-sample byte address it
has written since power-up and crosses it to video using Gray code.  This is useful
without inventing allocation metadata the YMF278B does not have, but is deliberately
not a count of non-zero or allocated bytes: a sparse write close to `3FFFFFh` makes
the bar nearly full.

The embedded SDRAM has 8 MB in four banks of 2 MB:

| Bank | Contents |
|---|---|
| 0 | YRW801 (wave addresses `000000h–1FFFFFh`) |
| 1 | OPL4 sample RAM (`200000h–3FFFFFh`) |
| 2 | MSX‑Audio bitstream: the 256 KB of ADPCM sample RAM, at the start of the bank |
| 3 | free |

`wv_to_sdram` has two ports with the same contract (hold `req` until a one‑cycle
`done`, then drop it): `wv_*` for `wave_sdram`, mapped to banks 0–1, and `wv2_*`
for the Y8950's `adpcm_sdram`, mapped to banks 2–3. In the bitstreams without the
MSX‑Audio `wv2_req` is tied to 0 and the bridge behaves as a single‑client one.

- **Priority**: refresh, then `wv` (the PCM engine), then `wv2`. The ADPCM needs at
  most one 16‑bit word every 80 µs while it plays, and an upload with `OTIR` writes
  one byte every 5.9 µs at 3.58 MHz, so it can afford to wait: in simulation the
  `wv2` port waits at most 46 cycles of 108 MHz (426 ns) with the engine saturated,
  and the engine keeps at least 99.7 % of its rate against an ADPCM at Z80 pace.
- **Ownership**: the read data comes back on a shared bus, but the `done` goes only
  to the client that owns the operation. If that client drops its request in the
  middle (an MSX reset resets `adpcm_sdram` but not the bridge), the operation ends
  without a `done`.
- **Watchdog**: it counts only while the bridge waits for the controller (4096
  cycles, about 38 µs). If it fires while a read or a write is pending, the owner
  gets its `done` with the data poisoned to `FFFFh`; during a refresh, the bridge
  just goes back to idle and serves whatever is pending.

The SDRAM controller is t.hara's. Read data is captured on the system clock, half a
cycle later than in the original (which was tuned for 85.9 MHz): at 108 MHz that is
where the data window is, and it is the point the official WonderTANG firmware and
tnCart use.

## Audio

The mixer is the MSXimus one: each FM channel side at its native level with the
attenuation of register `F8h`, plus the wave output 6 dB down, saturated to 16
bits. The core outputs left, right and their half‑sum.

- **WonderTANG.** The Tang's amplifier is mono, so both I2S frames carry the
  half‑sum. The HDMI bitstream adds the HDMI output below, in parallel. `i2s_feed` latches each sample right after the frame clock edge, so the
  transmitter — which runs on its own clock — always loads a value that has been
  stable for microseconds.
- **HDMI** (`moontang_av`). Left and right go to the HDMI transmitter at 48 kHz. The sample
  clock is generated in the 54 MHz domain and the samples change on its falling
  edge; the transmitter takes them on the rising one.

### With the MSX‑Audio

With `Y8950 = 1` the last stage of the mixer is `moontang_mix_y8950`:

- The Y8950 is mono. Its term is the MSXimus one, `(FM + ADPCM/8) × 5` — the
  ADPCM at its usual balance against an FM carrier, and the ×5 of the MSXimus
  between its "classic" chips and the OPL4 — and it is added to both sides.
- The sums are kept at 20 bits, then left, right and the half‑sum go through the
  MSXimus soft limiter: unity gain up to 24 576 (3/4 of full scale), slope 1/2
  above, ceiling ±32 767. Below the knee nothing changes — a full FM carrier of the
  Y8950 (±20 500 after the ×5), the ADPCM at full volume or a wave voice pass as
  they are. Above it the OPL4 is compressed too. With the ×5 there is room for
  about 1.6 full carriers, so loud Y8950 chords do reach the limiter (figures in
  [`VERIFICATION.md`](VERIFICATION.md)).
- Two more register stages at 54 MHz than the plain mixer: 37 ns more latency.
- The half‑sum goes to the I2S of the WonderTANG as in the other bitstreams.

## The VU meter (HDMI output)

`vu_meter` keeps the peak of each of six signals over a video frame and turns it
into 0–28 segments on a logarithmic scale of about 1.5 dB per segment, with a fast
rise, a decay of one segment every two frames and a peak marker. `vu_screen` draws
the bars and the texts directly from the pixel coordinates — there is no frame
buffer. The values only change during vertical blanking.

With `Y8950 = 1` (a parameter of `moontang_av` and `vu_screen`, set only by the
experimental HDMI + MSX‑Audio top) there is a seventh, mono bar, **MSX‑AUDIO**,
between WAVE and OUT: the Y8950's term as it enters the mix, `(FM + ADPCM/8) × 5`
(`out_y` of `moontang_mix_y8950`), saturated to 16 bits. The other bars move closer
together to make room. With the default `Y8950 = 0` the screen and the logic are
the usual ones: the netlists of the four regular bitstreams did not change.

## Bus front-end

Address and control lines are multiplexed on eight pins behind
  three buffers. tnCart's scanner selects each group in turn at 108 MHz and filters
  every bit. `/WAIT` and `/INT` leave through inverting transistors.

## MSX‑Audio (Y8950)

`moontang_y8950` (only with `Y8950 = 1`) puts the Y8950 of the MSXimus next to the
MoonSound:

- **FM**: `jtopl2`, jotego's JTOPL with `OPL_TYPE = 2`, mono output.
- **ADPCM‑B**: `y8950_adpcm` — registers 07h–12h, status and IRQ, with the
  behaviour of openMSX's Y8950 — driving jotego's `jt10_adpcmb` decoder and its
  interpolator.
- **Sample RAM**: `adpcm_sdram` with `FALLBACK_BSRAM = 0`: the 256 KB in SDRAM bank
  2 through the `wv2` port, with a one‑word cache and a prefetch (see *Wave
  memory*). The parameter keeps the 32 KB BSRAM alternative.
- **Clock**: 54 MHz with the 35/528 clock enable (see *Clocks*).

The glue around them:

- **Decoding.** The bus, already in the 54 MHz domain, is registered once and
  decoded the way `opl4fm` decodes `C4h–C7h`: same stage, `/IORQ` with `/M1` high,
  A0–A7 only. `C0h–C1h`; `C2h–C3h` (a second unit) are not decoded. No `/WAIT`.
  Reads leave through the core's `rd_data` with the same timing as the OPL4's.
- **Writes** are taken on the first cycle in which the write is seen, with the data
  of that cycle, as the FM shadow registers of `opl4fm` are. `jtopl` writes on a
  level, at every clock edge while its chip select lasts, and the WonderTANG
  front‑end delays `/WR` by 83 ns (to align it with the multiplexed address) but
  not the data: given the whole bus cycle, `jtopl` can still be writing when the
  MSX has already released the data bus (`FFh`) — in simulation, for some of the
  phases of the MSX clock against the FPGA's, as the index or as the data. So
  `jtopl` gets a two‑cycle pulse with the data and A0 latched on the first cycle,
  and the ADPCM part the usual one‑cycle strobe. The length of `/WR` and the
  moment the MSX releases the data bus do not matter.
- **Reads of `C1h`** produce one pulse per `IN`, so the side effects of register
  0Fh happen once. The pulse comes from the unregistered inputs, one cycle before
  the registered stage: the `C1h` data is ready from the first cycle of the read,
  like `C0h` and the OPL4 ports.
- **Status** (`C0h`): `(raw & (87h | mask)) | 06h` — `06h` after a reset. Buffer
  ready is 1 after a reset and is re‑armed by every write to register 04h.
- **IRQ**: timer 1, timer 2, end of sample and buffer ready, each masked by
  register 04h, all masked after a reset. Active low, ANDed with the OPL3's into
  `/INT`, behind the bus‑alive guard.
- **Write rate.** `jtopl` needs about 23 µs between data writes to the operator
  and channel registers (20h and up), what the real Y8950 asks for (84 cycles).

Cost, Gowin 1.9.12.03, WonderTANG without HDMI:

| | Without MSX‑Audio | With MSX‑Audio |
|---|---|---|
| Logic | 8 717 (43 %) | 11 225 (55 %) |
| CLS | 6 244 (61 %) | 8 444 (82 %) |
| Registers | 4 823 | 7 520 |
| BSRAM | 15 / 46 | 17 / 46 |
| DSP | 1.5 | 3.5 |
| Global clock nets (PRIMARY) | 8 / 8 | 8 / 8, the same ones |
| Setup slack at 108 / 54 MHz | 3.17 / 8.31 ns | 2.06 / 6.31 ns |
| Setup / hold violations | 0 / 0 | 0 / 0 |

The experimental WonderTANG bitstream with HDMI **and** the MSX‑Audio, against the
HDMI one:

| | HDMI | HDMI + MSX‑Audio (experimental) |
|---|---|---|
| Logic | 11 330 (55 %) | 14 056 (68 %) |
| CLS | 7 838 (76 %) | 9 322 (90 %) |
| Registers | 5 881 | 8 674 |
| BSRAM | 16 / 46 | 18 / 46 |
| DSP | 1.5 | 3.5 |
| Global clock nets (PRIMARY) | 8 / 8 | 8 / 8, the same ones |
| Setup slack at 108 MHz | 1.44 ns | 2.75 ns (1.2 ns or more in all 6 builds tried) |
| Setup / hold violations | 0 / 0 | 0 / 0 |

At 90 % of the CLS it is full; [WONDERTANG.md](WONDERTANG.md#experimental-hdmi-and-msx-audio-together)
says what that means for the SDRAM interface, which no `.sdc` constrains.
