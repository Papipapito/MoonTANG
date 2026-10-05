#!/usr/bin/env python3
"""Arregla en el Verilog de sv2v el puerto inout del modulo de bus.

sv2v "inlinea" los modulos con puertos de interfaz y conecta sus puertos con
assign de UN solo sentido: el inout CART_DATA_SIG queda como salida y el modulo
de bus deja de ver lo que escribe el MSX (en simulacion; la sintesis de Gowin
usa el SystemVerilog original y no pasa por aqui). Se sustituye ese assign por
un `tran` por bit, que si es bidireccional.

Uso: fix_inout.py <fichero.v>
"""
import sys

p = sys.argv[1]
t = open(p, encoding='utf-8').read()
old = 'assign CART_DATA_SIG = u_bus.CART_DATA_SIG;'
assert t.count(old) == 1, f'patron no encontrado exactamente una vez ({t.count(old)}): revisar la salida de sv2v'
new = ' '.join(f'tran t_bus_d{i} (CART_DATA_SIG[{i}], u_bus.CART_DATA_SIG[{i}]);' for i in range(8))
open(p, 'w', encoding='utf-8', newline=chr(10)).write(t.replace(old, new))
print('inout CART_DATA_SIG: assign de un sentido -> 8 tran')
