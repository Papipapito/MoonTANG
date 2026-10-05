#!/bin/bash
# Banco de pruebas de la pantalla del vumetro (fpga/src/vu_screen.v).
#
# Uso (WSL Ubuntu-24.04, con Icarus Verilog, python3 y sv2v):
#     bash tools/sim/vu/run_vu.sh            # alrededor de un minuto
#     bash tools/sim/vu/run_vu.sh completo   # los 58 cuadros de barrido enteros (~7 min)
#     BUILD=v1.0-beta bash tools/sim/vu/run_vu.sh    # con otro texto en el pie
# Desde Git Bash en Windows tambien vale: el script se relanza dentro de WSL.
#
#  1. tb_vu_screen.v: barrido 858x525 como el de hdmi.sv, cuadros de muestra y
#     comprobacion automatica de las barras y de la marca de pico. Acaba con
#     "RESULTADO: PASS" o "RESULTADO: FAIL".
#  2. vu_check.py compara los cuadros volcados, pixel a pixel, con un modelo
#     independiente de la pantalla, comprueba el margen de seguridad y deja los
#     PNG en out/ (vu_a, vu_b, vu_c... y su version estirada a 16:9).
#  3. tb_vu_hdmi.v: lo mismo pero con el modulo hdmi de verdad (fpga/hdmi, via
#     sv2v) generando cx/cy y recogiendo la imagen a su salida. Si no hay sv2v
#     este paso se salta y se avisa.
#
# La sintesis de comprobacion con Gowin va aparte: syn_check/run_syn.sh.
set -e
cd "$(dirname "$0")"

if ! command -v iverilog >/dev/null 2>&1 && command -v wsl.exe >/dev/null 2>&1; then
    # Git Bash: /c/ruta -> /mnt/c/ruta y a WSL
    here=$(pwd | sed -E 's#^/([a-zA-Z])/#/mnt/\L\1/#')
    # WSL no hereda el entorno de Windows: BUILD y SV2V se pasan por WSLENV
    export WSLENV="BUILD/u:SV2V/u${WSLENV:+:$WSLENV}"
    MSYS_NO_PATHCONV=1 exec wsl.exe -d "${WSL_DISTRO:-Ubuntu-24.04}" -- bash "$here/run_vu.sh" "$@"
fi

SRC=../../../fpga/src
HDMI=../../../fpga/hdmi
SV2V=${SV2V:-/home/albert/bin/sv2v}
BUILD=${BUILD:-2026-10-04}          # texto del pie (parametro BUILD), hasta 10 caracteres
Q='"'
PLUS=""
[ "$1" = "completo" ] && PLUS="+completo"

mkdir -p build out
# solo lo de este banco: el directorio se comparte con otros (tb_vu_meter)
rm -f build/vu_*.ppm build/frames.txt build/frames_hdmi.txt build/sim.log build/check.log
rm -f build/sim_hdmi.log build/check_hdmi.log build/tb_vu.vvp build/tb_vu_hdmi.vvp build/hdmi_sv2v.v
rm -f out/vu_*.png
fail=0

echo "################ 1. SIMULACION (tb_vu_screen) ################"
iverilog -g2005 -Wall -Wno-timescale -DVU_BUILD="${Q}$BUILD${Q}" -s tb_vu_screen -o build/tb_vu.vvp \
    $SRC/vu_screen.v $SRC/font8x8.v tb_vu_screen.v
( cd build && stdbuf -oL vvp -n tb_vu.vvp $PLUS ) | tee build/sim.log
grep -q "^RESULTADO: PASS" build/sim.log || { echo "FALLO: tb_vu_screen"; fail=1; }

echo "################ 2. MODELO Y PNG ################"
python3 vu_check.py build out $SRC/font8x8.v "$BUILD" | tee build/check.log
grep -q "^MODELO: .*PASS" build/check.log || { echo "FALLO: comparacion con el modelo"; fail=1; }

echo "################ 3. CON EL MODULO hdmi DE VERDAD (tb_vu_hdmi) ################"
if [ -x "$SV2V" ] || command -v "$SV2V" >/dev/null 2>&1; then
    "$SV2V" $HDMI/hdmi.sv $HDMI/tmds_channel.sv $HDMI/packet_picker.sv $HDMI/packet_assembler.sv \
        $HDMI/audio_clock_regeneration_packet.sv $HDMI/audio_info_frame.sv \
        $HDMI/audio_sample_packet.sv $HDMI/auxiliary_video_information_info_frame.sv \
        $HDMI/source_product_description_info_frame.sv -w build/hdmi_sv2v.v
    iverilog -g2012 -DVU_BUILD="${Q}$BUILD${Q}" -s tb_vu_hdmi -o build/tb_vu_hdmi.vvp \
        $SRC/vu_screen.v $SRC/font8x8.v build/hdmi_sv2v.v tb_vu_hdmi.v
    ( cd build && stdbuf -oL vvp -n tb_vu_hdmi.vvp ) | tee build/sim_hdmi.log
    python3 vu_check.py build out $SRC/font8x8.v "$BUILD" frames_hdmi.txt | tee build/check_hdmi.log
    grep -q "^RESULTADO HDMI: PASS" build/sim_hdmi.log || { echo "FALLO: tb_vu_hdmi"; fail=1; }
    grep -q "^MODELO: .*PASS" build/check_hdmi.log || { echo "FALLO: comparacion con el modelo (hdmi)"; fail=1; }
else
    echo "AVISO: no hay sv2v ($SV2V); paso 3 NO ejecutado"
fi

if [ $fail -ne 0 ]; then
    echo "HAY FALLOS"
    exit 1
fi
echo "TODO CORRECTO: imagenes en $(pwd)/out"
