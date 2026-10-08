# First tests on a real MSX

MSX‑BASIC programs for the first session with the cartridge. Each one prints what
it read and a verdict (`OK` / `FALLO`). Load them with `LOAD "MT1DET.ASC",R`.

Run them at **3.58 MHz**, once the LED is on (or the HDMI screen says
`YRW801 OK`), in this order:

| Program | Checks |
|---|---|
| `mt1det` | Detection: the four FM ports answer, FM registers read back, NEW2, wave ID (register 02h = 20h) |
| `mt2fm` | An FM sine at 440 Hz (check it with a tuner), a scale, and left/right panning (heard on HDMI only) |
| `mt3tmr` | OPL3 timers by polling, with interrupts off |
| `mt3int` | The timer 1 interrupt through `/INT` (WonderTANG only). Run it only if `mt3tmr` passed |
| `mt4yrw` | The YRW801 in SDRAM: header of wave 0, a text block and the version at the end. **Run it again after every flash** |
| `mt5ram` | Write and read back the sample RAM (200000h–3FFFFFh) |
| `mt6pcm` | A PCM note with wave 0 of the YRW801 |
| `mt7aud` | MSX‑Audio (Y8950 at C0h–C1h, MSX‑Audio bitstream only; with another one it says there is no MSX‑Audio and stops): status 06h, timers by polling with interrupts off, an FM note at 440 Hz, 256 ADPCM bytes written and read back, one pass up to EOS and a beep at 880 Hz, the 256 KB of sample RAM, and that it does not touch the OPL4 |
| `MTVOL.COM` | MSX-DOS utility: native OPL4 attenuation for its FM or Wave output; it uses no MoonTANG-specific I/O port |

## MTVOL.COM / Control de nivel

`MTVOL.COM` is deliberately limited to the **native** YMF278B mixer. It writes
register `F8h` (FM) or `F9h` (Wave) through the established Wave ports
`7Eh`/`7Fh`; there is no custom port, resident driver, or FPGA image change.
It sets the same attenuation on left and right.

Compile it with [SjASMPlus](https://github.com/z00m128/sjasmplus):

```powershell
.\build_mtvol.ps1
```

Then copy `MTVOL.COM` to a DOS disk and run one of the following:

```text
MTVOL
MTVOL FM 9
MTVOL WAVE 6
MTVOL FM M
```

With no arguments it reads and reports the current independent left/right FM
and Wave levels. The number is the human volume scale: `0`, `3`, `6`, `9`,
`12`, `15` or `18`. `0` is the lowest numeric level (−18 dB), `18` is the
maximum (0 dB), and `M` mutes. The setting applies immediately, but software
that writes `F8h`/`F9h` afterwards (or a reset) can replace it.

`MTVOL.COM` queda limitado deliberadamente al mezclador **nativo** del YMF278B.
Escribe `F8h` (FM) o `F9h` (Wave) a través de los puertos Wave ya establecidos,
`7Eh`/`7Fh`: no añade un puerto propio, un residente ni exige otro bitstream.
Aplica la misma atenuación a los dos canales. Los valores posibles son
`0`, `3`, `6`, `9`, `12`, `15`, `18` o `M` para silenciar. Sin argumentos,
`MTVOL` lee y muestra por separado los valores actuales izquierdo/derecho de
FM y Wave. La escala es humana: `0` es el mínimo numérico (−18 dB, un octavo
de amplitud) y `18` es el máximo (0 dB); `M` es silencio. El ajuste es
inmediato, pero un programa que vuelva a escribir `F8h`/`F9h` o un reset lo
reemplazará.

The expected values were checked against openMSX with a real MoonSound
(`moonsound` extension, YRW801 ROM), plus its MSX‑Audio for `mt7aud` (`audio`
extension, 256 KB).

Not to be used: the test programs of other OPL4 FPGA projects that start a timer
without masking it and without a handler hang the MSX through `/INT`, exactly
as a real MoonSound would; and those that access the wave memory without setting
register 02h bit 0 (memory mode) read nothing.

Then real software: VGMPlay twice in a row, leaving to DOS without a reset;
MoonBlaster Wave; a reset of the MSX followed by `mt4yrw` again. With the
MSX‑Audio bitstream, also VGMPlay with MSX‑Audio music and MoonBlaster 1.4: they
drive the chip directly and should work, but they have not been tried yet.
