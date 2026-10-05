# ============================================================================
#  syn.tcl - sintesis de COMPROBACION de vu_screen + font8x8 (solo sintesis,
#  sin place & route): LUT / FF / BSRAM y avisos de latch.        (MoonTANG)
#  Uso:  bash tools/sim/vu/syn_check/run_syn.sh        (Git Bash en Windows)
#    o:  cd tools/sim/vu/syn_check && gw_sh syn.tcl
# ============================================================================
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

add_file ../../../../fpga/src/vu_screen.v
add_file ../../../../fpga/src/font8x8.v

set_option -top_module vu_screen
set_option -verilog_std sysv2017
set_option -output_base_name vu_screen

run syn
