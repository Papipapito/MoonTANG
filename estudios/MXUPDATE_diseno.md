# MXUPDATE en MoonTANG: diseño

Fecha: 05/10/2026. Estado: diseño, sin implementar. Todo lo que aparece se ha hecho en solo lectura: no se ha tocado ningún repositorio y no se ha sintetizado con Gowin.

Rutas cortas:
- **M** = `C:\Users\alber\proyectosAI\msx\MoonTANG` (rama main; los cambios que se veían sin commitear durante el estudio eran los arreglos 1-3, commiteados después en aa7e0a4 + 5400f15).
- **X** = `...\msx\MSXimus` (rama V3.8).
- **N** = `...\msx\MSXnano` (rama v2.1.1).
- **Z** = `...\msx\MSXimus_zynq\fpga\zynq\ota`.
- **WF** = `C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\e19c5f05-c115-44f4-8d46-a0b0bdc94acb\scratchpad\wf4`.

Marcas: **[C]** = comprobado por mí en el código, en un binario o en simulación. **[I]** = dato de uno de los cuatro informes que no he vuelto a comprobar. **[S]** = supuesto.

---

## 0. Veredicto

**Es viable, con condiciones.** El puente de la flash del MSXimus V3.8 (`flash_bridge.v`) entra en MoonTANG sin modificarlo, envuelto en un módulo propio (`moontang_flashport.v`). MXUPDATE necesita una versión 1.3 con dos placas nuevas. Las condiciones no son opcionales:

1. **No basta con copiar el puente del MSXnano tal cual.** MoonTANG y MSXnano tienen el mismo IDCODE (0000081B) y el mismo tamaño de bitstream [C]. Con el ID 4Dh y la firma Ah, el MXUPDATE 1.2 que ya está publicado tomaría el cartucho por un MSXnano. Le grabaría el core del MSXnano y 512 KB del pack encima de la YRW801 [C, ver §2]. Por eso el MoonTANG usa el **ID 6Dh y la firma Bh**.
2. **La ventana de escritura del RTL tiene que congelar la dirección.** La ventana del prototipo (`WF\rtl\new\moontang_flashport.v`) se puede saltar: se acepta la orden y después se cambia la dirección con `OUT #41`. Lo he demostrado en simulación (§3.2.4) y el arreglo es una línea.
3. **La variante se identifica en el hardware, no la elige el usuario.** El core en marcha informa por `#4F` de qué placa es, y el bitstream lleva un USERCODE propio de cada variante. Así un core de WonderTANG nunca acaba en una SMD ni al revés.
4. **Nada de la YRW801 pasa por MXUPDATE ni por el servidor.** Solo se graba el bitstream (≤ 0x200000), y el RTL lo impone.
5. **No se publica nada hasta probarlo en placa.** Eso incluye las carpetas de MoonTANG en msx.barcelona y MXUPDATE 1.3, que se autoactualiza en todos los MSXimus y MSXnano.

Hay dos partes que no conviene prometer:
- **La SMD sin `/BUSDIR`:** en los MSX que lo necesitan, el puente no se ve. El fallo es seguro (no se graba nada) y es la misma limitación que ya tienen C4h y 7Eh.
- **Un MSX sin almacenamiento masivo:** el .UPD (907.674 B) no cabe en un disquete de 720 KB. Para esos usuarios la vía es el USB.

El "ordenador con internet" que pide el dueño encaja de tres formas (§4):
- el PC baja el .UPD y lo copia a la SD del MSX (la vía principal);
- el PC sirve el fichero en la red local y el MSX lo pide con `/N /S:` (vale con tarjetas de red sin TLS);
- el MSX va directo a msx.barcelona, solo si tiene un UNAPI con TLS (los firmwares ESP de ducasp).

---

## 1. Lo que he comprobado yo (no me he fiado de los informes)

| Dato | Cómo | Resultado |
|---|---|---|
| IDCODE de los tres .bin de MoonTANG y del MSXnano | `xxd` de `M\fpga\impl\pnr\moontang_{smd,wt,wt_hdmi}.bin` y `N\fpga\impl\pnr\project.bin` | Los cuatro llevan `A5 C3 06 00 00 00 00 00 08 1B` en 0x16 → 0000081B; los cuatro miden 907.418 B [C] |
| USERCODE | Final de los .bin (0xDD87C) y cabecera del .fs | `0A 00 00 00` + 4 bytes = USERCODE; hoy es el checksum: SMD 0x60EC, WT 0x6D9A, WT-HDMI 0xC817, nano 0xD774 [C]. Los informes daban otros valores porque los .bin se han regenerado a las 12:31 |
| Opción para fijar el USERCODE | Texto de `C:\Gowin\Gowin_V1.9.12.03_x64\IDE\doc\EN\SUG1220-2.0E_...Tcl Commands User Guide.pdf` | Existe `set_option -user_code <default\|value>`, y también `-bit_compress`, `-multi_boot` y `-mspi_jump` [C en el documento]. No he comprobado que el GW2AR-18 las acepte [S] |
| Peligro con MXUPDATE 1.2 | `X\tools\mxupdate\mxupdate.c` | Detección en :769; placa por IDCODE en :800, con la fila `{0x0008,"msxnano",...,0x20}` en :270; regla de segmentos en :838-848; comprobación de IDCODE en :873; `/R` en :923-925 [C]. `Z\servidor\msxnano\211_n214_es.upd` trae un segmento 0x000000 de 0xDD89A B y otro 0x200000 de 0x80000 B [C] |
| El cargador de la YRW801 | `M\fpga\src\yrw801_loader.v` (igual que la instantánea de WF) | `FLASH_BASE=0x200000` (:37). En S_WAIT no hay perro guardián (:108). En S_DONE deja `terminate=1` y `wl_done=1` (:172-176). `wl_done` sube aunque fallen los reintentos (:112-114) [C] |
| Núcleo actual | `M\fpga\src\moontang_core.sv` | `u_flash` con la escritura atada a 0 en :244-251; `any_rd` y `rd_data` en :256-257; `bus_ok` en :281; `loader_start` en :228 [C] |
| flash_rw de MoonTANG frente a V3.8 | `diff` contra `N\fpga\src\flash_rw.v` (igual byte a byte que el de X) | Solo cambian los 3 puertos, la rama `noerase`, la espera de `din_ok`, el reinicio de `wip_timeout` e `idle` [C] |
| Reset del puente en las otras placas | `N\fpga\top.v:2317`, `X\fpga\top.v:5021` | Los dos usan `bus_reset_n`, no el de encendido que pide el comentario de `flash_bridge.v:25` [C] |
| **Agujero en la ventana del prototipo** | Banco nuevo `WF\diseno\sim\tb_carrera.v` | Sin el arreglo, la YRW801 se borra (2 de 3 casos). Con él, 3/3 y 31/31 a 3,58 y 7,16 MHz [C, §3.2.4] |
| Margen de MXUPDATE | `WF\mxupdate\mxupdate.map` | CODE 0100h-48C7h, HOME hasta 4AB4h, INITIALIZER hasta 4AECh, DATA desde 8000h: quedan 13.587 B [C] |

---

## 2. Por qué no vale el puente del MSXnano tal cual

Esto es lo que hace hoy MXUPDATE 1.2 [C, `mxupdate.c`]:
- `OUT #40,4Dh` y da el puente por bueno si `IN #40 = B2h` y `IN #41 & F0h = A0h` (:768-769).
- Lee 256 B de la flash en 0 y saca el IDCODE (:796-800).
- Elige la placa por `IDCODE[23:8]`. 0x0008 es `msxnano`, con el pack en 0x20 → 0x200000 (:270).
- Comprueba que el `.UPD` es de esa placa (:832-836).
- Acepta segmentos en 0, en `pack` (≤512 KB) y en `pack+1 MB` (:838-848).
- Exige el mismo IDCODE en el bitstream del fichero (:873).
- Con `/R` borra `pack+512 KB` = 0x280000 (:923-925).

Si MoonTANG contestara como un MSXnano:
- 1.2 diría "Core instalado: 15.15.0 (msxnano)": los puertos #2F/#29 no son del cartucho y leen FFh [S].
- Con `MSXNANO.UPD` o `/N` grabaría el core del MSXnano en el cartucho, con su pinout sobre el bus del MSX (README.md:32-33: nunca).
- Escribiría 512 KB de pack en 0x200000, encima de la YRW801.
- Con `/R` borraría además 0x280000.

El banco de MXUPDATE del informe mxupdate lo reproduce [I: `WF\mxupdate\banco_mt_salida.txt`, 23/23]. Como MXUPDATE se autoactualiza y la 1.2 ya está en msx.barcelona y en SD Maker, **hay que suponer que cualquier MSX con un MoonTANG puede tener la 1.2**. La protección tiene que estar en el RTL del MoonTANG.

---

## 3. Arquitectura

### 3.1 Vista general

```
 slot MSX ──> front-end de la placa (wt_bus / smd_bus) ──> moontang_core (clk_54m)
                                                            ├─ opl4fm     C4h-C7h
                                                            ├─ opl4_pcm   7Eh-7Fh
                                                            └─ moontang_flashport  #40-#4F (NUEVO)
                                                                 ├─ registro de ID #40 (6Dh = nosotros)
                                                                 ├─ flash_bridge.v (X V3.8, sin tocar)
                                                                 ├─ ventana: borrar/programar solo < 0x200000
                                                                 ├─ #4C/#4D versión, #4E idioma, #4F placa
                                                                 └─ flash (flash_rw.v V3.8)  <── yrw801_loader (lectura, solo al arrancar)
                                                                       └─ MSPI pines 59-62 -> flash SPI de la Tang
```

Mapa de la flash de la Tang (8 MB; sectores de 4 KB, páginas de 256 B):

| Zona | Qué hay | ¿Lo escribe MXUPDATE? |
|---|---|---|
| 0x000000-0x0DD899 | bitstream (907.418 B) | Sí: 222 sectores de 4 KB |
| 0x0DD89A-0x1FFFFF | libre | El RTL lo permite y MXUPDATE no lo usa |
| 0x200000-0x3FFFFF | YRW801 (2 MB, la pone el usuario) | **No: el RTL lo prohíbe** |
| 0x400000-0x7FFFFF | libre | No |

### 3.2 RTL

#### 3.2.1 Ficheros

| Fichero | Cambio |
|---|---|
| `M\fpga\src\flash_rw.v` | Sustituir por el de X V3.8 (igual que N). Solo añade el camino de escritura del puente; la lectura del cargador no cambia [C, diff] |
| `M\fpga\src\flash_bridge.v` | Nuevo: copia exacta de X V3.8 (md5 7b36ebac…, igual en N) [C] |
| `M\fpga\src\moontang_flashport.v` | Nuevo: partir del prototipo `WF\rtl\new\moontang_flashport.v` con los cambios de §3.2.2-3.2.6 |
| `M\fpga\src\moontang_core.sv` | Quitar `u_flash` (:244-251); instanciar `u_fport` detrás de `bus_ok`; `any_rd = opl4fm_rd \| opl4pcm_rd \| fbr_rd_hit`; `rd_data = opl4fm_rd ? fm : fbr_rd_hit ? fbr : pcm`. Parámetros nuevos: `FBR_PLACA`, `FBR_VER`, `FBR_PAR`. Unas 20 líneas (diff del prototipo en `WF\rtl\new\core_fbr.diff`) |
| `moontang_wt_shell.sv`, `moontang_top.sv`, `moontang_wt_hdmi_top.sv`, `moontang_smd_top.sv` | Pasar `FBR_PLACA` (1, 2 o 3) y la versión hasta el núcleo. La WT pasa por `moontang_wt_shell` (:197) |
| `M\fpga\build.tcl`, `build_smd.tcl`, `build_wt_hdmi.tcl` | `add_file src/flash_bridge.v`, `add_file src/moontang_flashport.v`, `set_option -user_code 4D5400vv` |

Nota (05/10, tarde): lo que se veía editándose en `moontang_core.sv`, `yrw801_loader.v`, `opl4_pcm.v` y `opl3/timer.sv` eran los arreglos 1-3, ya commiteados (aa7e0a4). La integración parte de ahí. El diseño solo usa del cargador `fl_*`, `wl_done`, `wl_error` y `wl_badimg`, no su interior.

#### 3.2.2 Mapa de E/S (dispositivo de E/S conmutada, ID 6Dh)

| Puerto | OUT | IN (solo con 6Dh seleccionado; si no, el cartucho no conduce) |
|---|---|---|
| #40 | ID (todos lo guardan) | `~6Dh = 92h` |
| #41 | A[23:16] (**ignorado con una orden en curso**) | estado: `1011 b3 b2 b1 b0` (firma **Bh**). b3 = la flash la usa el cargador, b2 = hay dato, b1 = espera dato, b0 = ocupado |
| #42 | A[15:8] (**ignorado con una orden en curso**) | A[15:8] |
| #43 | orden: 1 borrar 4K, 2 programar página, 3 leer, 0 parar | FFh |
| #44 | dato a programar | dato leído (y pide el siguiente) |
| #4C | — | parche de la versión (lo que en el MSXimus es #29) |
| #4D | — | versión `mayor<<4 \| menor` (lo que en el MSXimus es #2F) |
| #4E | (lo guarda el puente, sin efecto) | constante `05h` = idioma inglés para MXUPDATE (parámetro) |
| #4F | — | `{rechazo, wl_error, wl_badimg, wl_done, placa[3:0]}`; placa 1 = WonderTANG, 2 = WonderTANG+HDMI, 3 = MSXhdmi SMD |
| #45-#4B | — | FFh |

- **Por qué 6Dh y además Bh** (los informes rtl y mxupdate proponían una cosa cada uno):
  - Con 6Dh, MXUPDATE ≤1.2 no ve nada (`IN #40` = FFh) y sale con "Hace falta…" sin tocar la flash (`mxupdate.c:784-788`).
  - Con 6Dh tampoco hay choque si algún día el anfitrión tiene su propio 4Dh, por ejemplo un goauld con puente. Con dos 4Dh, los `OUT #43` irían a las dos flash a la vez.
  - La firma Bh no cuesta nada y cubre un error de build (que se quede el 4Dh): la 1.2 exige A0h (:769).
  - Que 6Dh no lo use nadie está **sin verificar** [S]. Ya usados en el ecosistema: 08h (Panasonic, `N\fpga\top.v:2139-2149`), 48h (goauld), 4Dh y D4h (OCM) [I].
- **#4E constante 05h:** la documentación de MoonTANG está en inglés, así que MXUPDATE sale en inglés salvo con `/ES`. Decide el dueño (P5).
- **#4C/#4D:** MXUPDATE muestra la versión instalada sin leer #29/#2F, que en un MSX de verdad no son del cartucho.
- **Firma y `~ID` en el envoltorio.** `flash_bridge.v` devuelve B2h y `1010` fijos (:78-79). El envoltorio sustituye el byte de #40 y el nibble alto de #41, así el puente no se toca.

#### 3.2.3 Compartir la flash con el cargador de la YRW801

Es el mismo esquema que el MSXimus y el MSXnano [C en el prototipo y en el banco]:
- **Lectura:** `addr`, `rd` y `terminate` del módulo `flash` son del puente si `b_rd_sel` y del cargador en otro caso.
- **Escritura:** solo la usa el puente (`write_enable = b_wr_start`), y `write_din_ok = ~b_wr_sel | b_wdata_ok`.
- **`libre = wl_done`.** El cargador solo usa la flash al arrancar (unos 2 s, `M\docs\SMD.md`) y en S_DONE deja `terminate=1` para siempre (`yrw801_loader.v:172-176`).
  - Mientras carga, el estado lleva b3=1 y MXUPDATE espera hasta 60 s (`mxupdate.c:792-795`).
  - Una lectura (orden 3) pedida durante la carga se ignora.
  - Un borrado o programa queda pendiente hasta que acaba [C, banco unitario, caso 1].
- **Caso límite [C en el código]:** si la SDRAM no termina su arranque, `loader_start` no sube (`moontang_core.sv:228`). El cargador se queda en S_WAIT sin perro guardián (`yrw801_loader.v:108`) y `wl_done` no llega nunca.
  - El puente queda bloqueado y MXUPDATE dirá "La flash no responde".
  - Lo acepto: la placa estaría averiada igualmente, y queda el USB.
  - Alternativa, si el dueño la quiere: `libre = wl_done | (cargador en S_WAIT y más de 10 s)`, y además cortar `loader_start` cuando el puente toma la flash. Añade lógica y un caso de banco.
- **Resets:**
  - Módulo `flash` y cargador con `por_reset_n`: la YRW801 y una orden ya lanzada sobreviven a un reset del MSX.
  - Puente, registro de ID y ventana con `bus_reset_n`, como hacen `N\top.v:2317` y `X\top.v:5021`.
  - El informe rtl comprobó el control negativo [I, `WF\rtl\new\log_rstpor.txt`]: con el reset de encendido, un `/RESET` del MSX en mitad de una lectura deja `f_rd_sel=1` y la lectura siguiente sale rancia, 16 de 16 bytes.
  - Un reset en mitad de un programa deja `f_wdata=FF` y `f_wterm=1` (`flash_bridge.v:73-75`): cierra la página sin cambiar nada.
  - **[Corrección de la revisión de seguridad, demostrado en simulación]** Con un borrado el reset NO es inocuo. El módulo `flash` lee `write_addr` en STATE_20_2 (`flash_rw.v:370`), unos 170 ciclos (~3 µs) después de arrancar, y el reset del puente pone `a` a 0 (`flash_bridge.v:87`). Un `/RESET` del MSX en ese intervalo manda el borrado al sector **0x000000** en vez del pedido: `WF\rev_seguridad\tb_reset.v` + `run_reset.sh` (prototipo con el arreglo, borrar 0x010000; reset a 100 y 1000 ns de soltar `/WR` → se borra 0x000000; a 2500 y 6000 ns → se borra 0x010000). En un programa, el mismo caso lleva un FF a 0x000000 (no cambia nada). La YRW801 no corre peligro (0 está dentro de la ventana), pero la dirección **no** queda congelada frente a un `/RESET`. Arreglo en el envoltorio: guardar `b_addr` al subir `b_wr_sel` en un registro con `por_reset_n`, dar ese registro a `write_addr` y repetir la comprobación de la ventana sobre él en `write_enable`.

#### 3.2.4 La ventana de escritura (protege la YRW801 de cualquier programa)

- **Regla:** las órdenes 1 y 2 con `{A[23:8],00} ≥ 0x200000` no llegan al puente y ponen a 1 el bit 7 de #4F. Una orden aceptada pone el bit 7 a 0.
- **El agujero del prototipo.** El prototipo comprueba la dirección solo en el `OUT #43`. Pero el puente cambia `a` con cualquier `OUT #41/#42`, también con una orden en curso (`flash_bridge.v:110-112`). Y el módulo `flash` no guarda `write_addr` al arrancar: lo lee varios estados después (`X\fpga\src\flash_rw.v:370` borrar, `:470` programar). Un programa podría pedir borrar 0x010000 y cambiar la dirección enseguida.
- **Lo he simulado** (`WF\diseno\sim\tb_carrera.v`; cargador real, puente, `flash_rw` V3.8 y modelo de flash con escritura; Icarus 12 en WSL; `bash WF/diseno/sim/run.sh`):

| Caso | Prototipo | Con el arreglo |
|---|---|---|
| C1: durante la carga, `OUT #43,1` en 0x010000 (queda pendiente), luego `OUT #41,20h` | **FALLA**: "BORRADO en 0x200000 (zona de la YRW801)" | bien, YRW801 intacta |
| C2: tras la carga, `OUT #43,1` y en el acto `OUT #41,20h` (ritmo del Z80) | **FALLA**: se borra en la zona de la YRW801 | bien |
| C3: `OUT #43,2` y `OUT #41,20h` antes de los datos | bien (la dirección de página ya se había leído) | bien |

- **Arreglo (una línea, en el envoltorio):** los `OUT #41/#42` no pasan al puente mientras `b_wr_sel` (= `op | op_pend`):
  ```verilog
  .wr_req(io4x_wr && !bloquea && !(b_wr_sel && (addr_r[3:0] == 4'h1 || addr_r[3:0] == 4'h2)))
  ```
  - Con el arreglo y la firma Bh, el banco unitario del informe rtl (`tb_fport_fix.v`) pasa **31/31 a 3,58 MHz y 31/31 a 7,16 MHz** [C, `WF\diseno\sim\log_fport_fix*.txt`].
  - MXUPDATE no se entera: siempre espera a "no ocupado" antes de `Direccion()` (`mxupdate.c:193-199`).
- **Herramienta:** la ventana hace que `Borra4K` termine "bien" sin borrar, porque `Espera(OCUPADO,0)` pasa en el acto (`mxupdate.c:197-198`). MXUPDATE 1.3 debe mirar el bit 7 de #4F después de cada orden.

#### 3.2.5 Lectura hacia el bus, `/BUSDIR` y `/WAIT`

- El bus se registra una vez más, como en `opl4fm.v`. Así la lectura del puente llega al bus con la misma latencia que la del FM [I, informe rtl].
  - Consecuencia útil: **si el estado del FM (C4h) se lee bien en un MSX, el puente también**.
  - Simulado con el top real [I]: dato en el bus a 144 ns de `/IORQ` (SMD) y a 153 ns (WT). El Z80 lo toma a unos 620 ns (3,58 MHz) o a unos 259 ns (7,16 MHz).
- El byte se congela en el primer ciclo de la lectura. Sin eso, en la WT a 7,16 MHz el estado cambiaba de A1h a A4h a menos de 50 ns del muestreo (20 veces) [I]. Cuesta 9 FF.
- **`/WAIT` no hace falta.** MXUPDATE consulta el estado antes de cada `IN/OUT #44` (`mxupdate.c:209-210, 229-230`). El byte siguiente tarda unos 350 ns y un byte programado unos 1,6 µs [I].
- **WonderTANG:** `rd_active` incluye el puente, así que `/BUSDIR` baja exactamente cuando se conduce (`moontang_wt_shell.sv:226`) [C en el código; I en simulación: 1064 lecturas sin diferencia].
- **SMD:** no tiene `/BUSDIR` (`moontang_smd_top.sv:14-15`) [C].
  - En las máquinas que lo necesitan, `IN #40` da FFh y MXUPDATE no ve el puente: fallo seguro.
  - El apaño `EXT_A/EXT_B = 2` con un transistor (`moontang_smd_top.sv:41-44`) también cubre estas lecturas.
- **Guarda de bus vivo:** sin reloj del slot o en `/RESET` (`bus_ok`, `moontang_core.sv:265-281`) no se escribe ni se contesta nada [I, banco unitario caso 6].

#### 3.2.6 Identificación de la placa y de la variante

Hay tres fuentes y cada una cubre un fallo distinto:

| Fuente | Qué dice | De qué protege |
|---|---|---|
| IDCODE (bitstream, 0x16) | familia GW2AR-18 | De un core de otro chip (60K/138K). **No** distingue MoonTANG de MSXnano |
| `#4F` del core en marcha | 1 WT, 2 WT-HDMI, 3 SMD | De grabar el core de otra placa: manda el PCB real, no lo que diga el fichero |
| USERCODE dentro del bitstream (`set_option -user_code 4D5400vv`, vv = 01/02/03) | de qué variante es el bitstream del fichero | De un `.UPD` mal hecho (cabecera `moontang_wt` con bitstream de SMD o del MSXnano). MXUPDATE lo busca en los últimos 64 B del segmento (`0A 00 00 00 4D 54 00 vv`); mxupd.py y ota_subir.py lo miran antes de publicar |

- El USERCODE está en una posición fija del .bin (0xDD87C, `0A 00 00 00` + 4 bytes) [C en los cuatro .bin].
- Que `-user_code` funcione en el GW2AR-18 y deje ahí el valor fijado: **sin verificar** [S]. Es lo primero que hay que comprobar con una síntesis. Si no funcionara, quedan `#4F` y el nombre de placa del `.UPD`, que bastan para el usuario, pero no para un error de publicación.

#### 3.2.7 Coste y temporización

- **Medido en el MSXnano** [I, memoria y `N\docs\tecnica\08`]: puente 39 LUT + 16 ALU + 64 FF; `flash_rw` +214 LUT.
- **En MoonTANG será más:** hoy la síntesis quita todo el camino de escritura de `flash_rw` (`write_enable(1'b0)`, `moontang_core.sv:249`).
- **Estimación del informe rtl (yosys genérico)** [I]: +150-250 LUT/ALU y unos +145 FF, menos del 1,2 % de 20.736. Todo en `clk_54m`, sin cruces de reloj nuevos.
- **Margen actual** [C, corregido en la revisión de viabilidad: `M/fpga/impl/pnr/moontang_{wt,wt_hdmi,smd}_tr_content.html` ("Max Frequency Summary") y `.rpt.txt`, que son los informes de los mismos .bin de las 12:28-12:34 que usa §1. Las cifras que había aquí (102,3 / 84,0 / 61,9 MHz y +3,8/+4,8 MHz en `clk_eng`) no coinciden con esos informes; serían de builds anteriores]:

| Variante | CLS | `clk_54m` (54 MHz) | `clk_eng` (Fmax / restricción) |
|---|---|---|---|
| WT | 61 % (6.279/10.368) | 98,6 MHz | 46,5 / 37,125 MHz (+9,3) |
| WT-HDMI | 75 % (7.719/10.368) | 88,0 MHz | 45,8 / 40,0 MHz (+5,8) |
| SMD | 75 % (7.764/10.368) | 67,7 MHz (+13,7) | 48,1 / 40,0 MHz (+8,1) |

  El puente va entero en `clk_54m`, que es el reloj con más margen. `clk_eng` está declarado asíncrono respecto a `clk_108m`/`clk_sdram`/`clk_54m` (`set_clock_groups`: `moontang.sdc:23`, `moontang_wt_hdmi.sdc:29`, `moontang_smd.sdc:32`), así que el puente no añade caminos analizados hacia él. El riesgo es solo de colocación: con el CLS al 75 % se puede mover `clk_eng`.
- **Hace falta campaña de dados en las tres.** Los .sdc de MoonTANG no llevan `report_timing -setup -max_paths 400`, así que hoy no se ven las familias entre relojes; el TNS de Gowin las esconde (lección del nano 2.1.1) [I]. Añadirlo antes de la campaña.

### 3.3 MXUPDATE 1.3

Un único `MXUPDATE.COM` para todas las placas. Uno aparte para MoonTANG lo sustituiría el general en la primera autoactualización (`mxupdate.c:667-702`) **solo si conserva el canal de autoactualización** [C en el código; corrección de la revisión de viabilidad]: el canal es la constante `g_mxu = { 0, "mxupdate", "mxupdate/", 0, "MXUPDATE.COM" }` (`mxupdate.c:550`, usada en :673 y :684) más el cartel que busca `Comprueba()`. Un `MTUPDATE.COM` compilado con su propio `g_mxu` (`mtupdate/`) y su propio cartel no lo sustituye nadie, y publicarlo no llega a los 60K/138K/MSXnano. Es una alternativa que hay que valorar (ver la salida de la revisión).

**Detección** (sustituye a :768-770):
1. `OUT #40,4Dh`. Si `IN #40 = B2h` y `IN #41 & F0h = A0h` → MSXimus/MSXnano, como hoy.
2. Si no: `OUT #40,6Dh`. Si `IN #40 = 92h` y `IN #41 & F0h = B0h` → MoonTANG.
   - `g_id = 6Dh` en todas las rutinas: hoy `ID_PUENTE` es una constante (definida en :53 y usada en :186, :191, :228, :237 y :768).
   - Placa = `IN #4F & 0Fh` (1-2 → `moontang_wt`, 3 → `moontang_smd`; otro valor → "No reconozco la placa").
   - Versión = `#4D`/`#4C`.
   - Idioma = `#4E`.
3. Si no hay ninguno: "Hace falta MSXimus 3.8, MSXnano 2.1.1 o MoonTANG 1.0…".

**Tabla de placas.** Dos filas nuevas con `pack = 0`, que significa "solo bitstream" (**[corrección de la revisión]**: solo si la 1.3 lo trata aparte en cada uso de `pack`; el código de hoy no lo entiende así. Con `pack = 0`, la regla de segmentos (`mxupdate.c:840-845`) da `lim = 0`: rechaza el bitstream real (más de 512 KB en 0) y acepta hasta 2 MB en 0x100000. Y `/R` (`:923-924`) borraría el sector `(0<<16)+0x80000 = 0x080000`, que está **dentro** del bitstream, después de la relectura y con "Listo" en pantalla. Rechazar `/R` es una cuestión de seguridad, no un detalle):
```
{ 0x0008, "moontang_wt",  "moontang_wt/",  0x00, "MOONWT.UPD"  },
{ 0x0008, "moontang_smd", "moontang_smd/", 0x00, "MOONSMD.UPD" },
```
Los bucles de :780 y :832 pasan de 3 a `NPLACAS`. **El de :800 no** [C en el código; corrección de la revisión de viabilidad]: se queda en las tres placas del 4Dh, como en el prototipo (`WF/mxupdate/mxupdmt/mxupdate.c:815`). Ese bucle se queda con la ÚLTIMA fila cuyo id coincide, y las filas nuevas repiten el 0x0008 del MSXnano: con `NPLACAS` un MSXnano de verdad (camino 4Dh) saldría como `moontang_smd`, buscaría `MOONSMD.UPD` o bajaría `moontang_smd/`, y solo la comprobación del USERCODE frente a `#4F` (que en el puente 4Dh del nano lee FFh, `flash_bridge.v:83`) impediría grabarle un core de MoonTANG; en cualquier caso el MSXnano ya no se podría actualizar. La regresión 29/29 del banco lo cazaría (tiene casos del MSXnano), pero la especificación no debe pedirlo. En el camino 6Dh la placa sale de `#4F`, no de ese bucle.

**Reglas nuevas para MoonTANG:**
- **Segmentos:** solo uno, en `dir == 0`, con `256 ≤ tam ≤ 0x200000`. Nada de pack ni de ondas, al revés de lo que hacía el prototipo del informe mxupdate con `pack 0x10`; con la ventana del RTL, un segmento de ondas fallaría a medias.
- **IDCODE:** el del fichero debe ser **0000081B**. No hace falta el de la flash: puede estar en blanco si el core se cargó en SRAM, y la placa la dice #4F.
- **USERCODE:** el del fichero tiene que ser `4D5400vv`, con vv compatible con #4F (WT: 1 o 2; SMD: 3). Si no, "Este fichero es para otra placa".
- **`/R`:** rechazado ("no tiene ajustes y las ondas no se distribuyen").
- **Después de cada `Borra4K`/`Programa256`:** si el bit 7 de #4F está a 1, ir a `mal_flash`.
- **Interrupciones:** `DI` entre `Direccion()` y `P_ORDEN = n`, para que una interrupción no cambie #40 entre medias (:197, :205, :221). Vale para todas las placas.
- **Variante en `/N`:** la del manifiesto que coincide con #4F viene preseleccionada (Enter) y se puede cambiar entre `wt` y `wt-hdmi`. `Describe()` muestra el nombre de la variante (:518-522).
- **Textos:**
  - quitar el aviso de Nextor/SD (:727-732);
  - "No hay red (UNAPI)" sin "la W del menú" (:701);
  - mensaje final "Apaga el MSX **y desenchufa el USB de la Tang si está puesto**" (:931; hoy dice "MSXimus" incluso en el MSXnano);
  - ayuda con MOONWT/MOONSMD.UPD (:774).
- **Opcional:** si `#4F` bit 5 (YRW801 con suma mala), avisar "la YRW801 de la flash no es válida: grábala con el PC".

**Margen:** el prototipo del informe mxupdate ocupa +449 B y termina en 4CADh [I]. Lo de arriba añade, a mi juicio, otros 200-400 B [S]. Total por debajo de 1 KB de los 13.587 B libres [C, .map]. El `.COM` sigue midiendo 32.514 B (relleno hasta 8001h), así que la comprobación de tamaño de la autoactualización no cambia [I].

**Publicación de la 1.3**, con el procedimiento de siempre (memoria `feedback_mxupdate_release_sdmaker.md`):
- subir `MXU_VERSION`;
- `build.sh`;
- banco 29/29 más los casos de MoonTANG;
- `publicar_mxu.py`;
- `ota_subir.py mxupdate`;
- copiar a SD_Maker `sd/extras/FPGA` y al 138K.

Al subirla, **todos los MSXimus y MSXnano se la bajan solos**. Recomiendo no publicarla hasta probarla en un 60K y en un nano, aunque MoonTANG aún no esté listo.

### 3.4 El fichero: MOONWT.UPD / MOONSMD.UPD (sin YRW801)

Es el formato MXUPD1 de siempre (`X\tools\mxupd.py:9-21`), sin cambios:

| Campo | Valor |
|---|---|
| placa | `moontang_wt` o `moontang_smd` |
| versión | p. ej. `1.0.0` |
| variante | `wt`, `wt-hdmi` o `smd` |
| segmentos | 1: `{0x000000, 907418, CRC-32, 0x100}` |
| tamaño | 256 + 907.418 = **907.674 B** |

- Sin pack, sin ajustes y sin ondas.
- `mxupd.py crear` comprueba antes de escribir:
  - IDCODE 0000081B y tamaño ≤ 0x200000;
  - USERCODE `4D5400vv` coherente con `--variante`;
  - rechaza `--pack` y `--onda` para las placas moontang.

**Una YRW801 del usuario por MXUPDATE:** no en la primera versión, porque el RTL lo prohíbe. Se podría añadir más adelante con un desbloqueo explícito en el RTL (P2). Hoy la YRW801 se graba una vez por USB, en la misma sesión que la primera instalación.

### 3.5 Servidor

| Carpeta (local `Z\servidor\` y `https://msx.barcelona/wp-content/ota/`) | Manifiesto |
|---|---|
| `moontang_wt/` | `MSXIMUS-UPD 1` / `placa=moontang_wt` / `version=1.0.0` / `imagen=wt mtwt100.upd 907674` / `imagen=wt-hdmi mtwh100.upd 907674` |
| `moontang_smd/` | `MSXIMUS-UPD 1` / `placa=moontang_smd` / `version=1.0.0` / `imagen=smd mtsm100.upd 907674` |

- **Nunca** una línea `completa=`, ni segmentos fuera de 0, ni la YRW801.
- Nombres en 8.3 y en minúsculas, para que el PC los pueda copiar a la SD sin alias largos. Caben en los ≤23 caracteres del cliente (`mxupdate.c:494-505`).
- **`mxupd.py`:**
  - entradas en `PLACAS` (:48-52) con `(0x0000081B, 0x200000, None)`;
  - entradas en `CARPETAS` (:162);
  - un `publicar` para MoonTANG que solo genere `imagen=`;
  - extender a moontang el `--onda` prohibido (:95-97).
- **`Z\ota_subir.py`:**
  - entradas en `PLACAS` (:59-65);
  - `comprueba_upd` (:79-95) rechaza un segmento ≠ 0 o ≥ 0x200000, la cadena `CopyrightYAMAHA` y un USERCODE que no sea de la carpeta.
- **Pruebas** primero con `Z\ota_servidor.py` (sirve todo `servidor/` con `SimpleHTTPRequestHandler`, que da Content-Length [C en el código]) y `MXUPDATE /N /S:ip:8000`. El 60K ya bajó así en placa el 02/10 [I, memoria].
- **Decisión del dueño (P3):** publicar el `.UPD` es distribuir el binario. El repositorio de MoonTANG es privado y el código es GPL-3; el controlador de SDRAM de t.hara lleva una cláusula non-commercial (`M\CREDITS.md:16, 56-57`) [C].
- **Hallazgo aparte, no es de este diseño** [C en el espejo local, revisión de viabilidad: cada `Z/servidor/tang60k/*_full.upd` contiene la cadena `CopyrightYAMAHA` y `Z/servidor/tang60k/manifiesto.txt` (3.8.1) los anuncia con `completa=`; I: que la web tenga los mismos ficheros]: los `*_full.upd` del 60K que ya se publican llevan la YRW801 en 0x500000.

---

## 4. Flujos de usuario

### 4.0 Requisitos y primera vez

- **MSX-DOS 2 (Nextor) y un disco con sitio para ~1 MB:** SD, CF o IDE. MXUPDATE descarga a un fichero y graba desde él (`mxupdate.c:733-740`).
  - El MoonTANG no trae Nextor; tiene que venir de otro cartucho.
  - Un disquete de 720 KB (737.280 B) **no basta** para 907.674 B.
- **Primera instalación, una sola vez y por USB:** el core con puente (MoonTANG 1.0.0 o el que sea) en 0x000000 y `yrw801.bin` en 0x200000, como dicen hoy `M\docs\WONDERTANG.md` y `M\docs\SMD.md`.
  - En la SMD, fuera del MSX: no lleva diodo en los 5 V (`SMD.md`).
- **Comprobación previa sin riesgo** (propuesta):
  - un `mt7fbr.asc` en `M\tools\msx\` que seleccione 6Dh y lea `92h`, la firma Bh, #4F y #4C/#4D;
  - `MXUPDATE /C fichero` comprueba un fichero en cualquier MSX con DOS 2 (`mxupdate.c:776-783`).

### 4.1 Flujo A: el MSX tiene red

**A1. UNAPI con TLS** (ESP8266/ESP32 con el firmware de ducasp, en SM-X/OCM o en un adaptador):
1. Configurar la red con la herramienta del ESP.
2. Ejecutar `MXUPDATE /N`. MXUPDATE hace esto, en orden:
   - se autoactualiza desde `mxupdate/`;
   - lee `moontang_wt/manifiesto.txt` o `moontang_smd/`, según #4F;
   - propone la variante del core en marcha;
   - descarga a `MOONWT.UPD`;
   - comprueba la cabecera, los CRC, el IDCODE y el USERCODE;
   - pregunta S/N;
   - borra y programa unos 222 sectores;
   - relee y comprueba el CRC;
   - termina con "Listo".
3. Apagar el MSX y quitar el USB de la Tang si está puesto. Al encender, entra el core nuevo.
4. Comprobar `YRW801 OK` (pantalla HDMI o `mt4yrw`).

Sin validar el certificado sigue con un aviso; el cliente no cae nunca a HTTP:80 (`mxupdate.c:369-390`) [C]. Matiz de la revisión de viabilidad: `Net_OpenTLS` no consulta si el UNAPI tiene TLS (`sdk-tools/msx-unapi-env/lib/network.h:152-173`) y el reintento solo quita el bit de verificar (`mxupdate.c:381-383`). Con un UNAPI 1.0 que ignore el bit de TLS, el GET saldría en claro hacia el puerto 443, el servidor lo rechazaría y MXUPDATE diría "Sin conexión" [S: depende de cada implementación]. No se baja nada en claro, pero el mensaje no lleva al usuario a `/S`.

**A2. UNAPI sin TLS** (GR8NET, DenYoNet, ObsoNET con InterNestor Lite; BaDCaT, probablemente) [I, informe red]:
- No llega a msx.barcelona.
- El "ordenador con internet" baja `moontang_wt/` (o `moontang_smd/`) y `mxupdate/` a una carpeta y la sirve con `python Z\ota_servidor.py --dir <carpeta>` o con `python -m http.server 8000`.
- En el MSX: `MXUPDATE /N /S:192.168.x.y:8000`, que pide `GET /moontang_wt/manifiesto.txt` por HTTP/1.0 (`mxupdate.c:415-421`). El resto es igual.
- **Pasarela opcional** (P13): un `mxu_pasarela.py` en el PC que, a cada `GET /<carpeta>/<fichero>`, baje por HTTPS con validación de msx.barcelona y lo sirva en claro a la red local. El MSX sin TLS ve siempre la última versión y la autoactualización, sin que nadie copie carpetas.
- Sin probar con ninguna de esas tarjetas [S].

### 4.2 Flujo B: el MSX no tiene red, el PC tiene internet (el caso típico)

1. En el PC:
   - abrir `https://msx.barcelona/wp-content/ota/moontang_wt/manifiesto.txt` (o `moontang_smd/`);
   - bajar el `.upd` de su variante y, si no lo tiene, `mxupdate/MXUPDATE.COM`;
   - opcional: `python mxupd.py info fichero.upd`.
2. Copiarlo a la SD del MSX como `MOONWT.UPD` (o `MOONSMD.UPD`), junto a `MXUPDATE.COM`. MSX SD Maker podría hacerlo con una casilla (opcional).
3. En el MSX: `MXUPDATE`. Sin argumentos busca el fichero de su placa (`mxupdate.c:806-819`); también vale `MXUPDATE A:\MTWT100.UPD`.
4. Comprobación, S/N, grabación y relectura, como en A1.
5. Apagar, quitar el USB si está puesto, y encender.

Si el fichero no está, MXUPDATE ofrece bajarlo (:810-818). Sin red dirá "No hay red (UNAPI)" y no toca nada.

### 4.3 Tiempos (estimados, sin medir en un MSX real)

- Medido en el emulador del banco con el core de 907 KB [I, informe nano]:

| Pasada | Tiempo |
|---|---|
| Comprobar el fichero | 38 s |
| Borrar y programar | 43 s |
| Releer | 62 s |
| **Total de Z80** | **144 s** |

- Sumando el disco, los borrados reales (222 × 45 ms), la espera M1 y la consola: **unos 3,5-4 minutos** a 3,58 MHz [S].
- La ventana de riesgo por corte de luz es la pasada de borrar y programar: **unos 1-1,5 minutos**.

---

## 5. Seguridad

### 5.1 Amenazas y defensas

| Amenaza | Defensa | Dónde |
|---|---|---|
| MXUPDATE ≤1.2 trata el MoonTANG como un MSXnano | ID 6Dh (la 1.2 no lo ve) + firma Bh | RTL |
| Core de la otra placa (WT ↔ SMD) | #4F del core en marcha + nombre de placa del `.UPD` + USERCODE del bitstream | RTL + MXUPDATE + mxupd/ota_subir |
| Core del MSXnano u otro core GW2AR-18 | USERCODE `4D54xxxx` obligatorio + nombre de placa | MXUPDATE + herramientas |
| Core de otro chip | IDCODE 0000081B | MXUPDATE |
| YRW801 pisada (pack del nano, ondas, `/R`, programa ajeno) | Ventana < 0x200000 **con la dirección congelada** (frente a `OUT #41/#42`; frente a `/RESET`, solo con el registro de §3.2.3) + regla de un solo segmento + `/R` rechazado + el servidor rechaza ≥ 0x200000 y "CopyrightYAMAHA" | RTL + MXUPDATE + servidor |
| Fichero corrupto (descarga, SD) | CRC-32 de la cabecera y de cada segmento **antes** de borrar; relectura completa después | MXUPDATE (ya existe) |
| Dos dispositivos con el mismo ID | ID propio 6Dh. **[Corrección de la revisión]** Con dos MoonTANG sí es un caso nuevo: los dos guardan el 6Dh (`moontang_flashport_fix.v:79-82`) y los dos pasan las órdenes a su puente (:96-108), así que MXUPDATE borraría y grabaría las dos flash con el mismo fichero. Si son una WT y una SMD, el `#4F` que se lee es una colisión en el bus y una de las dos puede acabar con el core de la otra placa. Documentar "un solo MoonTANG en el MSX al actualizar" | RTL + guía |
| El cartucho conduce con el MSX apagado o arrancando | `bus_ok` (reloj del slot y fuera de `/RESET`) | RTL (ya existe para el OPL4) |
| Una interrupción cambia #40 entre la dirección y la orden | `DI` alrededor de `Direccion()` + orden | MXUPDATE |
| Un programa cualquiera selecciona 6Dh y escribe `#43=1` | Opcional: llave de escritura (las órdenes 1/2 solo valen tras `OUT #4F,'M'` después de seleccionar). Unos 10 FF y 4 B de MXUPDATE | RTL + MXUPDATE (P9) |
| Fichero auténtico | **No hay firma**: solo HTTPS (con validación cuando se puede) y CRC. Con `/S` va en claro por la red local. La OTA de la Zynq sí firma (ECDSA); llevarlo al Z80 es caro | Riesgo aceptado, documentarlo |

### 5.2 Corte de luz a mitad y recuperación

- **No hay imagen dorada.** No hay multiboot configurado en ningún `build.tcl` [I]. MXUPDATE borra y programa en orden desde 0x000000 (`mxupdate.c:887-903`) [C]: desde el primer borrado hasta la última página, la flash no tiene un bitstream válido.
  - Mientras no se apague, sigue funcionando el core viejo, que corre en SRAM, y se puede repetir ("NO APAGUES: sigue el core de antes", :946).
  - Si se corta la luz, la FPGA no arranca al encender.
- **Recuperación por el USB de la Tang** (BL616 USB-JTAG): Gowin Programmer en modo External Flash con el `.fs` en 0x000000.
  - **WonderTANG:** con el MSX apagado; lleva diodo (`WONDERTANG.md`).
  - **SMD:** **fuera del MSX** (`SMD.md`).
  - La YRW801 de 0x200000 no se ha tocado. Aun así, mirar `YRW801 OK` después: algunas herramientas borran más de la cuenta (`WONDERTANG.md:41-46`) [C].
  - Con la FPGA sin configurar, el JTAG dedicado responde (MoonTANG no reutiliza los pines JTAG, `M\fpga\build.tcl:75-80`) [C]. Que la WonderTANG 2.0b pida S1 en ese caso está sin verificar [S].
- **Mejora posible** (no necesaria para la primera versión): el documento de Gowin trae `-multi_boot`, `-multiboot_spi_flash_address` y `-mspi_jump`, y la cabecera del `.fs` tiene `MultiBootSPIAddr`. Falta comprobar, en UG290 o SUG100, si el GW2AR-18 vuelve a una imagen de reserva cuando falla el CRC. Si lo hace, se podría tener un core de rescate fijo [S].

### 5.3 La YRW801

Nunca la escribe MXUPDATE: el RTL lo impide, la herramienta lo rechaza y el servidor lo rechaza. Un `.UPD` del core cambia 222 sectores y ninguno en 0x200000 [I, banco del informe mxupdate].

### 5.4 Anfitriones problemáticos (fallo seguro: MXUPDATE no ve el puente y no graba)

- **SMD en máquinas o expansores con el bus de datos con buffer:** necesitan `/BUSDIR` y la SMD no lo tiene.
- **El OCM / SM-X no es un anfitrión problemático** [C en el código; corregido en la revisión de viabilidad: lo que había aquí, "el OCM devuelve FFh con los ID que no conoce", no es lo que hace el OCM-PLD]: el OCM solo conduce #40-#4F cuando `io40_n /= FFh` (`ocm-pld-dev/esemsx3/src/emsx_top.vhd:2029`, `ocm-pld-dev/ocm_sm/src_addons/sm_emsx_top.vhd:2215`), e `io40_n` vale FFh con cualquier ID que no sea 08h o D4h (`swioports.vhd:552-554`). Con 6Dh seleccionado deja el bus al cartucho y la CPU (`D => pSltDat`) lee al MoonTANG. Falta probarlo en un OCM real [S].

---

## 6. Plan de pruebas

### 6.1 Simulación de RTL (Icarus 12 + sv2v en WSL)

| Banco | Qué añade | Base |
|---|---|---|
| `tools/sim/fbr/tb_fport.v` (unitario) | Los 31 casos del informe rtl con ID 6Dh y firma Bh, más: carrera de dirección C1-C3, #4C/#4D/#4E, rechazo con el bit 7 de #4F, ID 4Dh callado, carga de 2 MB exacta | `WF\rtl\new\tb_fport.v` y `WF\diseno\sim\tb_carrera.v` (ya pasan: 31/31 + 4/4) |
| `tools/sim/board_smd/tb_smd_fbr.v` y `tools/sim/board/tb_wt_fbr.v` | Top real + placa, Z80 a 3,58 y 7,16 MHz; `/BUSDIR` = conducción en la WT; silencio sin seleccionar | Los del informe rtl (23/23 cada uno [I]) |
| **Regresión de todos los bancos de MoonTANG** que usan la flash (`tb_loader.v`, `tb_loader_real.v`, `board`, `board_smd`, `tb_diag.v`) | `flash_rw.v` es un recurso compartido: cada consumidor, otra vez | `M\tools\sim` |
| Reproducir en RTL la traza de MXUPDATE (opcional) | Sacar del banco Z80 de MXUPDATE la secuencia de `OUT/IN` de una actualización de MoonTANG y reproducirla en `tb_fport` | Une el banco de la herramienta con el RTL sin un Z80 en el simulador |

### 6.2 Banco de MXUPDATE (`X\tools\mxupdate\banco`)

- Parametrizar `Puente` en `banco_mxu.py`: ID, firma, #4F y #4C/#4D.
- Llevar `WF\mxupdate\banco\banco_moontang.py` (23 casos) a 6Dh + Bh + USERCODE.
- Casos nuevos:
  - un `.UPD` `moontang_wt` con bitstream de SMD, rechazado por USERCODE;
  - el `.UPD` del MSXnano, rechazado;
  - un segmento en 0x200000, rechazado;
  - el bit 7 de #4F a 1 tras un borrado, que lleva a `mal_flash`;
  - flash en blanco, que se acepta por #4F;
  - la 1.2 contra MoonTANG, que dice "Hace falta" y no escribe nada;
  - inglés por defecto con `#4E=05h`.
- Regresión de siempre: 29/29.
- Con YRW801 **sintética**, nunca la real.

### 6.3 En placa (WonderTANG 2.0b/2.02b y SMD rev B)

| Paso | Prueba | Criterio |
|---|---|---|
| P0 | Síntesis de las 3 variantes con `-user_code` y campaña de dados | `clk_54m`/`clk_eng` positivos en **todas** las familias de la tabla de caminos; USERCODE `4D5400vv` en el `.fs` y en 0xDD87C del `.bin` |
| P1 | Instalar por USB el core con puente + YRW801 | `mt1det`…`mt6pcm` igual que sin puente; `YRW801 OK` |
| P2 | `mt7fbr.asc` (nuevo, solo lecturas y un intento de borrar en 0x200000) | `92h`, firma Bh, #4F = placa + `wl_done`; el borrado en 0x200000 se rechaza (bit 7) y después `mt4yrw` sigue bien |
| P3 | MXUPDATE **1.2** en el MSX con el MoonTANG | "Hace falta…", nada escrito |
| P4 | MXUPDATE 1.3 con un `.UPD` del mismo core | "Listo"; apagar y encender; todo sigue; cronometrar |
| P5 | WT: cambiar a `wt-hdmi` y volver | Arranca la otra variante |
| P6 | `.UPD` de la SMD en la WT y al revés; `.UPD` del MSXnano | Rechazados sin tocar nada |
| P7 | Corte de luz a mitad (en el banco, a propósito) | La placa no arranca; recuperar por USB siguiendo la guía; anotar si la WT pide S1 |
| P8 | Máquinas: MSX2 a 3,58 MHz, MSX2+ de Panasonic (con 08h), turbo R (R800), un expansor con buffer | Funciona, o falla de forma segura en la SMD sin `/BUSDIR` |
| P9 | Red: flujo B con SD; flujo A2 con `ota_servidor.py` y `/S`; A1 si hay un ESP | Descarga correcta y "Listo" |

---

## 7. Lista de trabajo

| # | Área | Trabajo | Ficheros | Esfuerzo | Riesgo |
|---|---|---|---|---|---|
| 1 | rtl | `flash_rw.v` de la V3.8 | `M\fpga\src\flash_rw.v` | trivial | Activa el camino de escritura en los 3 bitstreams: hay que repasar los bancos del cargador |
| 2 | rtl | `flash_bridge.v` sin cambios | `M\fpga\src\flash_bridge.v` | trivial | Ninguno (igual que X y N) |
| 3 | rtl | `moontang_flashport.v`: ID 6Dh, firma Bh, #4C/#4D/#4E/#4F, ventana con dirección congelada, lectura congelada, resets | `M\fpga\src\moontang_flashport.v` | medio | Si se copia el prototipo sin el arreglo, la YRW801 queda desprotegida (demostrado) |
| 4 | rtl | Integración en el núcleo y en los 4 tops (parámetros de placa y versión) | `moontang_core.sv`, `moontang_wt_shell.sv`, `moontang_top.sv`, `moontang_wt_hdmi_top.sv`, `moontang_smd_top.sv` | pequeño | Partir de aa7e0a4 (los arreglos 1-3 ya están dentro) |
| 5 | rtl | `add_file` y `-user_code` por variante; `report_timing -max_paths` en los .sdc | `build.tcl`, `build_smd.tcl`, `build_wt_hdmi.tcl`, `constraints/*.sdc` | trivial | `-user_code` sin verificar en el GW2AR-18 |
| 6 | rtl | Síntesis + campaña de dados de las 3 variantes | `fpga/` | medio | CLS al 74-75 % en SMD y WT-HDMI; `clk_eng` justo |
| 7 | mxupdate | MXUPDATE 1.3 (detección 4Dh/6Dh, `g_id`, placas `pack=0`, regla de un segmento, IDCODE fijo, USERCODE, bit 7 de #4F, `/R` rechazado, `DI`, textos) | `X\tools\mxupdate\mxupdate.c` | medio | Un `.COM` para todas las placas que se autoactualiza: un fallo llega a todos los 60K/138K/nano |
| 8 | pruebas | Banco de MXUPDATE: `Puente` parametrizado, casos de MoonTANG, regresión 29/29 | `X\tools\mxupdate\banco\*` | medio | El banco no es un MSX real |
| 9 | mxupdate | Publicar la 1.3 (procedimiento de siempre + SD_Maker) | `publicar_mxu.py`, `Z\ota_subir.py mxupdate`, SD_Maker | pequeño | Solo después de P0-P9 y de probarla en un 60K y en un nano |
| 10 | servidor | `mxupd.py`: placas `moontang_wt`/`moontang_smd`, comprobar USERCODE, `publicar` solo con `imagen=` | `X\tools\mxupd.py` | pequeño | Bajo |
| 11 | servidor | `ota_subir.py`: placas nuevas; rechazar ≥ 0x200000, "CopyrightYAMAHA" y USERCODE ajeno | `Z\ota_subir.py` | pequeño | Bajo |
| 12 | servidor | Carpetas locales `servidor/moontang_wt`, `moontang_smd` y prueba con `/S` | `Z\servidor\` | trivial | Ninguno (local) |
| 13 | servidor | Pasarela del PC para UNAPI sin TLS (opcional) | `Z\mxu_pasarela.py` (nuevo) | pequeño | Sirve en claro en la red local |
| 14 | docs | Guía de actualización (flujos A/B, recuperación por USB, tiempos) y tabla de "qué grabar" con el core con puente | `M\docs\UPDATE.md` (nuevo), `README.md`, `docs\WONDERTANG.md`, `docs\SMD.md` | pequeño | Bajo |
| 15 | pruebas | Programa BASIC de prueba del puente | `M\tools\msx\mt7fbr.asc` | pequeño | Bajo (solo lee y un borrado en zona prohibida) |
| 16 | pruebas | Bancos de RTL: unitario ampliado + placa SMD/WT + regresión de los bancos de MoonTANG | `M\tools\sim\fbr\`, `board\`, `board_smd\` | medio | ~10 min por banco de placa |
| 17 | pruebas | Pruebas en placa P0-P9 (WT y SMD) | — | grande | Nada de MoonTANG se ha probado aún en placa, ni siquiera sin puente |

Orden recomendado:
1. Validar en placa el MoonTANG **sin** puente. Si el OPL4 no funciona, no tiene sentido actualizarlo por MXUPDATE.
2. Trabajos 1-6 y 16.
3. P0-P3.
4. Trabajos 7-8.
5. P4-P9.
6. Servidor (10-13) y documentación (14).
7. Publicar (9), con el visto bueno del dueño.

---

## 8. Preguntas abiertas para el dueño

Van numeradas y con la misma lista en la salida estructurada.

1. ¿ID 6Dh y firma Bh? ¿Te consta algún dispositivo de E/S conmutada con 6Dh?
2. ¿La YRW801 queda **siempre** fuera del alcance del MSX (recomendado: se graba por USB una vez), o quieres un desbloqueo en el RTL para grabar desde el MSX una YRW801 propia?
3. ¿Se publica MoonTANG en msx.barcelona? El repo es privado; la GPL-3 obliga a ofrecer la fuente al distribuir el binario; el SDRAM de t.hara es non-commercial; el OPL4 ya suena en placa (WT 2.02b), pero el puente no se ha probado. ¿O solo los flujos locales (SD, `/S`) hasta validar?
4. ¿WT y WT-HDMI como una sola placa con dos variantes que se pueden cambiar (propuesto), o dos placas?
5. ¿Idioma por defecto del MoonTANG en MXUPDATE: inglés (propuesto, como su documentación) o castellano?
6. ¿Versión del primer core con puente (¿1.0.0?) y nombres: `MOONWT.UPD` / `MOONSMD.UPD` en la SD, `mtwt100.upd` en el servidor?
7. ¿Vale un USERCODE propio (`4D5400vv`) en lugar del checksum por defecto?
8. ¿Probamos la compresión de bitstream de Gowin para que el `.UPD` quepa en un disquete, o se asume SD/USB?
9. ¿Llave de escritura contra programas que escriban en #43 por error (unos 10 FF, unos 4 B de MXUPDATE)?
10. ¿Cuándo se publica MXUPDATE 1.3, que se autoactualiza en todos los MSXimus y MSXnano? Recomiendo hacerlo tras probarla en un 60K, en un nano y en el MoonTANG.
11. ¿SMD sin `/BUSDIR`: se acepta el fallo seguro, o se documenta el apaño `EXT_A=2` con transistor?
12. (Aparte) Los `*_full.upd` del 60K publicados llevan la YRW801. ¿Se mantienen?
13. ¿Hacemos la pasarela del PC para tarjetas de red sin TLS?
14. ¿Cuándo integramos en `moontang_core.sv`? (ya libre: los arreglos 1-3 están commiteados)

---

## 9. Contradicciones entre informes y cómo las he resuelto

| Tema | Informes | Decisión y por qué |
|---|---|---|
| ID 6Dh (rtl, red) o 4Dh con firma Bh (mxupdate) | Cada uno protege a la 1.2 a su manera | **Las dos cosas**. 6Dh evita el choque con un anfitrión 4Dh; Bh cubre un error de build. Las dos cuestan casi nada |
| Placa en #4F: 1/2/3 (rtl) o 1/2 (mxupdate) | — | **1/2/3**: se sabe la variante en marcha y se preselecciona. MXUPDATE agrupa 1 y 2 en `moontang_wt` |
| `pack 0x10` con ondas en 0x200000 (mxupdate) o ventana en el RTL (rtl) | Incompatibles: con la ventana, un `.UPD` con ondas fallaría a medias | **Ventana + regla de un solo segmento** (`pack=0`). Las ondas, por USB |
| Reset del puente: de encendido (mxupdate, comentario de `flash_bridge.v:25`) o `bus_reset_n` (rtl) | El rtl tiene un control negativo simulado; N y X usan `bus_reset_n` [C] | **`bus_reset_n`** para el puente y **`por_reset_n`** para el módulo `flash` |
| Nombres de carpeta (`moontangwt/` o `moontang_wt/`) | — | **`moontang_wt/`, `moontang_smd/`** = el nombre de la placa (≤15 caracteres) |
| Valores de USERCODE | Los informes dan 9C7F/99DD/DCAC | Hoy son 6D9A/60EC/C817: se regeneraron a las 12:31. Da igual: se van a fijar |
| La ventana del prototipo "protege la YRW801 de cualquier herramienta" (rtl) | No es cierto tal cual | **Agujero demostrado** y arreglado (§3.2.4) |

## 10. Sin verificar

- Que 6Dh esté libre.
- Que `-user_code` funcione en el GW2AR-18 (la opción está en SUG1220, pero no he sintetizado).
- El coste real en Gowin y el cierre de temporización de las 3 variantes.
- Tiempos en un MSX real.
- El R800 del turbo R y los anfitriones con buffer.
- Qué UNAPI reales tienen TLS (y el reintento sin validar en el ESP8266).
- Multiboot o imagen dorada en el GW2AR-18.
- La compresión del bitstream.
- Si la WonderTANG 2.0b pide S1 con la FPGA sin configurar.
- **El puente no se ha probado en placa.** (Corrección del 05/10: el MoonTANG SIN puente sí suena en placa, en una WonderTANG 2.02b con el bitstream con HDMI.)

Artefactos de este diseño:
- `WF\diseno\sim\tb_carrera.v`, `moontang_flashport_fix.v`, `tb_fport_fix.v`, `run.sh`, `run2.sh` y los logs `log_orig.txt`, `log_fix.txt`, `log_fport_fix.txt`, `log_fport_fix_7m.txt`.
- `WF\diseno\sug1220.txt`: texto del documento de Gowin.
