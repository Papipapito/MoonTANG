#!/usr/bin/env python3
# ============================================================================
# vu_check.py - comprueba los cuadros de tb_vu_screen contra un modelo
# independiente de la pantalla y los convierte a PNG.              (MoonTANG)
#
#   python3 vu_check.py <dir_build> <dir_out> <font8x8.v> <BUILD> [lista]
#
# Lee <dir_build>/<lista> (por defecto frames.txt; una linea por cuadro
# volcado: fichero, 6 niveles, 6 picos, st_rom, st_msx, sample_level), pinta con este modelo
# lo que DEBERIA verse y lo
# compara pixel a pixel con el PPM de la simulacion. Tambien comprueba que nada
# que no sea fondo se sale del margen de seguridad (x 36..684, y 24..456).
#
# El modelo no sale del Verilog: pinta rectangulos y glifos a partir de la
# descripcion de la pantalla, sin adelantos ni contadores. Si las capas de
# vu_screen.v se desalinearan un solo pixel, aqui se veria.
# ============================================================================
import os
import re
import struct
import sys
import zlib

W, H = 720, 480

# Colores de diseño (0..255). vu_screen.v los saca en rango limitado (16..235,
# lo que espera una tele con un formato CE), asi que el modelo los compara ya
# escalados; los PNG se vuelven a expandir a 0..255 para verlos como en la tele.
def lim(c):
    return tuple(16 + (v * 219 + 127) // 255 for v in c)


def tv(c):
    return tuple(min(255, max(0, ((v - 16) * 255 + 109) // 219)) for v in c)


BG    = lim((0x06, 0x08, 0x0E))
SEP   = lim((0x2A, 0x35, 0x50))
OFF   = [lim(c) for c in ((0x0A, 0x24, 0x10), (0x2A, 0x26, 0x08), (0x2A, 0x0C, 0x08))]
ON    = [lim(c) for c in ((0x20, 0xE0, 0x40), (0xF0, 0xD0, 0x20), (0xF0, 0x30, 0x20))]
PK    = [lim(c) for c in ((0xB0, 0xFF, 0xC0), (0xFF, 0xF8, 0xA0), (0xFF, 0xA0, 0x90))]
TITLE = lim((0xE8, 0xF0, 0xFF))
CYAN  = lim((0x5C, 0xC8, 0xE8))
LABEL = lim((0xB8, 0xC4, 0xD8))
SCALE = lim((0x88, 0x94, 0xA8))
GREEN = ON[0]
YELL  = ON[1]
RED   = ON[2]
GREY  = lim((0x68, 0x74, 0x88))

BAR_Y = [112, 144, 200, 232, 288, 320]      # FM L, FM R, WAVE L, WAVE R, OUT L, OUT R
BAR_X = 168
PITCH = 18
SEG_W = 16
BAR_H = 24
NSEG  = 28


def load_font(path):
    rom = [0] * 512
    txt = open(path, encoding="ascii", errors="replace").read()
    for m in re.finditer(r"rom\[\s*(\d+)\]\s*=\s*8'b([01]{8});", txt):
        rom[int(m.group(1))] = int(m.group(2), 2)
    return rom


class Img:
    def __init__(self):
        self.p = [BG] * (W * H)

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            base = yy * W
            for xx in range(x, x + w):
                self.p[base + xx] = c

    def text(self, font, x, y, s, scale, c):
        """Celda en (x, y); cada glifo ocupa 8*scale x 8*scale."""
        for i, ch in enumerate(s):
            code = ord(ch) - 0x20
            assert 0 <= code < 64, "caracter fuera de la fuente: %r" % ch
            for r in range(8):
                bits = font[code * 8 + r]
                for col in range(8):
                    if bits >> (7 - col) & 1:
                        self.rect(x + (i * 8 + col) * scale, y + r * scale, scale, scale, c)


def zone(s):
    return 0 if s <= 20 else 1 if s <= 25 else 2


def model(font, lv, pk, st_rom, st_msx, sample_level, build):
    im = Img()
    # titulo: la tinta empieza en x = 48 (la columna 0 de la fuente va vacia)
    im.text(font, 48 - 4, 40, "MOONTANG", 4, TITLE)
    im.text(font, 328, 54, "MOONSOUND OPL4", 2, CYAN)       # misma linea base
    im.rect(48, 88, 672 - 48, 2, SEP)
    # barras
    for b in range(6):
        for s in range(1, NSEG + 1):
            if pk[b] != 0 and s == pk[b]:
                c = PK[zone(s)]
            elif s <= lv[b]:
                c = ON[zone(s)]
            else:
                c = OFF[zone(s)]
            im.rect(BAR_X + (s - 1) * PITCH, BAR_Y[b], SEG_W, BAR_H, c)
        im.text(font, 136, BAR_Y[b] + 5, "LR"[b & 1], 2, LABEL)
    for g, name in enumerate(("FM", "WAVE", "OUT")):
        im.text(font, 48 - 2, BAR_Y[2 * g] + 5, name, 2, LABEL)
    # regla en dB (1,5 dB por segmento, el 28 es 0 dB)
    for s, name in ((4, "-36"), (12, "-24"), (20, "-12")):
        centro = BAR_X + (s - 1) * PITCH + SEG_W // 2
        im.text(font, centro - 12, 352, name, 1, SCALE)
    fin = BAR_X + NSEG * PITCH - 2                           # 670: fin del segmento 28
    im.text(font, fin - 31, 352, "0 DB", 1, SCALE)           # la tinta acaba en 669
    # estado
    im.text(font, 48 - 2, 392, "YRW801", 2, LABEL)
    txt, col = {0: ("...", YELL), 1: ("OK", GREEN), 3: ("NO VALIDA", RED)}.get(st_rom, ("ERROR", RED))
    im.text(font, 48 - 2 + 7 * 16, 392, txt, 2, col)
    im.text(font, 400, 392, "MSX", 2, LABEL)
    im.text(font, 400 + 4 * 16, 392, "OK" if st_msx else "--", 2, GREEN if st_msx else GREY)
    # Marca de agua de los 2 MiB de sample RAM.
    im.text(font, 48 - 1, 416, "SAMPLE RAM", 1, LABEL)
    for s in range(1, NSEG + 1):
        im.rect(BAR_X + (s - 1) * PITCH, 416, SEG_W, 8,
                ON[zone(s)] if s <= sample_level else OFF[zone(s)])
    # pie
    im.text(font, 48 - 1, 440, "MOONTANG " + build, 1, GREY)
    return im.p


def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
    assert m and int(m.group(1)) == W and int(m.group(2)) == H and int(m.group(3)) == 255, path
    raw = d[m.end():]
    assert len(raw) == W * H * 3, "%s: %d bytes de imagen" % (path, len(raw))
    return [(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]


def write_png(path, pix, w=W, h=H):
    """PNG RGB de 8 bits sin dependencias (zlib)."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pix[y * w + x])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def write_16x9(path, src_png):
    """Vista previa estirada a 16:9 (854x480), como la pinta la tele. Solo con PIL."""
    try:
        from PIL import Image
    except ImportError:
        return False
    Image.open(src_png).resize((854, 480), Image.BILINEAR).save(path)
    return True


def main():
    build_dir, out_dir, font_path, build = sys.argv[1:5]
    # como el parametro de Verilog: 10 caracteres, los que falten son espacios
    # por la izquierda y las minusculas salen en mayusculas
    build = build.upper().rjust(10)[-10:]
    lista = sys.argv[5] if len(sys.argv) > 5 else "frames.txt"
    font = load_font(font_path)
    os.makedirs(out_dir, exist_ok=True)
    ok = True
    n = 0
    for line in open(os.path.join(build_dir, lista)):
        f = line.split()
        if not f:
            continue
        name = f[0]
        v = [int(t) for t in f[1:]]
        lv, pk, st_rom, st_msx, sample_level = v[0:6], v[6:12], v[12], v[13], v[14]
        sim = read_ppm(os.path.join(build_dir, name))
        ref = model(font, lv, pk, st_rom, st_msx, sample_level, build)
        # --- comparacion con el modelo ---
        dif = [i for i in range(W * H) if sim[i] != ref[i]]
        # --- margen de seguridad ---
        tinta = [i for i in range(W * H) if sim[i] != BG]
        fuera = [i for i in tinta if not (36 <= i % W <= 684 and 24 <= i // W <= 456)]
        caja = (min(i % W for i in tinta), min(i // W for i in tinta),
                max(i % W for i in tinta), max(i // W for i in tinta))
        base = os.path.splitext(name)[0]
        png = os.path.join(out_dir, base + ".png")
        write_png(png, [tv(c) for c in sim])
        write_16x9(os.path.join(out_dir, base + "_16x9.png"), png)
        print("%s  level=%s peak=%s st_rom=%d st_msx=%d sample=%d" %
              (name, lv, pk, st_rom, st_msx, sample_level))
        print("    distintos del modelo: %d    fuera de margen: %d    caja pintada: x %d..%d, y %d..%d"
              % (len(dif), len(fuera), caja[0], caja[2], caja[1], caja[3]))
        if dif:
            ok = False
            xs = [i % W for i in dif]
            ys = [i // W for i in dif]
            print("    zona distinta: x %d..%d, y %d..%d; primeros:" % (min(xs), max(xs), min(ys), max(ys)))
            for i in dif[:8]:
                print("      (%d,%d) sim=%02x%02x%02x modelo=%02x%02x%02x" % ((i % W, i // W) + sim[i] + ref[i]))
            write_png(os.path.join(out_dir, base + "_modelo.png"), [tv(c) for c in ref])
            write_png(os.path.join(out_dir, base + "_dif.png"),
                      [(255, 0, 255) if sim[i] != ref[i] else tuple(c // 3 for c in sim[i])
                       for i in range(W * H)])
        if fuera:
            ok = False
        n += 1
    print("MODELO: %d cuadros comparados pixel a pixel -> %s" % (n, "PASS" if ok and n else "FAIL"))
    return 0 if ok and n else 1


if __name__ == "__main__":
    sys.exit(main())
