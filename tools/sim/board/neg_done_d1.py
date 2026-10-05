#!/usr/bin/env python3
"""Control negativo del arreglo de done_d1 (opl4_pcm.v, 05/10/2026): a partir del
Verilog convertido, devuelve done_d1 a como estaba antes (reseteado con el motor y
sin exigir port_busy). Con eso, la fase J2 del banco TIENE que fallar.

Uso: neg_done_d1.py <entrada.v> <salida.v>
"""
import sys

src, dst = sys.argv[1:3]
t = open(src, encoding='utf-8').read()


def rep(a, b):
    global t
    assert t.count(a) == 1, f'no encuentro exactamente una vez: {a!r}'
    t = t.replace(a, b)


rep("\treg done_d1 = 1'b0;\n\talways @(posedge clk_eng) done_d1 <= mem_done_t;\n", "\treg done_d1;\n")
rep("if ((mem_done_t != done_d1) && port_busy) begin", "if (mem_done_t != done_d1) begin")
i = t.index("if (mem_done_t != done_d1) begin")
k = t.rfind("mrd_d1 <= 1'b0;", 0, i)
assert k > 0
t = t[:k] + "done_d1 <= 1'b0;\n\t\t\t" + t[k:]
i = t.index("if (mem_done_t != done_d1) begin")
k = t.rfind("mrd_d1 <= ~e_mrd_n;", 0, i)
assert k > 0
t = t[:k] + "done_d1 <= mem_done_t;\n\t\t\t" + t[k:]
open(dst, 'w', encoding='utf-8', newline='\n').write(t)
print(f'{dst}: done_d1 como antes del arreglo')
