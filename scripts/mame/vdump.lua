-- SPDX-License-Identifier: GPL-3.0-or-later
-- One region of the main CPU's program space, dumped at every frame notifier (MAME's screen update
-- with this driver's zero-length vblank), for the sprite and tile census (scripts/vram_census.py).
--
--   VD_OUT     output file: VD_FRAMES records of the region's bytes, big-endian dwords as read
--   VD_LO, VD_HI  the region, hex, inclusive, dword aligned
--   VD_SKIP    frames before the first record; VD_FRAMES records
--   VD_COIN, VD_COIN_PERIOD, VD_START_PERIOD, VD_PRESS  as WT_* in wtiming.lua; after Start, P1 Right
--              is held and P1 Button 1 pulsed

local OUT    = os.getenv("VD_OUT")
local LO     = tonumber(os.getenv("VD_LO"), 16)
local HI     = tonumber(os.getenv("VD_HI"), 16)
local SKIP   = tonumber(os.getenv("VD_SKIP") or "600")
local FRAMES = tonumber(os.getenv("VD_FRAMES") or "1800")
local COIN   = tonumber(os.getenv("VD_COIN") or "0")
local COIN_PER  = tonumber(os.getenv("VD_COIN_PERIOD") or "0")
local START_PER = tonumber(os.getenv("VD_START_PERIOD") or "0")
local PRESS  = tonumber(os.getenv("VD_PRESS") or "6")

local mach = manager.machine
local prog = mach.devices[os.getenv("CORE_CPU") or ":maincpu"].spaces[os.getenv("CORE_SPACE") or "program"]
local f = assert(io.open(OUT, "wb"))

local function field(name)
    for _, port in pairs(mach.ioport.ports) do
        local fl = port.fields[name]
        if fl then return fl end
    end
end
local f_coin, f_start = field("Coin 1"), field("1 Player Start")
local f_right, f_b1 = field("P1 Right"), field("P1 Button 1")

local n = 0
KEEP_VD = emu.add_machine_frame_notifier(function()
    n = n + 1
    if COIN > 0 then
        if COIN_PER > 0 then f_coin:set_value((n >= COIN and (n - COIN) % COIN_PER < PRESS) and 1 or 0)
        else f_coin:set_value((n >= COIN and n < COIN + PRESS) and 1 or 0) end
        local st = n - COIN - 90
        if START_PER > 0 then f_start:set_value((st >= 0 and st % START_PER < PRESS) and 1 or 0)
        else f_start:set_value((st >= 0 and st < PRESS) and 1 or 0) end
        if st >= PRESS then
            f_right:set_value(1)
            f_b1:set_value((n % 20) < 4 and 1 or 0)
        end
    end
    if n > SKIP then
        local parts = {}
        for a = LO, HI, 4 do parts[#parts + 1] = string.pack(">I4", prog:read_u32(a)) end
        f:write(table.concat(parts))
    end
    if n >= SKIP + FRAMES then
        f:close()
        mach:exit()
    end
end)
