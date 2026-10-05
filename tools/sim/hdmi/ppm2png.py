#!/usr/bin/env python3
"""Convierte el PPM de texto (P3) que escribe hdmi_rx_check.escribir_ppm en un PNG.

Uso: python3 ppm2png.py cuadro.ppm cuadro.png
Sin dependencias (solo zlib y struct de la biblioteca estandar).
"""
import struct
import sys
import zlib


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "r") as f:
        campos = f.read().split()
    if not campos or campos[0] != "P3":
        sys.exit("no es un PPM de texto (P3)")
    ancho, alto, maximo = int(campos[1]), int(campos[2]), int(campos[3])
    datos = bytes(int(v) * 255 // maximo for v in campos[4:4 + ancho * alto * 3])
    if len(datos) != ancho * alto * 3:
        sys.exit("faltan pixeles: %d de %d" % (len(datos) // 3, ancho * alto))
    filas = b"".join(b"\x00" + datos[y * ancho * 3:(y + 1) * ancho * 3] for y in range(alto))

    def trozo(tipo, cuerpo):
        return (struct.pack(">I", len(cuerpo)) + tipo + cuerpo
                + struct.pack(">I", zlib.crc32(tipo + cuerpo) & 0xFFFFFFFF))

    with open(sys.argv[2], "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0)))
        f.write(trozo(b"IDAT", zlib.compress(filas, 9)))
        f.write(trozo(b"IEND", b""))
    print("%s: %dx%d" % (sys.argv[2], ancho, alto))


if __name__ == "__main__":
    main()
