#!/bin/bash
# ============================================================================
# Banco del transmisor HDMI (fpga/hdmi, hdl-util/hdmi) contra un receptor de
# verificacion independiente (hdmi_rx_check.v). Ver la cabecera de tb_hdmi.v.
#
# Uso (WSL Ubuntu-24.04):  bash tools/sim/hdmi/run_hdmi.sh [modo] [+opciones]
#   (sin modo)   prueba principal ESTRICTA (CEA-861 + HDMI 1.4) sobre fpga/hdmi
#                tal cual esta. Acaba en "RESULTADO: PASS" o "RESULTADO: FAIL".
#   tolerante    la misma prueba ACEPTANDO A SABIENDAS las desviaciones
#                conocidas de esta copia de hdl-util: hsync un pixel antes
#                (porche delantero 15), vsync una linea tarde (porche delantero
#                10), 8 caracteres de control entre video e isla, y preambulo de
#                video sin video tras la ultima linea. Todo lo demas se exige.
#   parche       aplica hdmi_cea861.patch a una COPIA (build/) y repite la
#                prueba estricta: demuestra que el arreglo propuesto pasa.
#   negativos    controles negativos: cada uno estropea una cosa y el banco
#                TIENE que dar FAIL. Se hacen sobre la base que pase (estricta
#                si pasa; si no, tolerante).
#   todo         los cuatro anteriores y un resumen.
#   imagen       prueba principal + build/cuadro.png con el ultimo cuadro.
# Lo que siga al modo se pasa al banco (+cuadros=N, +tolerante, +hfp=15 ...).
#
# Variables:
#   SIM=verilator (por defecto) | icarus
#       verilator: ~1 min de compilacion y ~10 s por prueba ("todo": ~10 min).
#       icarus   : compila al instante pero tarda ~4 min por prueba; sirve de
#                  segunda opinion (4 estados: una X del transmisor se veria).
#   HDMI_SRC  directorio de los .sv del transmisor (por defecto ../../../fpga/hdmi)
#   SV2V      ruta de sv2v (por defecto /home/albert/bin/sv2v)
#   BUILD     directorio de trabajo (por defecto build/); util para lanzar dos
#             simuladores a la vez sin que se pisen
#
# Por que sv2v: el transmisor es SystemVerilog con matrices desempaquetadas en
# los puertos, que Icarus no traga; y Verilator 5.020 tampoco compila el
# original (no sabe evaluar int'(real) en un localparam de
# audio_clock_regeneration_packet.sv). sv2v lo deja en Verilog plano que valen
# para los dos. Se convierte con -DMODEL_TECH: sin eso las cabeceras de los
# paquetes nulos y ACR llevan 8'dX y en 4 estados la X llega al cable.
# Ademas hdmi.sv redeclara tmds_internal (linea 364), cosa que sv2v y Verilator
# rechazan: aqui se quita esa linea en una COPIA (build/), sin tocar fpga/hdmi.
# ============================================================================
set -u
cd "$(dirname "$0")"

SIM=${SIM:-verilator}
SV2V=${SV2V:-/home/albert/bin/sv2v}
HDMI_SRC=${HDMI_SRC:-../../../fpga/hdmi}
B=${BUILD:-build}
mkdir -p $B

MODO=principal
if [ $# -gt 0 ] && [ "${1#+}" = "$1" ]; then MODO=$1; shift; fi
EXTRA="$*"

# lo que se acepta a sabiendas en el modo tolerante
TOLERA="+tolerante +hfp=15 +vfp=10"

FICH="tmds_channel packet_picker packet_assembler audio_clock_regeneration_packet
      audio_sample_packet auxiliary_video_information_info_frame audio_info_frame
      source_product_description_info_frame"

VFLAGS="-Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-COMBDLY -Wno-INITIALDLY -Wno-REALCVT -Wno-UNOPTFLAT -Wno-TIMESCALEMOD"

die() { echo "ERROR: $*" >&2; exit 2; }

# convierte <hdmi.sv> <etiqueta>   ->  build/hdmi_<etiqueta>.v (Verilog plano)
convierte() {
    local top=$1 tag=$2 lista="" f
    grep -v '^logic \[9:0\] tmds_internal \[NUM_CHANNELS-1:0\]' "$top" > $B/hdmi_$tag.sv
    for f in $FICH; do lista="$lista $HDMI_SRC/$f.sv"; done
    $SV2V -DMODEL_TECH $B/hdmi_$tag.sv $lista -w $B/hdmi_$tag.v || die "sv2v ha fallado con $top"
}

# compila <etiqueta> <variante> [PARAMETRO=valor ...]
compila() {
    local tag=$1 var=$2 a p=""; shift 2
    if [ "$SIM" = icarus ]; then
        for a in "$@"; do p="$p -Ptb_hdmi.$a"; done
        iverilog -g2012 -s tb_hdmi $p -o $B/sim_${tag}_${var}.vvp tb_hdmi.v hdmi_rx_check.v $B/hdmi_$tag.v \
            || die "iverilog ha fallado"
    else
        for a in "$@"; do p="$p -G$a"; done
        verilator --binary --timing -j 0 $VFLAGS $p --top-module tb_hdmi \
            -Mdir $B/obj_${tag}_${var} -o sim tb_hdmi.v hdmi_rx_check.v $B/hdmi_$tag.v \
            > $B/compila_${tag}_${var}.log 2>&1 \
            || { grep -E "%Error" $B/compila_${tag}_${var}.log | head -20; die "verilator ha fallado (ver $B/compila_${tag}_${var}.log)"; }
    fi
}

# corre <etiqueta> <variante> <log> [+opciones]
corre() {
    local tag=$1 var=$2 log=$3; shift 3
    if [ "$SIM" = icarus ]; then
        vvp -n $B/sim_${tag}_${var}.vvp "$@" > $log 2>&1
    else
        $B/obj_${tag}_${var}/sim "$@" > $log 2>&1
    fi
}

# resultado <log>  ->  PASS, FAIL o NADA
resultado() {
    local r
    r=$(grep -o "^RESULTADO: [A-Z]*" "$1" | tail -1 | cut -d' ' -f2)
    echo "${r:-NADA}"
}

prepara_repo() {
    [ -f $B/.repo_listo ] && return
    convierte $HDMI_SRC/hdmi.sv repo
    compila repo base
    touch $B/.repo_listo
}

prueba_principal() {     # prueba_principal <log> [+opciones]
    local log=$1; shift
    prepara_repo
    corre repo base $log "$@"
    cat $log
}

prueba_parche() {
    local r
    if patch --dry-run -s --binary -o /dev/null $HDMI_SRC/hdmi.sv hdmi_cea861.patch > /dev/null 2>&1; then
        patch -s --binary -o $B/hdmi_parche_src.sv $HDMI_SRC/hdmi.sv hdmi_cea861.patch || die "patch ha fallado"
    elif patch -R --dry-run -s --binary -o /dev/null $HDMI_SRC/hdmi.sv hdmi_cea861.patch > /dev/null 2>&1; then
        echo "(fpga/hdmi/hdmi.sv ya lleva el parche: la prueba principal ya lo cubre)"
        return 3
    else
        echo "(hdmi_cea861.patch no casa con $HDMI_SRC/hdmi.sv: ha cambiado desde que se hizo el parche)"
        return 4
    fi
    convierte $B/hdmi_parche_src.sv parche
    compila parche base
    corre parche base $B/parche.log $EXTRA
    cat $B/parche.log
}

# ---------------------------------------------------------------------------
# Controles negativos: nombre | variante | opciones | que se estropea
# (las posiciones cx/cy son las del contador del transmisor, que va 3 ciclos
#  por delante de lo que sale por el cable)
# ---------------------------------------------------------------------------
NEGATIVOS="
tmds_periodico|base|+neg_tmds=100003|un bit TMDS invertido cada 100003 ciclos de pixel
bit_en_video|base|+neg_flip_cx=103 +neg_flip_cy=50 +neg_flip_canal=1 +neg_flip_bit=3|UN bit de UN simbolo de video
bit_en_isla_c0|base|+neg_flip_cx=770 +neg_flip_cy=200 +neg_flip_canal=0 +neg_flip_bit=0|UN bit de UN simbolo de isla (canal 0)
bit_en_isla_c2|base|+neg_flip_cx=780 +neg_flip_cy=300 +neg_flip_canal=2 +neg_flip_bit=5|UN bit de UN simbolo de isla (canal 2)
bit_en_control|base|+neg_flip_cx=842 +neg_flip_cy=400 +neg_flip_canal=1 +neg_flip_bit=9|UN bit de UN simbolo de control (canal 1)
bit_en_sync|base|+neg_flip_cx=842 +neg_flip_cy=500 +neg_flip_canal=0 +neg_flip_bit=9|UN bit de UN simbolo de control (canal 0: sincronismos)
dato_cuerpo|base|+neg_terc4_cx=770 +neg_terc4_cy=200 +neg_terc4_canal=1 +neg_terc4_xor=1|un dato TERC4 cambiado por otro VALIDO en el cuerpo de un paquete
dato_cabecera|base|+neg_terc4_cx=770 +neg_terc4_cy=210 +neg_terc4_canal=0 +neg_terc4_xor=4|un bit de cabecera de paquete cambiado (simbolo TERC4 valido)
checksum_avi|base|+neg_dato_tipo=82 +neg_dato_sub=0 +neg_dato_bit=20|un bit del AVI InfoFrame cambiado con el BCH recalculado (solo lo caza el checksum)
checksum_audioif|base|+neg_dato_tipo=84 +neg_dato_sub=0 +neg_dato_bit=16|un bit del Audio InfoFrame cambiado con el BCH recalculado
paridad_audio|base|+neg_dato_tipo=02 +neg_dato_sub=2 +neg_dato_bit=51|el bit de paridad de una muestra cambiado con el BCH recalculado
bit_de_muestra|base|+neg_dato_tipo=02 +neg_dato_sub=1 +neg_dato_bit=38|un bit de una muestra (canal derecho) cambiado con el BCH recalculado
acr_desigual|base|+neg_dato_tipo=01 +neg_dato_sub=1 +neg_dato_bit=20|un subpaquete del ACR distinto de los otros tres (BCH recalculado)
marca_b|base|+neg_dato_tipo=02 +neg_dato_sub=4 +neg_dato_bit=21|marca B de inicio de bloque cambiada en una cabecera de audio (BCH recalculado)
muestra_plana|base|+neg_dato_tipo=02 +neg_dato_sub=4 +neg_dato_bit=16|un paquete de audio marcado como muestra plana (un sumidero lo callaria)
cruce_tmds|base|+neg_cruce_tmds|canales TMDS 1 y 2 cruzados
audio_salto|base|+neg_audio_salto=1000|el estimulo se salta la muestra 1000
audio_repite|base|+neg_audio_repite=1500|el estimulo repite la muestra 1500
audio_pulso|base|+neg_audio_pulso=2000|el transmisor pierde un pulso de clk_audio
canales_lr|base|+neg_canales|izquierdo y derecho intercambiados
rgb_adelantado|base|+neg_rgb_comb|rgb combinacional (un ciclo antes de lo debido)
un_pixel|base|+neg_pixel|un bit de un pixel cambiado en un cuadro
aspecto_4_3|base|+neg_aspecto|aspect_16_9 = 0 (AVI anuncia VIC 2 y 4:3)
reloj_audio|base|+audio_div=1126|clk_audio de 47957 Hz (54 MHz / 1126)
formato_576p|vic17|VIC=17|el transmisor genera 720x576p (VIC 17)
audio_44k1|fs441|AUDIO_RATE=44100|el transmisor cree que el audio es de 44,1 kHz
"

controles_negativos() {     # controles_negativos <opciones de la base>
    local base="$1" nombre var opc desc r n=0 ok=0 log
    prepara_repo
    echo "base de los controles: fpga/hdmi con [${base:-estricto}]"
    while IFS='|' read -r nombre var opc desc; do
        [ -z "$nombre" ] && continue
        n=$((n + 1))
        log=$B/neg_$nombre.log
        if [ "$var" = base ]; then
            corre repo base $log $base $opc
        else
            compila repo $var $opc
            corre repo $var $log $base
        fi
        r=$(resultado $log)
        echo
        echo "---- control negativo $n: $nombre -- $desc"
        grep -E "ERROR|FALLO|MAL|TIEMPO AGOTADO|RESUMEN" $log | sed 's/^RESUMEN/resumen/' | cut -c1-230 | head -9 | sed 's/^/    | /'
        if [ "$r" = FAIL ]; then
            ok=$((ok + 1)); echo "    => el banco da FAIL: control CORRECTO"
        else
            echo "    => el banco da $r: CONTROL FALLIDO (el banco no detecta esto)"
        fi
    done <<< "$NEGATIVOS"
    echo
    echo "CONTROLES NEGATIVOS: $ok de $n detectados"
    [ $ok -eq $n ]
}

# ---------------------------------------------------------------------------
rm -f $B/.repo_listo
case "$MODO" in
    principal)
        prueba_principal $B/principal.log $EXTRA
        [ "$(resultado $B/principal.log)" = PASS ]
        ;;
    tolerante)
        prueba_principal $B/tolerante.log $TOLERA $EXTRA
        [ "$(resultado $B/tolerante.log)" = PASS ]
        ;;
    parche)
        rm -f $B/parche.log
        prueba_parche; rc=$?
        [ $rc -eq 3 ] && exit 0
        [ $rc -eq 0 ] && [ "$(resultado $B/parche.log)" = PASS ]
        ;;
    imagen)
        prueba_principal $B/principal.log +ppm=$B/cuadro.ppm $EXTRA
        python3 ppm2png.py $B/cuadro.ppm $B/cuadro.png
        ;;
    negativos|todo)
        echo "################ 1. PRUEBA ESTRICTA sobre fpga/hdmi ################"
        prueba_principal $B/principal.log $EXTRA > /dev/null
        R1=$(resultado $B/principal.log)
        if [ "$MODO" = todo ] || [ "$R1" != PASS ]; then cat $B/principal.log; fi
        BASE=""
        R2="(no hace falta)"
        if [ "$R1" != PASS ]; then
            echo
            echo "################ 2. PRUEBA TOLERANTE ($TOLERA) ################"
            prueba_principal $B/tolerante.log $TOLERA $EXTRA > /dev/null
            R2=$(resultado $B/tolerante.log)
            sed -n '/^Geometria/,$p' $B/tolerante.log | grep -vE "^\s*\[ ok  \]"
            [ "$R2" = PASS ] || die "ni la prueba tolerante pasa: no hay base para los controles negativos"
            BASE="$TOLERA"
        fi
        R3="(no pedida)"
        if [ "$MODO" = todo ]; then
            echo
            echo "################ 3. PRUEBA ESTRICTA con hdmi_cea861.patch (sobre una copia) ################"
            rm -f $B/parche.log
            prueba_parche > $B/parche.out 2>&1; rc=$?
            if [ $rc -eq 3 ]; then cat $B/parche.out; R3="(ya aplicado)"
            elif [ $rc -eq 4 ]; then cat $B/parche.out; R3="(el parche no casa)"
            else
                R3=$(resultado $B/parche.log)
                sed -n '/^---------------- informe/,$p' $B/parche.log | grep -vE "^\s*\[ ok  \]"
            fi
        fi
        echo
        echo "################ 4. CONTROLES NEGATIVOS ################"
        controles_negativos "$BASE"; RN=$?
        echo
        echo "================ RESUMEN ================"
        echo "  fpga/hdmi, prueba estricta          : $R1"
        echo "  fpga/hdmi, prueba tolerante         : $R2"
        echo "  copia con hdmi_cea861.patch, estricta: $R3"
        echo "  controles negativos                 : $([ $RN -eq 0 ] && echo todos detectados || echo ALGUNO SIN DETECTAR)"
        [ $RN -eq 0 ] && { [ "$R1" = PASS ] || [ "$R2" = PASS ]; }
        ;;
    *)
        die "modo desconocido: $MODO (principal, tolerante, parche, negativos, todo, imagen)"
        ;;
esac
