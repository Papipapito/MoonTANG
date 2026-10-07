# Informe de Codex (06/10/2026): congelaciones con el bitstream OPL4 + MSX-Audio + HDMI

No he editado nada. La evidencia apunta primero a un reinicio/reconfiguración, y después a una IRQ persistente del Y8950; el `/WAIT` normal del OPL4 no puede explicar paradas de segundos.

| Prioridad | Hipótesis | Duración compatible | Exclusiva / más probable con Y8950+HDMI |
|---|---|---:|---|
| 1 | Caída de alimentación o reconfiguración de FPGA | ~3 s | El diseño ocupa 90% de CLS frente a 76%; más conmutación y peor margen eléctrico/routing |
| 2 | Tormenta de `/INT` del Y8950 | Hasta que software la limpie/enmascare; segundos plausibles | Sí: es la única variante que conecta el IRQ Y8950 al slot |
| 3 | Reset por pérdida transitoria de `lock_hdmi`, seguido de recarga YRW801 | ~2 s de carga, pero no debería parar por sí solo al Z80 | HDMI existe también en OPL4-only, pero el diseño grande puede hacerlo más probable |
| 4 | Margen físico SDRAM o rutas de E/S degradado por placement | Fallos de transacción; watchdogs de 38 µs / 3.5 ms | El bitstream combinado está mucho más lleno y la SDRAM no está temporizada en SDC |
| 5 | Conducción espuria de datos/BUSDIR en C0h–C1h | Un ciclo; puede corromper software, no un `/WAIT` de segundos | Sí, sólo añade esos puertos |
| 6 | `/WAIT` OPL4 de 7Fh | Máximo ~19 µs | No: también existe en OPL4+HDMI |

## 1. Alimentación o reconfiguración completa de FPGA — hipótesis principal

La documentación ya mide sólo **4.59 V** en la Tang desde un slot de 5.0 V, tras el Schottky: marginal. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:131). Durante configuración desde flash, la propia WonderTANG mantiene `/WAIT` activo y el MSX queda detenido aproximadamente **3 s**. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:137).

Es la única ruta revisada que explica literalmente “todo el MSX se para 2–3 s y continúa” sin requerir que un programa concreto esté tocando el cartucho.

El bitstream combinado se documenta con 68% de lógica y **90% de CLS**, frente a 55%/76% del HDMI sin Y8950. Además, el propio documento advierte que la interfaz SDRAM no tiene restricciones temporales y que el placement cambia mucho al llenar el chip. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:180).

Confirmación fuerte:

- La pantalla HDMI se queda negra/reinicia durante la pausa; después reaparece.
- LED apagado durante la reconfiguración; tras ella, parpadeo rápido de SDRAM y lento mientras se copia la YRW801.
- El vumetro muestra `YRW801 ...` durante ~2 s antes de volver a `YRW801 OK`.
- `/WAIT` físico permanece activo unos ~3 s.
- Caída de 5 V medida en la Tang coincidente con el evento.

Descartaría esta hipótesis que HDMI permanezca completamente estable —sin black frame, sin volver a `YRW801 ...`— y que el LED permanezca fijo.

Arreglo: primero alimentar la Tang con 5 V realmente regulados y medir en la propia placa, bajo carga. A nivel RTL/placa, conviene no depender de una alimentación que cruza un Schottky ya marginal; añadir reserva de corriente/menor caída o alimentación local adecuada. No se arregla con un watchdog RTL si la FPGA se está reconfigurando.

## 2. IRQ del Y8950 mantenida: tormenta de interrupciones — muy probable si coincide con uso MSX-Audio

Con `Y8950=1`, el IRQ compuesto del chip se propaga físicamente al `/INT` del slot:

- El Y8950 compone `timers | EOS | BUF_RDY`, bajo máscaras de registro 04h. [y8950_adpcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/y8950/y8950_adpcm.v:516)
- `moontang_y8950` convierte `irq` a activo bajo. [moontang_y8950.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_y8950.sv:160)
- El core lo AND-ea con el IRQ OPL3 y lo lleva al bus. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:335)
- El front-end invierte correctamente para los NPN de colector abierto de WonderTANG 2.0b. [wt_bus.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/wondertang/wt_bus.sv:174)

El caso peligroso está incluso documentado: `BUF_RDY` es un nivel. Si queda desenmascarado con ADPCM inactivo, no se puede “limpiar” mediante la ISR; `/INT` seguirá activo hasta volver a enmascararlo. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:77). El BIOS normal del MSX tampoco limpia los flags del Y8950.

Esto puede dejar al Z80 entrando repetidamente en la ISR. No es un `/WAIT`: parece congelación, pero el CPU sigue ejecutando el handler.

Confirmación:

- Durante la pausa, pantalla HDMI y LED siguen estables en `YRW801 OK` / `MSX OK`.
- Sonda: `/INT` permanece bajo, mientras `/WAIT` permanece inactivo.
- Pasa al usar VGMPlay, MoonBlaster, detección MSX-Audio, timers, ADPCM, EOS o escritura en registro 04h; no pasa con un programa que no toque C0h–C1h.
- Al enmascarar todas las fuentes Y8950 o al no enrutar temporalmente su IRQ, desaparece.

Arreglo recomendado: no conectar el IRQ del Y8950 a `/INT` por defecto, o protegerlo detrás de un enable explícito y bien documentado. Como mínimo, tratar `BUF_RDY` como fuente no enrutable a `/INT`, o asegurar que una operación de “IRQ reset” realmente desarme/enmascare el nivel antes de volver a armarlos.

## 3. Pérdida de `lock_hdmi` que reinicia SDRAM/loader — posible, pero no explica sola un Z80 parado

En las variantes HDMI, `lock_eng` viene del PLL HDMI. [moontang_wt_hdmi_audio_top.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_hdmi_audio_top.sv:76). La carcasa forma:

```verilog
pll_locked = lock_main & lock_eng;
```

[moontang_wt_shell.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_shell.sv:129)

La pérdida de cualquiera de ambos fuerza `por_reset_n` a cero. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:117). Eso reinicia SDRAM, loader y deja `wl_done=0`; al recuperar lock, vuelve a copiar la YRW801. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:270).

Pero hay una matización importante: el propio core evita meter `sdram_init_busy` en `/WAIT`, precisamente para no matar el MSX si un PLL falla. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:331). Por tanto, una mera pérdida de lock, sin reconfiguración, debería silenciar/resetear el cartucho y recargar la YRW801, no congelar globalmente al Z80 durante dos segundos.

Confirmación:

- HDMI puede perder/rearmar vídeo, pero no necesariamente quedar negro los ~3 s de reconfiguración.
- LED pasa a apagado si no hay lock, luego a init/carga.
- Vumetro pasa de `YRW801 OK` a `...`.
- PCM se corta; el comportamiento del FM ayuda a distinguir cuánto se ha reseteado.

Arreglo: separar el reset del subsistema SDRAM/loader del `lock_hdmi`. El loader debería depender de `lock_main`; el motor PCM sí debe resetearse/gatearse cuando desaparezca `clk_eng`. Así una inestabilidad de HDMI no obliga a recargar 2 MB.

Esto no es exclusivo de Y8950+HDMI: también afecta al bitstream OPL4+HDMI. La diferencia sería indirecta: potencia, routing o mayor sensibilidad del diseño grande.

## 4. SDRAM y arbitraje con segundo cliente — riesgo serio de audio/estado, débil como causa directa del Z80 detenido

El Y8950 añade el segundo cliente `wv2` de SDRAM. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:246). El puente prioriza explícitamente:

```text
refresh > wave/loader/PCM (wv) > ADPCM Y8950 (wv2)
```

[wv_to_sdram.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/wv_to_sdram.v:21).

Eso implica:

- Durante carga YRW801, el ADPCM puede sufrir gran latencia.
- Un fallo SDRAM no queda bloqueado indefinidamente: el puente corta a ~38 µs, marca `sd_timeout` y devuelve `FFFFh`. [wv_to_sdram.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/wv_to_sdram.v:105).
- El motor OPL4 tiene además watchdog de ~3.5 ms. [opl4_pcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/opl4_pcm.v:515)
- Y8950 tiene watchdog de ~150 µs. [y8950_adpcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/y8950/y8950_adpcm.v:212)

Por diseño, esto degrada datos/audio, no mantiene `/WAIT` ni detiene al Z80. Puede provocar que software que haga polling de Y8950 parezca parado, pero no explica un congelamiento de toda la máquina en reposo.

El riesgo aumenta específicamente en el bitstream combinado porque la SDRAM externa de la Tang no tiene timing I/O constreñido en `moontang_wt_hdmi.sdc`; el proyecto lo reconoce expresamente. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:187)

Confirmación:

- No hay `/WAIT` ni `/INT` sostenidos.
- HDMI sigue estable.
- Fallan samples/ADPCM u OPL4 PCM, no necesariamente FM.
- Telemetría UART: aumentan `ifw_hits` del OPL4.
- Ojo: `sd_timeout` se genera pero el LED no lo usa en su selección final. [moontang_wt_shell.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_shell.sv:280)

Arreglo: caracterizar SDRAM con varios placements/seeds y restricciones/colocación física adecuadas; exponer `sd_timeout` al LED/vumetro/UART; si el ADPCM resulta sensible, darle cuota de arbitraje o usar BSRAM de respaldo limitado.

## 5. Datos/BUSDIR conducidos por error — posible corrupción puntual, no congelación de segundos

El bus sólo se reclama cuando hay una lectura decodificada y el bus está vivo:

```verilog
rd_active = any_rd & bus_ok;
```

[moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:304)

El front-end añade como guarda que `/RD` físico esté bajo antes de habilitar el transceptor. [wt_bus.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/wondertang/wt_bus.sv:184)

La variante Y8950 añade lecturas C0h/C1h, con decodificación registrada. [moontang_y8950.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_y8950.sv:96). Por tanto, una captura incorrecta del bus multiplexado podría conducir datos durante una lectura C0/C1 indebida; puede corromper una operación o colgar software que depende de ella, pero no hay camino RTL que mantenga BUSDIR durante segundos.

Confirmación: sólo aparece alrededor de accesos C0h/C1h, no hay `/WAIT` ni `/INT` sostenidos, y un analizador muestra `CART_DATA_DIR` activo únicamente con `/RD` bajo.

Arreglo: auditar con analizador el timing real de `CART_RD_n`, `CART_DATA_DIR` y datos; no eliminar la guarda física. Las salidas de bus están declaradas como falsos caminos en el SDC, por lo que el cierre STA no garantiza ese margen de salida. [moontang_wt_hdmi.sdc](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/constraints/moontang_wt_hdmi.sdc:55)

## 6. `/WAIT` de OPL4/7Fh — descartable para pausas largas

Sólo existe este `/WAIT` funcional:

```verilog
wait_n = opl4pcm_wait_n | ~bus_ok;
```

[moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:334)

Y `opl4pcm_wait_n` sólo estira una lectura `IN 7Fh`, hasta respuesta del motor o timeout de aproximadamente **19 µs**, incluso con el motor en reset o SDRAM recalibrando. [opl4_pcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/opl4_pcm.v:249)

Durante la carga de YRW801, el motor está en reset (`eng_rst_n = bus_reset_n & wl_done`), [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:173) pero el timeout sigue soltando el Z80. No puede producir 2–3 s.

Además existe exactamente igual en OPL4+HDMI sin Y8950; por tanto no cuadra con la diferencia observada.

## Pruebas mínimas, en este orden

1. Durante una pausa, observar simultáneamente 5 V en Tang, LED, HDMI, `/WAIT` e `/INT`.
2. Si `/WAIT` permanece activo ~3 s y HDMI reinicia: alimentación/reconfiguración.
3. Si `/INT` queda bajo y la imagen/LED no cambian: IRQ Y8950. Probar sin tocar C0/C1, y luego con software que use ADPCM/timers.
4. Probar `moontang_wt_audio_top.sv` sin HDMI:
   - falla también: Y8950/IRQ/SDRAM Y8950;
   - deja de fallar: interacción HDMI + ocupación/routing/alimentación.
5. Si HDMI se mantiene estable y ambas líneas están inactivas, mirar UART del PCM y el comportamiento de samples: SDRAM/routing antes que bus.

La observación más discriminante es sencilla: si durante el supuesto congelamiento el vumetro sigue vivo, continúa mostrando `YRW801 OK` y LED fijo, descarto casi por completo reset/reconfiguración y pondría el IRQ Y8950 como primer sospechoso.
tokens used
136.385
No he editado nada. La evidencia apunta primero a un reinicio/reconfiguración, y después a una IRQ persistente del Y8950; el `/WAIT` normal del OPL4 no puede explicar paradas de segundos.

| Prioridad | Hipótesis | Duración compatible | Exclusiva / más probable con Y8950+HDMI |
|---|---|---:|---|
| 1 | Caída de alimentación o reconfiguración de FPGA | ~3 s | El diseño ocupa 90% de CLS frente a 76%; más conmutación y peor margen eléctrico/routing |
| 2 | Tormenta de `/INT` del Y8950 | Hasta que software la limpie/enmascare; segundos plausibles | Sí: es la única variante que conecta el IRQ Y8950 al slot |
| 3 | Reset por pérdida transitoria de `lock_hdmi`, seguido de recarga YRW801 | ~2 s de carga, pero no debería parar por sí solo al Z80 | HDMI existe también en OPL4-only, pero el diseño grande puede hacerlo más probable |
| 4 | Margen físico SDRAM o rutas de E/S degradado por placement | Fallos de transacción; watchdogs de 38 µs / 3.5 ms | El bitstream combinado está mucho más lleno y la SDRAM no está temporizada en SDC |
| 5 | Conducción espuria de datos/BUSDIR en C0h–C1h | Un ciclo; puede corromper software, no un `/WAIT` de segundos | Sí, sólo añade esos puertos |
| 6 | `/WAIT` OPL4 de 7Fh | Máximo ~19 µs | No: también existe en OPL4+HDMI |

## 1. Alimentación o reconfiguración completa de FPGA — hipótesis principal

La documentación ya mide sólo **4.59 V** en la Tang desde un slot de 5.0 V, tras el Schottky: marginal. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:131). Durante configuración desde flash, la propia WonderTANG mantiene `/WAIT` activo y el MSX queda detenido aproximadamente **3 s**. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:137).

Es la única ruta revisada que explica literalmente “todo el MSX se para 2–3 s y continúa” sin requerir que un programa concreto esté tocando el cartucho.

El bitstream combinado se documenta con 68% de lógica y **90% de CLS**, frente a 55%/76% del HDMI sin Y8950. Además, el propio documento advierte que la interfaz SDRAM no tiene restricciones temporales y que el placement cambia mucho al llenar el chip. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:180).

Confirmación fuerte:

- La pantalla HDMI se queda negra/reinicia durante la pausa; después reaparece.
- LED apagado durante la reconfiguración; tras ella, parpadeo rápido de SDRAM y lento mientras se copia la YRW801.
- El vumetro muestra `YRW801 ...` durante ~2 s antes de volver a `YRW801 OK`.
- `/WAIT` físico permanece activo unos ~3 s.
- Caída de 5 V medida en la Tang coincidente con el evento.

Descartaría esta hipótesis que HDMI permanezca completamente estable —sin black frame, sin volver a `YRW801 ...`— y que el LED permanezca fijo.

Arreglo: primero alimentar la Tang con 5 V realmente regulados y medir en la propia placa, bajo carga. A nivel RTL/placa, conviene no depender de una alimentación que cruza un Schottky ya marginal; añadir reserva de corriente/menor caída o alimentación local adecuada. No se arregla con un watchdog RTL si la FPGA se está reconfigurando.

## 2. IRQ del Y8950 mantenida: tormenta de interrupciones — muy probable si coincide con uso MSX-Audio

Con `Y8950=1`, el IRQ compuesto del chip se propaga físicamente al `/INT` del slot:

- El Y8950 compone `timers | EOS | BUF_RDY`, bajo máscaras de registro 04h. [y8950_adpcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/y8950/y8950_adpcm.v:516)
- `moontang_y8950` convierte `irq` a activo bajo. [moontang_y8950.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_y8950.sv:160)
- El core lo AND-ea con el IRQ OPL3 y lo lleva al bus. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:335)
- El front-end invierte correctamente para los NPN de colector abierto de WonderTANG 2.0b. [wt_bus.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/wondertang/wt_bus.sv:174)

El caso peligroso está incluso documentado: `BUF_RDY` es un nivel. Si queda desenmascarado con ADPCM inactivo, no se puede “limpiar” mediante la ISR; `/INT` seguirá activo hasta volver a enmascararlo. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:77). El BIOS normal del MSX tampoco limpia los flags del Y8950.

Esto puede dejar al Z80 entrando repetidamente en la ISR. No es un `/WAIT`: parece congelación, pero el CPU sigue ejecutando el handler.

Confirmación:

- Durante la pausa, pantalla HDMI y LED siguen estables en `YRW801 OK` / `MSX OK`.
- Sonda: `/INT` permanece bajo, mientras `/WAIT` permanece inactivo.
- Pasa al usar VGMPlay, MoonBlaster, detección MSX-Audio, timers, ADPCM, EOS o escritura en registro 04h; no pasa con un programa que no toque C0h–C1h.
- Al enmascarar todas las fuentes Y8950 o al no enrutar temporalmente su IRQ, desaparece.

Arreglo recomendado: no conectar el IRQ del Y8950 a `/INT` por defecto, o protegerlo detrás de un enable explícito y bien documentado. Como mínimo, tratar `BUF_RDY` como fuente no enrutable a `/INT`, o asegurar que una operación de “IRQ reset” realmente desarme/enmascare el nivel antes de volver a armarlos.

## 3. Pérdida de `lock_hdmi` que reinicia SDRAM/loader — posible, pero no explica sola un Z80 parado

En las variantes HDMI, `lock_eng` viene del PLL HDMI. [moontang_wt_hdmi_audio_top.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_hdmi_audio_top.sv:76). La carcasa forma:

```verilog
pll_locked = lock_main & lock_eng;
```

[moontang_wt_shell.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_shell.sv:129)

La pérdida de cualquiera de ambos fuerza `por_reset_n` a cero. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:117). Eso reinicia SDRAM, loader y deja `wl_done=0`; al recuperar lock, vuelve a copiar la YRW801. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:270).

Pero hay una matización importante: el propio core evita meter `sdram_init_busy` en `/WAIT`, precisamente para no matar el MSX si un PLL falla. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:331). Por tanto, una mera pérdida de lock, sin reconfiguración, debería silenciar/resetear el cartucho y recargar la YRW801, no congelar globalmente al Z80 durante dos segundos.

Confirmación:

- HDMI puede perder/rearmar vídeo, pero no necesariamente quedar negro los ~3 s de reconfiguración.
- LED pasa a apagado si no hay lock, luego a init/carga.
- Vumetro pasa de `YRW801 OK` a `...`.
- PCM se corta; el comportamiento del FM ayuda a distinguir cuánto se ha reseteado.

Arreglo: separar el reset del subsistema SDRAM/loader del `lock_hdmi`. El loader debería depender de `lock_main`; el motor PCM sí debe resetearse/gatearse cuando desaparezca `clk_eng`. Así una inestabilidad de HDMI no obliga a recargar 2 MB.

Esto no es exclusivo de Y8950+HDMI: también afecta al bitstream OPL4+HDMI. La diferencia sería indirecta: potencia, routing o mayor sensibilidad del diseño grande.

## 4. SDRAM y arbitraje con segundo cliente — riesgo serio de audio/estado, débil como causa directa del Z80 detenido

El Y8950 añade el segundo cliente `wv2` de SDRAM. [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:246). El puente prioriza explícitamente:

```text
refresh > wave/loader/PCM (wv) > ADPCM Y8950 (wv2)
```

[wv_to_sdram.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/wv_to_sdram.v:21).

Eso implica:

- Durante carga YRW801, el ADPCM puede sufrir gran latencia.
- Un fallo SDRAM no queda bloqueado indefinidamente: el puente corta a ~38 µs, marca `sd_timeout` y devuelve `FFFFh`. [wv_to_sdram.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/wv_to_sdram.v:105).
- El motor OPL4 tiene además watchdog de ~3.5 ms. [opl4_pcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/opl4_pcm.v:515)
- Y8950 tiene watchdog de ~150 µs. [y8950_adpcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/y8950/y8950_adpcm.v:212)

Por diseño, esto degrada datos/audio, no mantiene `/WAIT` ni detiene al Z80. Puede provocar que software que haga polling de Y8950 parezca parado, pero no explica un congelamiento de toda la máquina en reposo.

El riesgo aumenta específicamente en el bitstream combinado porque la SDRAM externa de la Tang no tiene timing I/O constreñido en `moontang_wt_hdmi.sdc`; el proyecto lo reconoce expresamente. [docs/WONDERTANG.md](C:/Users/alber/proyectosAI/msx/MoonTANG/docs/WONDERTANG.md:187)

Confirmación:

- No hay `/WAIT` ni `/INT` sostenidos.
- HDMI sigue estable.
- Fallan samples/ADPCM u OPL4 PCM, no necesariamente FM.
- Telemetría UART: aumentan `ifw_hits` del OPL4.
- Ojo: `sd_timeout` se genera pero el LED no lo usa en su selección final. [moontang_wt_shell.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_wt_shell.sv:280)

Arreglo: caracterizar SDRAM con varios placements/seeds y restricciones/colocación física adecuadas; exponer `sd_timeout` al LED/vumetro/UART; si el ADPCM resulta sensible, darle cuota de arbitraje o usar BSRAM de respaldo limitado.

## 5. Datos/BUSDIR conducidos por error — posible corrupción puntual, no congelación de segundos

El bus sólo se reclama cuando hay una lectura decodificada y el bus está vivo:

```verilog
rd_active = any_rd & bus_ok;
```

[moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:304)

El front-end añade como guarda que `/RD` físico esté bajo antes de habilitar el transceptor. [wt_bus.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/wondertang/wt_bus.sv:184)

La variante Y8950 añade lecturas C0h/C1h, con decodificación registrada. [moontang_y8950.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_y8950.sv:96). Por tanto, una captura incorrecta del bus multiplexado podría conducir datos durante una lectura C0/C1 indebida; puede corromper una operación o colgar software que depende de ella, pero no hay camino RTL que mantenga BUSDIR durante segundos.

Confirmación: sólo aparece alrededor de accesos C0h/C1h, no hay `/WAIT` ni `/INT` sostenidos, y un analizador muestra `CART_DATA_DIR` activo únicamente con `/RD` bajo.

Arreglo: auditar con analizador el timing real de `CART_RD_n`, `CART_DATA_DIR` y datos; no eliminar la guarda física. Las salidas de bus están declaradas como falsos caminos en el SDC, por lo que el cierre STA no garantiza ese margen de salida. [moontang_wt_hdmi.sdc](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/constraints/moontang_wt_hdmi.sdc:55)

## 6. `/WAIT` de OPL4/7Fh — descartable para pausas largas

Sólo existe este `/WAIT` funcional:

```verilog
wait_n = opl4pcm_wait_n | ~bus_ok;
```

[moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:334)

Y `opl4pcm_wait_n` sólo estira una lectura `IN 7Fh`, hasta respuesta del motor o timeout de aproximadamente **19 µs**, incluso con el motor en reset o SDRAM recalibrando. [opl4_pcm.v](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/opl4_pcm.v:249)

Durante la carga de YRW801, el motor está en reset (`eng_rst_n = bus_reset_n & wl_done`), [moontang_core.sv](C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/src/moontang_core.sv:173) pero el timeout sigue soltando el Z80. No puede producir 2–3 s.

Además existe exactamente igual en OPL4+HDMI sin Y8950; por tanto no cuadra con la diferencia observada.

## Pruebas mínimas, en este orden

1. Durante una pausa, observar simultáneamente 5 V en Tang, LED, HDMI, `/WAIT` e `/INT`.
2. Si `/WAIT` permanece activo ~3 s y HDMI reinicia: alimentación/reconfiguración.
3. Si `/INT` queda bajo y la imagen/LED no cambian: IRQ Y8950. Probar sin tocar C0/C1, y luego con software que use ADPCM/timers.
4. Probar `moontang_wt_audio_top.sv` sin HDMI:
   - falla también: Y8950/IRQ/SDRAM Y8950;
   - deja de fallar: interacción HDMI + ocupación/routing/alimentación.
5. Si HDMI se mantiene estable y ambas líneas están inactivas, mirar UART del PCM y el comportamiento de samples: SDRAM/routing antes que bus.

La observación más discriminante es sencilla: si durante el supuesto congelamiento el vumetro sigue vivo, continúa mostrando `YRW801 OK` y LED fijo, descarto casi por completo reset/reconfiguración y pondría el IRQ Y8950 como primer sospechoso.
