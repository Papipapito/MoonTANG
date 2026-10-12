#!/usr/bin/env python3
"""check_trace.py - flag, in a moontang_trace.tcl log, every access where
MoonTANG answers differently from openMSX's MoonSound / MSX-Audio.

    python3 check_trace.py trace.log

Each finding says what the software did, what openMSX (and, as far as it is
known, the real YMF278B) answers, what MoonTANG answers, and where it happened
first (log line and PC). The list of differences comes from comparing
fpga/src/opl4fm.v, fpga/src/opl4_pcm.v, fpga/opl4wave/ymf278b_gowin.v and
fpga/opl3/host_if.sv with openMSX 19.1 (MSXMoonSound.cc, YMF278.cc, YMF262.cc).
"""
import re
import sys
from collections import OrderedDict

IO_RE = re.compile(r'^\s*([\d.]+) (OUT|IN ) ([0-9A-F]{2})h (?:<-|->) ([0-9A-F]{2})\s+pc=([0-9A-F]{4})')
MEM_RE = re.compile(r'^\s*([\d.]+) MEM([RW])\s+(\d+) bytes from ([0-9A-F]{6})h\s+pc=([0-9A-F]{4})\s+min\.gap=([\d.]+|-)(?: us)?\s+MA=(\d)')
CPU_RE = re.compile(r'^\s*([\d.]+) ===== CPU: (\w+)')
BIOS_RE = re.compile(r'^\s*([\d.]+) BIOS (\w+)\s+slot=([0-9A-F]{2}) addr=([0-9A-F]{4})')
REP_RE = re.compile(r'^\s*\(x(\d+) in total\)')

SEV_ORDER = {'ALTA': 0, 'MEDIA': 1, 'BAJA': 2, 'INFO': 3}


class Finding:
    def __init__(self, sev, title, detail):
        self.sev, self.title, self.detail = sev, title, detail
        self.count = 0
        self.first = None

    def hit(self, lineno, pc, n=1):
        self.count += n
        if self.first is None:
            self.first = (lineno, pc)


def main(path):
    f = OrderedDict()

    def flag(key, sev, title, detail, lineno, pc, n=1):
        if key not in f:
            f[key] = Finding(sev, title, detail)
        f[key].hit(lineno, pc, n)

    fm_latch = 0
    new = new2 = 0
    new2_sets = 0
    new2_ever = False   # MoonTANG's engine never clears NEW2 once set
    wave_latch = 0
    t1 = 0
    t1_started = False
    status_reads_since_t1 = 0
    last_wave_t = None
    min_wave_gap = None
    blocks = set()
    rdslt = []
    last = None   # (kind, lineno, pc) of the previous event, for "(xN)" lines

    def status_read(n, lineno, pc):
        nonlocal status_reads_since_t1
        if not (t1_started and t1 == 0xFF):
            return
        before = status_reads_since_t1
        status_reads_since_t1 += n
        if before < 50 <= status_reads_since_t1:
            flag('trick', 'MEDIA',
                 '50 lecturas de estado con el Timer 1 = FFh en marcha',
                 'El nucleo OPL3 de MoonTANG (trick_sw_detection.sv, heredado del PC) '
                 'FUERZA el desbordamiento del Timer 1 a la lectura 50 y lo mantiene '
                 'hasta la siguiente escritura de otro registro. openMSX no hace nada '
                 'parecido.', lineno, pc)

    def nonew2(lineno, pc):
        if new2_ever:
            flag('wr_new2off', 'MEDIA', 'Escribe en 7Eh/7Fh tras volver a poner NEW2=0',
                 'openMSX y el chip real la ignoran. MoonTANG no borra nunca NEW2 '
                 '(solo con reset) y la ejecuta.', lineno, pc)
            return 'wr_new2off'
        flag('wr_nonew2', 'INFO', 'Escribe en 7Eh/7Fh con NEW2=0',
             'Ignorado tanto en openMSX como en MoonTANG.', lineno, pc)
        return 'wr_nonew2'

    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.readlines()

    for lineno, line in enumerate(lines, 1):
        m = REP_RE.match(line)
        if m and last is not None:
            extra = int(m.group(1)) - 1
            kind, ln, pc = last
            for key in kind:
                if key in f:
                    f[key].count += extra
            if 'status' in kind:
                status_read(extra, lineno, pc)
            continue

        m = IO_RE.match(line)
        if m:
            t = float(m.group(1))
            out = m.group(2) == 'OUT'
            port = int(m.group(3), 16)
            val = int(m.group(4), 16)
            pc = m.group(5)
            keys = []

            if port in (0x7E, 0x7F):
                if last_wave_t is not None:
                    gap = (t - last_wave_t) * 1e6
                    if min_wave_gap is None or gap < min_wave_gap:
                        min_wave_gap = gap
                last_wave_t = t

            if port in (0xC4, 0xC6) and out:
                fm_latch = val | (0x100 if port == 0xC6 else 0)
            elif port in (0xC5, 0xC7) and out:
                if fm_latch == 0x105:
                    if val & 2:
                        new2_sets += 1
                        new2_ever = True
                    new, new2 = val & 1, (val >> 1) & 1
                elif fm_latch >= 0x100 and not new:
                    keys.append('opl2alias')
                    flag('opl2alias', 'BAJA',
                         'Escritura al banco 1 del FM (C6h/C7h) con NEW=0',
                         'openMSX y el YMF262 la redirigen al banco 0 (modo OPL2). '
                         'MoonTANG la escribe en el banco 1.', lineno, pc)
                if not (fm_latch == 0x004 and (val & 1)):
                    status_reads_since_t1 = 0
                if fm_latch == 0x002:
                    t1 = val
                if fm_latch == 0x004 and not (val & 0x80):
                    t1_started = bool(val & 1)
                    status_reads_since_t1 = 0
                    if val & 3:
                        keys.append('timers')
                        flag('timers', 'INFO', 'Usa los timers del OPL4 (registro 04h)',
                             'MoonTANG los tiene y lleva su IRQ a /INT. Si el programa '
                             'cuelga de la interrupcion, mirar mt3int.', lineno, pc)
            elif port in (0xC4, 0xC6) and not out:
                keys.append('status')
                status_read(1, lineno, pc)
                if port == 0xC6:
                    keys.append('c6')
                    flag('c6', 'ALTA', 'Lee el estado por C6h',
                         'openMSX: estado del chip (como en C4h). MoonTANG: siempre FFh '
                         '(host_if.sv: solo la direccion 0 da el estado). Un bucle que '
                         'espere BUSY=0 o LD=0 en C6h se cuelga; una deteccion que '
                         'compare con FFh dice "no hay MoonSound".', lineno, pc)
            elif port == 0x7E and out:
                if new2:
                    wave_latch = val
                else:
                    keys.append(nonew2(lineno, pc))
            elif port == 0x7E and not out:
                keys.append('rd7e')
                flag('rd7e', 'MEDIA', 'Lee el puerto 7Eh',
                     'openMSX: FFh. MoonTANG: el estado {LD,BUSY} (00h en reposo). Si '
                     'el programa espera FFh, o usa 7Eh como sonda, se comporta distinto.',
                     lineno, pc)
            elif port == 0x7F and out:
                if not new2:
                    keys.append(nonew2(lineno, pc))
                elif wave_latch == 0x02 and (val & 2):
                    keys.append('mt')
                    flag('mt', 'MEDIA', 'Registro 02h con el bit MT (memory type) a 1',
                         'openMSX remapea la RAM de muestras (solo 380000h-3FFFFFh visible). '
                         'MoonTANG ignora MT: RAM plana en 200000h-3FFFFFh.', lineno, pc)
            elif port == 0x7F and not out:
                if not new2:
                    keys.append('rd_nonew2')
                    flag('rd_nonew2', 'MEDIA', 'Lee 7Fh con NEW2=0',
                         'openMSX (y el chip real, verificado por openMSX): lee el registro '
                         'normalmente. MoonTANG: el motor ignora la lectura y devuelve el '
                         'ultimo dato leido.', lineno, pc)
                else:
                    keys.append('rd7f')
                    flag('rd7f', 'INFO', 'Lee registros wave por 7Fh',
                         'En MoonTANG cada lectura va y vuelve al motor PCM (~0,5 us) '
                         'sostenida por /WAIT. A 3,58 MHz llega; en modo turbo / R800 '
                         'puede devolver el dato de la lectura ANTERIOR.', lineno, pc)
                    if wave_latch in (3, 4, 5):
                        keys.append('rd345')
                        flag('rd345', 'BAJA', 'Lee los registros de direccion 03h-05h',
                             'openMSX: devuelve lo escrito. MoonTANG: la direccion VIVA '
                             '(ya incrementada por los accesos a 06h).', lineno, pc)
            elif port in (0xC0, 0xC1):
                keys.append('audio')
                flag('audio', 'INFO', 'Accede al MSX-Audio (C0h-C1h)',
                     'Solo existe en los bitstreams *_msxaudio_*. Sin BIOS de MSX-Audio.',
                     lineno, pc)
            elif port in (0xC2, 0xC3):
                keys.append('audio2')
                flag('audio2', 'ALTA', 'Accede a un segundo MSX-Audio (C2h-C3h)',
                     'MoonTANG no decodifica C2h-C3h.', lineno, pc)
            elif port in (0x7C, 0x7D):
                keys.append('opll')
                flag('opll', 'INFO', 'Usa MSX-Music (7Ch-7Dh)',
                     'MoonTANG no tiene MSX-Music: hace falta un FM-PAC o un MSX con '
                     'MSX-Music integrado.', lineno, pc)
            elif port == 0x0A:
                keys.append('dac')
                flag('dac', 'ALTA', 'Usa el DAC del Music Module (0Ah)',
                     'MoonTANG no lo tiene.', lineno, pc)
            last = (keys, lineno, pc)
            continue

        m = MEM_RE.match(line)
        if m:
            n = int(m.group(3))
            start = int(m.group(4), 16)
            pc = m.group(5)
            for a in (start, (start + n - 1) & 0x3FFFFF):
                if a >= 0x200000:
                    blocks.add((a - 0x200000) >> 17)
            if start + n - 1 >= 0x2A0000 or start >= 0x2A0000:
                flag('big', 'MEDIA', 'Toca RAM de muestras por encima de 640 kB',
                     'MoonTANG tiene 2 MB planos en 200000h-3FFFFFh. openMSX trae 640 kB '
                     'por defecto (y lee FFh fuera). Una deteccion de tamano que no '
                     'espere 2 MB puede fallar: probar con la extension MoonTANG.xml.',
                     lineno, pc)
            if m.group(6) != '-' and float(m.group(6)) < 0.6:
                flag('fastmem', 'ALTA', 'Rafaga de memoria de muestras a menos de 0,6 us por byte',
                     'MoonTANG atiende una peticion wave cada ~0,5 us: con tres accesos '
                     'seguidos en ese tiempo pierde escrituras, y las lecturas pueden '
                     'devolver el byte anterior.', lineno, pc)
            if m.group(7) == '0':
                flag('ma0', 'BAJA', 'Accede al registro 06h (datos de memoria) con MA=0',
                     'openMSX: lectura = FFh, escritura ignorada, la direccion no avanza. '
                     'MoonTANG: lee el ultimo dato precargado, avanza la direccion, y una '
                     'escritura queda pendiente hasta que MA vuelva a 1.', lineno, pc, n)
            if start < 0x200000 and m.group(2) == 'W':
                flag('romw', 'INFO', 'Escribe en la zona de ROM (<200000h)',
                     'Ignorado en openMSX y en MoonTANG.', lineno, pc)
            last = ([], lineno, pc)
            continue

        m = CPU_RE.match(line)
        if m:
            if m.group(2) == 'r800':
                flag('r800', 'ALTA', 'El programa usa el MoonSound con el R800 activo',
                     'En MoonTANG el /WAIT de IN 7Fh tiene ~70 ns de margen a 3,58 MHz y '
                     'puede llegar tarde con el R800: las lecturas de 7Fh (ID, RAM de '
                     'muestras) pueden devolver el dato de la lectura anterior. Probar '
                     'el disco en modo Z80 (arrancar con la tecla "1" pulsada).',
                     lineno, '-')
            last = ([], lineno, '-')
            continue

        m = BIOS_RE.match(line)
        if m:
            if m.group(2) == 'RDSLT':
                rdslt.append((lineno, m.group(3), m.group(4)))
            last = ([], lineno, '-')
            continue

    if new2_sets > 1:
        f['new2'] = Finding('BAJA', 'Escribe NEW2=1 %d veces' % new2_sets,
                            'MoonTANG pone LD=1 en el estado tras CADA activacion, hasta la '
                            'siguiente lectura de estado. openMSX y el chip real: solo la '
                            'primera vez tras el reset.')
        f['new2'].count = new2_sets

    print('Trazado: %s' % path)
    if min_wave_gap is not None:
        print('Hueco minimo entre accesos a 7Eh/7Fh: %.2f us %s' % (
            min_wave_gap, '(<0,6 us: MoonTANG puede perder escrituras)'
            if min_wave_gap < 0.6 else '(MoonTANG lo aguanta)'))
    if blocks:
        print('Bloques de 128 kB de RAM de muestras tocados: %s' %
              ', '.join('%06Xh' % (0x200000 + (b << 17)) for b in sorted(blocks)))
    if rdslt:
        addrs = sorted(set(a for _, _, a in rdslt))
        print('RDSLT: %d llamadas, direcciones: %s%s' % (
            len(rdslt), ' '.join(addrs[:24]), ' ...' if len(addrs) > 24 else ''))
        sig = [a for a in addrs if 0x401C <= int(a, 16) <= 0x4023]
        if sig:
            print('  -> lee 401Ch-4023h: busca la ROM de MSX-Music ("APRLOPLL")')
    print()
    if not f:
        print('Nada que MoonTANG haga distinto en este trazado.')
        return
    for k, x in sorted(f.items(), key=lambda kv: SEV_ORDER[kv[1].sev]):
        where = ''
        if x.first:
            where = ' (1a vez: linea %d, pc=%s)' % x.first
        print('[%s] %s - %d veces%s' % (x.sev, x.title, x.count, where))
        print('       %s' % x.detail)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
