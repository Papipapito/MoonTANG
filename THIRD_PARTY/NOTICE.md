# Third‑party notices

MoonTANG (GPL‑3.0) incorporates the components below. Their notices are
reproduced here as required by their licenses; the per‑file headers are
authoritative and must be kept intact in any redistribution.

---

## 1. OPL3 FPGA core — LGPL‑3.0‑or‑later

`fpga/opl3/*.sv` © **Greg Taylor** (`gtaylormb`), *OPL3 FPGA*, with clock‑retune
modifications © **Jokin Miragaia** (`antxiko`, *mangOPL4*). Algorithm origins:
Robson Cozendey, Steffen Ohrendorf, Nuke.YKT (Nuked‑OPL3), carbon14/"opl3".

Licensed under the GNU Lesser General Public License v3.0 or later. The LGPL is a
set of additional permissions on top of the GNU GPL v3 (see `../LICENSE`). Full
LGPL‑3.0 text: <https://www.gnu.org/licenses/lgpl-3.0.txt>.

## 2. Async FIFO — GPL‑3.0

`fpga/opl3/afifo.v` © **Dan Gisselquist, Ph.D.**, Gisselquist Technology, LLC.
Licensed GPL‑3.0 (see `../LICENSE`).

## 3. YMF278B PCM/wavetable engine — BSD‑3‑Clause

`fpga/opl4wave/ymf278b_gowin.v` (generated from srg320's `YMF278B.sv`).

- Origin: **srg320**, *Arcade‑PsikyoSH2_MiSTer* (`rtl/PSH2/YMF278B.sv`). srg320
  **licensed the file BSD‑3‑Clause** — the current upstream source header (commit
  `5379b34b`, 2026‑07‑14) reads:
  `//license:BSD-3-Clause (PCM engine derived from MAME's ymf278b)`. This
  supersedes the earlier e‑mail permission (2026‑07‑13); the file is now covered
  by a formal open‑source license.
- The engine derives from **MAME**'s `ymf278b.cpp`, which is **BSD‑3‑Clause**,
  copyright holders **R. Belmont, Olivier Galibert, hap**. The BSD‑3 text:

```
Copyright the MAME team (R. Belmont, Olivier Galibert, hap) and contributors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
  1. Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
  3. Neither the name of the copyright holder nor the names of its contributors
     may be used to endorse or promote products derived from this software
     without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DAMAGES ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE.
```

> **Note for redistributors:** if you fork MoonTANG, keep this notice and the
> BSD‑3‑Clause header. Upstream: <https://github.com/srg320/Arcade-PsikyoSH2_MiSTer>
> (`rtl/PSH2/YMF278B.sv`).

## 4. MSX slot interface & SDRAM controller — © Takayuki Hara (non‑commercial)

`fpga/src/ip_sdram_tangnano20k_c.v` © **Takayuki Hara** (`t.hara` / hra1129),
from the *V9968 Cartridge* project. The per‑file header grants redistribution and
use provided the notice is kept and **the work is not sold or used commercially
without prior written permission**. Honor that clause. (t.hara's repository root
carries an MIT license; the stricter per‑file non‑commercial header is honored
here to be safe.)

## 5. MSX slot bus front‑end and I2S — BSD‑3‑Clause

`fpga/wondertang/bus.sv` and `fpga/wondertang/wt_bus.sv` © **Shinobu Hashimoto**
(2024), from [tnCart](https://github.com/buppu3/tnCart), via **Albert Herranz**'s
WonderTANG port [tnCartWonder](https://github.com/herraa1/tnCartWonder).
`fpga/wondertang/i2s_audio_tx.sv` © **Albert Herranz** (2024). Both BSD‑3‑Clause;
the full licence text is reproduced in each file header — keep it.

MoonTANG modifications to `wt_bus.sv` (originally `board_rev1_bus.sv`): the module
was renamed `WT200B_BUS` and two dependencies on tnCart's `CONFIG`/`BOARD_ID`
packages were removed by fixing the board to WonderTANG 2.0b / 2.02b — the `/INT`
inversion takes the non‑101c branch, and the 21.6 MHz clock‑enable tap is fixed to
`delay_clk[0]` (the non‑IKASCC branch; MoonTANG has no SCC). Both changes are
marked in the file.

## 6. WonderTANG pinout — BSD‑2‑Clause

`fpga/constraints/moontang.cst` is derived from `fpga/src/top.cst` of
[lfantoniosi/WonderTANG](https://github.com/lfantoniosi/WonderTANG) (BSD‑2), which
is authoritative for the 2.0b board, cross‑checked against `board_wt200b.cst` from
tnCartWonder.

MoonTANG modification to `ip_sdram_tangnano20k_c.v`: a `bus_ready` output and a
`RD_CAPTURE_CLK` parameter that selects the clock edge on which read data is
captured (the original edge is the default of the module). Both are marked in the
file.

## 7. Gowin rPLL IP

`fpga/clocks/pll_main.v`, `pll_eng.v`, `pll_hdmi.v` adapt Gowin Semiconductor's rPLL
primitive wrappers (vendor IP, conventionally redistributed in Tang Nano projects).

## 8. HDMI transmitter — MIT OR Apache‑2.0

`fpga/hdmi/*.sv` are from [hdl‑util/hdmi](https://github.com/hdl-util/hdmi) by
**Sameer Puri** ("This project is dual‑licensed under MIT and Apache 2.0",
`SPDX-License-Identifier: MIT OR Apache-2.0`). The copy used here is the one
carried by the Tang Nano 20K MSX projects, which adds a Gowin `OSER10` branch to
`serializer.sv` and an `aspect_16_9` input that selects the 4:3 or 16:9 video
identification code. MoonTANG modification: the redundant redeclaration of the
`tmds_internal` port in `hdmi.sv` is commented out (marked in the file).

## 9. MSXhdmi_tn20k_smd pinout and bus turnaround

`fpga/constraints/moontang_smd.cst` follows the pinout of **Javier Abadia**'s
(`jabadiagm`) MSXhdmi / Asgard cartridge, verified against the KiCad PCB of the SMD
re‑layout. `fpga/src/smd_bus.v` is new code; the timing with which it turns the
data buffer around follows his Asgard `slave_bus.v`. No code of his is included.

---

## Not distributed

- **YRW801** GM wave sample ROM (2 MB) — copyright Yamaha; **user‑supplied**,
  flashed at `FLASH_BASE`. Never committed to this repository.
