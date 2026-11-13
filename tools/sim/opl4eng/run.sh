#!/bin/bash
# The OPL4 PCM engine alone against the YMF278B of openMSX: pan, TL ramp,
# decay level, the 24-slot accumulator and the wave interpolation (T5, measured
# by interp_snr.py). Icarus Verilog, about four minutes.
# Use: bash tools/sim/opl4eng/run.sh
set -e
cd "$(dirname "$0")"
mkdir -p build
iverilog -g2012 -s tb_opl4eng -o build/tb_opl4eng.vvp tb_opl4eng.v ../../../fpga/opl4wave/ymf278b_gowin.v 2>&1 | grep -v "warning: Part select" || true
vvp -n build/tb_opl4eng.vvp | tee build/tb_opl4eng.log | grep -v "^VCD\|\$finish"
python3 interp_snr.py build/t5_samples.txt && echo "RESULTADO T5: PASS" || echo "RESULTADO T5: FAIL"
