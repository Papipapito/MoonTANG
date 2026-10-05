#!/usr/bin/env python3
"""Genera `wt_official_pins.vh` a partir del top.cst del firmware OFICIAL de la
WonderTANG (lfantoniosi/WonderTANG, fpga/src/top.cst): los numeros de pin del
modelo de placa salen del artefacto real, no de una transcripcion a mano.

Uso: gen_board_pins.py <top.cst oficial> <salida.vh>
"""
import re
import sys

cst, out = sys.argv[1:3]
want = ['msel_n', 'mp', 'cd', 'datadir', 'busdir_n', 'int_n', 'wait_n', 'sltsl_n',
        'rd_n', 'wr_n', 'clock', 'clk', 'hp_din', 'hp_bck', 'hp_ws', 'pa_en', 'led',
        'mspi_cs', 'mspi_sclk', 'mspi_miso', 'mspi_mosi']
loc = {}
for m in re.finditer(r'^\s*IO_LOC\s+"(\w+)(?:\[(\d+)\])?"\s+(\d+)', open(cst, encoding='utf-8').read(), re.M):
    loc[(m.group(1), m.group(2))] = int(m.group(3))
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('// GENERADO por gen_board_pins.py desde el top.cst oficial de la WonderTANG 2.0x\n')
    f.write('// (lfantoniosi/WonderTANG, fpga/src/top.cst). No editar.\n')
    for (name, idx), pin in sorted(loc.items(), key=lambda kv: (kv[0][0], int(kv[0][1] or 0))):
        if name in want:
            f.write(f'localparam P_{name.upper()}{idx or ""} = {pin};\n')
print(out, 'generado')
