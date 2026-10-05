#!/usr/bin/env python3
"""Genera un envoltorio del top visto por NUMERO DE PIN del encapsulado QN88,
exactamente segun un fichero .cst (igual que tools/sim/board/gen_pins.py, pero
generico: admite pares diferenciales `IO_LOC "x_p" 33,34;` y cualquier top).

Los parametros del top no se repiten en el envoltorio: el banco los cambia con
`defparam <instancia>.u_top.<PARAMETRO> = ...`.

Uso: gen_pin_wrapper.py <top.sv> <modulo top> <fichero.cst> <salida.v> <modulo envoltorio>
"""
import re
import sys

top_sv, top_mod, cst, out, wrap = sys.argv[1:6]
NL = chr(10)

src = open(top_sv, encoding='utf-8').read()
i = src.index('module ' + top_mod)
hdr = src[i:]
# la lista de puertos es el ultimo parentesis antes del primer ');'
hdr = hdr[:hdr.index(');')]
hdr = hdr[hdr.rindex(') (') + 2:] if ') (' in hdr else hdr
ports = []          # (dir, nombre, ancho)
for m in re.finditer(r'^\s*(input|output|inout)\s+wire\s*(\[(\d+):0\])?\s*(\w+)', hdr, re.M):
    ports.append((m.group(1), m.group(4), int(m.group(3)) + 1 if m.group(3) else 1))
assert ports, 'no se han encontrado puertos en el top'

loc = {}            # (nombre, indice|None) -> pin
for m in re.finditer(r'^\s*IO_LOC\s+"(\w+)(?:\[(\d+)\])?"\s+(\d+)(?:\s*,\s*(\d+))?\s*;',
                     open(cst, encoding='utf-8').read(), re.M):
    name, idx = m.group(1), int(m.group(2)) if m.group(2) is not None else None
    assert (name, idx) not in loc, f'señal duplicada en el .cst: {name}[{idx}]'
    loc[(name, idx)] = int(m.group(3))
    if m.group(4):          # par diferencial: el negativo es el puerto hermano *_n
        assert name.endswith('_p'), f'par diferencial sin sufijo _p: {name}'
        loc[(name[:-2] + '_n', idx)] = int(m.group(4))
pins = list(loc.values())
assert len(pins) == len(set(pins)), 'dos señales comparten pin en el .cst'

lines, sdram, used, trans = [], [], set(), []
for d, name, w in ports:
    if 'sdram' in name:
        sdram.append((d, name, w))
        lines.append(f'        .{name}({name})')
        continue
    if w == 1:
        assert (name, None) in loc, f'el puerto {name} no tiene IO_LOC en {cst}'
        used.add((name, None))
        lines.append(f'        .{name}(pin[{loc[(name, None)]}])')
        continue
    for k in range(w):
        assert (name, k) in loc, f'el puerto {name}[{k}] no tiene IO_LOC en {cst}'
        used.add((name, k))
    if d == 'inout':
        # Icarus no propaga en los dos sentidos una concatenacion colgada de un
        # puerto inout: bus intermedio y un `tran` por bit.
        trans.append((name, w, [loc[(name, k)] for k in range(w)]))
        lines.append(f'        .{name}(w_{name})')
    else:
        bits = [f'pin[{loc[(name, k)]}]' for k in range(w - 1, -1, -1)]
        lines.append(f'        .{name}({{{", ".join(bits)}}})')
sobran = set(loc) - used
assert not sobran, f'IO_LOC sin puerto en el top: {sorted(sobran, key=str)}'

o = [f'// GENERADO por gen_pin_wrapper.py a partir de {cst} — no editar.',
     '`timescale 1ns/1ps',
     f'module {wrap} (']
plist = ['    inout wire [88:1] pin']
for d, name, w in sdram:
    rng = f'[{w-1}:0] ' if w > 1 else ''
    plist.append(f'    {d} wire {rng}{name}')
o.append((',' + NL).join(plist))
o.append(');')
for name, w, pins_ in trans:
    o.append(f'    wire [{w-1}:0] w_{name};')
    for k, pn in enumerate(pins_):
        o.append(f'    tran t_{name}_{k} (w_{name}[{k}], pin[{pn}]);')
o.append(f'    {top_mod} u_top (')
o.append((',' + NL).join(lines))
o.append('    );')
o.append('endmodule')
with open(out, 'w', encoding='utf-8', newline=NL) as f:
    f.write(NL.join(o) + NL)
print(f'{out}: {len(used)} señales con pin, {len(sdram)} puertos de SDRAM')
