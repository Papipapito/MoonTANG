# Y8950 (MSX-Audio) junto al MoonSound en MoonTANG: viabilidad con medida real

Fecha: 05/10/2026. Base: MoonTANG `main` 5400f15. Integración de prueba en un worktree aparte (ya
borrado), sin commit ni push; `main` no se ha tocado.

## Veredicto

| Variante | 32 KB en BSRAM (a) | 256 KB en SDRAM (b) |
|---|---|---|
| WonderTANG sin HDMI (`build.tcl`) | **cabe** (54 %, CLS 81 %, 33/46 BSRAM) | **cabe holgado** (55 %, CLS 81 %, 17/46 BSRAM) |
| WonderTANG + HDMI (`build_wt_hdmi.tcl`) | **cabe justo** (66 %, CLS 89 %, 34/46 BSRAM) | **cabe justo** (66 %, CLS 89 %, 18/46 BSRAM) |
| SMD con HDMI (`build_smd.tcl`) | **cabe justo** (67 %, CLS 89 %, 34/46 BSRAM) | **cabe justo** (66 %, CLS 88 %, 18/46 BSRAM) |

Los seis builds cierran con 0 violaciones de setup y de hold. No hace falta ninguna red global
nueva: siguen 8/8 PRIMARY en la WonderTANG y 7/8 en la SMD, igual que ahora. Tampoco hace falta
`/WAIT`.

En la SDRAM, el ADPCM le cuesta al motor PCM como mucho una operación de SDRAM de espera
(+130 ns) cuando le coincide. Con el tráfico real de un Z80 a 3,58 MHz el ritmo del motor no
cambia (ni a 38,57 ni a 37,125 MHz). Se ha medido en simulación con la cadena real.

**Recomendación: la opción (b), 256 KB en SDRAM.** Gasta la misma lógica que (a), ocupa 16 BSRAM
menos y es la que sirve para los VGM con bloques ADPCM grandes, la lección del MSXimus (el de
Psycho Soldier trae 128 KB). Debe poder desactivarse en tiempo de ejecución, por quien tenga un
MSX-Audio de verdad. En las dos variantes con HDMI el CLS queda en el 88-89 %. Si se quiere más
margen, hay una palanca medida (abajo): los shift-registers de jtopl en BSRAM bajan el CLS al 86 %.

## 1. Recursos y timing medidos

Gowin V1.9.12.03, mismos scripts y opciones (`place_option 2`, `route_option 1`). La holgura de
setup por reloj se calcula como periodo − 1/fMax (peor camino del dominio). Las cifras de
referencia son los builds de `main` de las 12:29-12:34 de hoy.

| Build | Lógica | LUT / ALU | FF | CLS | BSRAM | DSP | PRIMARY | setup 108 / 54 / eng (ns) | hold peor | PnR |
|---|---|---|---|---|---|---|---|---|---|---|
| **wt** (referencia) | 8749 (43 %) | 6691 / 1248 | 4822 (31 %) | 6279 (61 %) | 15 | 1,5 | 8/8 | 3,27 / 8,38 / 5,41 | 0,074 | 1 m 10 s |
| wt + Y8950 (a) | 11036 (54 %) | 8445 / 1733 | 7420 (47 %) | 8302 (81 %) | 33 | 3,5 | 8/8 | 1,50 / 7,74 / 7,02 | 0,198 | 1 m 45 s |
| wt + Y8950 (b) | 11395 (55 %) | 8805 / 1732 | 7491 (48 %) | 8314 (81 %) | 17 | 3,5 | 8/8 | 2,43 / 6,93 / 5,76 | 0,074 | 1 m 38 s |
| **wt_hdmi** (referencia) | 11118 (54 %) | 8943 / 1365 | 5879 (37 %) | 7719 (75 %) | 16 | 1,5 | 8/8 | 2,85 / 7,16 / 3,17 | 0,074 | 1 m 12 s |
| wt_hdmi + Y8950 (a) | 13525 (66 %) | 10814 / 1853 | 8477 (54 %) | 9194 (89 %) | 34 | 3,5 | 8/8 | 1,35 / 6,21 / 3,13 | 0,074 | 3 m 03 s |
| wt_hdmi + Y8950 (b) | 13637 (66 %) | 10926 / 1853 | 8548 (54 %) | 9191 (89 %) | 18 | 3,5 | 8/8 | 1,37 / 5,80 / 4,32 | 0,074 | 3 m 55 s |
| wt_hdmi + Y8950 (b) + jtopl en BSRAM | 13840 (67 %) | 11108 / 1874 | 7398 (47 %) | 8906 (86 %) | 23 | 3,5 | 8/8 | 1,93 / 4,93 / 2,88 | 0,074 | 1 m 41 s |
| **smd** (referencia) | 11063 (54 %) | 8920 / 1333 | 5808 (37 %) | 7764 (75 %) | 16 | 1,5 | 7/8 | 2,94 / 3,74 / 4,20 | 0,074 | 1 m 16 s |
| smd + Y8950 (a) | 13699 (67 %) | 11023 / 1818 | 8405 (53 %) | 9133 (89 %) | 34 | 3,5 | 7/8 | 1,70 / **1,12** / 3,68 | 0,074 | 1 m 44 s |
| smd + Y8950 (b) | 13665 (66 %) | 10990 / 1817 | 8476 (54 %) | 9075 (88 %) | 18 | 3,5 | 7/8 | 3,02 / 2,06 / 3,61 | 0,074 | 2 m 53 s |

En los builds con HDMI, el motor PCM tiene una restricción de 40 MHz y en los demás de 37,125
MHz. Los peores caminos de setup son los de antes: el controlador de SDRAM a 108 MHz y, en la SMD,
la atenuación F8 → vúmetro a 54 MHz. Ninguno pasa por el Y8950. Bajan porque el diseño está más
lleno. Los dos primeros builds con HDMI se hicieron con el mezclador en una sola etapa; también
cerraban, con 1,8 ns a 54 MHz (`rpt/*_mixer1etapa`). Después el mezclador se partió en dos etapas.

**Coste del Y8950 por bloque** (síntesis, prácticamente idéntico en las tres variantes):

| Bloque | FF | LUT | ALU | BSRAM | otros |
|---|---|---|---|---|---|
| FM `jtopl2` | 1977 | ~910 | 156 | 2 | 1 MULT, 1 SSRAM |
| ADPCM `y8950_adpcm` (+ jt10) | 538 | ~790 | 193 | 0 | 3 MULT, 7 SSRAM |
| RAM de muestras (a) `adpcm_sdram` FALLBACK_BSRAM=1 | 4 | 22 | 0 | **16** | |
| RAM de muestras (b) `adpcm_sdram` → SDRAM | 71 | 7 | 0 | 0 | |
| segundo cliente en `wv_to_sdram` | +2 | +40 | 0 | 0 | |
| bus registrado + CE + mezcla + mux de lectura | ~80 | ~300 | | | |
| **Total** | **~2600** | **~2050** | **~430** | 18 / 2 | DSP 1,5 → 3,5 |

El 75 % de los FF del FM (≈1500) son shift-registers de jtopl. El port de jtopl del MSXimus los
fuerza a biestables con `syn_srlstyle = "registers"`, porque la BSRAM del GW5A no admite
read-before-write. La GW2A sí la admite. **Palanca medida:** `jtopl_sh_rst` reescrito como buffer
circular en BSRAM, con reset síncrono que barre (pide `rst` ≥ 18 ciclos de cen, unos 5 µs; el
`/RESET` del MSX dura milisegundos). El FM pasa de 1977 a 827 FF y gasta +5 BSRAM; el CLS baja
del 89 al 86 % y el PnR de 3 m 55 s a 1 m 41 s. Se ha comparado con el original en Icarus: 150 000
comparaciones y 0 diferencias. El control negativo, con el retardo desplazado una etapa, da 149 578
errores. Es un cambio sobre el código de jotego y habría que validarlo en placa.

## 2. SDRAM: segundo cliente y plazos del motor PCM

**Diseño probado.** `wv_to_sdram` gana un segundo puerto `wv2_*` con el mismo contrato que el
primero, que va al bit 22 de la dirección: bancos 2-3, los 4 MB altos de la SDRAM, hoy sin usar.
La YRW801 y la RAM de muestras del OPL4 siguen en los bancos 0-1. La prioridad en `ST_IDLE` es
refresco > `wv`, que es `wave_sdram` (motor PCM y loader, con el motor primero) > `wv2` (ADPCM).
El dato vuelve por el `wv_dout` compartido y el fin, por un `wv2_done` propio. `ST_DONE` espera a
que suelte la petición el cliente dueño de la operación. Así, si un `/RESET` del MSX aborta al
ADPCM a mitad, la operación termina y no se le entrega a nadie. `adpcm_sdram.v` (MSXimus) se
conecta tal cual. `wave_sdram.v` no se toca.

**Medida de interferencia** (`tb_interf.v`): cadena real `wave_sdram` + `adpcm_sdram` →
`wv_to_sdram` → `ip_sdram` → `sdram_model` del banco de placa, que tiene ventana de dato real. Hay
un motor sintético que pide palabras aleatorias de los 4 MB **sin pausa**, el peor caso, uno tras
otro y comprobando el dato. Hay un ADPCM sintético que escribe un patrón y lo relee, con una pausa
entre operaciones. Cada caso son 50 000 fetches.

| ADPCM (pausa entre ops) | Motor a 38,571 MHz (HDMI): fetches/µs · latencia media / máx | Motor a 37,125 MHz (sin HDMI) |
|---|---|---|
| sin ADPCM | 3,180 · 289 / 363 ns | 3,329 · 273 / 404 ns |
| 30 µs (VGMPlay subiendo samples) | 3,180 · 289 / 415 ns | 3,328 · 274 / 458 ns |
| 5,9 µs (`OTIR` a 3,58 MHz) | 3,180 · 289 / 389 ns | 3,323 · 274 / 485 ns |
| 3 µs (`OTIR` con turbo de 7 MHz) | 3,171 · 289 / 493 ns | 3,325 · 274 / 404 ns |
| 1 µs (imposible para un Z80) | 3,180 · 289 / 363 ns | **3,221** (−3,2 %) · 284 / 458 ns |
| sin pausa (saturado) | 3,180 · 289 / 363 ns | 3,321 · 274 / 404 ns |

0 errores de dato en el motor y en el ADPCM, 0 errores de protocolo en el modelo de SDRAM y el
watchdog no salta nunca. El ADPCM se cuela en los huecos que deja la sincronización del motor. El
peor efecto es +130 ns de latencia en un fallo de caché puntual, y un −3,2 % del ancho de banda
**saturado** del motor con un ritmo de ADPCM imposible.

En el uso real el motor casi no va a memoria: tiene una caché de 8 palabras por slot con prefetch
por stride, y solo se para por el exceso de latencia de un fallo. Su margen de CE es del 13,9 %
con HDMI y del 9,6 % sin él. Además, `y8950_adpcm` tiene como mucho una operación en vuelo y el
software la frena con `BUF_RDY`. Conclusión: el motor no pierde plazos.

**Banco de placa** (`tools/sim/board`, WonderTANG sin HDMI, top real + modelo de placa + Z80): pasa
**79/79** en las dos configuraciones de RAM. Se han añadido 5 comprobaciones y se ha quitado la de
"IN C0h: silencio":
- status 06h tras el reset;
- timer 1 → status C6h y `/INT` en el slot;
- `/INT` liberado;
- 8 bytes subidos a la RAM de muestras y releídos por C1h con las dos lecturas de relleno.

Todo lo del OPL4 sigue verde: notas PCM y FM hasta el I2S, YRW801, `/WAIT` y el reset a mitad de
toggle. En (b) los 8 bytes van de verdad a la SDRAM: el modelo cuenta +8 WR y +6 RD frente a (a).

## 3. Bus y puertos

- **Decodificación.** El núcleo decodifica E/S con A0-A7 y las dos carcasas se lo pasan completo
  (`WT200B_BUS` da `Bus.ADDR[15:0]` y `smd_bus` da `bus_a[7:0]`). No hay ningún filtro de rangos en
  el frontal, así que C0h-C1h (`addr[7:1] == 7'b1100000`) entra sin tocar las carcasas. No choca con
  C4h-C7h (`[7:2]=110001`) ni con 7Eh-7Fh. El banco lo confirma, también con basura en A8-A15. Lo
  único que hay que tocar fuera del núcleo es el vigilante de bus del banco (`ours`).
- **`/WAIT`: no hace falta.** El status de C0h es combinacional desde registros y el dato de C1h se
  registra 2 ciclos de 54 MHz después del inicio del `IN`, mucho antes del muestreo del Z80. Las
  lecturas de RAM (modo 20h) van con control de flujo por `BUF_RDY`, que en el MSXimus ya incluye
  "byte en caché". Por eso funciona igual en la SMD, que no tiene `/WAIT`. El chip real tampoco usa
  `/WAIT`.
- **IRQ.**
  - En la WonderTANG va al `/INT` en wired-AND con la del OPL3. Ya pasa la guarda de bus vivo y
    arranca enmascarada.
  - En la SMD no hay `/INT`: el software que mira el status por sondeo (VGMPlay, juegos) funciona;
    el que espera la interrupción, no, igual que el timer del OPL4 en esa placa. Para eso ya existe
    el apaño `EXT_A/EXT_B = 1` (pin 75 o 79 con un transistor al `/INT`), que se llevaría también
    la IRQ del Y8950.
  - Siguen valiendo las reglas del MSXimus contra las tormentas de IRQ: el registro 4 se toca
    siempre enmascarado y con DI.
- **`/BUSDIR` en la SMD:** la misma limitación que ya tiene el OPL4. Las máquinas que lo necesiten
  no verán las lecturas de C0h-C1h.
- **Si ya hay un MSX-Audio de verdad:**
  - las lecturas de C0h-C1h chocan en el bus de datos (dos cartuchos conduciendo a la vez);
  - las escrituras llegan a los dos chips, así que el FM sonaría doble.

  Hay que poder apagarlo. Propuesta, de menos a más:
  1. parámetro de build `Y8950` (0/1; ya está así en la prueba, con `generate`);
  2. bit de configuración en tiempo de ejecución que corta la lectura, la IRQ y la mezcla del
     Y8950 a la vez. Se puede cambiar de dos formas:
     - con los botones S1/S2 de la propia Tang, pines 87/88, libres en los tres `.cst`. Por ejemplo,
       manteniendo uno pulsado al encender, si son accesibles con la Tang montada;
     - con una utilidad MSX que escriba un registro libre del OPL4. No conviene usar un registro de
       C0h-C1h, porque el MSX-Audio real también lo recibiría.

     El bit se guardaría en la flash SPI: `flash_rw.v` ya sabe borrar sector y programar. El
     estado se vería en la pantalla HDMI y en el código del LED;
  3. opcional: moverlo a C2h-C3h. openMSX documenta que el FS-CA1 conmuta C0h/C2h por software,
     pero casi ningún programa usa la segunda unidad, así que es de poca utilidad.

## 4. Relojes

Se reutiliza `clk_54m` (red global ya existente) con un CE de **3,579545 MHz exactos =
54 MHz × 35/528**, porque 315/88 MHz ÷ 54 MHz = 35/528: un acumulador de 10 bits. El MSXimus usa
3,6 MHz = 54/15, que sube el tono un 0,57 % (≈ +10 cents); aquí sale clavado. jtopl, el ADPCM y
jt10 corren en `clk_54m` y `adpcm_sdram` cruza a `clk_108m`; los dos relojes ya existen. **Medido:
PRIMARY sin cambios (8/8 en la WonderTANG, 7/8 en la SMD).**

## 5. Audio y vúmetro

- **Entrada en el mezclador de `moontang_core`.** Término mono `y = (FM_jtopl + ADPCM>>>3) × 5`.
  `>>>3` es el balance canónico _159b del MSXimus (el ADPCM a fondo pica como una portadora FM) y
  ×5 es la ganancia por defecto del grupo "clásico" del MSXimus frente al OPL4, que entra ×1. El
  término se suma a L y a R antes de la saturación. El mezclador va ahora en dos etapas (+1 ciclo de
  54 MHz, inaudible) porque con tres términos y dos saturaciones la holgura bajaba a 1,8 ns.
- **Salidas.** I2S de la WonderTANG: mono `(L+R)/2`, que lleva el Y8950 una sola vez. HDMI: estéreo,
  con el Y8950 centrado. El ×5 hay que ajustarlo de oído o con la medida de portadoras, como en el
  MSXimus.
- **Vúmetro.** Sí, una barra mono "MSX-AUDIO" (no dos: el chip es mono). El coste medido de
  `vu_meter` es 250 FF / 892 LUT para 6 canales, unos 42 FF y 150 LUT por canal, más el texto y la
  disposición en `vu_screen` (`level`/`peak` pasan de 30 a 35 bits). En total, unos 150-250 CLS, el
  1,5-2,5 %. Con el CLS al 88-89 % conviene que vaya detrás del parámetro `Y8950`, o liberar antes
  ese sitio con la palanca de jtopl.

## 6. BIOS de MSX-Audio

- **Qué decodifica hoy MoonTANG.** Solo E/S; nunca usa `/SLTSL` ni memoria. Las dos placas tienen
  las líneas:
  - la WonderTANG lleva `CART_SLTSL_n` al frontal de tnCart, que en otros cores ya sirve memoria;
  - la SMD tiene `bus_sltsl_n`, `bus_mreq_n` y A0-A15 en el `.cst`, marcados "sin uso".
- **Cómo son las BIOS** (según openMSX):
  - FS-CA1: ROM de 128 KB con mapper y SRAM en 0000h-FFFFh, tipo Panasonic, y conmutación C0h/C2h.
  - NMS-1205: ROM "Music Box" de 32 KB en 4000h-BFFFh, más MIDI (00h-01h/04h-05h) y DAC en 0Ah.
  - "MSX-AUDIO BIOS 1.3" de la comunidad: 48 KB. Es derivada del código de Panasonic, así que
    tampoco se puede distribuir.
- **Qué haría falta para la BIOS:**
  - decodificar memoria en el slot;
  - que el usuario ponga su ROM en la flash, como con la YRW801, y copiarla al arrancar;
  - servirla:
    - en la **WonderTANG**, desde la SDRAM con `/WAIT`, como tercer cliente o a través del loader;
    - en la **SMD**, que no tiene `/WAIT`, solo desde BSRAM: 48 KB son 24 bloques, que caben con
      (b) (18 + 24 = 42/46) y no con (a) (58 > 46);
  - la SRAM y el mapper del FS-CA1, si se quiere esa BIOS exacta;
  - y lógica y CLS que hoy no sobran en las variantes con HDMI.

  Es un proyecto aparte.
- **Funciona sin BIOS** (E/S directa, comprobado en el MSXimus):
  - **VGMPlay** de grauw, incluidos los VGM de Y8950 con ADPCM. Para los bloques de más de 32 KB
    hace falta (b);
  - **MoonBlaster 1.4** para MSX-Audio;
  - juegos con E/S directa como Xevious Fardraut Saga, Family Stadium y Labyrinth.
- **Con matices:** los juegos de Compile en disco (Golvellius II, Gorby's Pipeline, Disc Station)
  necesitan el truco `POKE -54,35 : POKE &HF346,1 : _SYSTEM`.
- **No funciona:** FAC SoundTracker y la versión parcheada de Fire Hawk que llama a la BIOS. La
  detección del Music Module que sondea los puertos MIDI/DAC tampoco: no se implementan.

## 7. Licencias

jtopl/jtopl2 (JTOPL) y `jt10_adpcmb*` (JT12) son de **Jose Tejada (jotego)**, **GPL-3.0 o
posterior**, y MoonTANG es GPL-3.0: son compatibles. Además, ya hay GPL-3.0 en el árbol
(`afifo.v`). `y8950_adpcm.v` y `adpcm_sdram.v` son del proyecto (MSXimus, GPL-3.0). Habría que:
- añadir dos filas a `CREDITS.md` (jtopl2 = FM del Y8950; jt10_adpcmb + interpol = ADPCM-B
  delta-T) y una sección a `THIRD_PARTY/NOTICE.md`;
- copiar `fpga/jtopl/LICENSE` y conservar las cabeceras por fichero.

No es nuevo, pero conviene recordarlo: la cláusula no comercial de `ip_sdram` (t.hara) ya convive
con código GPL-3 en la obra combinada. Añadir más GPL-3 no cambia esa situación, ya documentada en
"Licensing summary".

## 8. Riesgos

1. **Congestión.** Con HDMI, el CLS queda en el 88-89 % y el PnR tarda de 2 a 4 minutos en vez de
   1. Cierra con holgura positiva en todos los relojes, pero menor: 1,1-1,4 ns en los peores
   dominios frente a 2,9-3,7. Cualquier cosa que se añada después (barra del vúmetro, interruptor
   en flash, BIOS) se come ese margen. La palanca de jtopl en BSRAM da 285 CLS. Otra opción es dejar
   el Y8950 solo en algunos bitstreams.
2. **Lotería de placement.** Con márgenes de 1,1-1,4 ns, un cambio pequeño puede mover el peor
   camino. En la SMD (a), el camino F8 → vúmetro queda a 1,12 ns; es anterior al Y8950 y se arregla
   registrándolo.
3. **Redes globales.** No hay riesgo, porque todo cuelga de `clk_54m` y `clk_108m`. No se debe
   introducir ningún reloj nuevo para el Y8950.
4. **Motor PCM.** Medido arriba: peor caso +130 ns por fallo de caché, el ritmo no cambia con
   tráfico real y quedan un 9,6-13,9 % de margen de CE intactos. La prioridad del motor sobre el
   ADPCM está en el árbitro.
5. **Simulación de jtopl.** En Icarus, jtopl sale a X: `jtopl_slot_cnt` y `jtopl_div` solo se
   inicializan con `ifdef SIMULATION`, y `reg_fb` y los `jtopl_sh` no tienen reset. Sin
   inicializarlos, el banco de placa falla: el timer no salta y la mezcla entera queda en X, con el
   altavoz a 0. En placa no pasa, porque el GSR pone todo a 0. Hay que inicializarlos para simular,
   con `initial`s o con `-DSIMULATION` en `conv.sh` (este último trae volcados a fichero de jtopl).
6. **Conflicto con un MSX-Audio real.** Ver §3. Sin interruptor, hay choque en el bus.

## 9. Qué haría falta para hacerlo de verdad

Ficheros:
- `fpga/y8950/` (nuevo): jtopl (los 30 `jtopl*.v` de OPL2, sin `jtopll_*`), `jt10_adpcmb.v`,
  `jt10_adpcmb_interpol.v`, `y8950_adpcm.v` y `adpcm_sdram.v`, sincronizados con el MSXimus, y el
  `LICENSE` de jtopl. Decidir si se quita `syn_srlstyle="registers"` o si se usa el `jtopl_sh_rst`
  en BSRAM, que es propio de MoonTANG, con validación en placa.
- `moontang_core.sv`:
  - parámetros `Y8950` y `Y8950_SDRAM` (o `Y8950_RAM_KB`);
  - CE 35/528 y bus registrado de C0h-C1h;
  - strobes para el ADPCM y mux de lectura;
  - `int_n` en AND y el tercer término del mezclador en dos etapas;
  - salida `y8950_out` para el vúmetro;
  - entrada `y8950_en` para el interruptor en tiempo de ejecución.

  El diff de la prueba está en `prueba_fuentes/`.
- `wv_to_sdram.v`: segundo cliente `wv2_*` en los bancos 2-3. Ver además el hallazgo lateral 1.
- Carcasas y tops: pasar los parámetros. En la SMD, documentar que la IRQ solo llega con
  `EXT_A/EXT_B = 1`. Para el interruptor: pines 87/88 en los tres `.cst` y un byte de configuración
  en la flash (sector libre fuera de la YRW801 y del bitstream).
- `moontang_av.sv`, `vu_meter.v` y `vu_screen.v`: la barra "MSX-AUDIO" (NCH 7) y el estado "MSX-AUDIO
  ON/OFF" en pantalla.
- `build.tcl`, `build_wt_hdmi.tcl` y `build_smd.tcl`: añadir los ficheros.
- Documentación: `ARCHITECTURE.md` (puertos, mapa de la SDRAM con el ADPCM en los bancos 2-3,
  mezcla, árbitro), `README.md`, `VERIFICATION.md`, `CREDITS.md` y `THIRD_PARTY/NOTICE.md`.

Bancos que habría que ampliar:
- `tools/sim/board/tb_board.v`: la sección de la prueba, ya escrita (status, timer → `/INT`, subida
  y relectura del ADPCM) y el vigilante `ours` con C0h-C1h. Faltan:
  - una nota ADPCM en modo A0h con EOS y salida no nula en el I2S;
  - un sample de más de 32 KB que solo pase con (b);
  - un `/RESET` del MSX con una operación ADPCM en vuelo, comprobando que no envenena la wave;
  - un control negativo: el bit 22 forzado a 0 debe romper la YRW801.
- `tools/sim/board_smd/tb_smd.v`: lo mismo, por sondeo y sin `/INT`. Comprobar `datadir` en las
  lecturas de C0h/C1h.
- `tools/sim/board/conv.sh`: inicializar jtopl para Icarus (ver riesgo 5).
- Nuevo `tools/sim/tb_interf.v` (está en este directorio): interferencia motor/ADPCM, con umbral
  de aceptación.
- `tools/msx/`: un `mt6aud.asc` con detección (06h), timer → C6h y subida/relectura del ADPCM, al
  estilo de `mt1det`/`mt5ram`.

## 10. Recomendación

Hacerlo con **256 KB en SDRAM**:
- **por defecto en la WonderTANG sin HDMI**, que va holgada (CLS 81 %);
- **en las dos variantes con HDMI**, solo junto a la palanca de jtopl en BSRAM (CLS 86 %) y sin la
  barra extra del vúmetro hasta ver el margen. Si se prefiere no tocar jotego, como parámetro de
  build y quizá en bitstreams separados.

En todos los casos, con interruptor persistente para quien tenga un MSX-Audio real. La BIOS de
MSX-Audio, como proyecto aparte: solo es razonable en la WonderTANG, con `/WAIT`.

## Hallazgos laterales (no son del Y8950)

1. **`wv_to_sdram.v`, esquina del watchdog.** Si el watchdog salta durante un **refresco**
   (`was_ref`), la FSM va a `ST_DONE` y espera a que baje `wv_req`. Si `wave_sdram` tenía una
   petición pendiente, encolada detrás del refresco, nunca bajará, porque no recibe `wv_done`, y
   `ST_DONE` no está cubierto por el watchdog: la cadena se queda colgada. Solo ocurre si el
   controlador ya se ha colgado, pero anula justo la recuperación para la que existe el watchdog.
   Arreglo: con `was_ref`, ir a `ST_IDLE` en vez de a `ST_DONE`.
2. **Finales de línea de los `.tcl`.** Con `core.autocrlf=true`, un checkout nuevo en Windows saca
   los `.tcl` con CRLF. `.gitattributes` solo fuerza LF en `*.sh` y `*.py`. Con CRLF, `conv.sh` pasa
   a sv2v nombres con `\r` (`opl3/opl3_pkg.sv: does not exist`) y los bancos de placa no arrancan.
   Gowin no se queja. Arreglo: `*.tcl text eol=lf` en `.gitattributes`, o `tr -d '\r'` en `conv.sh`.

## Ficheros de este directorio

- `rpt/base_*`: informes de referencia (`main`).
- `rpt/{a,b}_{wt,wt_hdmi,smd}` y `rpt/bopt_wt_hdmi`: `rpt.txt`, `timing_paths`, `tr_content`,
  `syn_rsc.xml` y log de Gowin de cada build.
- `rpt/*_mixer1etapa`: los dos primeros builds con HDMI.
- `rpt/interf/*.log`: el barrido de interferencia.
- `rpt/tb_board_wt_y8950_{sdram,bsram}.log`: el banco de placa, 79/79.
- `prueba_fuentes/`:
  - `prueba_y8950.diff` (core, puente, tcl, banco de placa);
  - `moontang_core.sv` y `wv_to_sdram.v` de la prueba;
  - `fpga_y8950/`, con jtopl **ya con las inicializaciones para simulación** (`jtopl_slot_cnt`,
    `jtopl_div`, `jtopl_reg_ch`, `jtopl_sh`). Los builds medidos usaron los ficheros del MSXimus sin
    ellas.
- `jtopl_sh_rst_bram.v`, `tb_sh.v` y `neg_sh.v`: la variante en BSRAM y su equivalencia.
- `tb_interf.v` y `run_interf.sh`: el banco de interferencia (WSL Ubuntu-24.04, Icarus).
- `rsc.py`: desglose jerárquico de `*_syn_rsc.xml`.
