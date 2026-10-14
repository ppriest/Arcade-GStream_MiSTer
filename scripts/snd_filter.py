#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""gs_sound's output low-pass: the coefficients, and a bit-exact model to filter a recording.

    python scripts/snd_filter.py                       # print the coefficients for gs_sound.sv
    python scripts/snd_filter.py in.wav out.wav        # filter a 16-bit mono recording (sim/sys_tb +wav)
    python scripts/snd_filter.py --check <prefix>      # sim/sys_tb +filtchk=<prefix>: the RTL against the model

A 4th-order Butterworth at FC, as two RBJ biquads (Q = 1/(2cos(pi/8)), 1/(2cos(3pi/8))), run at FS (a sample
every 1266 clocks of 60.75 MHz). Coefficients are scaled by 2^CB; each section is direct form I on samples with
FB fraction bits, the sum shifted right by CB and saturated, as gs_sound.sv computes it.
"""
import math
import struct
import sys
import wave

FS = 60.75e6 / 1266
FC = 3500.0
CB = 22                 # coefficient fraction bits
FB = 4                  # fraction bits kept in the sections' samples


def coeffs():
    out = []
    for q in (1 / (2 * math.cos(math.pi / 8)), 1 / (2 * math.cos(3 * math.pi / 8))):
        w0 = 2 * math.pi * FC / FS
        al = math.sin(w0) / (2 * q)
        c = math.cos(w0)
        a0 = 1 + al
        b = [(1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0]
        a = [-2 * c / a0, (1 - al) / a0]
        out.append([round(v * (1 << CB)) for v in b + a])
    return out


def sat(v, bits):
    lim = 1 << (bits - 1)
    return max(-lim, min(lim - 1, v))


def run(xs):
    cs = coeffs()
    st = [[0, 0, 0, 0] for _ in cs]          # x1, x2, y1, y2 per section, FB fraction bits
    ys = []
    for x in xs:
        v = x << FB
        for (b0, b1, b2, a1, a2), s in zip(cs, st):
            acc = b0 * v + b1 * s[0] + b2 * s[1] - a1 * s[2] - a2 * s[3]
            y = sat(acc >> CB, 16 + FB + 2)
            s[1], s[0] = s[0], v
            s[3], s[2] = s[2], y
            v = y
        ys.append(sat(v >> FB, 16))
    return ys


def check(prefix):
    raw_in = open(prefix + "_in.raw", "rb").read()
    raw_out = open(prefix + "_out.raw", "rb").read()
    xs = struct.unpack("<%dh" % (len(raw_in) // 2), raw_in)
    rtl = struct.unpack("<%dh" % (len(raw_out) // 2), raw_out)
    model = run(xs)
    n = min(len(model) - 1, len(rtl) - 1)
    bad = [i for i in range(n) if rtl[i + 1] != model[i]]
    print(f"{n} samples, {len(bad)} differ" + (f"; first at {bad[0]}: RTL {rtl[bad[0] + 1]}, model {model[bad[0]]}" if bad else ""))
    return 1 if bad else 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        sys.exit(check(sys.argv[2]))
    if len(sys.argv) < 3:
        for i, c in enumerate(coeffs()):
            print(f"section {i}: b0 {c[0]} b1 {c[1]} b2 {c[2]} a1 {c[3]} a2 {c[4]}  (2^{CB})")
        return
    w = wave.open(sys.argv[1])
    raw = w.readframes(w.getnframes())
    xs = struct.unpack("<%dh" % (len(raw) // 2), raw)
    ys = run(xs)
    o = wave.open(sys.argv[2], "wb")
    o.setnchannels(1); o.setsampwidth(2); o.setframerate(w.getframerate())
    o.writeframes(struct.pack("<%dh" % len(ys), *ys))
    o.close()


if __name__ == "__main__":
    main()
