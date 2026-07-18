# MoonTANG 🌙

**An experimental MoonSound (OPL4 / YMF278B) cartridge for MSX, running on a
[Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(Gowin GW2AR‑18) inside a WonderTANG‑style carrier.**

MoonTANG puts a full OPL4 — **18‑channel OPL3 FM + 24‑slot PCM wavetable** — into
an FPGA that plugs into a real MSX I/O slot, so any MSX2+ can gain MoonSound. It
is a spin‑off of the OPL4 block developed for the **MSXimus** (Tang Console 60K)
core, ported to run **standalone** on a single Tang Nano 20K.

---

## ⚠️ EXPERIMENTAL — READ THIS FIRST

**This is a first, untested build. It has never run on real hardware.** It was
brought to the point of a **clean, timing‑closed `.fs` bitstream** as a starting
point for hardware bring‑up. Treat everything below as *intended* behaviour, not
*verified* behaviour.

Known open points that **must** be checked before / during bring‑up:

- **Pin mapping.** The constraints (`fpga/constraints/moontang.cst`) are derived
  from t.hara's **V9968 cartridge** carrier for the Tang Nano 20K. They **must be
  verified against the real WonderTANG schematic** before flashing — a wrong pin
  can drive the MSX bus incorrectly. Audio and flash pins are a *starting choice*.
- **Audio output routing.** Two 1‑bit sigma‑delta outputs (`audio_l`/`audio_r`,
  → RC low‑pass → jack, or to the slot `SOUND` pin). Where the WonderTANG exposes
  audio is a hardware detail to confirm.
- **YRW801 wave ROM.** The 2 MB GM sample ROM is **not included** (copyright). It
  is user‑supplied and must be flashed at `FLASH_BASE` (default `0x100000`). FM
  works without it; the PCM/wavetable half is silent until it is present.
- **SDRAM timing.** The embedded SDRAM controller (CAS latency, `clk_sdram`
  phase) uses conservative starting values — expect on‑hardware tuning.
- **`/M1` is not wired** on the carrier, so the chip treats every I/O cycle as
  non‑M1 (standard for I/O cartridges; MoonSound ports never collide with an
  interrupt‑ack vector in practice).

If you build hardware around this, **please open an issue with results** — good or
bad. That feedback is exactly what turns this from experimental into working.

---

## What works on paper

| Feature | Ports | Status |
|---|---|---|
| OPL3 FM (YMF262), 18 ch, MoonSound‑compatible | `C4h–C7h` | RTL from a HW‑validated core |
| PCM wavetable, 24 slots, YRW801 in SDRAM | `7Eh–7Fh` | RTL ported; needs HW bring‑up |
| Register read‑back / status / device‑ID detection | `C4h–C7h`, `7Fh` | implemented |
| Timer IRQ to the MSX (`/INT`) | — | wired |
| Stereo audio (sigma‑delta) | — | implemented, routing TBD |

**Not included:** Y8950/MSX‑Audio ADPCM (that's a *different* chip; a build with
it lands at ~90% of the FPGA and was deliberately left out — see the MSXimus,
which has it). MoonTANG is MoonSound‑only on purpose, to stay comfortably within
the 20K.

## Resource usage (GW2AR‑18C)

The **entire** cartridge — OPL4 FM + PCM engine + SDRAM controller + YRW801 loader
+ mixer + sigma‑delta DACs + slot bus glue — fits in:

```
Logic   10612 / 20736   52 %
CLS      6181 / 10368   60 %
BSRAM       3 / 46       7 %
DSP       3 MULT18X18    7 %
```

All four clock domains close timing with margin (FM 27→73 MHz, bus 54→114 MHz,
SDRAM 108→162 MHz, PCM motor 37.1→47.7 MHz). Plenty of head‑room left.

## Architecture

```
   MSX slot bus (I/O)                          Tang Nano 20K (GW2AR‑18)
  ┌───────────────┐   2FF   ┌─────────┐  C4‑C7 ┌──────────┐
  │ /IORQ /RD /WR │────────▶│  opl4fm │◀──────▶│ OPL3 FM  │
  │ A[7:0] D[7:0] │         └─────────┘        │  core    │
  │ /WAIT /INT    │◀── mux ─┐   7E‑7F ┌────────┴──────────┐
  └───────────────┘         └────────▶│  opl4_pcm (motor  │
     transceiver                      │  YMF278B srg320)  │
   (slot_data_dir)                    └──────┬────────────┘
                                    mem_* ◀──┘ (clk_eng 37.125 MHz)
                                        │
                    ┌───────────────────▼──────────────┐
   flash (YRW801) ─▶│ yrw801_loader ─▶ wave_sdram ─▶   │
                    │            wv_to_sdram ─▶ ip_sdram│──▶ embedded SDRAM (4 MB wave)
                    └───────────────────────────────────┘
             FM + wave L/R ─▶ saturating mixer ─▶ sigma‑delta DAC ─▶ audio
```

- **Clocks** (from the 27 MHz crystal): FM at 27 MHz (direct), bus 54 MHz, SDRAM
  108 MHz, PCM motor 37.125 MHz. See `fpga/clocks/`.
- **Memory path:** `wave_sdram` (the MSXimus arbiter) speaks its native `wv_*`
  port to a small bridge `wv_to_sdram`, which drives t.hara's proven `ip_sdram`
  controller (32‑bit, implicit embedded‑SDRAM pins).

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full walk‑through.

## Building

Requires the Gowin EDA toolchain (`gw_sh`). The open‑source flow is not used here
(rPLL + implicit SDRAM pins need the vendor tool).

```sh
cd fpga
gw_sh build.tcl
# -> impl/pnr/project.fs
```

A pre‑built (experimental) bitstream is in
[`bitstream/`](bitstream/). Flash it with `openFPGALoader` — but re‑read the
**EXPERIMENTAL** section first, and remember the YRW801 must be in flash for PCM.

## Credits & thanks

MoonTANG is a thin integration on top of excellent open work by others. Deep
thanks to all of them — see [`CREDITS.md`](CREDITS.md) for the full inventory and
[`THIRD_PARTY/`](THIRD_PARTY/) for upstream license texts.

- **Greg Taylor** (`gtaylormb`) — the [OPL3 FPGA](https://github.com/gtaylormb/opl3_fpga)
  core (LGPL‑3.0), the FM half. Built on the OPL3 reverse‑engineering of **Robson
  Cozendey**, **Steffen Ohrendorf**, **Nuke.YKT** (Nuked‑OPL3) and the carbon14 /
  "opl3" research.
- **Jokin Miragaia** (`antxiko`) — the **mangOPL4** fork whose Gowin fixes and
  MoonSound cartridge wrapper we adapted.
- **srg320** — the **YMF278B** PCM/wavetable engine (from Arcade‑PsikyoSH2_MiSTer),
  the first open RTL of the OPL4 wavetable, **licensed BSD‑3‑Clause** by the
  author; itself derived from **MAME**'s `ymf278b.cpp` by **R. Belmont,
  Olivier Galibert & hap** (BSD‑3‑Clause).
- **Takayuki Hara** (`t.hara` / hra1129 / HRA!) — the
  [V9968 Cartridge](https://github.com/hra1129) reference: the MSX slot interface,
  the `ip_sdram` controller and the Tang Nano 20K carrier this is modelled on.
- **Dan Gisselquist** — the async FIFO (`afifo.v`, GPL‑3.0) in the FM host path.
- **luca / lfantoniosi** — the **WonderTANG** cartridge that makes a Tang‑in‑a‑slot
  possible.
- **jotego** — JT cores lineage (ADPCM decoder used in the MSXimus sibling).
- **Gowin Semiconductor** — the rPLL IP primitives.

And **Claude** (Anthropic) — co‑author of this port: the standalone integration,
clocking, SDRAM bridge, loader, sigma‑delta DAC, constraints and bring‑up were
done in pair‑programming with Claude. See commit trailers.

## License

**GPL‑3.0** (see [`LICENSE`](LICENSE)). The gateware links LGPL‑3.0 and GPL‑3.0
components, so the combined work is GPL‑3.0. Per‑file headers and
[`THIRD_PARTY/`](THIRD_PARTY/) carry the authoritative upstream notices; keep them
intact. Some carrier/reference files (t.hara) carry a non‑commercial clause —
this is a hobby, non‑commercial release; do not sell the combined work.

---

*MoonTANG is a fan project, not affiliated with Yamaha. "MoonSound" and MSX are
referenced for interoperability only.*
