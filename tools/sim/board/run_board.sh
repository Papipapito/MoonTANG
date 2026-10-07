#!/bin/bash
# Simulacion de MoonTANG entero sobre el modelo de la WonderTANG 2.0b / 2.02b.
# Uso (WSL Ubuntu-24.04, con Icarus y sv2v):  bash tools/sim/board/run_board.sh [modo]
#   (sin modo)  la prueba principal de la variante SIN HDMI (unos 6 minutos)
#   hdmi        la prueba principal de la variante CON HDMI: lo mismo y ademas un
#               receptor HDMI de verificacion colgado del cable (unos 20 minutos)
#   audio       la prueba principal de la variante con MSX-Audio (moontang_wt_audio:
#               sin HDMI, con el Y8950 en C0h-C1h): lo mismo que la principal y
#               ademas la fase L del Y8950; y en paralelo la fase M (BUSV = 1:
#               turbo, /WR cortos, ruido de bus, /INT en AND, /RESET a mitad)
#   hdmi_audio  EXPERIMENTAL: la variante con HDMI y MSX-Audio (moontang_wt_hdmi_audio):
#               todo lo del modo hdmi (receptor HDMI pixel a pixel y audio muestra a
#               muestra), la fase L del Y8950 y la barra MSX-AUDIO del vumetro
#               (fase V; deja el cuadro del cable en build/hdmi_audio_cuadro.png),
#               y a la vez el control negativo 6 (la barra con la mezcla en vez
#               del aporte del Y8950) (unos 60 minutos). No entra en "todo".
#   todo        las tres primeras, los controles negativos (el 5, del FM del
#               Y8950, con la variante de MSX-Audio) y el barrido de
#               holgura (de la variante normal y de la de MSX-Audio), todos a
#               la vez (un nucleo cada uno)
set -e
cd "$(dirname "$0")"
GW=${GOWIN_SIMLIB:-/mnt/c/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw2a/prim_sim.v}
FPGA=../../../fpga
MODO=${1:-normal}
mkdir -p build

comp() {   # comp <salida> <envoltorio de pines> [opciones de iverilog]   (CORE= otro diseño convertido)
    local out=$1 pins=$2; shift 2
    iverilog -g2012 -I . -I ../board_smd -s tb_board "$@" -o build/$out.vvp \
        tb_board.v wt20x_board.v sdram_model.v ../spi_flash_model.v \
        $pins ${CORE:-build/moontang_sv2v.v} "$GW" 2>&1 | grep -v 'Pruning\|expects 1 bits' || true
}
run() { stdbuf -oL vvp -n build/$1.vvp > build/$1.log 2>&1 || true; }

prep_plain() {   # variante sin HDMI: moontang_top + moontang.cst
    bash conv.sh build.tcl "$PWD/build/moontang_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_top.sv moontang_top $FPGA/constraints/moontang.cst build/moontang_pins.v moontang_pins
    comp main build/moontang_pins.v
}
prep_audio() {   # variante con MSX-Audio: moontang_wt_audio_top + moontang.cst (los mismos pines)
    bash conv.sh build_wt_audio.tcl "$PWD/build/moontang_audio_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_wt_audio_top.sv moontang_wt_audio_top $FPGA/constraints/moontang.cst build/moontang_audio_pins.v moontang_pins
    CORE=build/moontang_audio_sv2v.v comp audio build/moontang_audio_pins.v -DWITH_Y8950
    CORE=build/moontang_audio_sv2v.v comp audio_bus build/moontang_audio_pins.v -DWITH_Y8950 -Ptb_board.BUSV=1
}
prep_hdmi() {    # variante con HDMI: moontang_wt_hdmi_top + moontang_wt_hdmi.cst + receptor
    bash conv.sh build_wt_hdmi.tcl "$PWD/build/moontang_hdmi_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_wt_hdmi_top.sv moontang_wt_hdmi_top $FPGA/constraints/moontang_wt_hdmi.cst build/moontang_hdmi_pins.v moontang_pins
    CORE=build/moontang_hdmi_sv2v.v comp hdmi build/moontang_hdmi_pins.v -Ptb_board.HDMI=1 -DWITH_HDMI_RX ../hdmi/hdmi_rx_check.v
}

prep_hdmi_lock() { # HDMI con inyeccion de una perdida corta de lock_hdmi
    bash conv.sh build_wt_hdmi.tcl "$PWD/build/moontang_hdmi_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_wt_hdmi_top.sv moontang_wt_hdmi_top $FPGA/constraints/moontang_wt_hdmi.cst build/moontang_hdmi_pins.v moontang_pins
    CORE=build/moontang_hdmi_sv2v.v comp hdmi_lock build/moontang_hdmi_pins.v -Ptb_board.HDMI=1 -DWITH_HDMI_RX -DTEST_HDMI_LOCK_GLITCH ../hdmi/hdmi_rx_check.v
}

prep_hdmi_audio() {   # EXPERIMENTAL: moontang_wt_hdmi_audio_top + moontang_wt_hdmi.cst + receptor
    bash conv.sh build_wt_hdmi_audio.tcl "$PWD/build/moontang_hdmi_audio_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_wt_hdmi_audio_top.sv moontang_wt_hdmi_audio_top $FPGA/constraints/moontang_wt_hdmi.cst build/moontang_hdmi_audio_pins.v moontang_pins
    CORE=build/moontang_hdmi_audio_sv2v.v comp hdmi_audio build/moontang_hdmi_audio_pins.v -Ptb_board.HDMI=1 -DWITH_HDMI_RX -DWITH_Y8950 -DWITH_VU_Y8950 ../hdmi/hdmi_rx_check.v
}

if [ "$MODO" = "hdmi_audio" ]; then
    prep_hdmi_audio
    # ---- control negativo 6: la septima barra alimentada con la mezcla (OUT R) ----
    # en vez del aporte del Y8950: se mueve mientras solo suena el OPL4
    sed 's/\.samples({y8950_vu, mix_r, mix_l,/.samples({mix_r, mix_r, mix_l,/' \
        build/moontang_hdmi_audio_sv2v.v > build/moontang_hdmi_audio_sv2v_negvu.v
    [ "$(diff build/moontang_hdmi_audio_sv2v.v build/moontang_hdmi_audio_sv2v_negvu.v | grep -c '^>')" = 1 ] || { echo "control negativo 6: el parche no aplica"; exit 1; }
    CORE=build/moontang_hdmi_audio_sv2v_negvu.v comp neg_vu build/moontang_hdmi_audio_pins.v -Ptb_board.HDMI=1 -Ptb_board.QUIET=1 -DWITH_HDMI_RX -DWITH_Y8950 -DWITH_VU_Y8950 ../hdmi/hdmi_rx_check.v
    rm -f build/hdmi_audio_cuadro.ppm build/hdmi_audio_cuadro.png
    run hdmi_audio & run neg_vu & wait
    echo "################ EXPERIMENTAL: con HDMI y MSX-Audio ################"
    cat build/hdmi_audio.log
    [ -f build/hdmi_audio_cuadro.ppm ] && python3 ../hdmi/ppm2png.py build/hdmi_audio_cuadro.ppm build/hdmi_audio_cuadro.png
    echo
    echo "################ CONTROL NEGATIVO 6: la barra MSX-AUDIO con la mezcla (OUT R) ################"
    grep -a "FAIL\|MSX-AUDIO: nivel\|RESULTADO\|comprobaciones" build/neg_vu.log | head -20
    if grep -a "FAIL" build/neg_vu.log | grep -q "MSX-AUDIO: quieta" && grep -q "RESULTADO: FAIL" build/neg_vu.log; then
        echo ">> control negativo 6 CORRECTO: con la mezcla, la barra se mueve mientras solo suena el OPL4"
    else
        echo ">> control negativo 6 INCORRECTO: la fase V no lo detecta"
    fi
    grep -q "RESULTADO: PASS" build/hdmi_audio.log
    exit $?
fi
if [ "$MODO" = "normal" ]; then
    prep_plain
    echo "################ PRUEBA PRINCIPAL, sin HDMI (.cst actual) ################"
    run main; cat build/main.log
    grep -q "RESULTADO: PASS" build/main.log
    exit 0
fi
if [ "$MODO" = "audio" ]; then
    prep_audio
    run audio & run audio_bus & wait
    echo "################ PRUEBA PRINCIPAL, con MSX-Audio (sin HDMI) ################"
    cat build/audio.log
    echo
    echo "################ MSX-Audio: fase M (bus, turbo, IRQ, /RESET) ################"
    cat build/audio_bus.log
    grep -q "RESULTADO: PASS" build/audio.log && grep -q "RESULTADO: PASS" build/audio_bus.log
    exit $?
fi
if [ "$MODO" = "hdmi" ]; then
    prep_hdmi
    echo "################ PRUEBA PRINCIPAL, con HDMI ################"
    run hdmi; cat build/hdmi.log
    grep -q "RESULTADO: PASS" build/hdmi.log
    exit 0
fi
if [ "$MODO" = "hdmi_lock" ]; then
    prep_hdmi_lock
    echo "################ HDMI: recuperacion de lock ################"
    run hdmi_lock; cat build/hdmi_lock.log
    grep -q "RESULTADO: PASS" build/hdmi_lock.log
    exit $?
fi

prep_plain
prep_hdmi
prep_audio
# ---- control negativo 1: el .cst de agosto (selectores de direccion cruzados) ----
git -C $FPGA show 35fac7c:fpga/constraints/moontang.cst > build/moontang_agosto.cst
python3 ../gen_pin_wrapper.py $FPGA/src/moontang_top.sv moontang_top build/moontang_agosto.cst build/moontang_pins_agosto.v moontang_pins
comp neg_cst build/moontang_pins_agosto.v -Ptb_board.QUIET=1 -Ptb_board.STOP_AFTER=4
# ---- control negativo 2: captura original de la SDRAM (medio ciclo antes) ----
comp neg_sdram build/moontang_pins.v -Ptb_board.QUIET=1 -Ptb_board.CAPTURE=0 -Ptb_board.STOP_AFTER=7
# ---- control negativo 3: la escritura de las shadow FM ve el strobe ya caido en el flanco de bajada ----
sed 's/shw_we\([01]\)_n <= wr_strobe && /shw_we\1_n <= wr_strobe \&\& prev_wr_active \&\& /' \
    build/moontang_sv2v.v > build/moontang_sv2v_negsh.v
[ "$(grep -c 'wr_strobe && prev_wr_active' build/moontang_sv2v_negsh.v)" = 2 ] || { echo "control negativo 3: el parche no aplica"; exit 1; }
CORE=build/moontang_sv2v_negsh.v comp neg_shadow build/moontang_pins.v -Ptb_board.QUIET=1 -Ptb_board.STOP_AFTER=4
# ---- flash en blanco: la suma de la YRW801 tiene que avisar (pantalla y LED) ----
CORE=build/moontang_hdmi_sv2v.v comp blank build/moontang_hdmi_pins.v -Ptb_board.HDMI=1 -Ptb_board.BLANK=1 -Ptb_board.QUIET=1 -DWITH_HDMI_RX ../hdmi/hdmi_rx_check.v
# ---- control negativo 4: done_d1 como antes del arreglo (lectura rancia tras /RESET) ----
python3 neg_done_d1.py build/moontang_sv2v.v build/moontang_sv2v_negarb.v
CORE=build/moontang_sv2v_negarb.v comp neg_arb build/moontang_pins.v -Ptb_board.QUIET=1
# ---- control negativo 5: el FM del Y8950 (jtopl) con el ciclo de bus entero, como en el MSXimus ----
# (cs_n por nivel mientras dura /WR, con el dato y A0 vivos del bus en vez del
# pulso de 2 ciclos con lo guardado del primero): al final del OUT jtopl puede
# ver el bus ya suelto (FFh), segun donde caiga /WR frente al reloj de la FPGA.
# La fase L4b escribe en las 105 fases del Z80 y tiene que fallar; la nota de L4
# solo cae en algunas fases y puede sonar o no
sed -e 's/\.din(jt_din),/.din(din_r),/' -e 's/\.addr(jt_a0),/.addr(addr_r[0]),/' \
    -e 's/\.cs_n(~(jt_wr | jt_wr2)),/.cs_n(~wr_act),/' \
    build/moontang_audio_sv2v.v > build/moontang_audio_sv2v_negjt.v
[ "$(diff build/moontang_audio_sv2v.v build/moontang_audio_sv2v_negjt.v | grep -c '^>')" = 3 ] || { echo "control negativo 5: el parche no aplica"; exit 1; }
CORE=build/moontang_audio_sv2v_negjt.v comp neg_jtopl build/moontang_audio_pins.v -DWITH_Y8950 -Ptb_board.QUIET=1
# ---- barrido: retardo reloj->pad de la FPGA en el lazo del multiplexado ----
SWEEP="2.0 4.0 6.0 8.0 9.0 10.0 11.0 12.0"
for co in $SWEEP; do
    comp sweep_$co build/moontang_pins.v -Ptb_board.QUIET=1 -Ptb_board.STOP_AFTER=4 -Ptb_board.T_FPGA_CO=$co
    CORE=build/moontang_audio_sv2v.v comp asweep_$co build/moontang_audio_pins.v -DWITH_Y8950 -Ptb_board.QUIET=1 -Ptb_board.STOP_AFTER=4 -Ptb_board.T_FPGA_CO=$co
done

echo "lanzando $(ls build/*.vvp | wc -l) simulaciones en paralelo..."
run main & run hdmi & run audio & run audio_bus & run blank & run neg_cst & run neg_sdram & run neg_shadow & run neg_arb & run neg_jtopl &
for co in $SWEEP; do run sweep_$co & run asweep_$co & done
wait

echo "################ PRUEBA PRINCIPAL, sin HDMI (.cst actual) ################"
cat build/main.log
echo
echo "################ PRUEBA PRINCIPAL, con HDMI ################"
cat build/hdmi.log
echo
echo "################ PRUEBA PRINCIPAL, con MSX-Audio (sin HDMI) ################"
cat build/audio.log
echo
echo "################ MSX-Audio: fase M (bus, turbo, IRQ, /RESET) ################"
cat build/audio_bus.log
echo
echo "################ FLASH EN BLANCO (la suma de la YRW801 avisa) ################"
grep -a "FAIL\|ok\]\|RESULTADO\|comprobaciones" build/blank.log | tail -8
echo
echo "################ CONTROL NEGATIVO 1: .cst de agosto (selectores cruzados) ################"
grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg_cst.log | head -20
grep -q "RESULTADO: FAIL" build/neg_cst.log && echo ">> control negativo 1 CORRECTO: el .cst de agosto falla en este banco"
echo
echo "################ CONTROL NEGATIVO 2: captura original de la SDRAM ################"
grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg_sdram.log | head -20
grep -q "RESULTADO: FAIL" build/neg_sdram.log && echo ">> control negativo 2 CORRECTO: la captura medio ciclo antes falla con la ventana de peor caso"
echo
echo "################ CONTROL NEGATIVO 3: escritura de las shadow FM sin strobe ################"
grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg_shadow.log | head -20
grep -q "RESULTADO: FAIL" build/neg_shadow.log && echo ">> control negativo 3 CORRECTO: sin la escritura de las shadow, C5h/C7h no releen"
echo
echo "################ CONTROL NEGATIVO 4: done_d1 como antes (lectura rancia tras /RESET) ################"
grep -a "192\|RESULTADO\|comprobaciones" build/neg_arb.log | head -6
grep -q "RESULTADO: FAIL" build/neg_arb.log && echo ">> control negativo 4 CORRECTO: sin el arreglo, la lectura de la YRW801 tras el /RESET falla"
echo
echo "################ CONTROL NEGATIVO 5: FM del Y8950 con el ciclo de bus entero (como en el MSXimus) ################"
grep -a "FAIL\|FM del Y8950:\|fase [0-9]*: jtopl\|RESULTADO\|comprobaciones" build/neg_jtopl.log | head -45
if grep -a "FAIL" build/neg_jtopl.log | grep -q "105 fases" && grep -q "RESULTADO: FAIL" build/neg_jtopl.log; then
    echo ">> control negativo 5 CORRECTO: con el ciclo entero, el FM del Y8950 se queda con un dato equivocado en alguna fase (L4b)"
else
    echo ">> control negativo 5 INCORRECTO: la fase L4b no lo detecta"
fi
echo
echo "################ BARRIDO: retardo reloj->pad de la FPGA en el multiplexado ################"
echo "(lazo = reloj->pad + 6,0 ns de habilitacion del buffer + 1,5 ns de entrada; la primera"
echo " muestra de cada grupo se toma 18,5 ns despues de cambiar el selector)"
for co in $SWEEP; do
    echo "  reloj->pad = $co ns  ->  normal: $(grep -a 'RESULTADO' build/sweep_$co.log || echo 'sin resultado') | MSX-Audio: $(grep -a 'RESULTADO' build/asweep_$co.log || echo 'sin resultado')"
done
grep -q "RESULTADO: PASS" build/main.log && grep -q "RESULTADO: PASS" build/hdmi.log && grep -q "RESULTADO: PASS" build/audio.log && grep -q "RESULTADO: PASS" build/audio_bus.log && grep -q "RESULTADO: PASS" build/blank.log
