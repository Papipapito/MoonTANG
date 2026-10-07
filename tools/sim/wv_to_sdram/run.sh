#!/bin/bash
# Banco unitario del puente wv_to_sdram (dos clientes, refresco, watchdog) con un
# controlador de SDRAM falso que se atasca a voluntad.
# Uso (WSL Ubuntu-24.04, Icarus):  bash tools/sim/wv_to_sdram/run.sh [negativo]
#   negativo: tres controles que TIENEN que fallar:
#     1. el wv_to_sdram.v de 5400f15 (antes del arreglo del watchdog durante
#        un refresco, y con un solo cliente): falla en (a).
#     2. el puente actual sin el arreglo de la operacion abortada (owner_gone
#        a 0: el done de la abortada se entrega): falla en (f).
#     3. el puente actual con el watchdog contando tambien en ST_IDLE: falla
#        en (g).
set -e
cd "$(dirname "$0")"
FPGA=../../../fpga
mkdir -p build
if [ "$1" = "negativo" ]; then
    ok=1
    git -C $FPGA show 5400f15:fpga/src/wv_to_sdram.v > build/wv_to_sdram_5400f15.v
    iverilog -g2012 -DNEG_HEAD -s tb_wv_to_sdram -o build/neg.vvp tb_wv_to_sdram.v build/wv_to_sdram_5400f15.v
    vvp -n build/neg.vvp > build/neg.log
    grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg.log
    if grep -q "RESULTADO: FAIL" build/neg.log; then
        echo ">> control negativo 1 CORRECTO: el puente de 5400f15 falla en este banco"
    else
        echo ">> control negativo 1 INCORRECTO: el puente de 5400f15 pasa"; ok=0
    fi
    sed 's/wire owner_gone = aborted || !owner_req;/wire owner_gone = 1'"'"'b0;/' \
        $FPGA/src/wv_to_sdram.v > build/wv_neg_abort.v
    [ "$(grep -c "owner_gone = 1'b0" build/wv_neg_abort.v)" = 1 ] || { echo "control negativo 2: el parche no aplica"; exit 1; }
    iverilog -g2012 -s tb_wv_to_sdram -o build/neg_abort.vvp tb_wv_to_sdram.v build/wv_neg_abort.v
    vvp -n build/neg_abort.vvp > build/neg_abort.log
    grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg_abort.log
    if grep -a "FAIL" build/neg_abort.log | grep -q "abortada" && grep -q "RESULTADO: FAIL" build/neg_abort.log; then
        echo ">> control negativo 2 CORRECTO: sin el arreglo, el done de la abortada llega a la peticion nueva"
    else
        echo ">> control negativo 2 INCORRECTO"; ok=0
    fi
    sed 's/wdog        <= (st_changed || st == ST_IDLE || st == ST_DONE) ? 13'"'"'d0/wdog        <= st_changed ? 13'"'"'d0/' \
        $FPGA/src/wv_to_sdram.v > build/wv_neg_wdog.v
    [ "$(grep -c "wdog        <= st_changed ? 13'd0" build/wv_neg_wdog.v)" = 1 ] || { echo "control negativo 3: el parche no aplica"; exit 1; }
    iverilog -g2012 -s tb_wv_to_sdram -o build/neg_wdog.vvp tb_wv_to_sdram.v build/wv_neg_wdog.v
    vvp -n build/neg_wdog.vvp > build/neg_wdog.log
    grep -a "FAIL\|RESULTADO\|comprobaciones" build/neg_wdog.log
    if grep -a "FAIL" build/neg_wdog.log | grep -q "(g)" && grep -q "RESULTADO: FAIL" build/neg_wdog.log; then
        echo ">> control negativo 3 CORRECTO: contando en ST_IDLE, el watchdog salta tras un init largo"
    else
        echo ">> control negativo 3 INCORRECTO"; ok=0
    fi
    [ $ok = 1 ] && exit 0
    exit 1
fi
iverilog -g2012 -s tb_wv_to_sdram -o build/tb.vvp tb_wv_to_sdram.v $FPGA/src/wv_to_sdram.v
vvp -n build/tb.vvp | tee build/tb.log
grep -q "RESULTADO: PASS" build/tb.log
