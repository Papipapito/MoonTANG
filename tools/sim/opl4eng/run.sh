#!/bin/bash
# The OPL4 PCM engine alone against the YMF278B of openMSX: pan, TL ramp,
# decay level and the 24-slot accumulator. Icarus Verilog, about a minute.
# Use: bash tools/sim/opl4eng/run.sh
set -e
cd "$(dirname "$0")"
mkdir -p build
iverilog -g2012 -s tb_opl4eng -o build/tb_opl4eng.vvp tb_opl4eng.v ../../../fpga/opl4wave/ymf278b_gowin.v 2>&1 | grep -v "warning: Part select" || true
vvp -n build/tb_opl4eng.vvp | tee build/tb_opl4eng.log | grep -v "^VCD\|\$finish"
