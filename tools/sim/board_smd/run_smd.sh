#!/bin/bash
# Simulacion de MoonTANG entero sobre el modelo del cartucho MSXhdmi_tn20k_smd.
# Uso (WSL Ubuntu-24.04, con Icarus y sv2v):  bash tools/sim/board_smd/run_smd.sh [corto]
#   sin argumentos: la prueba completa (bus, memoria, audio HDMI y un cuadro del vumetro)
#   corto         : solo arranque y bus (fases A-D)
set -e
cd "$(dirname "$0")"
GW=${GOWIN_SIMLIB:-/mnt/c/Gowin/Gowin_V1.9.12.03_x64/IDE/simlib/gw2a/prim_sim.v}
FPGA=../../../fpga
PCB=${SMD_PCB:-../../../../MSXhdmi_tn20k_smd/kicad/Cartucho_MSX_Tang_Nano_20k_V9958.kicad_pcb}
mkdir -p build

# 1. pines del modelo de placa, de la PCB real (si el repo de la placa esta al lado)
if [ -f "$PCB" ]; then python3 gen_smd_pins.py "$PCB" smd_pcb_pins.vh; else echo "(sin la PCB a mano: se usa smd_pcb_pins.vh tal cual)"; fi

# 2. el diseño, de SystemVerilog a Verilog plano (lista de ficheros de build_smd.tcl).
#    -DMODEL_TECH: los bytes "da igual" de las cabeceras de paquete del HDMI van a 0
#    y no a X, que en 4 estados llegaria al receptor de verificacion como error.
FILES=$(cd $FPGA && grep '^add_file' build_smd.tcl | awk '{print $2}' | grep -v 'constraints/' | sed "s#^#$FPGA/#" | tr '\n' ' ')
/home/albert/bin/sv2v -DMODEL_TECH -I $FPGA/src $FILES -w build/moontang_smd_sv2v.v
echo "sv2v OK: $(grep -c '^module ' build/moontang_smd_sv2v.v) modulos"

# 3. envoltorio por numero de pin, del .cst
python3 ../gen_pin_wrapper.py $FPGA/src/moontang_smd_top.sv moontang_smd_top $FPGA/constraints/moontang_smd.cst build/moontang_smd_pins.v moontang_smd_pins

EXTRA=""; DEFS=""
[ "$1" = "corto" ] && EXTRA="-Ptb_smd.STOP_AFTER=4"
if [ -f ../hdmi/hdmi_rx_check.v ] && [ -f hdmi_rx_hookup.vh ]; then DEFS="-DWITH_HDMI_RX ../hdmi/hdmi_rx_check.v"; fi

iverilog -g2012 -I . -I ../board -s tb_smd $EXTRA $DEFS -o build/smd.vvp \
    tb_smd.v smd_board.v ../board/sdram_model.v ../spi_flash_model.v \
    build/moontang_smd_pins.v build/moontang_smd_sv2v.v "$GW" 2>&1 | grep -v 'Pruning\|expects 1 bits' || true
stdbuf -oL vvp -n build/smd.vvp | tee build/smd.log
grep -q "RESULTADO: PASS" build/smd.log
