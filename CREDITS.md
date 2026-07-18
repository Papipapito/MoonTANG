# Credits & third‑party inventory

MoonTANG is an integration of open work by many authors. This file lists every
upstream component in the **OPL4‑only** build, its author/project, and its
license. Per‑file headers are authoritative; keep them intact.

| Component | Files | Author / Project | License |
|---|---|---|---|
| **OPL3 FM core** | `fpga/opl3/*.sv` | **Greg Taylor** (`gtaylormb`, *OPL3 FPGA*); algorithm origins **R. Cozendey**, **S. Ohrendorf**, **Nuke.YKT**, carbon14/"opl3" | LGPL‑3.0‑or‑later |
| OPL3 package (clock retune) | `fpga/opl3/opl3_pkg.sv` | Greg Taylor; mods **Jokin Miragaia** (`antxiko`, *mangOPL4*) | LGPL‑3.0 |
| Async FIFO (FM host_if) | `fpga/opl3/afifo.v` | **Dan Gisselquist** (Gisselquist Technology) | GPL‑3.0 |
| **PCM / wavetable engine** | `fpga/opl4wave/ymf278b_gowin.v` | **srg320** (*Arcade‑PsikyoSH2_MiSTer*), from **MAME** `ymf278b.cpp` (**R. Belmont, O. Galibert, hap**) | BSD‑3‑Clause + author's e‑mail permission (see `THIRD_PARTY/NOTICE.md`) |
| FM cartridge wrapper | `fpga/src/opl4fm.v` | **Papipapito** (Albert, with Claude); adapts mangOPL4's `cartridge_opl3.sv` | GPL‑3.0 |
| PCM glue | `fpga/src/opl4_pcm.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| Wave‑in‑SDRAM arbiter | `fpga/src/wave_sdram.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| **SDRAM controller** | `fpga/src/ip_sdram_tangnano20k_c.v` | **Takayuki Hara** (`t.hara` / hra1129) — *V9968 Cartridge* | non‑commercial (per header) / MIT (repo root) |
| Wave→SDRAM bridge | `fpga/src/wv_to_sdram.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| SPI flash reader | `fpga/src/flash_rw.v` | Papipapito project | GPL‑3.0 |
| YRW801 loader | `fpga/src/yrw801_loader.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| Sigma‑delta DAC | `fpga/src/sigma_delta_dac.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| Cartridge top | `fpga/src/moontang_top.v` | Papipapito (Albert, with Claude) | GPL‑3.0 |
| rPLL IP | `fpga/clocks/pll_main.v`, `pll_eng.v` | **Gowin Semiconductor** (tool IP, adapted) | vendor IP |

## Hardware / carrier

- **luca / lfantoniosi** — the **WonderTANG** open cartridge (Tang Nano 20K in an
  MSX slot) this targets.
- **Takayuki Hara** (hra1129) — the **V9968 Cartridge** whose pinout, SDRAM
  controller and slot interface this build is modelled on.
- **Sipeed** — the Tang Nano 20K.

## Co‑authorship

This standalone port — the cartridge top, clocking, the SDRAM bridge, the YRW801
loader, the sigma‑delta DAC, the constraints and the bring‑up work — was done by
**Albert (Papipapito)** in pair‑programming with **Claude (Anthropic)**, who is
credited as co‑author in the commit history (`Co-Authored-By` trailers).

## Licensing summary

Because `afifo.v` (GPL‑3.0) is linked with the LGPL‑3.0 OPL3 core, the combined
gateware is **GPL‑3.0**. The t.hara carrier/SDRAM files carry a **non‑commercial**
clause — MoonTANG is a hobby, non‑commercial release; do not sell the combined
work. The **YRW801** GM sample ROM is **not distributed** (copyright); it is
user‑supplied. See [`THIRD_PARTY/NOTICE.md`](THIRD_PARTY/NOTICE.md) for the
upstream notices and the srg320 permission record.
