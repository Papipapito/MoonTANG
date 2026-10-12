# Discos de música que fallan en MoonTANG: Moonsound Music Collection 1 (MiG) y Musix Dizk 3 (Surrec)

Fecha: 11/10/2026. Base: `dc4b38d` (1.0.1 beta). Estado: **sin los discos todavía**. Los
sitios donde están (download.file-hunter.com, msx.org, archive.org) no son accesibles desde
la sesión en la nube donde se ha hecho esto. Lo que sigue es lo que se puede afirmar sin
ellos: en qué responde MoonTANG distinto que openMSX y cómo saber cuál de esas diferencias
toca cada disco.

## Los discos

- **Moonsound Music Collection 1** (MiG, Jer Der, 1996/97). MSX2 + MoonSound, música MWM
  (MoonBlaster Wave) y MFM (MoonBlaster FM). Freeware. En file-hunter:
  `Music/Music Discs/Moonsound Music Collection 1 (MiG) (1997).zip` (~260 kB).
- **Musix Dizk 3** (Surrec). Dominio público desde 2005. En file-hunter:
  `Music/Music Discs/Musix Dizk 3 (Surrec).zip` (~171 kB). No está confirmado qué chip usa:
  de la misma serie, *13 in een dozijn* (1998) es MoonSound, pero Musix 1-4 pueden ser
  MoonBlaster 1.4 (MSX-Audio / MSX-Music).

Ninguno de los dos puede usar una BIOS del MoonSound: el MoonSound original no tiene ROM.
Si "usan BIOS", solo puede ser la del **MSX-Audio** (MoonTANG no la tiene) o la del
**MSX-Music** (MoonTANG no tiene MSX-Music).

## Puertos

MoonTANG decodifica los del MoonSound original: `C4h–C7h` (FM) y `7Eh–7Fh` (wave), con
A0–A7 y `/M1` alto, y en los bitstreams `*_msxaudio_*` `C0h–C1h`. **No** decodifica
`C2h–C3h` (segundo MSX-Audio), `7Ch–7Dh` (MSX-Music) ni `0Ah` (DAC del Music Module).

## Diferencias con openMSX 19.1

Comparando `fpga/` con `MSXMoonSound.cc`, `YMF278.cc` y `YMF262.cc` de openMSX 19.1 (lo
marcado "verificado" lo está en el chip real según los comentarios de openMSX).

| # | Acceso | openMSX | MoonTANG | Dónde | Riesgo |
|---|---|---|---|---|---|
| 1 | `IN C6h` | estado, igual que `C4h` | **FFh** siempre hasta la 1.0.1beta; **corregido** en esta rama (12/10/2026) | `fpga/opl3/host_if.sv` | **alto** con un bitstream anterior si el programa espera BUSY/LD o detecta por `C6h` |
| 2 | `IN 7Fh` (ID, registros wave, RAM de muestras) | inmediato | ida y vuelta al motor (~0,5 µs) sostenida por `/WAIT`, ~70 ns de margen a 3,58 MHz | `opl4_pcm.v:253,277`; `RD_MIRROR = 0` en la WonderTANG | **alto** en turbo R (R800) o MSX con turbo |
| 3 | RAM de muestras | 640 kB por defecto (el MoonSound real: 128 kB–1 MB) | **2 MB planos** `200000h–3FFFFFh` | `wave_sdram.v`, `wv_to_sdram.v` | medio: detección de tamaño |
| 4 | Primeros ~2 s tras configurar la FPGA | — | motor PCM en reset: escrituras wave perdidas (NEW2 incluido), `7Fh` caducado | `moontang_core.sv` (copia de la YRW801) | medio si el disco arranca solo |
| 5 | `IN 7Eh` | FFh | estado `{LD,BUSY}` | `opl4_pcm.v:253` | bajo-medio |
| 6 | `IN 7Fh` con NEW2=0 | lee el registro (verificado) | ignora la lectura, dato caducado | `ymf278b_gowin.v:987` | medio |
| 7 | Escribir NEW2=0 | desactiva la parte wave | NEW2 no se borra hasta un reset | `ymf278b_gowin.v:997` | bajo |
| 8 | LD tras NEW2=1 | solo la primera vez tras el reset (verificado) | cada vez que se escribe NEW2=1 | `ymf278b_gowin.v:997` | bajo |
| 9 | Registro 02h, bit MT=1 | remapea la RAM | se ignora | `ymf278b_gowin.v` | bajo |
| 10 | Escribir 03h/04h | no mueve la dirección hasta 05h (verificado) | la mueve al momento | `ymf278b_gowin.v:1024` | bajo |
| 11 | Leer 03h–05h | lo escrito | la dirección viva, ya incrementada | `ymf278b_gowin.v:1072` | bajo |
| 12 | Registro 06h con MA=0 | lee FFh, ignora escrituras, no avanza (verificado) | lee el byte precargado, avanza; la escritura queda pendiente | `ymf278b_gowin.v:1037,1080` | bajo |
| 13 | FM banco 1 con NEW=0 | va al banco 0 | va al banco 1 | núcleo OPL3 | bajo |
| 14 | Timer 1 = FFh en marcha + 50 lecturas | normal | fuerza el desbordamiento (truco de detección de PC) | `trick_sw_detection.sv:81` | bajo-medio |
| 15 | MSX-Audio | — | sin BIOS, sin `C2h–C3h`, sin DAC `0Ah` ni MIDI | `moontang_y8950.sv` | **alto** si el disco busca la BIOS |

El propio `tools/msx/mt1det.asc` documenta la #1: espera `C4=00 C5=00 C6=FF C7=00`.

## Cómo saber cuál es

Con openMSX y el kit de [`tools/openmsx/`](../tools/openmsx/):

1. Prueba A/B/C del README: openMSX tal cual, con la RAM de MoonTANG (`-ext MoonTANG`) y
   además con un MSX-Audio sin BIOS (`-ext audio`). Si falla B o C, ya está aislado.
2. `check_trace.py` sobre el trazado lista las diferencias de la tabla que el disco toca
   de verdad, con el PC.
3. En el MSX real, lo que el emulador no imita: arrancar el disco con un reset cuando el
   LED esté fijo (#4) y, en un turbo R, en modo Z80 (#2).

## Arreglos preparados (sin aplicar)

Solo tienen sentido si el trazado lo confirma; los tres cambian el bitstream (Gowin).

- **#1, estado en `C6h`.** Hecho en esta rama (`fpga/opl3/host_if.sv`,
  `mt1det.asc` espera ahora `C6=00`). Pendiente de pasar al MSXimus (el fichero se
  comparte).
- **#2, lecturas de `7Fh` en turbo.** Pasar `.WAVE_RD_MIRROR(1)` a `moontang_core` en
  `fpga/src/moontang_wt_shell.sv`: los registros 02h (ID) y 06h (RAM) se sirven desde el
  dominio del bus sin esperar al motor, como ya hace la placa SMD. El `/WAIT` se mantiene.
- **#3, tamaño de RAM.** Un parámetro que limite la RAM visible (por ejemplo 1 MB, con
  espejo o FFh fuera), si la prueba B demuestra que el disco no acepta 2 MB.
