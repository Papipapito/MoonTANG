#!/bin/bash
# Sintesis de comprobacion de vu_screen + font8x8 con Gowin (SOLO sintesis, sin
# place & route) y resumen de recursos.
#
# Uso (Git Bash en Windows):   bash tools/sim/vu/syn_check/run_syn.sh
# Otra instalacion de Gowin:   GW_SH=/c/Gowin/.../IDE/bin/gw_sh.exe bash run_syn.sh
set -e
cd "$(dirname "$0")"
GW_SH=${GW_SH:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe}

rm -rf impl syn.log
if ! "$GW_SH" syn.tcl > syn.log 2>&1; then
    tail -30 syn.log
    echo "SINTESIS: FALLO"
    exit 1
fi

RPT=impl/gwsynthesis/vu_screen_syn.rpt.html
RSC=impl/gwsynthesis/vu_screen_syn_rsc.xml
[ -f "$RPT" ] && [ -f "$RSC" ] || { tail -30 syn.log; echo "SINTESIS: sin informe"; exit 1; }

val() { sed -n "s/.*<Module name=\"vu_screen\".* $1=\"\([^\"]*\)\".*/\1/p" "$RSC" | head -1; }
after() { grep -A"$2" "$1" "$RPT" | sed -n "$(( $2 + 1 ))p" | sed 's/<[^>]*>//g'; }

echo "LUT:      $(val Lut)"
echo "ALU:      $(val Alu)"
echo "FF:       $(val Register)"
echo "BSRAM:    $(val T_Bsram | sed 's/(.*//')   (la ROM de font8x8)"
echo "Latches:  $(after 'Register as Latch' 1)"
echo "Fmax estimada (sin P&R): $(after 'Actual Fmax' 8), $(after 'Actual Fmax' 9) niveles de logica"
echo "Avisos y errores en el log:"
grep -i 'warn\|error\|latch' syn.log impl/gwsynthesis/vu_screen.log || echo "  ninguno"
