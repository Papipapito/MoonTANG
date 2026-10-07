# Correcciones tras la revisión adversarial (léelas antes del informe)

Dos revisores (técnico y práctico/legal) comprobaron el informe contra los .rpt, el repo de New Juice y simulaciones propias. Lo que cambia:

1. **La SDRAM compartida NO es el obstáculo de fondo.** Simulado con la cadena real (motor PCM -> árbitro de la prueba -> controlador de New Juice -> modelo de SDRAM, con un Z80 sintético a 3,58 / 5,37 / 7,16 MHz): el motor espera como mucho UNA operación (83 ns) y su salida no cambia (1,000 en los casos normales); la CPU pasa de 93 a 167-176 ns como máximo, sin perder órdenes ni datos. Lo que sí queda: refresco propio por temporizador (el de New Juice va atado a los RFSH del Z80), el mapa de memoria (lleno: habría que bajar el mapper de 4 a 2 MB) y probar la escritura y el IN 7Fh. Logs en `scratchpad\wf6\rev_sim\`.
2. **Timing:** la holgura de la ruta crítica de New Juice varía 1-1,7 ns entre compilaciones (+0,016 / +0,065 / +0,654 ns sin OPL4). Con una sola compilación por variante NO se puede decir que v3 (solo FM, sin SFG-01) no cierre ni que v4 cierre de forma robusta. "place 3 y 4" eran la misma ejecución con place_option 0. El árbitro NO está en la ruta crítica.
3. **v1 tampoco cabría con BSRAM ilimitada** (≈ 20,97k de lógica tras P&R > 20736).
4. **Reloj del motor:** el PLL de vídeo de New Juice se resetea con CADA /RESET del MSX, no solo al arrancar: mejor la salida CLKOUTD3 de rpll_main (36 MHz; simulado: los casos normales siguen en 1,000). La FM a 27 MHz del cristal es asíncrona de 54 MHz (en MoonTANG es síncrona): costaría un CLKDIV y un global más hacerlo como en MoonTANG. Dentro de New Juice el motor llega a 41,5-43,7 MHz, no a 45,8-49,5.
5. **Mezcla de New Juice:** no recorta, desborda con vuelta (ya puede pasar de ±65k sin el OPL4).
6. **Falta una base con licencia: el firmware WonderTANG original de lfantoniosi es BSD-2** (clon en `proyectosAI\msx\WonderTANG-ref`), soporta la 2.0b y trae Nextor, OPLL, Super MegaRAM SCC+, mapper de 4 MB y Franky. Un "WonderTANG + OPL4" sobre esa base SÍ se podría publicar (BSD-2 + GPL-3). Matices: sin SFG-01 ni depurador ni Nextor 3, lleva VM2413 (no comercial), recursos sin medir, y para la 2.02b su propio README remite a New Juice.
7. **Falta la opción de DOS cartuchos a la vez:** New Juice en un slot y MoonTANG en otra Tang (otra WonderTANG o la MSXhdmi SMD). No chocan los puertos (New Juice: 48-49, 7C-7D, 88-89, 8E-8F, FC-FF; MoonTANG: C4-C7, 7E-7F).
8. **Opción A (cambiar de core en la misma WT):** con MoonTANG cargado se pierden la SD, Nextor, la MegaRAM y el mapper. El bitstream se graba en "External Flash mode"; "exFlash C Bin Erase" es solo para la YRW801. Los dos bitstreams miden 907 418 B (acaban en 0x0DD89A). Albert ya pasó su WT 2.02b de New Juice a MoonTANG el 05/10; falta comprobar que al volver a New Juice arranca Nextor (si no, regrabar sus ROMs). También se puede cargar MoonTANG solo en SRAM por USB sin tocar la flash.
9. **Licencias:** New Juice ya lleva más GPL-3 de lo dicho (jt49, jt51, jt2413, jt89, sd_reader de WangXuan95 y probablemente el sdram.v de nand2mario). La LGPL-3 del OPL3 permitiría a lfantoniosi integrar un módulo LGPL/BSD sin relicenciar New Juice, salvo que el módulo arrastre `afifo.v` (GPL-3). "Uso privado" debe leerse como "evaluación privada, sin distribuir". El apartado 5 (esfuerzo) solo es aplicable en las opciones B o C, porque toca código de New Juice.
10. **De MoonTANG (aparte):** `fpga/src/flash_rw.v` deriva del `flash.v` de lfantoniosi (BSD-2, © 2023 lfantoniosi) y CREDITS.md lo da como GPL-3 propio; `opl4fm.v` adapta `cartridge_opl3.sv` de Jokin Miragaia (BSD-3) y NOTICE.md no recoge su aviso. Y GPL-3 (por `afifo.v`) + `ip_sdram` de t.hara con cláusula no comercial chocan (GPL-3 §10) si se publica MoonTANG: se arregla sustituyendo `afifo.v` o con la confirmación de t.hara. No es de New Juice; se corrige en MoonTANG antes de publicarlo.

---

# ¿Entra el OPL4 de MoonTANG en New Juice (WonderTANG 2.0b/2.02b)?

Estudio de solo lectura, 05/10/2026. No he tocado ningún repo tuyo, ni he hecho commit, push o publicado nada. Todo el material está en
`C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\e19c5f05-c115-44f4-8d46-a0b0bdc94acb\scratchpad\wf6\` (abajo lo abrevio como `wf6\`).
Las rutas de New Juice son relativas a `wf6\nj_src\` (HEAD `306ca0e`). Las de MoonTANG son de la copia `wf6\mt_cost\` (HEAD `5400f15`).

---

## 1. Veredicto

- **Tal cual, no entra.** New Juice ya usa las **46 BSRAM** del GW2AR-18 y el OPL4 pide **15 más**. Compilé la suma y Gowin aborta en la síntesis con la lógica al **112 %** (`ERROR (RP0006)`).
- **Entero solo cabe quitando la Franky**: el VDP de la SMS, su SN76489, el framebuffer de 64K×6 y el osciloscopio. Así compila y cierra timing con lógica al 81 %, **CLS al 95 %** y 31 BSRAM. El chip queda lleno, y la integración de verdad está por hacer y por probar en placa: árbitro de SDRAM, refresco propio y mapa de memoria.
- **Solo la FM (OPL3) en lugar del SFG-01** cabe en recursos, pero falla timing por poco en una ruta que es de New Juice. Y en cualquier variante hay un límite previo: **New Juice sigue sin licencia**. Lo que salga solo vale para uso privado, salvo que lfantoniosi lo permita o lo integre él.

---

## 2. Recursos

El chip es el GW2AR-LV18QN88C8/I7: 20736 de lógica, 15552 FF, 10368 CLS, 46 BSRAM, 2 rPLL, 8 PRIMARY y 8 LW. Gowin cuenta la lógica como LUT + ALU + 6 × SSRAM.

### 2.1 Medido (place & route completo)

Todo con Gowin 1.9.12.03, salvo donde pone otra versión.

| Build | Lógica | CLS | FF | BSRAM | DSP | PRIMARY / LW / rPLL | Peor setup | ¿Cierra? |
|---|---|---|---|---|---|---|---|---|
| New Juice publicado (bitstream del autor, 1.9.11.03 Edu) | 12546 (61 %) | 9002 (87 %) | 8157 | **46/46** | 2 | 3/8 · 8/8 · 2/2 | main_clk **+0,065 ns** | Sí |
| New Juice tal cual (mío) | 12555 (61 %) | 9008 (87 %) | 8705 | **46/46** | 2 | 3/8 · 8/8 · 2/2 | main_clk **+0,016 ns** | Sí |
| MoonTANG WT sin HDMI | 8749 (43 %) | 6279 (61 %) | 4822 | 15 | 1,5 | 8/8 · 8/8 · 2/2 | clk_eng 46,5 MHz (restricción 37,1) | Sí |
| MoonTANG WT+HDMI | 11118 (54 %) | 7719 (75 %) | 5879 | 16 | 1,5 | 8/8 · 8/8 · 2/2 | clk_eng 45,8 MHz (restricción 40) | Sí |
| **v1**: NJ + OPL4 completo | **23273 (112 %)** | – | – | – | – | – | – | **No**: aborta en síntesis |
| **v2**: NJ + solo FM | 15393 (75 %) | 9881 (**96 %**) | 12289 | 46/46 | 2,5 | 4/8 · 8/8 · 2/2 | main_clk **−0,538 ns** (64 endpoints) | **No** |
| **v3**: NJ − JT51 + solo FM | 12707 (62 %) | 8934 (87 %) | 7883 | 44/46 | 1,5 | 4/8 · 8/8 · 2/2 | −0,656 ns (place 1); −0,075 ns (place 3 y 4); −0,995 ns con 1.9.11 | **No, por poco** |
| **v4**: NJ − Franky + OPL4 completo | 16784 (81 %) | 9828 (**95 %**) | 9316 | 31/46 | 3,5 | 5/8 · 8/8 · 2/2 | main_clk **+1,024 ns**; clk_eng 43,7 MHz (restricción 40) | **Sí** |
| v4 con 1.9.11.03 Edu | 17002 (82 %) | 9769 (95 %) | 9033 | 31/46 | 3,5 | 5/8 · 8/8 · 2/2 | main_clk **+0,089 ns**; clk_eng 42,6 MHz | Sí, justo |
| v4base: NJ − Franky, sin OPL4 (referencia para restar) | 8788 (42 %) | 6513 (63 %) | 5187 | 16 | 2 | 3/8 · 8/8 · 2/2 | +0,222 ns | Sí |
| **v5**: NJ − todo el vídeo + OPL4 completo | 15225 (73 %) | 9351 (90 %) | 8417 | 30/46 | 3,5 | 5/8 · 8/8 · 2/2 | main_clk +0,450 ns; clk_eng 41,5 MHz | Sí |

En v5 «todo el vídeo» es la Franky, el osciloscopio, el framebuffer, el terminal del depurador y el transmisor HDMI.

**Lo que cuesta de verdad el OPL4 dentro de New Juice** (v4 − v4base, medido): **+7996 de lógica, +3315 CLS, +4129 FF, +15 BSRAM, +1,5 DSP y +2 relojes PRIMARY.** Las CLS salen menos de lo que estimaba (unas 5,5k) porque, con el chip lleno, Gowin empaqueta más apretado.

**Informes:**
- New Juice publicado: `wf6\nj_rpt\upstream_commit\new-juice.rpt.txt` y `new-juice_tr_content.html`.
- New Juice mío: `wf6\nj_rpt\v1912\new-juice.rpt.txt` y `wf6\nj_rpt\v1911\new-juice.rpt.txt`.
- MoonTANG: `C:\Users\alber\proyectosAI\msx\MoonTANG\fpga\files\20261005\moontang_wondertang202b_20261005.rpt.txt` y `...\moontang_wondertang202b_hdmi_20261005.rpt.txt`. Las reproduje idénticas en `wf6\mt_cost_rpt\full_wt.pnr.rpt.txt` y `full_hdmi.pnr.rpt.txt`.
- Pruebas v1 a v5: `wf6\trial_rpt\<build>\new-juice.rpt.txt` y `new-juice_tr_content.html`. El resumen de todas está en `wf6\trial_rpt\resumen_chk.txt`.
- El aborto de v1 está en `wf6\trial_rpt\v1_full_gw2ar18\build.log`, con este texto: `The number(23273(19241 LUTs, 2034 ALUs, 0 ROM16s, 333 SSRAMs)) of logic in the design exceeds the resource limit(20736)`.

### 2.2 Estimado (síntesis o cuentas, sin place & route)

| Caso | Cifra | De dónde sale |
|---|---|---|
| Lo que pediría v1 si no hubiera límite de BSRAM | 20715 de lógica (99,9 % del GW2AR-18), 12247 FF, **63 BSRAM**, 5 DSP | Síntesis en GW2A-55: `wf6\trial_rpt\v1_full_55\desglose_modulos_syn.txt` |
| OPL4 «neto», sin el bus, la SDRAM, el I2S ni la telemetría de MoonTANG | Unas 7,65k de lógica en síntesis y 7,8-8k tras P&R; unos 4k FF; 15 BSRAM; 3 MULT18; +2 PRIMARY | `wf6\mt_cost_rpt\*.syn_rsc.xml` y diferencias entre variantes en `wf6\mt_cost_rpt\resumen_pnr.txt` |
| Solo la FM (OPL3) | Unas 2,8k de lógica, 0,9k FF y 7 BSRAM | Variante completa − `nofm` |
| Suma bruta New Juice + MoonTANG WT | 21295 de lógica (103 %) y 61 BSRAM (133 %) | Cuentas sobre los .rpt |

**Dónde se va la BSRAM de New Juice** (síntesis, `wf6\nj_rpt\v1912\desglose_modulos_syn.txt`):

| Bloque | BSRAM |
|---|---|
| Framebuffer `sms_framebuffer` | 24 |
| `jt51` (SFG-01) | 10 |
| VDP de la SMS | 8 |
| `jt2413` | 2 |
| Terminal del depurador | 1 |
| SD | 1 |

Solo la Franky (8 + 24) libera más de las 15 que hacen falta. Quitar el JT51 solo libera 10.

**v2 es engañosa.** Gowin consigue meter la FM porque pasa las RAM del JT51 a flip-flops: el JT51 pasa de 814 a 3680 FF y de 11 a 3 BSRAM. Eso sube la CLS al 96 % y rompe la ruta de 108 MHz.

---

## 3. Obstáculos de integración, uno por uno

### 3.1 SDRAM compartida: plazos del motor PCM frente a la megaRAM del Z80

Es el obstáculo de fondo. Aunque sobrara chip, habría que resolverlo.

**Cómo es la SDRAM de New Juice:**
- **Controlador sin árbitro.** Es `sdram.v` de nand2mario: 108 MHz, CAS 3 y unos 80 ns por operación.
  - Los clientes pasan por un multiplexor de prioridad fija: flash > lineal > MegaRAM > mapper (`src/top.v:1741-1769`). No compiten de verdad porque el decodificador de slot solo activa uno cada vez.
  - El adaptador guarda **una sola** petición en cola (`src/sdram_command_adapter.v:113-119`).
- **La Z80 se sirve sin /WAIT.** Las esperas de MegaRAM, lineal y mapper están comentadas (`src/top.v:517-521`; commit `42ff17bf` del 08/08, «remove memory-waits»). Así que cada acceso de la CPU tiene que terminar a tiempo.
  - Según el inventario, el acceso tarda unos 200-250 ns y la Z80 lee el dato a los ~560 ns. Hay margen, pero es una estimación sin medir.
- **El refresco lo marca la Z80.** Solo refresca después de ver un ciclo RFSH y con el bus en reposo (`src/sdram_command_adapter.v:69-72, 121-126, 175-185`). La única excepción es un refresco cada 10 µs con el depurador parado (líneas 128-141).
  - Si la Z80 deja de hacer RFSH (reset mantenido, otro cartucho que retiene /WAIT, etc.), la SDRAM no se refresca y **la copia de la YRW801 se degrada**.
  - El OPL4 necesita un temporizador de refresco propio, como el que lleva `wv_to_sdram` en MoonTANG.

**Lo que pide el motor PCM.** Lo medí con el banco `wf6\mt_sim\tb_pcm_bw.v`, sobre la cadena real de MoonTANG; los logs están en `wf6\mt_cost_rpt\sim\`.
- **Caudal:** entre 0,5 y 3 M operaciones/s según tono y bits. La CPU ocupa como mucho un ~16 % de la SDRAM, así que **el caudal cabe**. El problema es el arbitraje.
- **Latencia:** con música normal aguanta **como mucho ~200 ns de espera añadida** por operación. Las ondas de 16 bits a tono 2 ya pierden velocidad con +74 ns.
- **Límite propio de MoonTANG:** con 24 voces a 4 bytes por voz y muestra, MoonTANG ya se queda corto hoy (velocidad 0,71-0,83). Es un límite del diseño, no de la integración.

**Árbitro de la prueba** (`wf6\trial_rpt\fuentes\nj_wave_arb.v`):
- Las ondas tienen prioridad y el adaptador de New Juice ve `busy` mientras tanto.
- La CPU puede esperar una operación de ondas entera (~65-85 ns).
- El motor espera como mucho una operación de la CPU más un refresco (~150 ns), dentro del presupuesto de 200 ns.
- **Son cuentas, no simulación.** No lo he simulado.

**Mapa de memoria.** La SDRAM de 8 MB está casi llena:

| Rango | Uso | Fuente |
|---|---|---|
| 0x000000-0x3FFFFF | Mapper (4 MB) | `src/sdram_mapper.v:92, 106-109, 145` |
| 0x400000-0x5FFFFF | MegaRAM (2 MB) | `src/super_megaram.v:64` |
| 0x600000-0x627FFF | ROMs (160 KB) | `src/flash_roms.v:40-42, 93-94` |
| 0x628000-0x7FFFFF | **Libre (~1,84 MB)** | — |

- El OPL4 necesita 2 MB de ROM (YRW801) y hasta 2 MB de RAM de muestras.
- **La prueba puso las ondas encima de la MegaRAM, y eso está mal.**
- Lo razonable sería:
  - recortar el mapper a 2 MB, con lo que queda libre 0x200000-0x3FFFFF para la YRW801;
  - poner la RAM de ondas en el hueco libre de 1,84 MB, con una traducción de direcciones sencilla.
- Se pierden 2 MB de mapper (de 4 a 2 MB), que casi ningún programa echa de menos.

**Ruta crítica.** La ruta peor de New Juice es justo la decodificación del bus hasta el comando de SDRAM: `mp_debouncer/latched_*` → `flash_roms/sdrc_cmd_en_reg`.
- Tiene +0,016 ns de margen (o +0,065 en el bitstream publicado) en un solo ciclo de 108 MHz, y **el árbitro va justo ahí**.
- En v4 cerró con +1,02 ns porque quitar la Franky descongestiona el chip. Con 1.9.11.03, que es la versión del autor, solo quedaron +0,089 ns, y en v3 falló siempre por esa ruta.
- Una integración seria tendría que segmentarla, y eso ya es cambiar lógica de New Juice.

**/WAIT en `IN 7Fh`.** MoonTANG retiene la CPU con /WAIT para leer la memoria de ondas por 7Fh, mientras que New Juice no usa /WAIT en funcionamiento normal.
- La prueba metió `opl4_wait_n` en el `wait_in_n` del `cd_demux` (`wf6\trial_rpt\v4_nofranky_full\top.v:1760`).
- Alternativa: `RD_MIRROR = 1` (`fpga/src/opl4_pcm.v:194-247`), como en la placa SMD (`fpga/src/moontang_smd_top.sv:144`), que evita el /WAIT.
- Hay que decidirlo y probarlo en placa.

### 3.2 PLL y relojes

**Situación de partida.** New Juice ocupa **los 2 rPLL**:
- `rpll_main` da 108 MHz más 108 MHz a 180° para la SDRAM (`src/top.v:373-379`, `src/rpll/rpll_main.v:44-51`).
- `rpll_video` da los 135 MHz del TMDS (`src/top.v:408-419`).

**Lo que necesita el OPL4:**
- 54 MHz para el lado del bus.
- Un reloj de FM de al menos ~12,7 MHz.
- `clk_eng` para el motor PCM, en una ventana de **36 a 45 MHz**. A 54 MHz no cierra: su Fmax medida está entre 45,8 y 49,5 MHz.

**Cómo lo resolvió la prueba, sin PLL nuevo** (medido en v4 y v5):
- **54 MHz:** de la salida `CLKOUTD` (÷2) de `rpll_main`, que New Juice declara pero no usa (`wf6\trial_rpt\v4_nofranky_full\top.v:393`).
  - Primero probé un CLKDIV ÷2 de `main_clk` y salió mal: **109 violaciones de hold de hasta −2,93 ns**, por unos 3,6 ns de desfase del CLKDIV. Lo descarté.
- **FM:** con los 27 MHz del cristal. El cruce de dominios lo resuelve la FIFO asíncrona del `host_if`. `pcm_out` cruza sin sincronizar, igual que en MoonTANG; con un reloj no emparentado podría romperse alguna muestra suelta.
- **`clk_eng`:** CLKDIV ÷3,5 desde los 135 MHz, es decir 38,57 MHz.
  - **Pega:** New Juice solo arranca `rpll_video` al final de su secuencia de arranque (`src/top.v:1440-1523`), así que el motor PCM estaría parado hasta entonces.
- **Alternativa sin medir:** `rpll_main` tiene `CLKOUTD3` declarado y sin usar (`src/rpll/rpll_main.v:19, 31, 64`), que da 108/3 = **36 MHz**.
  - Ventaja: independiza el motor del PLL de vídeo.
  - Inconveniente: está en el borde inferior de la ventana. El margen para parones baja a unos 48 ciclos por muestra, frente a 74 a 37,125 MHz.
- **Ojo:** el resumen del MCP de Gowin decía «CLEAN» con violaciones en los cruces de reloj. Las cifras buenas salen de «Numbers of Setup/Hold Violated Endpoints» del informe de timing (`wf6\trial_rpt\fuentes\chk.py`).

### 3.3 Redes globales

- **New Juice:**
  - PRIMARY **3/8**: `clkin`, `main_clk` y el reloj de la SDRAM.
  - LW **8/8**: `cpu_clk`, `sms_clk_54`, `hdmi_audio_clk` y varios resets.
  - Fuente: apartados 5 y 6 de `new-juice.rpt.txt`.
- **El OPL4 añade 2 PRIMARY** (`clk_eng` y los 54 MHz) y New Juice pasa a 5/8.
  - Las LW siguen en 8/8, pero Gowin las rellena con resets y no bloquea.
  - CLKDIV: 1 de 8 usado.
- **No es un obstáculo.** El 8/8 de PRIMARY de MoonTANG viene de su propio I2S y de su infraestructura, que New Juice no necesita.

### 3.4 Flash: dónde iría la YRW801 y si choca con New Juice

**Mapa de la flash de New Juice:**

| Rango | Contenido | Fuente |
|---|---|---|
| 0x000000-0x0DD89A | Bitstream (907 418 B) | — |
| 0x100000-0x11FFFF | Nextor | `Makefile:26` |
| 0x120000-0x123FFF | FM-PAC | `Makefile:28` |
| 0x124000-0x127FFF | SFG-01 | `README.md:249-253` |
| Desde 0x128000 | Libre | — |

- **La YRW801 va en 0x200000-0x3FFFFF**, igual que en MoonTANG (`fpga/src/yrw801_loader.v:37`; `MoonTANG\docs\WONDERTANG.md:19`). **No choca con nada.**
- **Copia a la SDRAM:**
  - Con el lector de New Juice (comando 03h a 27 MHz con pausa por byte, `src/spi_flash_reader.v:21, 74-100`), 2 MB tardarían unos 0,7 s.
  - New Juice tiene la CPU en /WAIT mientras copia sus ROMs. La YRW801 conviene copiarla en segundo plano después de soltar el bus.
  - En la prueba, los pines de la flash pasan del lector de New Juice al `flash_rw` de MoonTANG cuando se activa `flash_rom_loaded` (`wf6\trial_rpt\v4_nofranky_full\top.v:1866`).
  - Reutilizar el lector de New Juice ahorraría unas 400 de lógica.
- **El pin 63**, que MoonTANG usa como HOLD de la flash, está sin asignar en New Juice. No hay problema.
- **Efecto secundario útil:** como los dos mapas son compatibles, una misma flash puede tener a la vez las ROMs de New Juice y la YRW801. Esto importa para la opción de dos bitstreams (apartado 4.3).

### 3.5 Puertos

- **New Juice usa:**
  - 48h-49h y 88h-89h: Franky.
  - 7Ch-7Dh: OPLL (`src/top.v:789-790`).
  - 8Eh-8Fh: MegaRAM y depurador.
  - A0h-A1h y AAh-ABh: solo escucha.
  - FCh-FFh: mapper.
- **C4h-C7h y 7Eh-7Fh están libres.**
- **Lo que hay que tocar** (hecho en la prueba):
  - Añadir las lecturas del OPL4 (C4h de estado, 7Eh y 7Fh) a `mapper_port_read`, para que se activen `/BUSDIR` y la dirección del transceptor (`src/cd_demux.v:17-18`), y su dato a la OR de salida (`src/top.v:1790-1803`).
  - Añadir un tercer término al AND de `/INT` para los temporizadores de la FM (`src/top.v:1890-1898`).
- Si se quita la Franky, quedan libres 48h/49h y 88h/89h, y **dejan de funcionar los juegos de Franky**.

### 3.6 Mezcla y salida

**Cómo suena New Juice hoy:**
- La mezcla es **mono**, de 18 bits, sin saturación, y sale por `[16:1]` (`src/top.v:883-890`).
- **I2S** hacia el MAX98357A:
  - BCLK de 705,6 kHz nominales sacado de 27 MHz (`src/top.v:315-323`), con 32 bits por trama (`src/audio_drive.v:36-42`).
  - Eso da **unos 22 kHz de muestreo**, con L = R.
- **HDMI** a 44,1 kHz con +6 dB (`src/top.v:1296-1320`).

**Qué pasaría con el OPL4 metido tal cual:**
- Pierde el estéreo.
- Por I2S, todo lo que pase de 11 kHz se pliega o se pierde, cosa que el PCM a 44,1 kHz notaría.
- Por HDMI sonaría bien.
- En la prueba entra como séptimo término de la suma, desplazado `>>1`. Sin saturación hay riesgo de recorte.

**Arreglo:**
- Subir el I2S a 44,1 o 48 kHz (doblar el BCLK) y hacer la mezcla estéreo con saturación. Es poca lógica.
- Pero cambia el sonido de todo New Juice, no solo del OPL4. MoonTANG usa 48,2 kHz por I2S y 48 kHz por HDMI.

---

## 4. Licencia y camino práctico

### 4.1 New Juice: sin licencia

Lo he comprobado hoy:
- La API de GitHub devuelve `license: null`, con `pushed_at` del 2026-08-25T06:39:09Z.
- HEAD es `306ca0e` («update windows instructions»).
- El clon no tiene LICENSE ni COPYING, y ningún fichero propio del autor lleva cabecera.
- Conclusión: todos los derechos reservados. **No ha cambiado nada desde el 25/08.**

**Sí se puede:**
- leerlo;
- compilarlo en local para evaluar, que es lo que he hecho;
- implementar por nuestra cuenta lo que documenta en el README (protocolos de puertos, comportamiento de los mappers).

**No se puede:**
- copiar su código a tus repos;
- publicar un bitstream de New Juice modificado, ni un parche que contenga su código;
- distribuir la mezcla con el OPL4.

**Observación, no consejo legal:** el bitstream de New Juice ya incluye núcleos GPL-3 de jotego (jt49, jt51, jt2413 y jt89). Una licencia GPL-3 sería la natural para New Juice, y es un argumento amable para pedírsela.

### 4.2 MoonTANG: GPL-3, con piezas de otras licencias

Según `MoonTANG\CREDITS.md`, el conjunto es GPL-3. Del OPL4 «neto», lo que habría que llevar a New Juice es esto:

| Pieza | Licencia | Comentario |
|---|---|---|
| Núcleo FM OPL3 (gtaylormb) | LGPL-3.0-or-later | — |
| `afifo.v` (Gisselquist) | GPL-3 | Es la pieza que obliga a que el conjunto sea GPL-3. Se puede sustituir por una FIFO propia |
| Motor PCM (srg320, derivado de MAME) | BSD-3 | — |
| Tu pegamento: `opl4fm.v`, `opl4_pcm.v`, `wave_sdram.v`, `wv_to_sdram.v`, `yrw801_loader.v` y `flash_rw.v` | GPL-3 | El copyright es tuyo, así que **puedes relicenciarlo** (por ejemplo LGPL o BSD) para dárselo a lfantoniosi |
| `ip_sdram` de t.hara (cláusula no comercial) | No comercial | **No hace falta en New Juice**, que tiene su propio `sdram.v`. Se queda fuera |
| YRW801 | Copyright de Yamaha | No se distribuye nunca; la pone el usuario |

Un «módulo OPL4 para New Juice» se podría ofrecer como LGPL-3 (por el OPL3) más BSD-3. Eso es compatible con GPL-3 y, con matices, con una licencia permisiva. Lo único con lo que no encaja es con «todos los derechos reservados».

### 4.3 Opciones

| Opción | Qué supone | A favor | En contra |
|---|---|---|---|
| **A. Dos bitstreams en la misma WonderTANG y cambiar de core** | New Juice y MoonTANG tal cual. La flash es compatible (ROMs de NJ en 0x100000-0x127FFF, YRW801 en 0x200000). Cambiar de core es regrabar solo el bitstream en 0x000000 (`openFPGALoader -b tangnano20k -f <core>.fs`, ~907 KB) | Funciona **hoy**, sin tocar New Juice ni un problema de licencia, y cada core tiene el chip entero (con la Franky y con el OPL4 completo con HDMI) | No es simultáneo y hace falta un PC por USB para cambiar. **Sin comprobar en placa** que grabar uno no borre la zona del otro: openFPGALoader escribe por sectores; el modo «exFlash C Bin Erase» del Gowin Programmer, que usa MoonTANG, habría que confirmarlo. Tampoco he mirado si el GW2A permite arranque dual desde la flash para cambiar sin PC |
| **B. Proponer a lfantoniosi que integre el OPL4** | Le escribes tú; yo no he escrito a nadie. Le ofreces el módulo, el árbitro, los bancos de prueba y las cifras de v4. Él decide qué quitar, o hace una variante de build «NJ-MoonSound» sin Franky | Una sola distribución, mantenida por el autor, y sin conflicto de licencia si lo integra él | Depende de él, y New Juice lleva 41 días sin commits |
| **C. Que New Juice adopte una licencia compatible (GPL-3) y la integración la hagas tú** | Pedirle la licencia primero | Tú controlas el resultado y es publicable | Mantener un fork de un proyecto que evoluciona, con el chip al 95 % de CLS: cada actualización suya obliga a fusionar y volver a cerrar timing |
| D. Fork privado sin permiso | Solo para uso propio | — | No se puede publicar. No lo recomiendo |

---

## 5. Esfuerzo de una integración real

La prueba ya demuestra que v4 cabe y cierra timing (`wf6\trial_rpt\fuentes\opl4_nj.sv`, `nj_wave_arb.v` y `mkvar.py`, unas 12 líneas cambiadas en `top.v`). Esto es lo que falta:

| Tarea | Esfuerzo | Riesgo |
|---|---|---|
| Árbitro definitivo con refresco por temporizador propio y banco de pruebas con el adaptador de New Juice y el motor PCM (reutilizando `tb_pcm_bw.v`) | 2-3 días | Medio |
| Nuevo mapa de SDRAM: mapper de 2 MB, YRW801 y RAM de ondas con traducción de direcciones | 0,5-1 día | Bajo |
| Segmentar la ruta `mp_debouncer → sdrc_cmd_en` y cerrar timing con 1.9.11 Edu (la del autor) y con 1.9.12 | 1-2 días | Medio, con la CLS al 95 % |
| Reloj del motor independiente del PLL de vídeo (`CLKOUTD3` a 36 MHz, o arrancar antes `rpll_video`) | 0,5-1 día | Medio |
| Lectura de 7Fh con /WAIT o con `RD_MIRROR`, y latencia de la Z80 sin /WAIT con el OPL4 metiendo tráfico | 1 día más placa | Medio-alto |
| Audio: I2S a 44,1 o 48 kHz y mezcla estéreo con saturación | 1 día | Bajo |
| Copia de la YRW801 en segundo plano, reutilizando el lector de New Juice | 0,5 día | Bajo |
| Pruebas en la WT 2.02b: MoonBlaster/MBWave, SymbOS, Nextor y SD, mapper, SCC, OPLL, depurador… regresión de todo New Juice | 1-2 semanas de uso | Alto |
| **Total** | **Unas 2 semanas de desarrollo más 1-2 de pruebas** | |

A eso se suma, si integra él, el tiempo de lfantoniosi. Y, si es un fork tuyo, el mantenimiento continuo de seguir sus cambios con el chip lleno.

---

## 6. Recomendación

1. **No haría un fork propio de New Juice con OPL4.** No tiene licencia, el chip queda al 95 % de CLS, la ruta crítica de New Juice va al límite y el precio es la Franky, que es una función que sus usuarios tienen hoy.
2. **Para ya: la opción A.** New Juice y MoonTANG como dos cores en la misma WonderTANG, con las ROMs y la YRW801 grabadas a la vez en la flash. Lo único pendiente es comprobar en placa que grabar uno no pisa la zona del otro.
3. **Si quieres un solo core: escríbele tú a lfantoniosi** con dos propuestas:
   - que ponga licencia a New Juice (GPL-3 sería la natural, porque ya lleva núcleos GPL-3);
   - una variante de build «NJ-MoonSound» sin Franky. Le ofreces el módulo OPL4: tu pegamento relicenciado, `afifo` sustituida y sin el `ip_sdram` de t.hara.

   Con las cifras medidas de v4: 81 % de lógica, 95 % de CLS, 31 BSRAM y +1,0 ns en `main_clk`.
4. **Descartaría «solo FM».** Da un OPL3 sin wavetable, que no es un MoonSound; cuesta el SFG-01 y no cierra timing sin tocar New Juice.

---

## 7. Incidencia

A eso de las 16:00 la compilación de prueba lanzó `taskkill /IM gw_sh.exe` y mató tres procesos `gw_sh`. Coincidían con sus builds en marcha (v2, v3c y v3d), pero el filtro era por nombre. **Si al proceso que edita MoonTANG se le cortó una compilación hacia las 16:00, pudo ser esto.** Las mediciones de MoonTANG no tocaron su `fpga/impl` ni sus `build/`: usé copias en `wf6\mt_cost\` y `wf6\mt_head\`.

---

## 8. Ficheros

Todo está en `wf6\` (`C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\e19c5f05-c115-44f4-8d46-a0b0bdc94acb\scratchpad\wf6\`):

- `inventario.md`: inventario de New Juice, con cada dato referenciado a fichero:línea.
- `nj_src\`: clon de New Juice en `306ca0e`, con los submódulos en los commits que fija el repo.
- `nj_rpt\`: informes de New Juice.
  - `upstream_commit\`: el publicado.
  - `v1911\` y `v1912\`: mis compilaciones, con `desglose_modulos_syn.txt`.
  - `moontang_head_syn\`: el desglose de MoonTANG.
- `nj_build\`, `nj_build_1911\` y `nj_committed_impl\`: árboles de compilación y el `impl` original con el `.fs` publicado.
- `mt_cost\` y `mt_cost_rpt\`: coste del OPL4 por bloques.
  - Las variantes son `full_wt`, `full_hdmi`, `full_dbg0`, `nofm`, `nopcm` y `shell`.
  - `resumen_pnr.txt` y los logs de simulación en `sim\`.
- `mt_sim\`: `tb_pcm_bw.v` y los guiones del barrido de ancho de banda y latencia, que se ejecutan en WSL Ubuntu-24.04.
- `trial\` y `trial_rpt\`: las compilaciones de prueba v0 a v5 (`rpt`, `timing`, `top.v` y `top.sdc` de cada una) y `resumen_chk.txt`.
  - `trial_rpt\fuentes\`: `opl4_nj.sv`, `nj_wave_arb.v`, `mkvar.py`, `run.sh` y `chk.py`.
- `INFORME_NEWJUICE_OPL4.md`: este informe.


---

# Anexo A. Revisión técnica

# Revisión técnica del informe «¿Entra el OPL4 de MoonTANG en New Juice?»

Es una revisión de solo lectura. No he tocado el informe ni ningún repositorio (ni MoonTANG ni el clon de New Juice), y no he compilado nada en el repo vivo de MoonTANG. Lo único que he creado es el banco de simulación de `wf6\rev_sim\`.

**Veredicto de la revisión:** las cifras de recursos son correctas y la prueba no infla nada por poda, así que la conclusión principal se sostiene: tal cual no entra, y v4 (sin la Franky) cabe al 95 % de CLS. Pero el apartado 3.1, el de la SDRAM, es demasiado pesimista. Al simular el árbitro de la prueba, el Z80 no afecta al motor PCM. Además hay tres afirmaciones de timing que son falsas o no tienen base: «place 3 y 4», «el árbitro va justo ahí» y «v3 falla siempre / v4 cierra porque descongestiona».

---

## 1. Lo comprobado que está bien

**Recursos (2.1) contra los `.rpt`:** todo cuadra.
- New Juice publicado: 12546 / 9002 / 8157 / 46 / +0,065 ns. Mi compilación con 1.9.12: 12555 / 9008 / 8705 / +0,016 ns.
- v2: 15393 / 9881 / 12289, −0,538 ns con 64 endpoints. v3: 12707 / 8934 / 7883, 44 BSRAM.
- v4: 16784 / 9828 / 9316 / 31 BSRAM / 3,5 DSP / 5 PRIMARY, +1,024 ns y clk_eng a 43,665 MHz. v4 con 1.9.11: 17002 / 9769 / 9033, +0,089 ns y 42,55 MHz.
- v4base: 8788 / 6513 / 5187 / 16, +0,222 ns. v5: 15225 / 9351 / 8417 / 30, +0,450 ns y 41,45 MHz.
- Las restas v4 − v4base salen exactas: +7996 de lógica, +3315 CLS, +4129 FF, +15 BSRAM.
- El aborto de v1 es real: `ERROR (RP0006)` con 23273 = 19241 + 2034 + 6 × 333. Ocurre en GowinSynthesis.

**Poda.** No hay poda que abarate el OPL4. El `opl4_inst` de v4 coincide con el MoonTANG `full_dbg0` (sin telemetría):

| Bloque | v4 | MoonTANG `full_dbg0` |
|---|---|---|
| `u_opl4pcm` | 2739 FF, 4438 de lógica, 8 BSRAM, 2 DSP | 2738 FF, 4441 de lógica, 8 BSRAM |
| `u_opl4fm` | 928 FF, 7 BSRAM | 928 FF |

- Lo único podado es la telemetría `dbg_tx`/`diag` y el checksum y el diagnóstico del cargador de la YRW801 (unos 80 de lógica).
- Fuentes: `wf6\trial_rpt\v4_nofranky_full\desglose_modulos_syn.txt:106-114` y `wf6\mt_cost_rpt\full_dbg0.jerarquia.txt`.

**Otras comprobaciones correctas:**
- `CLKOUTD_SRC = "CLKOUT"` con SDIV 2 en `rpll_main.v`: los 54 MHz están en fase con `main_clk`, así que la restricción del SDC es coherente.
- Mapa de la SDRAM de New Juice en bytes, I2S a unos 22 kHz (BCLK de 710,5 kHz real, 32 bits por trama) y globales en 3/8 → 5/8.

---

## 2. Errores encontrados

### E1. Media-alta (3.1): la SDRAM compartida no es «el obstáculo de fondo»

**Qué dice el informe:**
- Es el obstáculo de fondo, «el problema es el arbitraje».
- El motor espera como mucho una operación de la CPU más un refresco, unos 150 ns.
- Con 16 bits a tono 2 ya se pierde velocidad con +74 ns.
- Lo del árbitro son cuentas, sin simular.

**Qué es verdad.** Lo he simulado con la cadena real de la prueba: `opl4_pcm` → `wave_sdram` → `nj_wave_arb` → `sdram.v` de New Juice → modelo de SDRAM. El cliente A es el `sdram_command_adapter` real de New Juice, movido por un Z80 sintético que encadena M1 con la espera del MSX, MR y MW sin parar, y llega con 170 ns de retardo de entrada. Resultados:

- **Espera del motor:** como mucho **una** operación. `W_PEND` llega a un máximo de **9 ciclos de 108 MHz (83 ns)**.
  - El motivo: mientras W está pendiente, el árbitro mantiene `a_busy` a 1 y el adaptador no puede lanzar un refresco detrás de la operación de la CPU.
- **Latencia de una operación de ondas:** 233 ns sin Z80 y 238 ns de media (311 máx.) con Z80 a 3,58 MHz. La cadena de MoonTANG (`wv_to_sdram` + `ip_sdram`) tarda **260 ns**, así que la de New Juice es **más rápida**.
- **Salida del PCM a 38,571 MHz** (ratio, sin Z80 / con Z80 a 3,58 MHz):

  | Caso | Sin Z80 | Con Z80 | MoonTANG |
  |---|---|---|---|
  | f2o1 | 1,000 | 1,000 | – |
  | f2o2 | 1,000 | 1,000 | – |
  | mezcla | 1,000 | 1,000 | – |
  | f2o3 | 0,842 | 0,842 | 0,8045 |
  | f2o5 | 0,759 | 0,744 | – |

  - Con el Z80 a 5,37 y a 7,16 MHz (hasta 1,95 M operaciones/s y 0,65 M refrescos/s), f2o2 y la mezcla siguen en 1,000 y f2o3 queda en 0,835.
- **Lado CPU:** una lectura tarda (de `cmd_en` a ack) 93 ns sin PCM. Con PCM llega a **167 ns** máximo (a 3,58 y 5,37 MHz) y a 176 ns a 7,16 MHz.
  - Las escrituras llegan a 20 ciclos como máximo, frente a 12 sin PCM.
  - No se pierde ninguna orden (`DROP=0`), los datos llegan bien (`BAD_CPU=0`, `BAD_W=0/13820`) y se sirve 1 refresco por M1.
- **El experimento de «+74 ns»** sumaba la latencia a **todas** las operaciones de la cadena de MoonTANG. Con el árbitro, la espera solo cae en las operaciones que coinciden con la CPU: +5 ns de media. Así que ese número no sirve como presupuesto de la integración.

**Evidencia:** `wf6\rev_sim\tb_nj_bw.v`, `set.sh` y `set2.sh`. Logs en `wf6\rev_sim\build\nj_*.log`, `r_*.log` y `k1.log`/`k2.log`.

**Lo que sí queda pendiente** (y no es caudal ni latencia):
- refresco propio por temporizador;
- mapa de memoria;
- prueba de la ruta de escritura (el cargador) y de `IN 7Fh`.

### E2. Media (2.1 y 3.1): «−0,075 ns (place 3 y 4)» es falso

- Las dos ejecuciones se lanzaron con `-place_option 0`, no con 3 ni con 4: `wf6\trial\runs\v3_nojt51_fm_p3\impl\pnr\cmd.do`, línea 12, y la de `_p4`.
- Los dos `cmd.do` solo se diferencian en las rutas. El `process_config.json` dice 3 y 4, pero Gowin escribió 0.
- Es la misma configuración repetida, y por eso los resultados son idénticos: CLS 8952 y los mismos caminos.

### E3. Media (3.1 y 1): «v3 falló siempre» y «v4 cierra porque quitar la Franky descongestiona» no tienen base

- v4 ocupa **más** CLS (95 %) que New Juice solo (87 %). No se puede hablar de descongestión.
- La misma ruta de New Juice, sin OPL4, ya varía mucho de una compilación a otra:
  - +0,016 ns (1.9.12);
  - +0,065 ns (la del autor);
  - **+0,654 ns** (mi recompilación con 1.9.11, `wf6\nj_rpt\v1911`, que el informe no pone en la tabla).
- v4 va de +1,024 a +0,089 ns, y v3 de −0,995 a −0,075.
- Esa dispersión, de 1 a 1,7 ns, es mayor que las diferencias con las que se ordenan las variantes. Con una sola compilación por variante no se puede afirmar que v3 no cierre ni que v4 cierre de forma robusta.

### E4. Media (3.1): «el árbitro va justo ahí» es falso

- La ruta crítica es `mp_debouncer/latched_*` → registros `sdrc_*` del cliente (`flash_roms`, `sdram_mapper` o `super_megaram`), y termina **antes** del adaptador.
- El árbitro es un multiplexor entre los registros del adaptador y los de `sdram.v`, que es otra ruta.
- En los 57 peores caminos de setup de v3, v4, v4 con 1.9.11 y v5 no aparece `opl4_arb_inst` ni `sdram_inst`.

### E5. Media (3.2): el cruce de la FM no es «igual que en MoonTANG»

- **En MoonTANG**, la FM va a `clk_27m` = CLKDIV ÷4 de `clk_108m` (`moontang_wt_shell.sv:129-131`). Es síncrono con `clk_54m` y Gowin lo analiza: `u_div27/CLKOUT.default_gen_clk` aparece en el timing de `full_wt`.
- **En la prueba**, la FM va al cristal `clkin`, que el SDC declara asíncrono de `opl4_clk54`. Así que el cruce de `pcm_out_l/r` (16 bits) **no se analiza**.
- Además, los dos relojes están enganchados por el PLL (54 = 2 × 27). Si falla, fallará de forma sistemática según el rutado, no en «alguna muestra suelta».
- Efecto sobre las cifras: la prueba se ahorra un global. Hacerlo como en MoonTANG costaría +1 CLKDIV y +1 PRIMARY (quedaría en 6/8).

### E6. Media-baja (3.2): `rpll_video` también se resetea con cada /RESET del MSX

- No solo se arranca al final del arranque. Cuando `reset_in_n` (el /RESET del MSX, `mp_debouncer`) baja:
  1. `cpu_modules_ready_reg` pasa a 0 (`top.v:1496-1501`);
  2. `module_sequence_done` pasa a 0;
  3. `video_pll_reset_n` pasa a 0 (`top.v:262-265`) y el rPLL de vídeo entra en reset.
- Por tanto, `clk_eng` se para con cada reset del MSX. `wave_sdram` solo tiene reset de encendido y puede quedarse a medias en el cruce. Es un riesgo que hay que probar.
- Esto refuerza la opción `CLKOUTD3` (36 MHz). Simulado a 36 MHz con Z80: mezcla y f2o2 dan 1,000; f2o3 da 0,782 y f1o3 0,8045 (frente a 0,842 y 0,857 a 38,57 MHz). Logs: `rev_sim\build\r_36_*.log`.

### E7. Baja-media (3.1): el solape del mapa de la prueba es mayor de lo que dice

- `nj_wave_arb` pone la onda `b` en el byte 0x400000 + b.
- La YRW801 pisa la MegaRAM (0x400000-0x5FFFFF), como dice el informe.
- La RAM de ondas (0x200000-0x3FFFFF de ondas) cae en 0x600000-0x7FFFFF y pisa **también las ROMs copiadas**: Nextor, FM-PAC y SFG en 0x600000-0x627FFF.

### E8. Baja (2.2): v1 sin límite de BSRAM tampoco cabría

- El «99,9 %» sale de síntesis. Como referencia, en v4 el place & route sube un 1,2 % sobre síntesis (16578 → 16784). Con eso v1 rondaría 20,97k > 20736, y la CLS pasaría del 100 %. **No cabría ni con BSRAM ilimitada.**
- Mezcla de unidades: «5 DSP» es la columna DSP* de síntesis, que va en MULT. En la tabla 2.1 «3,5 DSP» es el bloque del place & route.

### E9. Baja (2.2): v2 se compara con la base equivocada

- En New Juice tal cual, el JT51 ya está derramado a FF: 1080 FF y 10 BSRAM. El jt2413 también: 1165 FF y 2 BSRAM, frente a 776 FF y 3 BSRAM sin presión.
- v2 pasa del JT51 de **1080 FF y 10 BSRAM** a 3680 FF y 3 BSRAM, no de 814 y 11.
- La demanda natural de BSRAM de New Juice es **48**, no 46. Por eso v4base usa 16 BSRAM y no 14.

### E10. Baja (3.6): no es recorte, es desbordamiento con vuelta

- `audio_mix_wide[16:1]` tira el bit de signo.
- La suma de New Juice ya puede llegar a unos ±82k, por encima de 65,5k. Con el OPL4 (±16k) llega a unos 98k.
- El riesgo no es «recorte»: es **desbordamiento con vuelta**, que suena mucho peor.

### E11. Baja (3.2): la ventana de `clk_eng` dentro de New Juice es más estrecha

- «Fmax 45,8-49,5 MHz» es la cifra de MoonTANG solo.
- Dentro de New Juice sale **41,5-43,7 MHz** (v4, v4 con 1.9.11 y v5). El techo real de la ventana es de unos 41 MHz, y a 38,57 MHz el margen es del 7 al 13 %.

### E12. Baja: detalles de contabilidad

- Los FF de MoonTANG incluyen los de E/S (4822 = 4753 + 69 y 5879 = 5809 + 70). Los de New Juice solo cuentan los de lógica.
- Los porcentajes del `.rpt`, que Gowin redondea hacia arriba, no coinciden en tres casos: v4base sale al 43 % de lógica, y v5 al 74 % de lógica y 91 % de CLS.
- Las «109 violaciones de hold de −2,93 ns» del CLKDIV ÷2 no se pueden comprobar: no se guardó ningún artefacto de esa prueba.

### E13. Baja: Z80 en turbo

- El margen sin /WAIT solo se ha estimado a 3,58 MHz.
- A 5,37 MHz (2T = 372 ns), la cuenta de 200-250 ns más los 74-83 ns de árbitro deja muy poco margen.
- A 7,16 MHz, New Juice ya no llega aunque no haya OPL4.

---

## 3. Correcciones concretas

1. **En 3.1 y 5:** cambiar «una operación de la CPU más un refresco (~150 ns)» por «**una** operación, simulado: `W_PEND` máximo 9 ciclos = 83 ns».
   - Añadir que la CPU espera +74-83 ns como máximo (167-176 ns de `cmd_en` a ack, frente a 93 sin PCM).
   - Añadir que con Z80 a 3,58, 5,37 y 7,16 MHz la salida del PCM no cambia, y que la cadena de New Juice tarda 233 ns frente a los 260 de MoonTANG.
   - Rebajar «obstáculo de fondo» a lo que de verdad queda: refresco propio, mapa y pruebas de escritura y `IN 7Fh`. Quitar «son cuentas, no simulación» y citar `wf6\rev_sim\`.
2. **Quitar la frase de «+74 ns con 16 bits a tono 2» como presupuesto**, o dejarla aclarando que es latencia constante sobre la cadena de MoonTANG.
3. **v3:** cambiar «−0,075 ns (place 3 y 4)» por «−0,075 ns con `place_option` 0 (3 y 4 no se aplicaron; es la misma ejecución dos veces)».
4. **Ruta crítica:**
   - Añadir a la tabla la fila de New Juice con 1.9.11 (+0,654 ns, CLS 8953).
   - Sustituir «porque quitar la Franky descongestiona» por «la holgura de esta ruta varía de 1 a 1,7 ns entre compilaciones; una sola compilación no basta para distinguir v3 de v4».
   - Recomendar un barrido de semillas o de `place_option` antes de descartar v3.
5. **Quitar «el árbitro va justo ahí».** La ruta está en el cliente de New Juice y se segmenta igual con OPL4 que sin él.
6. **3.2, cruce de la FM:** corregir «igual que en MoonTANG». En MoonTANG la FM va a CLKDIV ÷4 de 108 MHz y se analiza; en la prueba va al cristal y no se analiza. Contar +1 PRIMARY y +1 CLKDIV para hacerlo bien.
7. **3.2, `rpll_video`:** añadir que New Juice resetea `rpll_video` con cada /RESET del MSX (`top.v:1496-1501` y `262-265`), así que `clk_eng` se para. Esto pesa a favor de `CLKOUTD3` (36 MHz), que la simulación da por buena (mezcla y f2o2 en 1,000).
8. **3.1, mapa:** completar «encima de la MegaRAM» con «y la RAM de ondas encima de las ROMs copiadas (0x600000-0x627FFF)».
9. **2.2:** decir que v1 no cabría ni con BSRAM ilimitada (el place & route suma un 1,2 % sobre los 20715 de síntesis) y aclarar que los «5» son MULT, no DSP del place & route.
10. **v2:** poner como base 1080 FF y 10 BSRAM, y decir que la demanda natural de BSRAM de New Juice es 48.
11. **3.6:** cambiar «riesgo de recorte» por «desbordamiento con vuelta», y pedir saturación o más bits en la mezcla.
12. **3.2:** decir que la Fmax de `clk_eng` dentro de New Juice es de 41,5-43,7 MHz.
13. **Contabilidad:** usar el mismo criterio de FF (lógica sola) y los porcentajes del `.rpt` (43 %, 74 %, 91 %). Marcar como no comprobable lo de las 109 violaciones de hold.
14. **Añadir el riesgo del turbo** (5,37 MHz) en el presupuesto sin /WAIT.
15. **Añadir que v4 es una integración incompleta.** Faltan:
    - el temporizador de refresco;
    - la traducción de direcciones;
    - el reloj de la FM bien hecho;
    - el checksum de la YRW801;
    - la mezcla estéreo y el I2S a 44,1/48 kHz.

    Todo esto suma unos cientos de LUT y FF más 1 PRIMARY, sobre un chip con 540 CLS libres.

---

## 4. Límites de la simulación

- El Z80 es sintético, con 170 ns fijos de retardo de entrada, y el cliente de New Juice está simplificado.
- Solo se simulan lecturas del motor: no entran las escrituras del cargador de la YRW801 ni la lectura de 7Fh desde la CPU.
- El modelo de SDRAM es funcional.
- Las 48 lecturas «X» de onda salen de direcciones X del motor durante la configuración, antes de la ventana de medida, y no tienen que ver con el árbitro.

**Ficheros:** todo está en `C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\e19c5f05-c115-44f4-8d46-a0b0bdc94acb\scratchpad\wf6\rev_sim\`:
- `tb_nj_bw.v` (el banco)
- `one.sh`, `set.sh`, `set2.sh` (se ejecutan en WSL Ubuntu-24.04)
- `build\*.log` (resultados)

---

# Anexo B. Revisión práctica y legal

REVISIÓN ADVERSARIAL DEL INFORME «¿Entra el OPL4 de MoonTANG en New Juice?», CON LENTE PRÁCTICA Y LEGAL

Revisión de solo lectura: no he editado ningún repo, no he hecho commit, push ni publicación, y no he escrito a nadie. Mi única escritura son dos ficheros de comparación en `scratchpad\wf6_rev\` (a.txt y b.txt).

== Resumen ==
- El informe acierta en lo principal: New Juice (NJ) sigue sin licencia, su flash y sus puertos están bien descritos, no se propone copiar ni distribuir código de NJ, y la YRW801 está bien tratada.
- Pero tiene tres problemas:
  - **Falta una alternativa con licencia.** lfantoniosi/WonderTANG es BSD-2, del mismo autor y para la misma placa, y el informe no la menciona.
  - **Dice algo falso sobre el copyright de dos ficheros del pegamento de MoonTANG.** `flash_rw.v` deriva de código BSD-2 de lfantoniosi y `opl4fm.v` de un wrapper BSD-3 de Jokin Miragaia.
  - **La opción A está menos aterrizada de lo que parece** para un usuario normal de WT 2.02b.

== Errores y omisiones ==

**1. ALTA. Omite la base con licencia: el firmware WonderTANG original es BSD-2.**
- Qué dice: «en cualquier variante hay un límite previo: New Juice sigue sin licencia; lo que salga solo vale para uso privado». Ni las opciones A-D ni la recomendación contemplan otra base.
- Qué es verdad:
  - Por la API de GitHub, `lfantoniosi/WonderTANG` tiene licencia BSD-2-Clause (pushed_at 2026-07-31).
  - Hay un clon local en `C:\Users\alber\proyectosAI\msx\WonderTANG-ref` (LICENSE «BSD 2-Clause, Copyright (c) 2023, lfantoniosi»).
  - Soporta la V2.0b (README:214) e implementa:
    - Nextor 2.1 con microSD;
    - OPLL + MSX-Music;
    - Super MegaRAM SCC+ de 2 MB;
    - mapper de 4 MB;
    - Franky (README:9-15).
  - Usa el mismo mapa de flash, con Nextor en 0x100000 (README:238).
- Consecuencia: existe un camino de «WonderTANG + OPL4» **publicable sin permiso del autor**. Sería opción E: BSD-2 + GPL-3, conservando los avisos.
- Matices que hay que contar:
  - Le faltan SFG-01, depurador, osciloscopio y Nextor 3.
  - Lleva VM2413 (Okazaki), con cláusula no comercial, y el PSG de MikeJ.
  - No sabemos sus recursos: habría que compilarlo.
  - En la 2.0b reutiliza los pines JTAG (README:226: mantener S1 pulsado para regrabar).
  - El propio README remite a new-juice para la 2.02b.
- Sirve además como argumento para la opción B: el autor ya licencia su trabajo anterior con BSD-2.

**2. MEDIA-ALTA. «Tu pegamento (…) `flash_rw.v` (…) el copyright es tuyo, así que puedes relicenciarlo» (apartado 4.2) es falso en parte.**
- `flash_rw.v` deriva del `fpga/src/flash.v` de WonderTANG:
  - mismo `module flash`, mismo parámetro `STARTUP_WAIT` y mismos estados `STATE_INIT_POWER`…`STATE_LOAD_ADDRESS_TO_SEND`;
  - 105 de sus 113 líneas únicas están en `flash_rw.v` (comparación en `scratchpad\wf6_rev\`).
  - Es BSD-2 © 2023 lfantoniosi.
  - `MoonTANG\CREDITS.md` lo atribuye mal («Papipapito project», GPL-3.0), y `THIRD_PARTY\NOTICE.md` no lleva su aviso BSD-2.
- `opl4fm.v` adapta `cartridge_opl3.sv` de mangOPL4, que es BSD-3 © 2026 Jokin Miragaia (cabecera, líneas 14-15, de `antxiko/tnCartWonder` `rtl/src/cartridge_opl3.sv`; el repo mangOPL4 no tiene LICENSE).
  - Se puede relicenciar lo de Albert, pero conservando el aviso BSD-3. NOTICE.md tampoco lo recoge.
- `wv_to_sdram.v` no forma parte del módulo para NJ: es el puente a `ip_sdram`, y `opl4_nj.sv` lo excluye. Sobra en esa lista.
- Lo que sí es propio de Albert (con Claude): `opl4_pcm.v`, `wave_sdram.v` y `yrw801_loader.v`.

**3. MEDIA. «Lo único con lo que no encaja es con "todos los derechos reservados"» (4.2) es impreciso.**
- La LGPL-3 (§4, Combined Works) permite combinar con código no libre si se entrega el fuente LGPL y la forma de recombinar; NJ ya publica su fuente. BSD-3 encaja con cualquier cosa.
- Por tanto, lfantoniosi podría integrar un módulo LGPL/BSD sin relicenciar NJ. El bloqueo de «todos los derechos reservados» es solo para Albert, que no puede distribuir derivados de NJ.
- Si el módulo conserva `afifo.v` (GPL-3), entonces sí exige GPL-3.
- Además, NJ ya contiene más código GPL-3 del que cita el informe:
  - jt49 (fork de lfantoniosi), jt51, jt2413 y jt89;
  - `sd_reader.sv` de WangXuan95 (GPL-3.0 según la API), que el informe no cita;
  - probablemente `sdram.v` de nand2mario (nestang es GPL-3; el fichero no lleva licencia en la cabecera).

**4. MEDIA. La opción A es menos realista para un usuario típico de WT 2.02b.**
- Con MoonTANG cargado, la WT pierde Nextor/SD, MegaRAM, mapper, SCC, FM-PAC y SFG-01. El software MoonSound tendría que cargarse desde otro almacenamiento y con la RAM del propio MSX.
- Para quien usa la WT como su SD y su RAM, la opción A apenas sirve.
- En el caso de Albert sí vale: el MSXBOOK/OCM tiene SD y mapper propios.
- El informe solo dice «no es simultáneo».

**5. MEDIA. Falta la opción de dos cartuchos a la vez.**
- NJ en un slot y MoonTANG en otra TN20K: otra WT 2.02b, o la MSXhdmi_tn20k_smd con `moontang_smd`.
- Es simultáneo, sin licencias de por medio y sin regrabar nada.
- No hay choque de puertos:
  - NJ usa 48-49, 7C-7D, 88-89, 8E-8F y lecturas de FC-FF (`top.v:790, 995, 998`; `super_megaram.v:100-102`; `sdram_mapper.v:68`).
  - MoonTANG solo decodifica C4-C7 y 7E-7F (`opl4fm.v:73,77`; `opl4_pcm.v:96-97`).
- Coste: otra TN20K con su portadora y un slot libre.

**6. MEDIA-BAJA. Detalles de la opción A mal atribuidos o incompletos.**
- **Modo de borrado.** MoonTANG no graba su bitstream con «exFlash C Bin Erase»: ese modo es solo para la YRW801 en 0x200000. El bitstream va en «External Flash mode» (`MoonTANG\docs\WONDERTANG.md`, tabla «What to flash»).
  - El riesgo real es el borrado al grabar el bitstream. La guía Windows de NJ usa «exFlash Erase,Program thru GAO-Bridge» en 0x000000 (`nj_src\images\win-program-fs.png`).
  - `WONDERTANG.md` ya avisa: «erasing the flash for a new bitstream also wipes the area after it», y a mangOPL4 le pasó dos veces.
- **Tamaños.** Los dos bitstreams miden 907 418 B: `MoonTANG\fpga\files\20261005\*.bin` y `nj_src\impl\pnr\new-juice.bin`. Acaban en 0x0DD89A, por debajo de 0x100000. El informe solo da el tamaño de NJ.
- **Ya probado en placa.** Albert ya pasó su WT 2.02b de NJ a MoonTANG el 05/10 y validó los dos cores (memoria `msxbook_fpgacard.md:44-45`, `msx_opl4_wondertang_tn20k.md:259`).
  - La comprobación pendiente son cinco minutos: `make reprogram` de NJ y ver si arranca Nextor; si no, `make roms`.
  - MoonTANG ya muestra «YRW801 OK / NO VALIDA» con suma de comprobación.
- **Variante sin tocar la flash.** Se puede dejar NJ en la flash y cargar MoonTANG en SRAM por USB (openFPGALoader sin `-f`). Es volátil y no escribe nada en la flash. `WONDERTANG.md` lo documenta.
- **Pista de arranque dual, sin verificar.**
  - `new-juice_process_config.json` tiene `"MSPI_JUMP": false`.
  - El Programmer menciona un «DUAL BOOT mode».
  - El plan BookTANG de Albert ya cuenta con «multiboot GW2A».
- **No hace falta el truco de S1.** Ni NJ (`"JTAG": false`) ni MoonTANG (`fpga/build.tcl:76-81`, solo MSPI/SSPI como GPIO) reutilizan JTAG. El truco de S1 es del firmware WonderTANG antiguo.

**7. BAJA-MEDIA. Tensión de licencias dentro del propio MoonTANG, no tratada.**
- MoonTANG declara GPL-3 por `afifo.v` y a la vez incluye `ip_sdram` de t.hara, con cláusula no comercial. La GPL-3 (§10) prohíbe añadir restricciones.
- Solo se salva si rige la MIT de la raíz del repo de t.hara.
- Afecta a publicar MoonTANG (hoy es privado), no al uso privado de la opción A.
- Sustituir `afifo.v`, que el informe ya propone para NJ, lo arreglaría también en MoonTANG. Otra vía: que t.hara confirme la MIT.

**8. BAJA. «Lo que salga solo vale para uso privado» (veredicto y opción D) sobrestima.**
- Sin licencia, ni la modificación privada está amparada expresamente: el art. 100 de la LPI cubre solo los actos necesarios para el uso previsto. Es tolerancia de hecho, no un derecho.
- Mejor: «solo evaluación privada, sin distribuir».

**9. BAJA. El apartado 5 (esfuerzo) se puede leer como un plan de trabajo para Albert.**
- Segmentar la ruta de NJ, reutilizar su lector de flash, rehacer su mapa de SDRAM… todo eso es modificar código de NJ. Solo cabe en la opción B (lo hace lfantoniosi) o en la C (tras la licencia), y el informe debe decirlo.
- Igual en 3.4: «Reutilizar el lector de New Juice».

**10. BAJA. Fuera de mi lente, pero lo anoto.**
- En 3.6, «L = R» no es exacto. `audio_drive.v` carga `idata` en cada media trama (req en bit 0 y 16), así que L y R llevan muestras consecutivas de la mezcla mono.
- «Pierde el estéreo» solo vale para HDMI: por SOUNDIN la WT es mono tanto con NJ como con MoonTANG (`WONDERTANG.md`: «in mono»).

**11. BAJA. Documentación de MoonTANG desfasada (aparte, no es del informe).**
- `docs\WONDERTANG.md` dice «Not yet run on hardware», pero se validó el 05/10.
- El aviso de S1/JTAG no aplica a los bitstreams de MoonTANG.

== Comprobado y correcto ==
- **Licencia de NJ:** la API devuelve `license: null`; `/license` da 404; pushed_at 2026-08-25T06:39:09Z; HEAD 306ca0e. Ninguna de las tres ramas (master, v101c y v102d) tiene LICENSE; el informe no menciona las ramas y conviene añadirlo. Sin releases ni tags. Lleva 41 días sin commits.
- **Flash de NJ:**
  - `Makefile:24-28`: DOS2 en 1048576 = 0x100000 y FM en 1179648 = 0x120000.
  - README:249-253: SFG-01 en 0x124000.
  - `flash_roms.v:40-42`: 0x28000 B a la SDRAM en 0x600000.
  - NJ solo lee la flash (`spi_flash_reader.v:21`, comando 03h). No escribe, así que no pisa 0x200000.
- **Puertos y funciones:** como dice el informe. C4-C7 y 7E-7F están libres.
- **Commit 42ff17bf:** existe en GitHub (08/08, «remove AB header, remove memory-waits»). El clon local es shallow y no lo contiene.
- **Licencias de MoonTANG:**
  - opl3_fpga: LGPL-3.0, confirmado en la API y en la cabecera («or later»).
  - `afifo.v`: GPL-3.
  - YMF278B de srg320: BSD-3.
  - `ip_sdram` de t.hara: no comercial y excluido del módulo.
  - YRW801: el usuario la pone y nunca se distribuye.
- **No se propone copiar ni distribuir código de NJ:** correcto. Las pruebas (`trial\`, `top.v` modificado) quedan en scratch. Ojo: `opl4_nj.sv` y `mkvar.py:176-179` meten `afifo.v` y `flash_rw.v`.
- **Incidencia del taskkill:** bien declarada.

== Correcciones concretas ==
1. **Opción E nueva:** integrar el OPL4 en lfantoniosi/WonderTANG (BSD-2), con sus matices (sin SFG-01 ni depurador, VM2413 no comercial, recursos sin medir). Reescribir el veredicto: «con New Juice, solo evaluación privada; con WonderTANG BSD-2 sí es publicable».
2. **Opción A' nueva:** NJ y MoonTANG en dos cartuchos a la vez, sin choque de puertos.
3. **Opción A:**
   - Decir que con MoonTANG se pierden SD, Nextor y RAM.
   - Corregir el modo de borrado (bitstream en «External Flash mode»; «C Bin Erase» solo para la YRW801) y citar el aviso de `WONDERTANG.md`.
   - Dar los 907 418 B de los dos bitstreams.
   - Proponer la comprobación de cinco minutos sobre la WT de Albert, que ya llevó los dos cores el 05/10.
   - Añadir la variante de MoonTANG en SRAM y la pista, sin verificar, de MSPI_JUMP / arranque dual.
4. **Apartado 4.2:**
   - `flash_rw.v` es derivado BSD-2 © lfantoniosi: no es de Albert y hay que conservar el aviso.
   - `opl4fm.v` es derivado BSD-3 © Jokin Miragaia: se puede relicenciar conservando el aviso.
   - Quitar `wv_to_sdram.v` de la lista.
   - Sustituir «lo único con lo que no encaja…» por la explicación LGPL §4 del error 3.
5. **Apartado 4.1:**
   - Añadir que se miraron las tres ramas.
   - Ampliar la lista de GPL-3 en NJ con `sd_reader` (WangXuan95) y probablemente `sdram.v`.
   - Usar como argumento para pedir licencia que su WonderTANG ya es BSD-2.
6. **Apartados 3.4 y 5:** indicar que esas tareas solo son posibles en las opciones B o C.
7. **Veredicto y opción D:** «uso privado» pasa a «evaluación privada, sin distribuir».
8. **Nota aparte para MoonTANG, antes de hacerlo público:**
   - Corregir CREDITS.md y NOTICE.md (`flash_rw.v` BSD-2 de lfantoniosi; wrapper BSD-3 de Jokin Miragaia).
   - Resolver GPL-3 frente a la cláusula no comercial de t.hara: sustituir `afifo.v` o que t.hara confirme la MIT.
   - Actualizar `WONDERTANG.md` («Not yet run on hardware» y el aviso de S1).
9. **Apartado 3.6:** matizar «L = R» y que el estéreo solo se pierde en HDMI.

== Evidencia principal ==
- `C:\Users\alber\proyectosAI\msx\WonderTANG-ref\LICENSE`, `README.md:1-15, 214, 226, 238`
- `C:\Users\alber\proyectosAI\msx\WonderTANG-ref\fpga\src\flash.v` frente a `C:\Users\alber\proyectosAI\msx\MoonTANG\fpga\src\flash_rw.v`
- `C:\Users\alber\proyectosAI\msx\MoonTANG\CREDITS.md`, `THIRD_PARTY\NOTICE.md`, `docs\WONDERTANG.md`, `fpga\src\opl4fm.v` (cabecera), `fpga\build.tcl:75-81`
- `C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\e19c5f05-c115-44f4-8d46-a0b0bdc94acb\scratchpad\wf6\nj_src\`: `Makefile`, `README.md`, `impl\new-juice_process_config.json`, `images\win-program-fs.png`, `src\top.v`, `src\audio_drive.v`, `src\flash_roms.v`, `src\spi_flash_reader.v`
- `...\scratchpad\wf6\trial_rpt\fuentes\opl4_nj.sv` y `mkvar.py:176-179`
- API de GitHub:
  - lfantoniosi/new-juice: license null, ramas master, v101c y v102d.
  - lfantoniosi/WonderTANG: BSD-2-Clause.
  - WangXuan95/FPGA-SDcard-Reader: GPL-3.0.
  - gtaylormb/opl3_fpga: LGPL-3.0.
  - antxiko/tnCartWonder: BSD-3-Clause; `rtl/src/cartridge_opl3.sv`, BSD-3 © Jokin Miragaia.
  - nand2mario/nestang: GPL-3.0.
- Memoria: `msxbook_fpgacard.md:44-45`, `msx_opl4_wondertang_tn20k.md:259`
