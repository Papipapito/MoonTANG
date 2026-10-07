#!/bin/bash
# Interferencia en la SDRAM entre el motor PCM del OPL4 y el ADPCM del Y8950.
# Uso (WSL Ubuntu-24.04, Icarus):  bash tools/sim/y8950/run.sh [mix]
#   mix: solo tb_mix.v (la mezcla del Y8950 con su limitador; ver el fichero)
# Motor saturado (un fallo de cache detras de otro, el peor caso) a 38,571 MHz
# (variantes con HDMI) y a 37,125 MHz (sin HDMI), contra un ADPCM que sube y
# relee sin parar con una pausa entre operaciones de:
#   -1    sin ADPCM (referencia)
#   1620  30 us   (VGMPlay subiendo muestras; en bloques de 256 bytes en vez de
#                  2048, para que en los ~15 ms simulados tambien relea)
#   318   5,9 us  (OTIR a 3,58 MHz)
#   160   3 us    (OTIR con turbo de 7 MHz)
#   54    1 us    (imposible para un Z80)
#   0     sin pausa (saturado)
# Cada ejecucion con ADPCM tiene que releer (y comprobar) al menos una palabra.
# PASA si todas las ejecuciones pasan y, con cada reloj, el ritmo del motor con
# un ADPCM al ritmo de un Z80 (pausa >= 3 us) es >= 99 % del de referencia y
# con cualquier pausa >= 95 %.
# Ademas (tb_rst.v): /RESET del MSX a mitad de operaciones del ADPCM con el
# motor saturado, en tres configuraciones (resets de 1-40 ciclos y peticion
# nueva inmediata; 1-40 ciclos y 1 us de pausa; 1-3 ciclos y peticion nueva
# inmediata, 6000 resets): ningun done de una operacion abortada llega a la
# peticion nueva y ninguna lectura sale mal.
set -e
cd "$(dirname "$0")"
FPGA=../../../fpga
mkdir -p build
if [ "$1" = "mix" ]; then
    # tb_mix.v: limitador de la mezcla del Y8950 (exhaustivo) + acordes de jtopl
    F="$(ls $FPGA/y8950/jtopl/*.v) $(ls $FPGA/y8950/jt10/*.v) $FPGA/y8950/y8950_adpcm.v $FPGA/y8950/adpcm_sdram.v $FPGA/src/moontang_y8950.sv $FPGA/src/moontang_mix_y8950.v"
    iverilog -g2012 -DMOONTANG_SIM -s tb_mix -o build/mix.vvp tb_mix.v $F
    vvp -n build/mix.vvp | tee build/mix.log
    grep -q "RESULTADO: PASS" build/mix.log
    exit $?
fi
SRC="tb_interf.v ../board/sdram_model.v $FPGA/src/ip_sdram_tangnano20k_c.v $FPGA/src/wv_to_sdram.v $FPGA/src/wave_sdram.v $FPGA/y8950/adpcm_sdram.v"
GAPS="-1 1620 318 160 54 0"
mkdir -p build
for half in 12.963 13.468; do
  for g in $GAPS; do
    blk=2048; [ "$g" = 1620 ] && blk=256      # 30 us: 2048 escrituras no caben en la simulacion
    iverilog -g2012 -o build/h${half}_g${g}.vvp -s tb_interf -Ptb_interf.ADPCM_GAP=$g -Ptb_interf.N_ENG=50000 -Ptb_interf.ENG_HALF=$half -Ptb_interf.A_BLK=$blk $SRC
  done
done
RSRC="tb_rst.v ../board/sdram_model.v $FPGA/src/ip_sdram_tangnano20k_c.v $FPGA/src/wv_to_sdram.v $FPGA/src/wave_sdram.v $FPGA/y8950/adpcm_sdram.v"
iverilog -g2012 -s tb_rst -Ptb_rst.RELAY=0  -o build/rst_a.vvp $RSRC
iverilog -g2012 -s tb_rst -Ptb_rst.RELAY=54 -o build/rst_b.vvp $RSRC
iverilog -g2012 -s tb_rst -Ptb_rst.RELAY=0 -Ptb_rst.RMAX=3 -Ptb_rst.N_RST=6000 -o build/rst_c.vvp $RSRC
for half in 12.963 13.468; do
  for g in $GAPS; do (vvp -n build/h${half}_g${g}.vvp > build/h${half}_g${g}.log 2>&1) & done
done
for c in a b c; do (vvp -n build/rst_$c.vvp > build/rst_$c.log 2>&1) & done
wait
ok=1
for half in 12.963 13.468; do
  ref=$(grep 'fetches/us' build/h${half}_g-1.log | awk '{print $3}')
  echo "== motor a $(awk "BEGIN{printf \"%.3f\", 500/$half}") MHz =="
  for g in $GAPS; do
    L=build/h${half}_g${g}.log
    r=$(grep 'fetches/us' $L | awk '{print $3}')
    res=$(grep -o 'RESULTADO: [A-Z]*' $L || echo 'RESULTADO: FAIL')
    pct=$(awk "BEGIN{printf \"%.1f\", 100*$r/$ref}")
    lat=$(grep '^MOTOR :.*latencia' $L | sed 's/.*(\(.*\))/\1/')
    ad=$(grep '^ADPCM' $L | sed 's/^ADPCM : //')
    echo "  pausa ADPCM $g: motor $r fetches/us ($pct %), latencia min/media/max $lat | $res"
    echo "      ADPCM: $ad"
    [ "$res" = "RESULTADO: PASS" ] || ok=0
    if [ "$g" != "-1" ]; then
      lim=95; [ "$g" -ge 160 ] && lim=99
      awk "BEGIN{exit !($pct >= $lim)}" || { echo "      [FAIL] el motor baja de $lim %"; ok=0; }
    fi
  done
done
echo "== /RESET del MSX a mitad de operaciones del ADPCM (tb_rst) =="
for c in a b c; do
  L=build/rst_$c.log
  grep -a '^RESETS' $L | sed 's/^/  /'
  res=$(grep -o 'RESULTADO: [A-Z]*' $L || echo 'RESULTADO: FAIL')
  echo "  $res"
  [ "$res" = "RESULTADO: PASS" ] || ok=0
done
if [ $ok = 1 ]; then echo "RESULTADO: PASS"; else echo "RESULTADO: FAIL"; exit 1; fi
