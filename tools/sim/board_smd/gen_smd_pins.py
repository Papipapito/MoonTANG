#!/usr/bin/env python3
"""Genera `smd_pcb_pins.vh` a partir de la PCB REAL del cartucho MSXhdmi_tn20k_smd
(fichero .kicad_pcb de KiCad): que señal del conector del MSX llega a que PIN DE
LA FPGA, siguiendo el cobre a traves de los 74LVC245.

No se copia nada de un .cst: el modelo de placa del banco de pruebas sale del
artefacto de fabricacion. Recorrido:
    dedo de CON1 (red "A7")  ->  245, pin del lado A  ->  su pareja del lado B
    (red "A7_33")  ->  pad del zocalo de la Tang (U6)  ->  numero de pin de FPGA
    (el nombre de funcion del pad lo lleva: "73_IOT40A_..." o "..._IOR49B_48").
Ademas comprueba como estan cableados DIR y /OE de cada 245 y se niega a generar
si no es lo que el modelo supone.

Uso: gen_smd_pins.py <placa.kicad_pcb> <salida.vh>
"""
import re
import sys

pcb, out = sys.argv[1:3]
txt = open(pcb, encoding='utf-8').read()
NL = chr(10)


def footprints(text):
    """Trocea el fichero en bloques (footprint ...) de primer nivel."""
    res, i = [], 0
    while True:
        i = text.find('(footprint ', i)
        if i < 0:
            return res
        depth, j = 0, i
        while True:
            c = text[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        res.append(text[i:j + 1])
        i = j + 1


def pads(block):
    """{numero de pad: (red, funcion)} de un footprint."""
    res = {}
    for m in re.finditer(r'\(pad "([^"]+)"', block):
        depth, j = 0, m.start()
        while True:
            c = block[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = block[m.start():j + 1]
        net = re.search(r'\(net "([^"]*)"\)', body)
        fn = re.search(r'\(pinfunction "([^"]*)"\)', body)
        res[m.group(1)] = (net.group(1) if net else '', fn.group(1) if fn else '')
    return res


fps = {}
for blk in footprints(txt):
    ref = re.search(r'\(property "Reference" "([^"]+)"', blk)
    if ref:
        fps[ref.group(1)] = pads(blk)

for need in ('CON1', 'U1', 'U2', 'U3', 'U4', 'U6', 'J2'):
    assert need in fps, f'no encuentro {need} en la PCB'

# ---- red del lado FPGA -> pin de FPGA (zocalo U6) ----
net2pin = {}
for pad, (net, fn) in fps['U6'].items():
    # el simbolo de la Tang pone el numero de pin al principio en los pads 1-20
    # ("73_IOT40A_...") y al final en los 21-40 ("LCD_DE_IOR49B_48")
    m = re.match(r'(\d+)_', fn) or re.search(r'_(\d+)$', fn)
    if m and net and not net.startswith('unconnected'):
        assert net not in net2pin or net in ('GND', '+3V3', '+3.3V', '+5V'), f'red {net} en dos pads de U6'
        net2pin[net] = int(m.group(1))

# ---- 245: parejas A/B (pin 2<->18 ... 9<->11), DIR = pin 1, /OE = pin 19 ----
PAIRS = [(str(a), str(20 - a)) for a in range(2, 10)]
slot2fpga = {}          # red del slot -> (red FPGA, pin FPGA, 245)
ctl = {}
for u in ('U1', 'U2', 'U3', 'U4'):
    p = fps[u]
    ctl[u] = (p['1'][0], p['19'][0])
    for a, b in PAIRS:
        na, nb = p[a][0], p[b][0]
        if nb in net2pin and na and not na.startswith('unconnected') and na != 'GND':
            slot2fpga[na] = (nb, net2pin[nb], u)

V33 = [n for n in ('+3V3', '+3.3V') if any(n == c[0] for c in ctl.values())]
assert V33, f'ningun 245 tiene DIR a 3V3: {ctl}'
for u in ('U1', 'U2', 'U4'):
    assert ctl[u][0] in V33 and ctl[u][1] == 'GND', f'{u}: DIR/OE inesperados {ctl[u]}'
assert ctl['U3'][1] == 'GND', f'U3: /OE no esta a masa: {ctl["U3"]}'
dir_net = ctl['U3'][0]
assert dir_net in net2pin, f'la red de DIR de U3 ({dir_net}) no llega a la FPGA'

# ---- que dedos del conector llevan esas redes ----
con = {}
for pad, (net, fn) in fps['CON1'].items():
    con.setdefault(net, []).append(pad)

want = ['A%d' % i for i in range(16)] + ['D%d' % i for i in range(8)]
names = {}
for n in want:
    assert n in slot2fpga, f'la señal {n} del slot no llega a la FPGA'
    names[n] = n
# control: los nombres de red del slot varian (MERQ/MREQ...), se buscan por la red FPGA
for fpga_net, tag in (('MERQ_33', 'MREQ_N'), ('IORQ_33', 'IORQ_N'), ('RD_33', 'RD_N'), ('WR_33', 'WR_N'),
                      ('RESET_33', 'RESET_N'), ('CLOCK_33', 'CLOCK'), ('SLTSL_33', 'SLTSL_N')):
    hit = [s for s, v in slot2fpga.items() if v[0] == fpga_net]
    assert len(hit) == 1, f'no encuentro la señal del slot de {fpga_net}: {hit}'
    names[tag] = hit[0]

# ---- señales del slot que NO deben llegar a la FPGA en esta placa ----
missing = []
for pad, (net, fn) in sorted(fps['CON1'].items(), key=lambda kv: int(kv[0])):
    if re.search(r'WAIT|INT|M1|BUSDIR|SOUND', fn.upper()) or re.search(r'^(WAIT|INT|M1|BUSDIR)$', net.upper()):
        reach = net in slot2fpga or net in net2pin
        missing.append((pad, fn, net, reach))

o = []
o.append('// GENERADO por gen_smd_pins.py desde la PCB real (KiCad) del cartucho')
o.append('// MSXhdmi_tn20k_smd. No editar. Señal del slot -> 74LVC245 -> pin de FPGA.')
for n in want:
    v = slot2fpga[n]
    o.append(f'localparam P_{n} = {v[1]};   // CON1.{"/".join(con.get(n, ["?"]))} {n} -> {v[2]} -> {v[0]}')
for tag in ('MREQ_N', 'IORQ_N', 'RD_N', 'WR_N', 'RESET_N', 'CLOCK', 'SLTSL_N'):
    s = names[tag]
    v = slot2fpga[s]
    o.append(f'localparam P_{tag} = {v[1]};   // CON1.{"/".join(con.get(s, ["?"]))} {s} -> {v[2]} -> {v[0]}')
o.append(f'localparam P_DATADIR = {net2pin[dir_net]};   // DIR de U3 ({dir_net}); /OE de U3 a masa')
j2 = {pad: net for pad, (net, fn) in fps['J2'].items() if net in net2pin and net not in ('GND', '+3V3', '+3.3V', '+5V')}
for pad, net in sorted(j2.items()):
    o.append(f'localparam P_J2_{pad} = {net2pin[net]};   // zocalo ESP-01S, pad {pad} ({net})')
for pad, fn, net, reach in missing:
    o.append(f'// CON1.{pad} {fn}: {"LLEGA a la FPGA" if reach else "no llega a la FPGA"} (red "{net}")')
    assert not reach, f'CON1.{pad} {fn} llega a la FPGA: el modelo de placa no lo contempla'
open(out, 'w', encoding='utf-8', newline=NL).write(NL.join(o) + NL)
print(f'{out}: {len(want) + 7} señales del slot, DIR de U3 en el pin {net2pin[dir_net]}, zocalo J2 en {sorted(net2pin[n] for n in j2.values())}')
