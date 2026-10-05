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
/home/albert/bin/sv2v -DMODEL_TECH -I src $FILES -w "$OUT"
python3 "$HERE/fix_inout.py" "$OUT"
echo "sv2v OK ($TCL): $(grep -c '' "$OUT") lineas, $(grep -c '^module ' "$OUT") modulos"
