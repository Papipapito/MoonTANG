# MoonTANG 🌙

**An experimental MoonSound (OPL4 / YMF278B) cartridge for MSX, running on a
[Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(Gowin GW2AR‑18) in a [WonderTANG 2.0b](https://github.com/lfantoniosi/WonderTANG) carrier.**

MoonTANG puts a full OPL4 — **18‑channel OPL3 FM + 24‑slot PCM wavetable** — into an
FPGA cartridge that plugs into a real MSX slot, so any MSX2+ can gain MoonSound.
It is a spin‑off of the OPL4 block developed for the **MSXimus** (Tang Console 60K)
core, ported to run **standalone**.

**Scope is deliberately narrow: a MoonSound and nothing else.** No megaROM, no RAM
expansion, no Nextor, no V9990. If you want those, use
[tnCart](https://github.com/buppu3/tnCart) — it is excellent and this project
borrows its bus front‑end.

---

## ⚠️ EXPERIMENTAL — not yet run on hardware

**This has never been tested on a real machine.** It builds to a clean, timing‑closed
bitstream and the risky pieces are covered by simulation, but nothing has been
validated on a physical MSX yet. Treat everything below as *intended* behaviour.

Read [`docs/BRINGUP_PLAN.md`](docs/BRINGUP_PLAN.md) before powering it up. Highlights:

- **The YRW801 wave ROM is not included** (copyright). It is user‑supplied: 2 MB
  flashed at `0x200000`. FM works without it; the wavetable half stays silent
  until it is present.
- **/WAIT and /INT go through inverting 2N3904s that the WonderTANG 2.0b lacks base
  pulldowns for** (a documented board quirk). During the ~200 ms FPGA configuration
  window they can self‑assert. Verify with a scope on cold boot, or fit the pulldowns.
- **SDRAM clock phase** (`PSDA_SEL` in `fpga/clocks/pll_main.v`) is a tuning point:
  sweep `0110 / 1000 / 1010` and pick by loader checksum, not by ear. Each value
  needs its own bitstream — it is a `defparam`, not a runtime knob.

If you build one, **please open an issue with results** — good or bad.

---

## What it does

| Feature | Ports | Status |
|---|---|---|
| OPL3 FM (YMF262), 18 ch | `C4h–C7h` | RTL validated in hardware on MSXimus |
| PCM wavetable, 24 slots, YRW801 in SDRAM | `7Eh–7Fh` | RTL ported; needs bring‑up |
| Register read‑back / status / device‑ID detection | `C4h–C7h`, `7Fh` | implemented |
| Timer IRQ to the MSX (`/INT`) | — | wired (inverted for the 2.0b NPN) |
| Stereo audio via the board's **I2S DAC + headphone jack** | — | verified in simulation |

Audio comes out of the WonderTANG's own I2S DAC and headphone amplifier — which is
faithful to the real MoonSound, that also has its own stereo jack rather than
feeding the MSX's `SOUNDIN`.

## Resource usage (GW2AR‑18C)

The whole cartridge — OPL4 FM + PCM engine + SDRAM controller + YRW801 loader +
mixer + I2S + the multiplexed slot front‑end:

```
Logic  10908 / 20736   53 %
CLS     6693 / 10368   65 %
BSRAM      2 / 46       5 %
DSP        3 MULT18X18  7 %

Setup violated endpoints: 0
Hold  violated endpoints: 3   (FF->RAM inside clk_eng: the chip's documented floor)
```

## Architecture

```
   MSX slot (bus MULTIPLEXED by the WonderTANG)
   cd[7:0] · mp[7:0] · msel_n[2:0] · datadir · rd/wr/sltsl/wait/int/busdir
        │
        ▼
   WT200B_BUS  ── 9-state scanner @108 MHz + PIN_FILTER ──▶ BUS_IF (ADDR[15:0], IORQ_n, …)
        │                                        (tnCart, BSD-3)
        ▼ (registered into clk_54m)
   ┌──────────┐   C4-C7   ┌───────────┐
   │ opl4fm   │◀─────────▶│ OPL3 FM   │
   └────┬─────┘           └───────────┘
   ┌────▼─────┐   7E-7F                    (clk_eng 37.125 MHz)
   │ opl4_pcm │────── mem_* ──▶ wave_sdram ──▶ wv_to_sdram ──▶ ip_sdram ──▶ SDRAM (4 MB wave)
   └────┬─────┘                     ▲
        │                    yrw801_loader ◀── flash_rw ◀── SPI flash (YRW801 @0x200000)
        ▼
   FM + wave L/R ──▶ saturating mixer ──▶ I2S_AUDIO_TX ──▶ DAC + headphone jack
```

**Clocks** (all from the 27 MHz crystal): bus/SDRAM 108 MHz, host 54 MHz,
FM 27 MHz (`CLKDIV /4` off the PLL — *not* the crystal pad, which cost 77 hold
violations), PCM engine 37.125 MHz, I2S 1.542 MHz.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full walk‑through.

## Building

Requires the Gowin toolchain (`gw_sh`). Verified with **1.9.11.03 Education** and
**1.9.12.03 Standard** — both produce a clean build on this device (the SSRAM
inference regression of the 1.9.12 line only affects Arora‑V / GW5AT‑60B, not the
GW2AR‑18).

```sh
cd fpga
gw_sh build.tcl
# -> impl/pnr/project.fs
```

## Simulation

The two pieces with no hardware precedent are covered, using Icarus Verilog:

```sh
# stereo I2S: channel assignment and bit alignment
iverilog -g2012 -o /tmp/tb_i2s tools/sim/tb_i2s.v fpga/wondertang/i2s_audio_tx.sv && vvp /tmp/tb_i2s

# YRW801 loader against the REAL flash_rw plus an SPI flash model serving a ramp
iverilog -g2012 -o /tmp/tb tools/sim/tb_loader_real.v tools/sim/spi_flash_model.v \
    fpga/src/yrw801_loader.v fpga/src/flash_rw.v && vvp /tmp/tb
```

Both pass. The loader test was checked against a **negative control** — the previous
buggy handshake reintroduced on purpose — and it catches it with the predicted
symptom (every byte written twice). A test that cannot fail proves nothing.

## Credits & thanks

MoonTANG is a thin integration on top of excellent open work. See
[`CREDITS.md`](CREDITS.md) and [`THIRD_PARTY/`](THIRD_PARTY/) for the full inventory.

- **Greg Taylor** (`gtaylormb`) — the [OPL3 FPGA](https://github.com/gtaylormb/opl3_fpga)
  core (LGPL‑3.0), the FM half; built on reverse‑engineering by **Robson Cozendey**,
  **Steffen Ohrendorf** and **Nuke.YKT**.
- **Jokin Miragaia** (`antxiko`) — the **mangOPL4** fork with the Gowin fixes and the
  MoonSound cartridge wrapper we adapted.
- **srg320** — the **YMF278B** PCM/wavetable engine (BSD‑3‑Clause), the first open RTL
  of the OPL4 wavetable, derived from **MAME**'s `ymf278b.cpp` by **R. Belmont,
  Olivier Galibert and hap**.
- **Shinobu Hashimoto** (`buppu3`) — [**tnCart**](https://github.com/buppu3/tnCart)
  (BSD‑3), whose MSX bus interface and multiplexed slot front‑end MoonTANG uses.
- **Albert Herranz** (`herraa1`) — [**tnCartWonder**](https://github.com/herraa1/tnCartWonder),
  the WonderTANG port, the `wt200b` board definition and the I2S transmitter.
- **luca / lfantoniosi** — the [**WonderTANG**](https://github.com/lfantoniosi/WonderTANG)
  cartridge (BSD‑2) and its authoritative pinout.
- **Takayuki Hara** (`t.hara` / hra1129) — the `ip_sdram` controller from the V9968
  cartridge project.
- **Dan Gisselquist** — the async FIFO (`afifo.v`, GPL‑3.0) in the FM host interface.
- **Gowin Semiconductor** — the rPLL / CLKDIV primitives.

And **Claude** (Anthropic) — co‑author of this port: the standalone integration,
clocking, SDRAM bridge, loader, mixer, constraints and testbenches were written in
pair‑programming with Claude. See commit trailers.

## License

**GPL‑3.0** (see [`LICENSE`](LICENSE)). The gateware links LGPL‑3.0 and GPL‑3.0
components, so the combined work is GPL‑3.0. Per‑file headers and
[`THIRD_PARTY/NOTICE.md`](THIRD_PARTY/NOTICE.md) carry the upstream notices — keep
them intact. Some vendored files carry a non‑commercial clause; this is a hobby,
non‑commercial release. Do not sell the combined work.

---

*MoonTANG is a fan project, not affiliated with Yamaha. "MoonSound" and MSX are
referenced for interoperability only.*
