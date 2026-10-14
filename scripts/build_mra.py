#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the .mra files and prove each one byte for byte; the download image for the benches.

    python scripts/build_mra.py                          # every set -> releases/
    python scripts/build_mra.py gstream                  # one set
    python scripts/build_mra.py --check                  # verify only, write nothing
    python scripts/build_mra.py --image gstream out.bin  # the image, and out.nv: the backup RAM's default

The image is the layout of rtl/gs_sdram_map.svh, whose SD_* localparams are read here: the .mra's index-0 ROM goes to
DDR3 at 0x30000000 (fast loading), its first SD_SDRAM_END bytes are copied to SDRAM, the graphics are read from DDR3.
Each image is built twice: by this script's loader from the driver's ROM_START records (scripts/extract_romstart.py),
with MAME's region bytes (the CPU's byte order for "maincpu" and "maindata", ROM_REGION32_BE; the regions as MAME holds
them for the graphics and samples), and by re-reading the written .mra with scripts/mra.py (mra-tools-c's semantics);
the two must be identical. The interleave map of each part is not reasoned about: each candidate is tried against the
ROM_START bytes and the one that reproduces them is written. The backup RAM's default ("nvram", gstream.nv) is MAME's
dwords in host order; the .mra's index-2 ROM sends it in the CPU's byte order, checked the same way.
X2222's sets come with Phase 4. After Arcade-Eolith_MiSTer's scripts/build_mra.py.
"""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_romstart as ers     # noqa: E402
import mra as mra_lib              # noqa: E402
from coretools import setting      # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DRIVER = Path(setting("MAME_SRC") or "E:/mame/src/mame/promat/gstream.cpp")
ROMDIRS = [Path(p) for p in (setting("MAME_ROMPATH") or "F:/Emulation/roms/MAME ROMs").split(";")]
OUT_DIR = REPO / "releases"

# set: (parent or None, mod byte (GStream.sv: [0] X2222's map))
SETS = {"gstream": (None, 0x00)}
# The game's controls. gstream: in MAME, in play, button 1 fires and button 2 sets off the bomb (debug/btn, held one at
# a time from frame 1490); buttons 3 and 4 showed nothing there, and the game's own input test names all four PUSH1-4.
BUTTONS = {"gstream": ["Shot", "Bomb", "-", "-"]}
CATEGORY = {"gstream": "Shooter"}


def sdram_map():
    text = (REPO / "rtl" / "gs_sdram_map.svh").read_text(encoding="utf-8")
    return {k: int(v, 16) for k, v in re.findall(r"localparam \[26:0\] (SD_\w+)\s*=\s*27'h([0-9a-fA-F]+);", text)}


def game_info(text, setname):
    m = re.search(r"GAME\(\s*(\d+)\s*,\s*" + setname + r"\s*,.*?,\s*ROT(\d+)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"", text)
    if not m:
        sys.exit(f"no GAME line for {setname}")
    return {"year": m.group(1), "rot": int(m.group(2)), "manufacturer": m.group(3), "title": m.group(4)}


def zips_for(setname):
    names = [setname + ".zip"] + ([SETS[setname][0] + ".zip"] if SETS[setname][0] else [])
    found = []
    for n in names:
        for d in [REPO / "roms"] + ROMDIRS:
            if (d / n).exists():
                found.append(d / n)
                break
    return names, found


def load_region(zs, records, size):
    """ROM_START records -> region bytes, as MAME's loader puts them (zero fill)."""
    out = bytearray(size)
    for kind, name, dest, length, crc, *rest in records:
        data = mra_lib._zip_read(zs, name, crc)
        assert len(data) == length, (name, len(data), length)
        if kind == "load":
            out[dest:dest + length] = data
        elif kind == "load16_wswap":
            for k in range(length // 2):
                out[dest + 2 * k:dest + 2 * k + 2] = data[2 * k:2 * k + 2][::-1]
        elif kind == "load32_word":
            for k in range(length // 2):
                out[dest + 4 * k:dest + 4 * k + 2] = data[2 * k:2 * k + 2]
        else:
            sys.exit(f"record kind {kind} not handled")
    return bytes(out)


def region_size(body, region):
    m = re.search(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+)\s*,\s*"' + re.escape(region) + '"', body)
    return int(m.group(1), 16) if m else 0


def mame_version():
    exe = Path(setting("MAME_DIR") or "C:/Emulation/Emulators/MAME") / (setting("MAME_EXE") or "mame.exe")
    out = subprocess.run([str(exe), "-version"], capture_output=True, text=True, timeout=30).stdout
    m = re.match(r"\s*0\.(\d+)", out)
    if not m:
        sys.exit(f"cannot read the MAME version from {exe}")
    return "%04d" % int(m.group(1))


def build(setname, sm, write=True):
    parent, mod = SETS[setname]
    text = DRIVER.read_text(encoding="utf-8", errors="replace")
    body = ers.blocks(text)[setname]
    info = game_info(text, setname)
    names, paths = zips_for(setname)
    if not paths:
        print(f"{setname}: no zip found ({' / '.join(names)}); skipped")
        return False
    zs = [zipfile.ZipFile(p) for p in paths]
    rec = {}
    for r in ("maincpu", "maindata", "oki1", "oki2", "gfx1", "gfx2", "gfx3", "gfx4", "nvram"):
        recs, unknown = ers.region_records(body, r)
        if unknown:
            sys.exit(f"{setname}: region {r}: unparsed {unknown}")
        rec[r] = recs
    reg = {r: load_region(zs, rec[r], region_size(body, r)) for r in rec}

    # the image this script expects
    img = bytearray(sm["SD_IMAGE_END"])
    place = [("maincpu", sm["SD_BOOT"] + 0x80000), ("maindata", sm["SD_DATA"]), ("oki1", sm["SD_OKI1"]),
             ("oki2", sm["SD_OKI2"]), ("gfx1", sm["SD_SPR"]), ("gfx2", sm["SD_TILE0"]), ("gfx3", sm["SD_TILE1"]),
             ("gfx4", sm["SD_TILE2"])]
    for r, at in place:
        img[at:at + len(reg[r])] = reg[r]
    img = bytes(img)
    nv = reg["nvram"]
    nv_cpu = b"".join(nv[i:i + 4][::-1] for i in range(0, len(nv), 4))

    # the .mra, part by part, in image order
    L = []
    pos = 0

    def pad_to(addr, why):
        nonlocal pos
        if addr > pos:
            L.append(f'        <part repeat="0x{addr - pos:X}">00</part>  <!-- {why} -->')
            pos = addr
        assert pos == addr, (why, hex(pos), hex(addr))

    def raw(name, crc):
        return mra_lib._zip_read(zs, name, crc)

    for r, at in place:
        L.append(f"        <!-- {r} -->")
        recs = sorted(rec[r], key=lambda x: x[2])
        if r == "gfx1":                                   # ROM_LOAD32_WORD pairs
            for i in range(0, len(recs), 2):
                lo, hi = recs[i], recs[i + 1]
                assert lo[0] == hi[0] == "load32_word" and hi[2] == lo[2] + 2 and lo[3] == hi[3], (lo, hi)
                pad_to(at + lo[2], f"{r} 0x{lo[2]:x}")
                want = reg[r][lo[2]:lo[2] + 2 * lo[3]]
                dlo, dhi = raw(lo[1], lo[4]), raw(hi[1], hi[4])
                chosen = next(((a, b) for a, b in (("0021", "2100"), ("0012", "1200"), ("2100", "0021"), ("1200", "0012"))
                               if mra_lib.interleave([(dlo, a), (dhi, b)], 32) == want), None)
                if not chosen:
                    sys.exit(f"{setname}: no interleave map reproduces {r} 0x{lo[2]:x}")
                L.append('        <interleave output="32">')
                L.append(f'            <part name="{escape(lo[1])}" crc="{lo[4]:08x}" map="{chosen[0]}"/>')
                L.append(f'            <part name="{escape(hi[1])}" crc="{hi[4]:08x}" map="{chosen[1]}"/>')
                L.append('        </interleave>')
                pos += 2 * lo[3]
            continue
        for kind, name, dest, length, crc, *rest in recs:
            pad_to(at + dest, f"{r} 0x{dest:x}")
            if kind == "load16_wswap":
                want = reg[r][dest:dest + length]
                chosen = next((m for m in ("21", "12") if mra_lib.interleave([(raw(name, crc), m)], 16) == want), None)
                if not chosen:
                    sys.exit(f"{setname}: no map reproduces {r} 0x{dest:x}")
                L.append('        <interleave output="16">')
                L.append(f'            <part name="{escape(name)}" crc="{crc:08x}" map="{chosen}"/>')
                L.append('        </interleave>')
            else:
                assert kind == "load", (r, kind)
                L.append(f'        <part name="{escape(name)}" crc="{crc:08x}"/>')
            pos += length
    pad_to(len(img), "image end")

    nvn, nvc = rec["nvram"][0][1], rec["nvram"][0][4]
    nvmap = next((m for m in ("4321", "1234") if mra_lib.interleave([(raw(nvn, nvc), m)], 32) == nv_cpu), None)
    if not nvmap:
        sys.exit(f"{setname}: no map turns {nvn} into the CPU's byte order")

    game = BUTTONS[parent or setname]
    btn_names = ",".join(game + ["Start", "Coin", "Pause", "Service Coin", "Service Mode"])
    btn_def = ",".join(["A", "B", "X", "Y"][:len(game)] + ["Start", "Select", "L", "R"])
    rot = {0: "horizontal", 90: "vertical (cw)", 270: "vertical (ccw)"}[info["rot"]]
    title = info["title"]
    xml = [
        "<misterromdescription>",
        "    <!-- Generated by scripts/build_mra.py from MAME promat/gstream.cpp; the layout is",
        "         rtl/gs_sdram_map.svh. Do not edit by hand. -->",
        f"    <name>{escape(title)}</name>",
        f"    <setname>{setname}</setname>",
        "    <rbf>GStream</rbf>",
        f"    <mameversion>{mame_version()}</mameversion>",
        f"    <year>{info['year']}</year>",
        f"    <manufacturer>{escape(info['manufacturer'])}</manufacturer>",
        f"    <category>{CATEGORY[parent or setname]}</category>",
        f"    <rotation>{rot}</rotation>",
        f'    <buttons names="{btn_names}" default="{btn_def}" count="{len(game)}"/>',
        "",
        "    <!-- mod byte (GStream.sv): [0] X2222's map -->",
        f'    <rom index="1"><part>{mod:02X}</part></rom>',
        "",
        "    <!-- address: the HPS puts the image in DDR3; the core copies its first 5 MB to SDRAM and reads the graphics",
        "         from DDR3 (rtl/memory/vh_rom_loader.sv, rtl/video/gs_video.sv) -->",
        f'    <rom index="0" zip="{"|".join(names)}" md5="none" address="0x30000000">',
        *L,
        "    </rom>",
        "",
        "    <!-- the backup RAM's default (MAME's gstream.nv, each dword turned to the CPU's byte order); a saved .nvm,",
        "         sent at <nvram>, replaces it -->",
        f'    <rom index="2" zip="{"|".join(names)}" md5="none">',
        '        <interleave output="32">',
        f'            <part name="{escape(nvn)}" crc="{nvc:08x}" map="{nvmap}"/>',
        '        </interleave>',
        "    </rom>",
        '    <nvram index="4" size="8192"/>',
        "</misterromdescription>",
        "",
    ]

    def safe(t):
        return re.sub(r'[\\/:*?"<>|]', "-", t)
    odir = OUT_DIR / "_alternatives" / ("_" + safe(game_info(text, parent)["title"])) if parent else OUT_DIR
    odir.mkdir(parents=True, exist_ok=True)
    fname = odir / (safe(title) + ".mra")
    tmp = fname.with_suffix(".mra.tmp")
    tmp.write_text("\n".join(xml), encoding="utf-8", newline="\n")
    got = mra_lib.build_image(str(tmp), [str(p) for p in paths])
    for z in zs:
        z.close()
    if got != img:
        diff = next((i for i in range(min(len(got), len(img))) if got[i] != img[i]), min(len(got), len(img)))
        tmp.unlink()
        sys.exit(f"{setname}: the .mra image differs from the ROM_START image at 0x{diff:x} ({len(got)} vs {len(img)} bytes)")
    if write:
        tmp.replace(fname)
        print(f"{setname}: {fname.name}, image {len(img)} bytes, identical to ROM_START")
    else:
        tmp.unlink()
        print(f"{setname}: image {len(img)} bytes, identical to ROM_START (not written)")
    return img, nv


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sets", nargs="*")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--image", nargs=2, metavar=("SET", "OUT"))
    a = ap.parse_args()
    sm = sdram_map()
    if a.image:
        r = build(a.image[0], sm, write=False)
        if r is False:
            return 1
        img, nv = r
        out = Path(a.image[1])
        out.write_bytes(img)
        out.with_suffix(".nv").write_bytes(nv)
        print(f"wrote {out} and {out.with_suffix('.nv')}")
        return 0
    ok = True
    for s in a.sets or list(SETS):
        if s not in SETS:
            sys.exit(f"unknown set {s}")
        ok = build(s, sm, write=not a.check) is not False and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
