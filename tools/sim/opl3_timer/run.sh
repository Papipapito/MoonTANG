#!/bin/bash
# Banco del temporizador del OPL3 parado en el ciclo critico (Verilator).
# Uso (WSL Ubuntu-24.04):  bash tools/sim/opl3_timer/run.sh [negativo]
#   negativo: con el timer.sv anterior al arreglo (el de 35fac7c): TIENE que fallar.
set -e
cd "$(dirname "$0")"
FPGA=../../../fpga
rm -rf build && mkdir -p build/src
cp $FPGA/opl3/*.sv $FPGA/opl3/*.v $FPGA/src/opl4fm.v build/src/
if [ "$1" = "negativo" ]; then
    git -C $FPGA show 35fac7c:fpga/opl3/timer.sv > build/src/timer.sv
    echo "(control negativo: timer.sv sin el arreglo)"
fi
FILES="build/src/opl3_pkg.sv $(ls build/src/*.sv build/src/*.v | grep -v opl3_pkg.sv | grep -v opl4fm.v | tr '\n' ' ') build/src/opl4fm.v"
verilator --cc --exe --build -j 4 -Wno-fatal --public-flat-rw --Mdir build/obj --top-module opl4fm -CFLAGS "-O2" \
    $FILES $PWD/tb_timer_stop.cpp > build/verilator.log 2>&1 || { tail -40 build/verilator.log; exit 1; }
./build/obj/Vopl4fm "${1:-actual}"
