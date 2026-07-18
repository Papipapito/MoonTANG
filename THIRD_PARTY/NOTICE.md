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

## 3. YMF278B PCM/wavetable engine — BSD‑3‑Clause + author permission

`fpga/opl4wave/ymf278b_gowin.v` (generated from srg320's `YMF278B.sv`).

- Origin: **srg320**, *Arcade‑PsikyoSH2_MiSTer* (`rtl/PSH2/YMF278B.sv`). srg320's
  upstream repository carries no LICENSE file, so the author's **explicit e‑mail
  permission of 2026‑07‑13 — "You can use the code in any form"** — is the basis
  for reuse and is recorded here and in the file header. (The original e‑mail is
  archived by the maintainer.)
- The engine derives from **MAME**'s `ymf278b.cpp`, which is **BSD‑3‑Clause**,
  copyright holders **R. Belmont, Olivier Galibert, hap**. That BSD‑3 license is
  preserved, as agreed with srg320:

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
> file header. If srg320 later adds a formal LICENSE to the upstream repo, this
> section should be updated to point at it.

## 4. MSX slot interface & SDRAM controller — © Takayuki Hara (non‑commercial)

`fpga/src/ip_sdram_tangnano20k_c.v` © **Takayuki Hara** (`t.hara` / hra1129),
from the *V9968 Cartridge* project. The per‑file header grants redistribution and
use provided the notice is kept and **the work is not sold or used commercially
without prior written permission**. Honor that clause. (t.hara's repository root
carries an MIT license; the stricter per‑file non‑commercial header is honored
here to be safe.)

## 5. Gowin rPLL IP

`fpga/clocks/pll_main.v`, `pll_eng.v` adapt Gowin Semiconductor's rPLL primitive
wrappers (vendor IP, conventionally redistributed in Tang Nano projects).

---

## Not distributed

- **YRW801** GM wave sample ROM (2 MB) — copyright Yamaha; **user‑supplied**,
  flashed at `FLASH_BASE`. Never committed to this repository.
