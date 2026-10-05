# MoonTANG — architecture

MoonTANG is a MoonSound cartridge as a pure **I/O peripheral**: OPL3 FM on ports
`C4h–C7h` and the 24‑voice PCM wavetable on `7Eh–7Fh`. It never uses `/SLTSL` or
the memory space.

The design is one **core** — the MoonSound itself — and one thin **shell** per
carrier board.

```
                    ┌───────────────────────── moontang_core ─────────────────────────┐
  bus (in clk_54m)  │  opl4fm ── OPL3 FM core (gtaylormb)                    27 MHz   │
  iorq/rd/wr/addr ─▶│     │                                                           │
  din / rd_data     │  opl4_pcm ── YMF278B PCM engine (srg320)              clk_eng   │
  wait_n / int_n  ◀─│     │                                                           │
                    │  wave_sdram ─▶ wv_to_sdram ─▶ ip_sdram ─▶ embedded SDRAM 108 MHz│
                    │     ▲                                                           │
                    │  yrw801_loader ◀─ flash_rw ◀─ SPI flash (YRW801 at 0x200000)    │
                    │                                                                 │
                    │  mixer: FM (register F8h attenuation) + wave  ─▶ L, R, mono     │
                    └─────────────────────────────────────────────────────────────────┘
        ▲                                                         │
        │                                                         ▼
  ┌─────┴──────────────────────────┐          ┌───────────────────────────────────────┐
  │ WonderTANG shell               │          │ WonderTANG: i2s_feed ▶ I2S ▶ Tang amp │
  │   WT200B_BUS (tnCart): scans   │          │   ▶ J3 ▶ SOUNDIN (mono)               │
  │   the multiplexed bus          │          ├───────────────────────────────────────┤
  ├────────────────────────────────┤          │ moontang_av (HDMI, both boards):      │
  │ MSXhdmi_tn20k_smd top          │          │   48 kHz stereo ▶ hdl‑util/hdmi       │
  │   smd_bus: direct bus + data   │          │   vu_meter ▶ vu_screen ▶ 720x480p     │
  │   buffer turnaround            │          └───────────────────────────────────────┘
  └────────────────────────────────┘
```

| File | Role |
|---|---|
| `src/moontang_core.sv` | the MoonSound: FM, PCM, wave memory chain, loader, mixer, bus‑alive guard |
| `src/moontang_wt_shell.sv` | WonderTANG 2.0b / 2.02b shell: bus scanner, core, I2S; the PCM engine clock comes from the top |
| `src/moontang_wt_hdmi_top.sv` | WonderTANG top **with** HDMI: shell + `moontang_av` |
| `src/moontang_top.sv` | WonderTANG top **without** HDMI: shell + a PLL for the PCM engine |
| `src/moontang_smd_top.sv` | MSXhdmi_tn20k_smd top: direct bus + core + `moontang_av` |
| `src/moontang_av.sv` | the HDMI output shared by both boards: stereo sound, VU meter, and the PCM engine clock |
| `src/opl4fm.v`, `opl3/*` | FM half; register shadow for read‑back; timer IRQ |
| `src/opl4_pcm.v`, `opl4wave/ymf278b_gowin.v` | PCM half: bus glue, fractional clock enable, sample cache, engine |
| `src/wave_sdram.v`, `wv_to_sdram.v`, `ip_sdram_tangnano20k_c.v` | wave memory: arbiter, byte‑to‑word bridge with refresh and watchdog, SDRAM controller |
| `src/yrw801_loader.v`, `flash_rw.v` | copy of the YRW801 from SPI flash to SDRAM at power‑up |
| `wondertang/*` | tnCart multiplexed bus front‑end and I2S transmitter; `src/i2s_feed.v` hands samples to it |
| `src/smd_bus.v` | direct bus front‑end for the HDMI board |
| `src/vu_meter.v`, `vu_screen.v`, `font8x8.v`, `hdmi/*` | level meters, their screen, HDMI transmitter (all inside `moontang_av`) |

The OPL4 files are the ones of the MSXimus (Zynq branch) and are kept in sync with
it. MoonTANG's own differences are confined to parameters of `opl4_pcm.v`: the
clock‑enable fraction of the PCM engine, the telemetry baud divisor, and the
optional read mirror (`RD_MIRROR`, off by default).

## Clocks

Everything derives from the Tang's 27 MHz crystal. The GW2AR‑18 has two PLLs.

| Clock | Without HDMI (WonderTANG) | With HDMI (both boards) | Used by |
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
only internal difference between the two WonderTANG bitstreams.

The PCM engine needs an average of 33.8688 MHz (44.1 kHz × 768). It gets it from a
fractional clock enable: 6272/6875 of 37.125 MHz, or 2744/3125 of 38.57 MHz.
The FM clock is derived from the PLL and not taken from the crystal pad: from the
pad its skew against the 54 MHz domain produced hold violations.

## Resets

- **Power‑on reset** follows PLL lock only. It covers the SDRAM, the loader and the
  wave memory chain, so the wave ROM **survives an MSX reset**.
- **Bus reset** follows the slot's `/RESET` and resets the chip logic.
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

## The VU meter (HDMI output)

`vu_meter` keeps the peak of each of six signals over a video frame and turns it
into 0–28 segments on a logarithmic scale of about 1.5 dB per segment, with a fast
rise, a decay of one segment every two frames and a peak marker. `vu_screen` draws
the bars and the texts directly from the pixel coordinates — there is no frame
buffer. The values only change during vertical blanking.

## Bus front‑ends

- **WonderTANG.** Address and control lines are multiplexed on eight pins behind
  three buffers. tnCart's scanner selects each group in turn at 108 MHz and filters
  every bit. `/WAIT` and `/INT` leave through inverting transistors.
- **HDMI board.** The bus is direct. Inputs go through a two‑stage synchroniser and
  a two‑sample filter. For a read, the data buffer is turned towards the MSX about
  130 ns after `/RD` and the FPGA starts driving one cycle later; both are released
  together within about 50 ns of `/RD` rising. Because that board has no `/WAIT`, the
  wave memory data and the device ID are answered from the bus side
  (`RD_MIRROR`).
