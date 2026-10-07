# MoonTANG: notas para el post de msx.barcelona (borrador)

Post: `post.html` en esta misma carpeta. Bloques de Gutenberg con el botón ES/EN al principio (plantilla de las fichas). Cada texto va duplicado en `repa-es` / `repa-en`; las imágenes van una sola vez, con el pie en los dos idiomas. **No se ha subido nada a WordPress**: cuando des el visto bueno, se crea como borrador.

## 1. Qué hay que decidir o completar antes de publicar

### Marcadores que hay en el post (buscar `[`)
| Marcador | Qué poner |
|---|---|
| `[DESCARGA VERSIÓN 1 .fs]` | enlace al `.fs` OPL4 + MSX-Audio (sin HDMI) |
| `[DESCARGA VERSIÓN 2 .fs]` | enlace al `.fs` OPL4 + MSX-Audio + HDMI |
| `[DESCARGA VERSIÓN 3 .fs]` | enlace al `.fs` OPL4 + HDMI |
| `[DESCARGA PROGRAMAS DE PRUEBA]` (2 sitios por idioma) | ZIP con los **ocho** programas (`MT1DET`, `MT2FM`, `MT3TMR`, `MT3INT`, `MT4YRW`, `MT5RAM`, `MT6PCM`, `MT7AUD`, `.ASC`) (ojo: son binarios byte a byte, CRLF + 1Ah; no pasarlos por nada que toque los finales de línea) |
| `[ENLACE REPOSITORIO]` (aviso de experimental y descargas) | URL del repo de GitHub, si se publica |
| `[LICENCIA]` | la licencia que decidas (ver punto 5) |
| `[URL moontang_hdmi_opl4_msxaudio.webp]`, `[URL moontang_hdmi_opl4.webp]` | URL de las dos capturas una vez subidas |

### Ficheros actuales y nombre propuesto para el release
| Versión | Fichero actual | md5 | Nombre propuesto |
|---|---|---|---|
| 1 · OPL4 + MSX-Audio | `bitstream/moontang_wondertang202b_msxaudio_20261005.fs` | 3cc18cdffea2aed54ded40b98332a465 | `moontang_wt202b_opl4_msxaudio_vX.fs` |
| 2 · OPL4 + MSX-Audio + HDMI | `fpga/files/20261005/moontang_wondertang202b_hdmi_msxaudio_EXPERIMENTAL_20261005.fs` | 690bb11a1532db5369a0ae92ac7f69ad | `moontang_wt202b_opl4_msxaudio_hdmi_vX.fs` |
| 3 · OPL4 + HDMI | `bitstream/moontang_wondertang202b_hdmi_20261005.fs` | 1914465330f65d82e92b2afd9250e0a5 | `moontang_wt202b_opl4_hdmi_vX.fs` |

- La versión 2 hoy lleva `EXPERIMENTAL` en el nombre y no está en `bitstream/`. Si entra en el release como una más, hay que moverla a `bitstream/` y cambiar `docs/WONDERTANG.md` y el README, que hoy la presentan como "solo un experimento" y dicen "tres bitstreams" contando la de solo OPL4 sin HDMI, que en el release no va.
- Con cada build del release, decir qué se graba: solo el `.fs` en `0x000000` (y la YRW801 de cada uno en `0x200000`). Para estas tres no hace falta `.bin` ni pack.

### Número de versión
Propuesta: **v1.0** si antes de publicar suenan en placa las tres versiones; si se publica sin probarlas todas, **v0.9 (beta)** y dejar el aviso de experimental del post tal cual. En el post no he puesto número; va en los nombres de los ficheros, en el título si quieres y en el pie de la pantalla HDMI (ver punto 3).

### Estado de prueba en placa (06/10)
| Versión | En placa |
|---|---|
| 3 · OPL4 + HDMI | **Sonó** en tu WonderTANG 2.02b, pero con la compilación del 05/10 por la mañana (`fpga/files/20261005/probado_en_placa/`, md5 .fs 9eeb73673cbf07c8c46501b4d0fcf24b). La que se publicaría es la de después, que **no** se ha probado en placa. |
| 1 · OPL4 + MSX-Audio | **Sin probar** en placa (solo simulación de placa). |
| 2 · OPL4 + MSX-Audio + HDMI | **Sin probar** en placa. Es la que más llena el chip (68 % de lógica, 90 % de CLS); el riesgo que el análisis de tiempos no cubre es el interfaz con la SDRAM embebida (sin restringir en el `.sdc`): si falla la memoria de ondas o el ADPCM solo con esta, es lo primero que hay que mirar. |

El software de MSX-Audio (VGMPlay con música de MSX-Audio, MoonBlaster 1.4) **no se ha probado**: en el post pone "debería funcionar". Si al probarlo funciona, se puede cambiar a "funciona".

### Datos del post que conviene confirmar en tu placa
- **Botón S1**: el README oficial de la WonderTANG lo pide solo para la 2.0b (su firmware reutiliza los pines JTAG). MoonTANG no reutiliza el JTAG (`build_wt_*.tcl`: solo MSPI y SSPI como GPIO), así que en el post va como "si el Programmer no ve la Tang porque lleva un firmware que usa el JTAG". Confirma si en la 2.02b con su firmware de fábrica hace falta.
- **Orden de openFPGALoader para el `.fs`**: los documentos de MoonTANG solo traen la de la YRW801 (`openFPGALoader -b tangnano20k --external-flash -o 2097152 yrw801.bin`, copiada tal cual). La del `.fs` (`openFPGALoader -f -b tangnano20k --external-flash moontang_version.fs`) sale del README oficial de la WonderTANG. Conviene probarla una vez y añadirla a `docs/WONDERTANG.md`. Ojo: el README oficial pone `-f` también en la orden del fichero de datos (`-f ... --external-flash -o ...`); la de MoonTANG para la YRW801 va sin `-f`. Comprueba que graba de verdad en la flash (luego `MT4YRW`). En el post el nombre de fichero es genérico (`moontang_version.fs`): cámbialo si quieres poner los nombres reales.
- **Pasos de Gowin Programmer**: sacados del README oficial de la WonderTANG (serie GW2AR, External Flash Mode, Generic Flash, una entrada por fichero y grabar de una en una) con las operaciones y direcciones de MoonTANG. Unas capturas del Programmer ayudarían mucho.
- "Gowin Programmer (Windows)" y "en Linux no va bien": lo dice el README oficial de la WonderTANG.
- En el post sale el MSXnano como ejemplo de firmware que usa `0x200000` (dato de `docs/WONDERTANG.md`). Quítalo si no quieres mezclar proyectos.

### Cambios de la revisión crítica (06/10)
- Programas de prueba: son **ocho**, no siete (MT3TMR y MT3INT son dos).
- Turbo: «el FM y el MSX-Audio leen bien hasta 7,16 MHz» era un dato de simulación presentado como hecho; ahora dice «no usan /WAIT; en simulación se leen bien hasta 7,16 MHz».
- Botón S1: «con MoonTANG ya grabado no hace falta» pasa a «no debería hacer falta» (sale de la configuración del build, no se ha comprobado en placa).
- Créditos: añadida una línea con las licencias de las piezas (LGPL-3.0, GPL-3.0, BSD-2/3, MIT/Apache-2.0).
- Comprobado sin cambios: direcciones (0x000000 / 0x200000), operaciones del Programmer, puertos (C4h–C7h, 7Eh–7Fh, C0h–C1h), LED, pantalla HDMI (720×480, 16:9, 48 kHz), MT1…MT7, alimentación por diodo, botón ES/EN idéntico a la plantilla, bloques de Gutenberg equilibrados, ES/EN equivalentes, sin SMD / New Juice / 2.0b / historial, YRW801 sin enlaces.

## 2. Capturas del HDMI
En esta carpeta (854×480, estiradas a 16:9 igual que hace `tools/sim/vu`; los `.webp` son sin pérdidas):
- `moontang_hdmi_opl4_msxaudio.webp` / `.png`: versión 2, siete barras. Es el cuadro `tools/sim/board/build/hdmi_audio_cuadro.png` (simulación de placa de la versión 2, pie `MOONTANG 2026-10-05`).
- `moontang_hdmi_opl4.webp` / `.png`: versión 3, seis barras. **Regenerada** con el RTL actual en una copia (`copia/`, sin tocar el repo): `BUILD=2026-10-05 bash tools/sim/vu/run_vu.sh` en WSL Ubuntu-24.04, con el resultado `TODO CORRECTO` (5 cuadros del banco y 1 a la salida del módulo `hdmi`, comparados píxel a píxel con el modelo: 0 diferencias). Es el cuadro `vu_hdmi`, sacado a través del módulo `hdmi` de verdad.
- Pie en el post: "Imagen generada desde la señal HDMI (no es una foto)". **Cambiar por fotos reales** cuando las haya (pantalla y la WonderTANG montada; no hay ninguna foto del cartucho en el post).
- El pie de la pantalla muestra el parámetro `BUILD` (hasta 10 caracteres; hoy `2026-10-05`). Si en el release pones la versión (p. ej. `v1.0`), conviene regenerar las dos capturas con ese texto para que coincidan.
- Subida: método curl con la app password guardada (memoria `msx_barcelona_reparaciones_kanban`), y cambiar los dos `[URL ...]` por las URL que devuelva.

## 3. Datos de WordPress propuestos
- **Título**: "MoonTANG: un MoonSound (OPL4) y un MSX-Audio para tu MSX en una WonderTANG".
- **Extracto**: "MoonTANG convierte la WonderTANG 2.02b con Tang Nano 20K en un MoonSound OPL4, con MSX-Audio y salida HDMI opcionales. Tres versiones y cómo flashearlas."
- **Categorías**: Cartuchos (5) y MSX (7). **Etiquetas**: fpga (34), msx (11) y, cuando se publique, live (28) para que salga en la portada.
- **Estado**: borrador. Imagen destacada: una foto real cuando la haya (o la captura de la versión 2 mientras tanto).
- Enlaces internos que lleva: el post del MSXimus (`/msximus-msx2-fpga/`). Se podría añadir el de la historia de las FPGA (`/fpga-msx-proyectos/`), que habla de la WonderTANG.
- Rank Math: palabra clave "MoonTANG" (ya está en el primer párrafo y en el título).

## 4. Qué se ha dejado fuera, como pediste
- La placa MSXhdmi_tn20k_smd (congelada), la WonderTANG sin HDMI y sin MSX-Audio, la 2.0b (solo se nombra la 2.02b), el fork de New Juice y los estudios internos.
- La YRW801: ni se distribuye ni se dice dónde conseguirla; solo "tu copia, por ejemplo volcada de tu MoonSound".
- Nada de historial (fechas de cambios, arreglos, bugs). La telemetría por el puerto serie y el parámetro `SDRAM_RD_CAPTURE_CLK` tampoco salen: son cosas de desarrollo.
- Créditos: no sale **Javier Abadia** (jabadiagm), porque su parte (asignación de pines y cambio de sentido del bus) solo está en la placa SMD congelada. Si sale el código completo en el repo, en `CREDITS.md` sigue estando.
- En los créditos va la línea "Albert (Papipapito) programando a cuatro manos con Claude (Anthropic)", sacada de `CREDITS.md`. Quítala o cámbiala si no la quieres en la web.

## 5. Licencia (si se publica el código)
- El repo es **GPL-3.0** (`LICENSE`): el OPL3 (LGPL-3) va enlazado con `afifo.v` y JTOPL/JT12 (GPL-3), así que el conjunto es GPL-3.
- **Posible choque**: `fpga/src/ip_sdram_tangnano20k_c.v` (Takayuki Hara) lleva en la cabecera una cláusula **no comercial** ("not sold or used commercially without prior written permission"). La GPL-3 no admite restricciones añadidas (sección 7 / 10), así que distribuir ese fichero dentro de una obra GPL-3 con esa cláusula es, en rigor, incompatible. La raíz del repo de t.hara es MIT, y `THIRD_PARTY/NOTICE.md` hoy aplica la cláusula más estricta "por si acaso". Opciones:
  1. Pedir a t.hara permiso por escrito para usar el fichero bajo MIT o GPL-3 (lo más limpio).
  2. Usar el fichero de su repo bajo la MIT de la raíz, si él confirma que es la que vale.
  3. Cambiar ese controlador por otro de licencia compatible.
- Mientras no se resuelva, el post dice "proyecto hobby y sin ánimo de lucro… algunas piezas llevan una cláusula no comercial: no se puede vender" y deja `[LICENCIA]` pendiente. Si el choque se resuelve con las opciones 1 o 2, esa frase sobra.
- El resto es compatible: srg320 (BSD-3), Jokin Miragaia en `opl4fm.v` (BSD-3), lfantoniosi en `flash_rw.v` (BSD-2), herraa1/buppu3 (BSD-3), hdl-util/hdmi (MIT/Apache-2.0).
