# Credits & third‑party inventory

MoonTANG is an integration of open work by many authors. This file lists every
upstream component in the builds — the MSX‑Audio bitstream included — its
author/project, and its license. Per‑file headers are authoritative; keep them
intact.

| Component | Files | Author / Project | License |
|---|---|---|---|
| **OPL3 FM core** | `fpga/opl3/*.sv` | **Greg Taylor** (`gtaylormb`, *OPL3 FPGA*); algorithm origins **R. Cozendey**, **S. Ohrendorf**, **Nuke.YKT**, carbon14/"opl3" | LGPL‑3.0‑or‑later |
| OPL3 package (clock retune) | `fpga/opl3/opl3_pkg.sv` | Greg Taylor; mods **Jokin Miragaia** (`antxiko`, *mangOPL4*) | LGPL‑3.0 |
| Async FIFO (FM host_if) | `fpga/opl3/afifo.v` | **Dan Gisselquist** (Gisselquist Technology) | GPL‑3.0 |
| **PCM / wavetable engine** | `fpga/opl4wave/ymf278b_gowin.v` | **srg320** (*Arcade‑PsikyoSH2_MiSTer*), from **MAME** `ymf278b.cpp` (**R. Belmont, O. Galibert, hap**) | BSD‑3‑Clause (srg320 upstream header, see `THIRD_PARTY/NOTICE.md`) |
| FM cartridge wrapper | `fpga/src/opl4fm.v` | derived from `cartridge_opl3.sv` of *mangOPL4* © 2026 **Jokin Miragaia** (`antxiko`); MSXimus/MoonTANG changes (shadow registers, status on `C4h`/`C6h`, `7Eh`/`7Fh` stub, 54 MHz bus) by Papipapito (Albert, with Claude) | BSD‑3‑Clause (original notice kept in the header, see `THIRD_PARTY/NOTICE.md`); changes GPL‑3.0 |
| PCM glue | `fpga/src/opl4_pcm.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| Wave‑in‑SDRAM arbiter | `fpga/src/wave_sdram.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| **Y8950 FM** (MSX‑Audio bitstreams) | `fpga/y8950/jtopl/*.v` | **José Tejada** (`jotego`) — [*JTOPL*](https://github.com/jotego/jtopl); copy carried by the MSXimus (shift registers kept in flip‑flops); simulation‑only initial values added by MoonTANG, marked in the files | GPL‑3.0‑or‑later (`fpga/y8950/jtopl/LICENSE`) |
| **ADPCM‑B decoder** (MSX‑Audio bitstreams) | `fpga/y8950/jt10/jt10_adpcmb.v`, `jt10_adpcmb_interpol.v`, `jt10_adpcm_div.v` | **José Tejada** (`jotego`) — [*JT12*](https://github.com/jotego/jt12) | GPL‑3.0‑or‑later (`fpga/y8950/jt10/LICENSE`) |
| Y8950 ADPCM registers and sample RAM in SDRAM | `fpga/y8950/y8950_adpcm.v`, `fpga/y8950/adpcm_sdram.v` | Papipapito (Albert, with Claude) — from the **MSXimus** core, unchanged; register behaviour modelled on **openMSX**'s Y8950 | GPL‑3.0 |
| MSX‑Audio glue and mixer | `fpga/src/moontang_y8950.sv`, `fpga/src/moontang_mix_y8950.v` | Papipapito (Albert, with Claude); the limiter is the MSXimus one | GPL‑3.0 |
| **SDRAM controller** | `fpga/src/ip_sdram_tangnano20k_c.v` | **Takayuki Hara** (`t.hara` / hra1129) — *V9968 Cartridge* | non‑commercial (per header) / MIT (repo root) |
| Wave→SDRAM bridge | `fpga/src/wv_to_sdram.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| **MSX slot bus front‑end** (multiplexed) | `fpga/wondertang/bus.sv`, `fpga/wondertang/wt_bus.sv` | **Shinobu Hashimoto** (`buppu3`) — *tnCart*; port by **Albert Herranz** (`herraa1`) — *tnCartWonder* | BSD‑3‑Clause |
| **I2S transmitter** | `fpga/wondertang/i2s_audio_tx.sv` | **Albert Herranz** (`herraa1`) | BSD‑3‑Clause |
| **Board pinout (WonderTANG 2.0b / 2.02b)** | `fpga/constraints/moontang.cst`, `moontang_wt_hdmi.cst` | derived from **lfantoniosi** *WonderTANG* `fpga/src/top.cst` + `board_wt200b.cst` (herraa1) | BSD‑2 / BSD‑3 |
| **HDMI transmitter with audio** | `fpga/hdmi/*.sv` | **Sameer Puri** — *hdl‑util/hdmi*; Gowin OSER10 serializer branch and `aspect_16_9` input as carried in the Tang Nano 20K MSX projects | MIT OR Apache‑2.0 |
| **Board pinout (MSXhdmi_tn20k_smd)** | `fpga/constraints/moontang_smd.cst` | pinout of **Javier Abadia**'s (`jabadiagm`) MSXhdmi / Asgard cartridge, checked against the KiCad PCB of the SMD board | — |
| Direct bus front‑end (HDMI board) | `fpga/src/smd_bus.v` | Papipapito (Albert, with Claude); data‑buffer turnaround timing after jabadiagm's Asgard `slave_bus.v` | GPL‑3.0 |
| VU meter and screen | `fpga/src/vu_meter.v`, `vu_screen.v`, `font8x8.v` | Papipapito (Albert, with Claude); the 8x8 font is the clean‑room one from SlotDoctor | GPL‑3.0 |
| I2S sample hand‑off | `fpga/src/i2s_feed.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| SPI flash reader | `fpga/src/flash_rw.v` | derived from `fpga/src/flash.v` of *WonderTANG* © 2023 **lfantoniosi**; write path (erase, page program, status polling with timeout) added by Papipapito (Albert, with Claude) | BSD‑2‑Clause (original notice kept in the header, see `THIRD_PARTY/NOTICE.md`); changes GPL‑3.0 |
| YRW801 loader | `fpga/src/yrw801_loader.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| MoonSound core, board shells and tops | `fpga/src/moontang_core.sv`, `moontang_wt_shell.sv`, `moontang_top.sv`, `moontang_wt_audio_top.sv`, `moontang_wt_hdmi_top.sv`, `moontang_wt_hdmi_audio_top.sv` (experimental), `moontang_smd_top.sv`, `moontang_av.sv` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| rPLL IP | `fpga/clocks/pll_main.v`, `pll_eng.v`, `pll_hdmi.v` | **Gowin Semiconductor** (tool IP, adapted) | vendor IP |

## Hardware / carrier

- **luca / lfantoniosi** — the **WonderTANG 2.0b / 2.02b** cartridge, and the
  authoritative `top.cst` pinout (BSD‑2). Note its KiCad netlist is stale (it still
  describes a Tang Nano 9K with a non‑multiplexed address bus) — `top.cst` and the
  schematic are the sources of truth.
- **Shinobu Hashimoto** (`buppu3`) and **Albert Herranz** (`herraa1`) — tnCart /
  tnCartWonder, including the `wt200b` board definition for this exact revision.
- **Javier Abadia** (`jabadiagm`) — the MSXhdmi / Asgard cartridge for the Tang
  Nano 20K. The HDMI variant runs on an SMD re‑layout of that board and follows the
  way his firmware turns the data buffer around.
- **Takayuki Hara** (hra1129) — the `ip_sdram` controller from the V9968 Cartridge.
- **Sipeed** — the Tang Nano 20K.

## Co‑authorship

This standalone port — the core and board tops, clocking, the SDRAM bridge, the
YRW801 loader, the audio mixer, the VU meter, the MSX‑Audio integration, the
constraints and the testbenches — was done by **Albert (Papipapito)** in
pair‑programming with **Claude (Anthropic)**, who is credited as co‑author in the
commit history (`Co-Authored-By` trailers).

## Licensing summary

Because `afifo.v` (GPL‑3.0) is linked with the LGPL‑3.0 OPL3 core, the combined
gateware is **GPL‑3.0**; the MSX‑Audio bitstreams add jotego's JTOPL and JT12 files,
also GPL‑3.0‑or‑later. The t.hara carrier/SDRAM files carry a **non‑commercial**
clause — MoonTANG is a hobby, non‑commercial release; do not sell the combined
work. srg320's YMF278B engine is **BSD‑3‑Clause** (upstream header);
`opl4fm.v` keeps Jokin Miragaia's BSD‑3‑Clause notice and `flash_rw.v`
lfantoniosi's BSD‑2‑Clause one. The
**YRW801** GM sample ROM is **not distributed** (copyright); it is user‑supplied.
See [`THIRD_PARTY/NOTICE.md`](THIRD_PARTY/NOTICE.md) for the upstream notices.
