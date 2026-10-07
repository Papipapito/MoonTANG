#!/bin/bash
# Convierte un diseño completo (la lista de ficheros de un .tcl de build) a
# Verilog plano con sv2v, para poder simularlo con Icarus (que no soporta
# interfaces SystemVerilog).
# Uso: conv.sh [build.tcl] [salida.v]      (por defecto: build.tcl -> build/moontang_sv2v.v)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TCL=${1:-build.tcl}
OUT=${2:-$HERE/build/moontang_sv2v.v}
mkdir -p "$HERE/build"
cd "$HERE/../../../fpga"
FILES=$(grep '^add_file' $TCL | awk '{print $2}' | grep -v 'constraints/' | tr '\n' ' ')
# -DMODEL_TECH: los bytes "da igual" de las cabeceras de paquete del HDMI van a 0
# y no a X (solo afecta a la variante con HDMI).
# -DMOONTANG_SIM: valores iniciales de jtopl (FM del Y8950) que en la FPGA pone
# el GSR y que Icarus dejaria en X (solo afecta a la variante con MSX-Audio).
# Aun asi, en Icarus jtopl solo sale de X con un reset largo (>= 100 us; el
# /RESET del MSX lo es): un banco nuevo con resets cortos lo veria en X.
/home/albert/bin/sv2v -DMODEL_TECH -DMOONTANG_SIM -I src $FILES -w "$OUT"
python3 "$HERE/fix_inout.py" "$OUT"
echo "sv2v OK ($TCL): $(grep -c '' "$OUT") lineas, $(grep -c '^module ' "$OUT") modulos"
