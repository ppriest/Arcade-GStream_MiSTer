-- SPDX-License-Identifier: GPL-3.0-or-later
-- The OKI commands and banks, per frame, as sim/sys_tb +okilog writes them: "<frame> <chip> <byte>" for each
-- byte written to an M6295 (I/O 0x1014 chip 1, 0x1018 chip 2) and "<frame> bank <b1> <b2>" when the banks
-- latched from I/O 0x100c change (gstream_oki_banking_w). The frame is the count of frame notifiers so far.
-- Inputs as busy.lua: from OKI_COIN a coin, then Start 30 frames later, every 300 frames; from OKI_FIRE P1
-- button 1 tapped 4 frames down, 4 up.
--
--   OKI_OUT     output file
--   OKI_FRAMES  frames to run, then exit
--   OKI_COIN    (0 = never)
--   OKI_FIRE    (0 = never)

local OUT    = os.getenv("OKI_OUT")
local FRAMES = tonumber(os.getenv("OKI_FRAMES") or "1500")
local COIN   = tonumber(os.getenv("OKI_COIN") or "0")
local FIRE   = tonumber(os.getenv("OKI_FIRE") or "0")

local mach = manager.machine
local iosp = mach.devices[":maincpu"].spaces["io"]
local f = assert(io.open(OUT, "w"))
local frame = 0
local b1, b2 = 0, 0
f:write("0 bank 0 0\n")

local function bit(v, n) return (v >> n) & 1 end

-- globals, or the taps are garbage-collected (LESSONS_LEARNED)
KEEP_OKI1 = iosp:install_write_tap(0x1014, 0x1017, "oki1", function(offset, d, mask)
    if not mach:side_effects_disabled() then f:write(string.format("%d 1 %02x\n", frame, d & 0xff)) end
end)
KEEP_OKI2 = iosp:install_write_tap(0x1018, 0x101b, "oki2", function(offset, d, mask)
    if not mach:side_effects_disabled() then f:write(string.format("%d 2 %02x\n", frame, d & 0xff)) end
end)
KEEP_BANK = iosp:install_write_tap(0x100c, 0x100f, "okibank", function(offset, d, mask)
    if mach:side_effects_disabled() then return end
    local n1 = (bit(d, 6) & (1 - bit(d, 7))) << 1 | (bit(d, 2) & bit(d, 3))
    local n2 = (bit(d, 4) & (1 - bit(d, 5))) << 1 | (bit(d, 0) & bit(d, 1))
    if n1 ~= b1 or n2 ~= b2 then
        b1, b2 = n1, n2
        f:write(string.format("%d bank %d %d\n", frame, b1, b2))
    end
end)

local function press(field, on)
    for _, p in pairs(mach.ioport.ports) do
        local fld = p.fields[field]
        if fld then fld:set_value(on and 1 or 0) end
    end
end

KEEP_OKI_F = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if COIN > 0 and frame >= COIN then
        local k = (frame - COIN) % 300
        press("Coin 1", k < 6)
        press("1 Player Start", k >= 30 and k < 36)
    end
    if FIRE > 0 and frame >= FIRE then press("P1 Button 1", (frame - FIRE) % 8 < 4) end
    if frame >= FRAMES then
        f:close()
        mach:exit()
    end
end)
