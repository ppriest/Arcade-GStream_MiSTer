#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Is the sample data in the right bit order? Every ordering of the 8 data bits, decoded with MAME's OKI ADPCM.

    python scripts/oki_bitorder.py [debug/sys/gstream.bin]

For 8 KB of four long phrases, each of the 40,320 orderings (as data lines swapped on the board would make) is
decoded; a wrong order makes the decoder random-walk into its +-2048 clamp, a right one stays bounded and centred.
Prints, per stretch, the ROM order's clamp share and drift, its rank (clamp + drift), and the orderings that never
clamp (written high bit first: 76543210 is the ROM as loaded).
"""
import itertools
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
img = Path(sys.argv[1] if len(sys.argv) > 1 else REPO / "debug" / "sys" / "gstream.bin").read_bytes()
step = [int(16.0 * 1.1 ** i) for i in range(49)]
diff = np.zeros((49, 16), np.int32)
for s in range(49):
    st = step[s]
    for n in range(16):
        v = st // 8 + (st if n & 4 else 0) + (st // 2 if n & 2 else 0) + (st // 4 if n & 1 else 0)
        diff[s, n] = -v if n & 8 else v
shift = np.array([-1, -1, -1, -1, 2, 4, 6, 8] * 2, np.int32)
perms = np.array(list(itertools.permutations(range(8))), np.int32)       # perms[p][k]: source bit of output bit k
P = len(perms)
lut = np.zeros((P, 256), np.uint8)                                        # byte -> permuted byte, per permutation
bytes_ = np.arange(256)
for k in range(8):
    lut |= (((bytes_[None, :] >> perms[:, k][:, None]) & 1) << k).astype(np.uint8)
ident = int(np.nonzero((perms == np.arange(8)).all(1))[0][0])
for name, base, bank, start in (('oki1', 0x300000, 1, 0x8000), ('oki1', 0x300000, 3, 0x8000),
                                ('oki2', 0x400000, 1, 0x20000), ('oki2', 0x400000, 2, 0x8000)):
    a = base + bank * 0x40000 + start
    chunk = np.frombuffer(img[a:a + 8192], np.uint8)
    pb = lut[:, chunk]                                                    # P x 8192 permuted bytes
    nib = np.empty((P, 16384), np.int32); nib[:, 0::2] = pb >> 4; nib[:, 1::2] = pb & 15
    sig = np.zeros(P, np.int32); si = np.zeros(P, np.int32)
    out = np.empty((P, 16384), np.int16)
    for i in range(16384):
        n = nib[:, i]
        sig = np.clip(sig + diff[si, n], -2048, 2047)
        si = np.clip(si + shift[n], 0, 48)
        out[:, i] = sig
    # a wrong bit order makes the decoder random-walk into its clamps; a right one stays bounded and centred
    clamp = (np.abs(out) >= 2000).mean(1)
    drift = np.abs(out.astype(np.float32).mean(1)) / 2048
    score = clamp + drift
    order = np.argsort(score, kind='stable')
    rank = int(np.nonzero(order == ident)[0][0])
    nzero = int((clamp == 0).sum())
    print('%s bank %d +%05x: as loaded clamp %.4f drift %.4f, rank %d of %d; %d orderings never clamp; best %s; median clamp %.3f'
          % (name, bank, start, clamp[ident], drift[ident], rank + 1, P, nzero, ''.join(map(str, perms[order[0]][::-1])), np.median(clamp)))
    if nzero <= 12:
        print('   never clamp:', ' '.join(''.join(map(str, perms[p][::-1])) for p in np.nonzero(clamp == 0)[0]))
