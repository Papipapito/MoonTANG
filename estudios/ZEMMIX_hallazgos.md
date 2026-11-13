# ZEMMIX (BigMist / rampa069) y ZEMMIX-poseidon: qué nos sirve y qué les sirve

Fecha: 12/10/2026, puesto al día el 13/11/2026 (§1). Base entonces: `dc4b38d` (1.0.1 beta).
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

## 1. Estado (13/11/2026)

Este estudio se escribió el 12/10 sobre la 1.0.1beta. Entre el 13 y el 16/10 Albert hizo,
en paralelo y sin usarlo, las mismas correcciones del motor en el MSXimus Z (Z1.2.5–Z1.2.10)
y las trajo a MoonTANG (1.0.3beta–1.0.5): margen de 24 voces, rampa de TL hacia el valor
escrito, DL de 3 dB, paneo de 3 dB por paso, y bastante más (envolvente, DAMP, LFO…). La
tabla de abajo queda como registro de lo que se midió entonces; la 1.0.6 añade lo que
faltaba de esta lista:

| Qué | Dónde está ahora |
|---|---|
| Paneo 3 dB/paso, rampa de TL, DL 3 dB, suma con margen | MoonTANG 1.0.3beta (motor Z1.2.5–Z1.2.8) |
| **Interpolación lineal entre muestras** (srg320 `5e8599e` + signo) | MSXimus Z1.2.12 (27/10, un producto con signo; "el arreglo de BigMist/ZEMMIX, reescrito") → **MoonTANG 1.0.6** |
| **Estado en `C6h`** | **MoonTANG 1.0.6** (`opl3/host_if.sv`); el MSXimus sigue dando FFh |
| Temporizadores del FM con los periodos del YMF278B | MSXimus Z1.2.12 → **MoonTANG 1.0.6** |

Medido con `tools/sim/opl4eng/` sobre el motor de la 1.0.6 (= Z1.2.12): paneo L/R 0,50 y
0,75; rampa de TL en el sentido correcto; sustain a 0,242 del pico con DL = 4; 12 slots
saturan sin envolverse; **interpolación**: un seno a pitch fraccionario pasa de 30,9 dB de
SNR y saltos de 1,55 (motor 1.0.5, muestra mantenida) a 65,2 dB y saltos de 1,02.

### Lo que se midió el 12/10 sobre la 1.0.1beta

| # | Fallo del motor (`fpga/opl4wave/ymf278b_gowin.v`) | Lo que hace el chip (openMSX) | Antes | Después | Origen |
|---|---|---|---|---|---|
| 1 | **Paneo**: desplazaba la muestra 2 × PAN bits: **12 dB por paso** | 3 dB por paso (`pan_left`/`pan_right`), 7 y 8 silencian la izquierda, 8 y 9 la derecha | PAN 2: L/R = 0,063 (−24 dB); PAN 1: 0,25 | 0,50 y 0,75 | srg320 31/07 (`1a1d3e6`), fórmula de la derecha corregida aquí (la suya cuenta un paso de menos) |
| 2 | **Rampa de TL** (escritura del nivel sin *level direct*): iba en sentido contrario y daba la vuelta (nivel máximo y −48 dB alternos) | hacia el valor escrito: un paso cada 27 muestras al bajar el volumen, cada 13,5 al subirlo | 3Fh→00h: 1977 → 436 (baja); 00h→3Fh: acaba en 29742 (vuelta) | sube a 29766 en ~850 muestras; baja a 1977 en ~1700 | ZEMMIX `06ed1cf` |
| 3 | **Nivel de decay** (DL): comparaba `EVOL[9:6]`, **6 dB por paso** | `dl_tab`: 3 dB por paso, DL = 15 → 3E0h | sustain a 0,059 del pico (−24,6 dB con DL = 4) | 0,234 (−12,6 dB) | srg320 31/07 |
| 4 | **Suma de slots** de 18 bits: con muchos slots fuertes daba la vuelta (clic con el signo cambiado) | satura a ±32767 | 8 slots: cambia de signo en los picos | satura limpiamente | ZEMMIX `eb4ae7c` |
| 5 | **Estado en `C6h`** (`fpga/opl3/host_if.sv`): FFh | el estado, como en `C4h` | `mt1det` esperaba `C6=FF` | `C6=00` | ZEMMIX `baef789`; openMSX `MSXMoonSound::readIO` |

## 2. Pendiente de ZEMMIX / srg320

1. **Cola de accesos de bus** (`opl4_wave.sv`): ZEMMIX encola hasta 8 accesos del bus y los
   sirve al motor uno a uno cuando no está BUSY. Nosotros tenemos un *latch* de una posición
   por sentido (`wr_t`/`req_dat`): dos accesos en menos de ~0,6 µs pierden el primero. A
   3,58 MHz no pasa (un `OUT` son 3,35 µs); con R800 o un Z80 a 7 MHz, sí.
   `check_trace.py` ya lo mide (`min.gap`).
2. **Lecturas de estado no encoladas** (ZEMMIX `2b64b8d`): con el R800, un bucle que lee BUSY
   veía su propia lectura encolada. En MoonTANG BUSY sale solo del motor, no de la cola, así
   que no tenemos ese fallo; pero tampoco se refleja BUSY mientras una escritura espera en el
   *latch*.
3. **Programas de prueba** (`misc/opl4/tools/`): `OPL4SIN.BAS` (acorde de senos escritos en la
   RAM, cabeceras en RAM con WTH, rampa de TL, pan, LD) es la prueba de hardware de estas
   correcciones; portarlo a `tools/msx/mt8sin.asc`. `OPL4MEM.BAS` es nuestro `mt5ram`;
   `SNDTEST.BAS` prueba el OPL3 por `C4h`/`C5h` y el OPL4 (opción A).
4. **Placa de pruebas.** El Poseidon GX150 y el NeptUNO+ tienen **ranura de cartucho**: un
   ZEMMIX con su MoonSound apagado en el OSD es un MSX turbo R (R800, S1990) donde probar
   MoonTANG; con el interno encendido, los dos responden en los mismos puertos.

## 3. Para el MSXimus (Zynq y 60K)

Del parche de octubre solo queda el **estado en `C6h`** (`fpga/opl3/host_if.sv`, el mismo
fichero en los dos proyectos):

```systemverilog
-    dout = address_p1 == 0 ? host_status_p1 : '1;
+    dout = address_p1[0] == 0 ? host_status_p1 : '1;
```

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
