# MoonTANG 🌙

![MoonTANG 1.0 beta — overview](docs/img/moontang-1.0beta-overview.png)

> **Español.** MoonTANG es un cartucho MoonSound / MSX-Audio experimental para
> MSX basado en una Tang Nano 20K. Añade OPL4, muestras PCM, HDMI opcional y,
> según la versión, MSX-Audio.
>
> **English.** MoonTANG is an experimental MoonSound / MSX-Audio cartridge for
> MSX based on a Tang Nano 20K. It adds OPL4, PCM samples, optional HDMI and,
> depending on the build, MSX-Audio.

## ⚠️ BETA — use at your own risk / úsalo bajo tu responsabilidad

> **Español — aviso importante.** MoonTANG es hardware y firmware **beta y
> experimental**. Puede contener errores, producir comportamientos inesperados o
> no funcionar con tu equipo. Al cargar un bitstream o conectar el cartucho,
> aceptas el riesgo: los autores y colaboradores no se responsabilizan de daños,
> pérdidas de datos ni averías en el MSX, la WonderTANG, la Tang Nano, la fuente
> de alimentación o cualquier otro equipo. Prueba primero en SRAM, con el MSX
> apagado al conectar, y verifica siempre la alimentación y J3.
>
> **English — important notice.** MoonTANG is **beta, experimental** hardware
> and firmware. It may contain bugs, behave unexpectedly or fail to work with
> your equipment. By loading a bitstream or connecting the cartridge, you accept
> the risk: the authors and contributors accept no liability for damage, data
> loss or failure affecting the MSX, WonderTANG, Tang Nano, power supply or any
> other equipment. Test in SRAM first, connect it with the MSX powered off, and
> verify power and J3 before use.

## 1.0 beta: three WonderTANG versions / tres versiones WonderTANG

All three builds are for the **WonderTANG 2.02b only**.

| Bitstream | English | Español |
|---|---|---|
| [`moontang_wondertang202b_hdmi_1.0beta.fs`](bitstream/moontang_wondertang202b_hdmi_1.0beta.fs) | **OPL4 + HDMI.** MoonSound, stereo HDMI audio/video and mono sound into the MSX through `SOUNDIN`. Use this when you already own a real MSX-Audio. | **OPL4 + HDMI.** MoonSound, vídeo y audio HDMI estéreo y sonido mono hacia el MSX por `SOUNDIN`. Úsala si ya tienes un MSX-Audio real. |
| [`moontang_wondertang202b_hdmi_msxaudio_1.0beta.fs`](bitstream/moontang_wondertang202b_hdmi_msxaudio_1.0beta.fs) | **OPL4 + MSX-Audio + HDMI.** Everything together: MoonSound, Y8950 MSX-Audio and HDMI. It is the largest build (91 % CLS); test it in SRAM first. | **OPL4 + MSX-Audio + HDMI.** Todo junto: MoonSound, MSX-Audio Y8950 y HDMI. Es la versión más grande (91 % CLS); pruébala primero en SRAM. |
| [`moontang_wondertang202b_msxaudio_1.0beta.fs`](bitstream/moontang_wondertang202b_msxaudio_1.0beta.fs) | **OPL4 + MSX-Audio, no HDMI.** MoonSound plus Y8950 MSX-Audio, with sound through the MSX. | **OPL4 + MSX-Audio, sin HDMI.** MoonSound más MSX-Audio Y8950, con sonido por el propio MSX. |

### Before flashing / antes de grabar

- **YRW801:** program `yrw801.bin` separately at `0x200000`; it is not included
  for copyright reasons. Without it, FM works but the PCM wavetable is silent.
  **ES:** programa la YRW801 por separado en `0x200000`; sin ella funciona FM,
  pero no las muestras PCM.
- **SOUNDIN:** the WonderTANG sends its mono mix through the Tang I²S amplifier.
  **J3 must be soldered** to connect that amplifier to the MSX slot's `SOUNDIN`.
  **ES:** J3 debe estar soldado para que el audio llegue al `SOUNDIN` del MSX.
- **First test:** load the `.fs` into SRAM before writing external flash. It is
  lost at power-off, which makes recovery simple. **ES:** primero carga la
  imagen en SRAM; al apagar se recupera el firmware anterior.

---

**An experimental MoonSound (OPL4 / YMF278B) cartridge for MSX on a
[Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(Gowin GW2AR‑18).**

A full OPL4 — **18‑channel OPL3 FM + 24‑voice PCM wavetable** — in an FPGA cartridge
that plugs into a real MSX slot. It is a spin‑off of the OPL4 block of the
**MSXimus** core, kept in sync with it, running standalone.

On the WonderTANG there is also a bitstream that adds an **MSX‑Audio** (Y8950:
9‑channel FM + ADPCM with 256 KB of sample RAM) at ports `C0h–C1h`, next to the
MoonSound.

**Scope is deliberately narrow: a MoonSound (plus, optionally, an MSX‑Audio) and
nothing else.** No megaROM, no RAM expansion, no Nextor. If you want those, use
[tnCart](https://github.com/buppu3/tnCart) — this project borrows its bus front‑end.

## ⚠️ Experimental / experimental

**Español.** La versión HDMI normal funcionó diez minutos continuos de música
en una WonderTANG 2.02b después de la corrección de recuperación del PLL. Las
otras combinaciones han pasado simulación y compilación, pero siguen necesitando
pruebas en hardware. Si pruebas una, abre una incidencia con el resultado.

**English.** The plain HDMI build played ten continuous minutes of music on a
WonderTANG 2.02b after the PLL-recovery fix. The other combinations pass
simulation and implementation, but still need hardware testing. Please open an
issue with results, good or bad.

## Compatible hardware / hardware compatible

MoonTANG is documented and released for the
[**WonderTANG 2.02b**](https://github.com/lfantoniosi/WonderTANG), with its Tang
Nano 20K installed.

**Español.** MoonTANG está documentado y se distribuye únicamente para la
**WonderTANG 2.02b** con su Tang Nano 20K.

The Tang I²S amplifier carries the mono mix to the MSX through jumper J3 and
`SOUNDIN`; HDMI builds add stereo HDMI audio and the on-screen VU display in
parallel.

**Español.** El amplificador I²S de la Tang lleva la mezcla mono al MSX mediante
J3 y `SOUNDIN`; las versiones HDMI añaden en paralelo audio HDMI estéreo y el
indicador VU en pantalla.

## What to flash

| Step | File | Address | Tool |
|---|---|---|---|
| 1 | the `.fs` for **your** board (see [`bitstream/`](bitstream/)) | `0x000000` | [Gowin Programmer](https://www.gowinsemi.com/en/support/download_eda/) — External Flash mode |
| 2 | `yrw801.bin` — the 2 MB Yamaha YRW801 wave ROM, **not included** (copyright) | `0x200000` | Gowin Programmer — *exFlash C Bin Erase, Program thru GAO‑Bridge* |

FM works without the YRW801; the wavetable half stays silent until it is there.
The MSX‑Audio needs nothing more: its sample RAM is in the Tang's SDRAM.

## Building

Gowin toolchain 1.9.12.03 (`gw_sh`):

```sh
cd fpga
gw_sh build_wt_audio.tcl  # WonderTANG + MSX-Audio, without HDMI -> impl/pnr/moontang_wt_audio.fs
gw_sh build.tcl           # WonderTANG without HDMI   -> impl/pnr/moontang_wt.fs
gw_sh build_wt_hdmi.tcl   # WonderTANG with HDMI      -> impl/pnr/moontang_wt_hdmi.fs
gw_sh build_wt_hdmi_audio.tcl  # EXPERIMENTAL: WonderTANG with HDMI and MSX-Audio (see docs/WONDERTANG.md)
```

## Simulation

The whole design is simulated against a WonderTANG model wired **by FPGA pin
number**. Its pin table comes from the official WonderTANG firmware constraints, so
a wrong pin in our `.cst` shows up as a failing test. A Z80 bus model with real
timing drives it, with models of the SPI flash and of the embedded SDRAM.

```sh
# WSL / Linux with Icarus Verilog and sv2v
bash tools/sim/board/run_board.sh todo     # WonderTANG: the three bitstreams + negative controls
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
- **José Tejada** (`jotego`) — [**JTOPL**](https://github.com/jotego/jtopl) (the Y8950
  FM) and the ADPCM‑B decoder of [**JT12**](https://github.com/jotego/jt12), both
  GPL‑3.0, in the MSX‑Audio bitstreams.
- **Shinobu Hashimoto** (`buppu3`) — [**tnCart**](https://github.com/buppu3/tnCart)
  (BSD‑3), whose multiplexed slot front‑end the WonderTANG variant uses.
- **Albert Herranz** (`herraa1`) — [**tnCartWonder**](https://github.com/herraa1/tnCartWonder),
  the WonderTANG port, the `wt200b` board definition and the I2S transmitter.
- **luca / lfantoniosi** — the [**WonderTANG**](https://github.com/lfantoniosi/WonderTANG)
  cartridge (BSD‑2) and its authoritative pinout.
- **Sameer Puri** — [**hdl‑util/hdmi**](https://github.com/hdl-util/hdmi)
  (MIT / Apache‑2.0), the HDMI transmitter with audio.
- **Takayuki Hara** (`t.hara` / hra1129) — the `ip_sdram` controller from the V9968
  cartridge project.
- **Dan Gisselquist** — the async FIFO (`afifo.v`, GPL‑3.0) in the FM host interface.
- **Gowin Semiconductor** — the rPLL / CLKDIV / OSER10 primitives.

And **Claude** (Anthropic) — co‑author of this port: the standalone integration,
clocking, SDRAM bridge, loader, mixer, VU meter, MSX‑Audio integration, constraints
and testbenches were written in pair‑programming with Claude. See commit trailers.

## License

**GPL‑3.0** (see [`LICENSE`](LICENSE)). The gateware links LGPL‑3.0 and GPL‑3.0
components, so the combined work is GPL‑3.0. Per‑file headers and
[`THIRD_PARTY/NOTICE.md`](THIRD_PARTY/NOTICE.md) carry the upstream notices — keep
them intact. Some vendored files carry a non‑commercial clause; this is a hobby,
non‑commercial release. Do not sell the combined work.

---

*MoonTANG is a fan project, not affiliated with Yamaha. "MoonSound" and MSX are
referenced for interoperability only.*
