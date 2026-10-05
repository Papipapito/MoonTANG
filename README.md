# MoonTANG 🌙

**An experimental MoonSound (OPL4 / YMF278B) cartridge for MSX on a
[Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(Gowin GW2AR‑18).**

A full OPL4 — **18‑channel OPL3 FM + 24‑voice PCM wavetable** — in an FPGA cartridge
that plugs into a real MSX slot. It is a spin‑off of the OPL4 block of the
**MSXimus** core, kept in sync with it, running standalone.

**Scope is deliberately narrow: a MoonSound and nothing else.** No megaROM, no RAM
expansion, no Nextor. If you want those, use
[tnCart](https://github.com/buppu3/tnCart) — this project borrows its bus front‑end.

## ⚠️ Experimental — not yet run on hardware

Both variants build to a clean, timing‑closed bitstream and pass a board‑level
simulation, but **neither has been tested on a real machine**. If you build one,
please open an issue with the result — good or bad.

## Two boards

| | [WonderTANG 2.0b / 2.02b](https://github.com/lfantoniosi/WonderTANG) | MSXhdmi_tn20k_smd (rev B) |
|---|---|---|
| MSX bus | multiplexed | direct |
| Sound output | **the MSX's own audio** (mono), through the Tang's amplifier and jumper J3 to `SOUNDIN` — and, at the same time, **HDMI** (stereo) with a VU meter on screen | **HDMI** (stereo), with a VU meter on screen |
| `/INT`, `/WAIT`, `/BUSDIR` | yes | **not routed on that PCB** — see the limits below |
| Bitstream | `moontang_wondertang202b_hdmi_*.fs`, or `moontang_wondertang202b_*.fs` without the HDMI output | `moontang_smd_*.fs` |
| Build script | `fpga/build_wt_hdmi.tcl` (with HDMI), `fpga/build.tcl` (without) | `fpga/build_smd.tcl` |
| Guide | [`docs/WONDERTANG.md`](docs/WONDERTANG.md) | [`docs/SMD.md`](docs/SMD.md) |

**A bitstream for one board must never be flashed on the other**: the pins do not
match and the outputs would fight the bus buffers.

### Limits of the MSXhdmi_tn20k_smd board

The MSXhdmi_tn20k_smd board was designed as a video cartridge. Three slot lines a
MoonSound uses are not connected to the FPGA, so on that board:

- **no `/INT`** — software that waits for the OPL4 timer interrupt does not get it
  (VGMPlay on anything but a turbo R plays far too slowly);
- **no `/BUSDIR`** — on machines that need it to read I/O ports from a cartridge,
  the MoonSound is not detected;
- **no `/WAIT`** — use the MSX at its normal 3.58 MHz speed.

[`docs/SMD.md`](docs/SMD.md) has the details and what a board revision would need.

## What to flash

| Step | File | Address | Tool |
|---|---|---|---|
| 1 | the `.fs` for **your** board (see [`bitstream/`](bitstream/)) | `0x000000` | [Gowin Programmer](https://www.gowinsemi.com/en/support/download_eda/) — External Flash mode |
| 2 | `yrw801.bin` — the 2 MB Yamaha YRW801 wave ROM, **not included** (copyright) | `0x200000` | Gowin Programmer — *exFlash C Bin Erase, Program thru GAO‑Bridge* |

FM works without the YRW801; the wavetable half stays silent until it is there.

## Building

Gowin toolchain 1.9.12.03 (`gw_sh`):

```sh
cd fpga
gw_sh build_wt_hdmi.tcl   # WonderTANG with HDMI      -> impl/pnr/moontang_wt_hdmi.fs
gw_sh build.tcl           # WonderTANG without HDMI   -> impl/pnr/moontang_wt.fs
gw_sh build_smd.tcl       # MSXhdmi_tn20k_smd board   -> impl/pnr/moontang_smd.fs
```

## Simulation

The whole design is simulated against a model of each board, wired **by FPGA pin
number**: the pin table of each model comes from the real artefact (the official
WonderTANG firmware constraints; the KiCad PCB of the HDMI board), so a wrong pin in
our `.cst` shows up as a failing test. A Z80 bus model with real timing drives it,
with models of the SPI flash and of the embedded SDRAM.

```sh
# WSL / Linux with Icarus Verilog and sv2v
bash tools/sim/board/run_board.sh todo     # WonderTANG, with and without HDMI, + negative controls
bash tools/sim/board_smd/run_smd.sh        # MSXhdmi_tn20k_smd: bus, memory, HDMI audio, VU meter
```

See [`docs/VERIFICATION.md`](docs/VERIFICATION.md) for what is and is not covered.

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
  (BSD‑3), whose multiplexed slot front‑end the WonderTANG variant uses.
- **Albert Herranz** (`herraa1`) — [**tnCartWonder**](https://github.com/herraa1/tnCartWonder),
  the WonderTANG port, the `wt200b` board definition and the I2S transmitter.
- **luca / lfantoniosi** — the [**WonderTANG**](https://github.com/lfantoniosi/WonderTANG)
  cartridge (BSD‑2) and its authoritative pinout.
- **Javier Abadia** (`jabadiagm`) — the MSXhdmi / Asgard cartridge the HDMI board
  derives from; its pinout and the way its firmware turns the data bus around.
- **Sameer Puri** — [**hdl‑util/hdmi**](https://github.com/hdl-util/hdmi)
  (MIT / Apache‑2.0), the HDMI transmitter with audio.
- **Takayuki Hara** (`t.hara` / hra1129) — the `ip_sdram` controller from the V9968
  cartridge project.
- **Dan Gisselquist** — the async FIFO (`afifo.v`, GPL‑3.0) in the FM host interface.
- **Gowin Semiconductor** — the rPLL / CLKDIV / OSER10 primitives.

And **Claude** (Anthropic) — co‑author of this port: the standalone integration,
clocking, SDRAM bridge, loader, mixer, VU meter, constraints and testbenches were
written in pair‑programming with Claude. See commit trailers.

## License

**GPL‑3.0** (see [`LICENSE`](LICENSE)). The gateware links LGPL‑3.0 and GPL‑3.0
components, so the combined work is GPL‑3.0. Per‑file headers and
[`THIRD_PARTY/NOTICE.md`](THIRD_PARTY/NOTICE.md) carry the upstream notices — keep
them intact. Some vendored files carry a non‑commercial clause; this is a hobby,
non‑commercial release. Do not sell the combined work.

---

*MoonTANG is a fan project, not affiliated with Yamaha. "MoonSound" and MSX are
referenced for interoperability only.*
