# Comparar software con MoonTANG en openMSX

Para averiguar por qué un programa que suena en openMSX (o en un MoonSound real)
no funciona en MoonTANG: se traza en openMSX todo lo que el programa hace con
los puertos de sonido y un script marca cada acceso en el que MoonTANG
responde distinto.

| Fichero | Qué es |
|---|---|
| `MoonTANG.xml` | Extensión: el MoonSound de openMSX con la RAM de muestras de MoonTANG, **2 MB planos** en `200000h–3FFFFFh` (openMSX trae 640 kB). Usa la misma `yrw801.rom` que la extensión `moonsound`. |
| `moontang_trace.tcl` | Trazador para la consola de openMSX: cada acceso a `7Eh–7Fh`, `C0h–C7h`, `7Ch–7Dh` y `0Ah` con tiempo, PC y valor; ráfagas de RAM de muestras resumidas; llamadas `RDSLT`/`CALSLT`/`ENASLT`/`EXTBIO` (búsqueda de BIOS); cambios Z80/R800; y un recuento de todos los demás puertos (salvo el VDP). |
| `check_trace.py` | Lee el trazado y lista, por gravedad, cada acceso en que MoonTANG difiere de openMSX, con la línea y el PC. |

## Instalación

- `MoonTANG.xml` → carpeta de extensiones de usuario de openMSX:
  - Windows: `%USERPROFILE%\Documents\openMSX\share\extensions\`
  - Linux / macOS: `~/.openMSX/share/extensions/`
- `moontang_trace.tcl` puede quedarse aquí: se carga con `-script`.

## Prueba A / B / C

Con el mismo MSX en las tres (mejor un MSX2 a 3,58 MHz; luego, si es el caso,
el turbo R donde falló). Sustituye `<maquina>` y `disco.dsk`:

```text
A  openmsx -machine <maquina> -ext moonsound            -diska disco.dsk -script moontang_trace.tcl -command "moontang_trace::start A.log"
B  openmsx -machine <maquina> -ext MoonTANG             -diska disco.dsk -script moontang_trace.tcl -command "moontang_trace::start B.log"
C  openmsx -machine <maquina> -ext MoonTANG -ext audio  -diska disco.dsk -script moontang_trace.tcl -command "moontang_trace::start C.log"
```

- **A** es la referencia: el MoonSound de openMSX (640 kB).
- **B** tiene la RAM de muestras de MoonTANG. Si A funciona y B no, la causa es
  el tamaño de RAM (la detección del programa no espera 2 MB).
- **C** es como los bitstreams `*_msxaudio_*`: además un MSX-Audio **sin BIOS**
  en `C0h–C1h` (`audio` es el MSX-Audio genérico de openMSX, sin ROM, 256 kB).

Deja que el disco arranque, detecte el hardware y toque unos 20 s. Luego, en la
consola (F10):

```text
moontang_trace::mark "fin"
moontang_trace::stop
```

y analiza cada trazado:

```text
python check_trace.py A.log
```

`moontang_trace::mark "texto"` mete una marca en el trazado (por ejemplo,
antes de elegir una canción).

## Lo que openMSX no puede imitar

`check_trace.py` avisa de estas diferencias, pero el emulador no las reproduce;
en el MSX real se comprueban así:

- **Ventana de arranque.** Durante los ~2 s que MoonTANG copia la YRW801 tras
  configurarse la FPGA, el motor PCM está en reset: pierde las escrituras wave
  (NEW2 incluido) y las lecturas de `7Fh` devuelven un dato caducado. Arranca el
  disco con un **reset** del MSX cuando el LED ya esté fijo.
- **Velocidad.** El `/WAIT` de las lecturas de `7Fh` llega con ~70 ns de margen
  a 3,58 MHz. En un turbo R arranca con la tecla **1** pulsada (modo Z80) y
  compara.
