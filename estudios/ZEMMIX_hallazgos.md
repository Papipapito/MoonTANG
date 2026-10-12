# ZEMMIX (BigMist / rampa069) y ZEMMIX-poseidon: qué nos sirve y qué les sirve

Fecha: 12/10/2026. Base: rama `claude/intelligent-franklin-953fqq` sobre `dc4b38d` (1.0.1 beta).
Revisados: [BigMist/ZEMMIX](https://github.com/BigMist/ZEMMIX) (`f91ae39`, 115 commits) y
[Dalekamistoso/ZEMMIX-poseidon](https://github.com/Dalekamistoso/ZEMMIX-poseidon) (`e6a2822`,
una copia del anterior con otro `.gitignore`; sus *releases* son los bitstreams: el último,
`20261010`, "Added OPL4 (Moonsound), Updated OCMPLD, Changed OPLL to Ikacore, Added V9990,
Turbo R with full PCM support").

ZEMMIX es un MSX2+/turbo R para las placas MiST (SiDi128, Poseidon GX150, NeptUNO+) sobre
OCM-PLD, con un MoonSound hecho con **las mismas dos piezas que MoonTANG y el MSXimus**: el
OPL3 de Greg Taylor y el motor PCM YMF278B de srg320. Lo añadieron entre el 8 y el 10 de
octubre de 2026 y, al validarlo contra openMSX con Verilator, encontraron fallos del motor que
nosotros también tenemos: nuestra copia es la del 2 de julio de srg320 y la suya la del 31 de
julio, y encima corrigieron tres cosas más.

## 1. Lo que entra en MoonTANG en esta rama (hecho y medido)

Comprobado uno a uno contra el código de openMSX 19.1 (`YMF278.cc`), no solo contra lo que
dice ZEMMIX, con un banco nuevo del motor solo: `tools/sim/opl4eng/` (un seno de 64 muestras
escrito en la RAM de muestras por los registros 02h–06h, cabecera del tono 384 con WTH = 4,
como hace un programa).

| # | Fallo del motor (`fpga/opl4wave/ymf278b_gowin.v`) | Lo que hace el chip (openMSX) | Antes | Después | Origen |
|---|---|---|---|---|---|
| 1 | **Paneo**: desplazaba la muestra 2 × PAN bits: **12 dB por paso** | 3 dB por paso (`pan_left`/`pan_right`), 7 y 8 silencian la izquierda, 8 y 9 la derecha | PAN 2: L/R = 0,063 (−24 dB); PAN 1: 0,25 | 0,50 y 0,75 | srg320 31/07 (`1a1d3e6`), fórmula de la derecha corregida aquí (la suya cuenta un paso de menos) |
| 2 | **Rampa de TL** (escritura del nivel sin *level direct*): iba en sentido contrario y daba la vuelta (nivel máximo y −48 dB alternos) | hacia el valor escrito: un paso cada 27 muestras al bajar el volumen, cada 13,5 al subirlo | 3Fh→00h: 1977 → 436 (baja); 00h→3Fh: acaba en 29742 (vuelta) | sube a 29766 en ~850 muestras; baja a 1977 en ~1700 | ZEMMIX `06ed1cf` |
| 3 | **Nivel de decay** (DL): comparaba `EVOL[9:6]`, **6 dB por paso** | `dl_tab`: 3 dB por paso, DL = 15 → 3E0h | sustain a 0,059 del pico (−24,6 dB con DL = 4) | 0,234 (−12,6 dB) | srg320 31/07 |
| 4 | **Suma de slots** de 18 bits: con muchos slots fuertes daba la vuelta (clic con el signo cambiado) | satura a ±32767 | 8 slots: cambia de signo en los picos | satura limpiamente | ZEMMIX `eb4ae7c` |
| 5 | **Estado en `C6h`** (`fpga/opl3/host_if.sv`): FFh | el estado, como en `C4h` | `mt1det` esperaba `C6=FF` | `C6=00` | ZEMMIX `baef789`; openMSX `MSXMoonSound::readIO` |

Los cuatro del motor se oían: paneos exagerados en el HDMI estéreo, instrumentos que al
cambiar de volumen sin LD (MoonBlaster Wave lo hace) se iban al máximo o a −48 dB, decays que
bajaban el doble, y clics en los acordes fuertes. El 5 cuelga a quien espere BUSY o LD por
`C6h`.

Resultado del banco con las correcciones: `RESULTADO: PASS` (9 comprobaciones; antes fallaban
las 9). Lo que el banco no cubre: **la síntesis**. La multiplicación del volumen pasa de la
etapa OP6→OP7 a la de acumulación (dos `VolCalc`, una por lado, como en srg320 y ZEMMIX):
hay que compilar con Gowin, mirar la holgura de `clk_eng` (37,125 / 38,57 MHz) y el recuento
de DSP (uno más). No se ha podido hacer aquí (sin Gowin ni su `prim_sim.v` para el banco de
placa).

## 2. Pendiente de ZEMMIX / srg320, por orden de interés

1. **Interpolación lineal entre muestras** (srg320 `5e8599e`, 27/07/2026, más la corrección
   de signo de ZEMMIX `06ed1cf`: el producto era signed × unsigned y daba un clic en cada paso
   por cero). Nuestro motor **no interpola**: cada muestra de la onda se repite (se ve en el
   banco: `2894 2894 5806 5806 …`), con el *aliasing* que eso supone en los tonos agudos. Es un
   cambio estructural del motor (dos RAM de 24 × 16 con las dos muestras anteriores por slot,
   `PHASE_OVF`, y una lectura de memoria menos por muestra), no un parche: conviene hacerlo
   primero en el `YMF278B.sv` del MSXimus y regenerar.
2. **Cola de accesos de bus** (`opl4_wave.sv`): ZEMMIX encola hasta 8 accesos del bus y los
   sirve al motor uno a uno cuando no está BUSY. Nosotros tenemos un *latch* de una posición
   por sentido (`wr_t`/`req_dat`): dos accesos en menos de ~0,6 µs pierden el primero. A
   3,58 MHz no pasa (un `OUT` son 3,35 µs); con R800 o un Z80 a 7 MHz, sí.
   `check_trace.py` ya lo mide (`min.gap`).
3. **Lecturas de estado no encoladas** (ZEMMIX `2b64b8d`): con el R800, un bucle que lee BUSY
   veía su propia lectura encolada. En MoonTANG BUSY sale solo del motor, no de la cola, así
   que no tenemos ese fallo; pero tampoco se refleja BUSY mientras una escritura espera en el
   *latch*.
4. **Programas de prueba** (`misc/opl4/tools/`): `OPL4SIN.BAS` (acorde de senos escritos en la
   RAM, cabeceras en RAM con WTH, rampa de TL, pan, LD) es la prueba de hardware de estas
   correcciones; portarlo a `tools/msx/mt8sin.asc`. `OPL4MEM.BAS` es nuestro `mt5ram`;
   `SNDTEST.BAS` prueba el OPL3 por `C4h`/`C5h` y el OPL4 (opción A).
5. **Placa de pruebas.** El Poseidon GX150 y el NeptUNO+ tienen **ranura de cartucho**: un
   ZEMMIX con su MoonSound apagado en el OSD es un MSX turbo R (R800, S1990) donde probar
   MoonTANG; con el interno encendido, los dos responden en los mismos puertos.

## 3. Para el MSXimus (Zynq y 60K): el mismo parche

`fpga/opl4wave/YMF278B.sv` y `YMF278B_pkg.sv` del MSXimus_zynq (`1b6f1ac`, Z1.2.4) tienen
los cuatro fallos del motor, y `fpga/opl3/host_if.sv` el del estado. En SystemVerilog:

```systemverilog
// YMF278B.sv, EST_DECAY1 (línea ~597): 3 dB por paso de DL
-    if (OP4_EVOL[9:6] == OP4_DL) begin
+    if (OP4_EVOL[9:5] == {&OP4_DL, OP4_DL}) begin

// YMF278B.sv, rampa de TL (líneas ~664-672)
-    if (TL_INT > OP5_TL)      TL_RAM_D <= {TL_INT,TL_FRAC} + 17'd19;
-    else if (TL_INT < OP5_TL) TL_RAM_D <= {TL_INT,TL_FRAC} - 17'd38;
-    else                      TL_RAM_D <= {TL_INT,TL_FRAC};
+    if (TL_INT < OP5_TL)      TL_RAM_D <= {TL_INT,TL_FRAC} + 17'd38;   // más flojo: 1 paso / 27 muestras
+    else if (TL_INT > OP5_TL) TL_RAM_D <= {TL_INT,TL_FRAC} - 17'd76;   // más fuerte: 1 paso / 13,5
+    else                      TL_RAM_D <= {TL_INT,10'h000};

// YMF278B_pkg.sv: OP7_t lleva la onda y un nivel por lado en vez de SD
-    bit [15:0] SD;
+    bit [15:0] WD;  bit [9:0] LVLL;  bit [9:0] LVLR;
+  function bit [9:0] LevelAddPanL(bit [9:0] LEVEL, bit [3:0] PAN);
+    bit [9:0] PL; bit [10:0] SUM;
+    PL  = (PAN == 4'h7 || PAN == 4'h8) ? 10'h3FF : (PAN > 4'h8 || PAN == 4'h0) ? 10'h000 : {2'b00, PAN[2:0], 5'b00000};
+    SUM = {1'b0,LEVEL} + {1'b0,PL};
+    return SUM[10] ? 10'h3FF : SUM[9:0];
+  endfunction
+  function bit [9:0] LevelAddPanR(bit [9:0] LEVEL, bit [3:0] PAN);
+    bit [3:0] ST; bit [9:0] PL; bit [10:0] SUM;
+    ST  = 4'd8 - {1'b0, PAN[2:0]};                       // 16 - PAN pasos (openMSX pan_right)
+    PL  = (PAN == 4'h8 || PAN == 4'h9) ? 10'h3FF : (PAN < 4'h8) ? 10'h000 : {2'b00, ST[2:0], 5'b00000};
+    SUM = {1'b0,LEVEL} + {1'b0,PL};
+    return SUM[10] ? 10'h3FF : SUM[9:0];
+  endfunction
-  function bit signed [15:0] TrimWave(bit signed [17:0] WAVE);
-    return WAVE[17] && WAVE[16:15] != 2'b11 ? 16'h8000 : !WAVE[17] && WAVE[16:15] != 2'b00 ? 16'h7FFF : WAVE[15:0];
+  function bit signed [15:0] TrimWave(bit signed [20:0] WAVE);
+    return WAVE[20] && WAVE[19:15] != 5'b11111 ? 16'h8000 : !WAVE[20] && WAVE[19:15] != 5'b00000 ? 16'h7FFF : WAVE[15:0];
   (PanLCalc / PanRCalc sobran)

// YMF278B.sv, etapa OP6 -> OP7: el pan se suma al nivel (el pan del slot llega
// por REG_PAN_Q en la ventana OP7, igual que ahora)
-    OP7.SD <= VolCalc(OP6.WD, OP6.LEVEL);
+    OP7.WD <= OP6.WD;  OP7_LEVEL <= OP6.LEVEL;           // bit [9:0] OP7_LEVEL
   ...
-    bit [17:0] ACC_L, ACC_R;
+    bit [20:0] ACC_L, ACC_R;  bit [9:0] OP7_LVLL, OP7_LVLR;  bit signed [15:0] TEMP_L, TEMP_R;
     if (CYCLE0_CE) begin
-      {OP7_CH,OP7_PAN} <= REG_PAN_Q[4:0];
+      OP7_LVLL <= REG_PAN_Q[4] ? 10'h3FF : LevelAddPanL(OP7_LEVEL, REG_PAN_Q[3:0]);   // CH = fuera de la mezcla
+      OP7_LVLR <= REG_PAN_Q[4] ? 10'h3FF : LevelAddPanR(OP7_LEVEL, REG_PAN_Q[3:0]);
     end
-    TEMP  = !OP7_CH ? OP7.SD : '0;  PAN_L = PanLCalc(TEMP,OP7_PAN);  PAN_R = PanRCalc(TEMP,OP7_PAN);
+    TEMP_L = VolCalc(OP7.WD, OP7_LVLL);  TEMP_R = VolCalc(OP7.WD, OP7_LVLR);
     if (SLOT1_CE) begin
-      ACC_L <= (S == 0) ? {{2{PAN_L[15]}},PAN_L} : ACC_L + {{2{PAN_L[15]}},PAN_L};   (y R)
+      ACC_L <= (S == 0) ? {{5{TEMP_L[15]}},TEMP_L} : ACC_L + {{5{TEMP_L[15]}},TEMP_L}; (y R)

// opl3/host_if.sv: estado también en C6h
-    dout = address_p1 == 0 ? host_status_p1 : '1;
+    dout = address_p1[0] == 0 ? host_status_p1 : '1;
```

El `ymf278b_gowin.v` de esta rama ya lo lleva hecho en Verilog plano y sirve de referencia
(cada cambio va comentado "MoonTANG (12/10/2026)"). El banco `tools/sim/opl4eng/` se puede
apuntar al motor del MSXimus (mismos puertos más `MEM_SLOT`/`MIX_FM`).

## 4. Lo que ZEMMIX no tiene y nosotros sí (por si se les quiere pasar)

- **Mezcla F8h/F9h**: su `MixCalc` es el original, `>>> {MIX, 1'b0}` = **12 dB por paso**; el
  MSXimus lo corrigió en la `_114` (pasos de 3 dB: 1, 0,75, 0,5…). Con el reset canónico del
  F8h (1Bh) el FM les queda a /64: inaudible en software que no toca F8h (VGMPlay con VGM de
  OPL3).
- **LFO**: `AMCalc`/`VIBCalc` originales (el contador en crudo: una sierra con un salto por
  ciclo, y el doble de profundidad). El MSXimus `_113` usa el triángulo y las tablas de
  profundidad del datasheet.
- **Timer parado en el ciclo del desbordamiento** (`opl3/timer.sv`, MoonTANG 05/10/2026):
  su `timer.sv` es el original; el timer parado seguía desbordando y `/INT` volvía a subir.
- **Escribir las máscaras (reg 04h, bit 7 = 0) borra los flags** (`timers.sv` `_109`): sin
  ello la detección AdLib de VGMPlay deja la IRQ clavada. Su `timers.sv` tiene el `irq_rst`
  como pulso pero no esto.
- **Pan derecho**: su `LevelAddPanR` cuenta `7 - PAN[2:0]` pasos; las tablas de openMSX/MAME
  dan `16 - PAN` (PAN = 15 → un paso de 3 dB, no 0; PAN = 10 → seis, no cinco).
- **Caché de la memoria de ondas por slot con prefetch por *stride*** (`opl4_pcm.v` `_107`–
  `_112`): la suya es de 32 líneas asociativas; con 22 slots (Bombaman) la nuestra pasó por
  el mismo problema que describen ("la música iba lenta") y acabó así.
- Lo que comparten con nosotros y con openMSX no: NEW2 nunca se borra, 7Eh devuelve el estado,
  registro 06h con MA = 0 (ver `estudios/COMPAT_discos_musica.md`).
