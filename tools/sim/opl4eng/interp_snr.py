#!/usr/bin/env python3
"""interp_snr.py - quality of the wave interpolation from a dump of tb_opl4eng (T5).

    python3 interp_snr.py build/t5_samples.txt [table_len] [ratio]

Fits one sine at the theoretical frequency (ratio table positions per output
sample over a table of table_len samples; default 64 and 0.646 = OCT 0, FN 300)
by least squares and prints the SNR (sine power over residual power) and the
biggest step between consecutive samples relative to the maximum slope of the
fitted sine (1.0 = clean). Holding the sample (no interpolation) leaves steps
and a poor reconstruction: about 35 dB; linear interpolation gives 44 dB or
more. An interpolation that multiplies a signed sample by an unsigned phase
clicks at every zero crossing: steps of 12 to 80. Pure Python, no numpy.
Exit code 0 when SNR >= 44 dB and step <= 1.15.
"""
import math, sys

fn = sys.argv[1]
table = int(sys.argv[2]) if len(sys.argv) > 2 else 64
ratio = float(sys.argv[3]) if len(sys.argv) > 3 else (1024 + 300) / 1024.0 * 0.5
f = ratio / table                                   # cycles per output sample
x = [int(v.split()[0]) for v in open(fn) if v.strip() and 'x' not in v.split()[0]]
x = x[200:1300]                                     # past the header load and the attack
n = len(x)
# normal equations for a*sin + b*cos + c
S = [[0.0] * 3 for _ in range(3)]; T = [0.0] * 3
for i, v in enumerate(x):
    r = [math.sin(2 * math.pi * f * i), math.cos(2 * math.pi * f * i), 1.0]
    for a in range(3):
        T[a] += r[a] * v
        for b in range(3):
            S[a][b] += r[a] * r[b]
# solve 3x3 (Gaussian elimination)
M = [S[a] + [T[a]] for a in range(3)]
for col in range(3):
    piv = max(range(col, 3), key=lambda r: abs(M[r][col])); M[col], M[piv] = M[piv], M[col]
    for r in range(3):
        if r != col:
            k = M[r][col] / M[col][col]
            M[r] = [M[r][j] - k * M[col][j] for j in range(4)]
a, b, c = (M[i][3] / M[i][i] for i in range(3))
amp = math.hypot(a, b)
res = 0.0
for i, v in enumerate(x):
    res += (v - (a * math.sin(2 * math.pi * f * i) + b * math.cos(2 * math.pi * f * i) + c)) ** 2
snr = 10 * math.log10((amp * amp / 2) / max(res / n, 1e-9))
slope = amp * 2 * math.pi * f
step = max(abs(x[i + 1] - x[i]) for i in range(n - 1)) / slope
ok = snr >= 44.0 and step <= 1.15
print("  interpolation: ratio %.4f  amp %.0f  snr %.2f dB  step %.2f  %s" % (ratio, amp, snr, step, "ok" if ok else "FAIL"))
sys.exit(0 if ok else 1)
