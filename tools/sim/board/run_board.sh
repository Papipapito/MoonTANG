#!/bin/bash
# Simulacion de MoonTANG entero sobre el modelo de la WonderTANG 2.0b / 2.02b.
# Uso (WSL Ubuntu-24.04, con Icarus y sv2v):  bash tools/sim/board/run_board.sh [modo]
#   (sin modo)  la prueba principal de la variante SIN HDMI (unos 6 minutos)
#   hdmi        la prueba principal de la variante CON HDMI: lo mismo y ademas un
#               receptor HDMI de verificacion colgado del cable (unos 20 minutos)
#   todo        las dos anteriores, los controles negativos y el barrido de
#               holgura, todos a la vez (un nucleo cada uno)
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
prep_hdmi() {    # variante con HDMI: moontang_wt_hdmi_top + moontang_wt_hdmi.cst + receptor
    bash conv.sh build_wt_hdmi.tcl "$PWD/build/moontang_hdmi_sv2v.v"
    python3 ../gen_pin_wrapper.py $FPGA/src/moontang_wt_hdmi_top.sv moontang_wt_hdmi_top $FPGA/constraints/moontang_wt_hdmi.cst build/moontang_hdmi_pins.v moontang_pins
    CORE=build/moontang_hdmi_sv2v.v comp hdmi build/moontang_hdmi_pins.v -Ptb_board.HDMI=1 -DWITH_HDMI_RX ../hdmi/hdmi_rx_check.v
}

if [ "$MODO" = "normal" ]; then
    prep_plain
    echo "################ PRUEBA PRINCIPAL, sin HDMI (.cst actual) ################"
    run main; cat build/main.log
    grep -q "RESULTADO: PASS" build/main.log
    exit 0
fi
if [ "$MODO" = "hdmi" ]; then
    prep_hdmi
    echo "################ PRUEBA PRINCIPAL, con HDMI ################"
    run hdmi; cat build/hdmi.log
    grep -q "RESULTADO: PASS" build/hdmi.log
    exit 0
fi

prep_plain
prep_hdmi
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
# ---- barrido: retardo reloj->pad de la FPGA en el lazo del multiplexado ----
SWEEP="2.0 4.0 6.0 8.0 9.0 10.0 11.0 12.0"
for co in $SWEEP; do
    comp sweep_$co build/moontang_pins.v -Ptb_board.QUIET=1 -Ptb_board.STOP_AFTER=4 -Ptb_board.T_FPGA_CO=$co
done

echo "lanzando $(ls build/*.vvp | wc -l) simulaciones en paralelo..."
run main & run hdmi & run blank & run neg_cst & run neg_sdram & run neg_shadow & run neg_arb &
for co in $SWEEP; do run sweep_$co & done
wait

echo "################ PRUEBA PRINCIPAL, sin HDMI (.cst actual) ################"
cat build/main.log
echo
echo "################ PRUEBA PRINCIPAL, con HDMI ################"
cat build/hdmi.log
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
echo "################ BARRIDO: retardo reloj->pad de la FPGA en el multiplexado ################"
echo "(lazo = reloj->pad + 6,0 ns de habilitacion del buffer + 1,5 ns de entrada; la primera"
echo " muestra de cada grupo se toma 18,5 ns despues de cambiar el selector)"
for co in $SWEEP; do
    echo "  reloj->pad = $co ns  ->  $(grep -a 'RESULTADO' build/sweep_$co.log || echo 'sin resultado')"
done
grep -q "RESULTADO: PASS" build/main.log && grep -q "RESULTADO: PASS" build/hdmi.log && grep -q "RESULTADO: PASS" build/blank.log
