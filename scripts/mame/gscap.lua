-- Video state and MAME's picture at chosen frames, for scripts/render_model.py.
-- At each frame notifier N in GC_FRAMES writes the state to GC_OUT, and at notifier N + 1 the picture MAME drew from
-- it: screen:pixels() at a notifier returns the picture drawn from the previous notifier's RAM (measured: frame 1500's
-- pixels equal render_model.py's frame from 1499's RAM, 0 of 76,800 differ; from 1500's RAM, 61,024 differ):
--   f<N>_vram.bin  the VRAM, 0x80000000-0x80003fff, big-endian dwords as the CPU reads them
--   f<N>_pal.bin   the palette RAM, 0x4f400000-0x4f406fff, likewise (gstream)
--   f<N>_scr.txt   the scroll registers as the last writes left them: sx0 sy0 sx1 sy1 sx2 sy2, hex (bits 31:16)
--   f<N>_screen.bin  the screen bitmap, 32-bit 0xAARRGGBB words, little-endian, W x H, and f<N>_screen.txt "W H"
-- Inputs as scripts/mame/busy.lua: GC_COIN (coin and Start every 300 frames from it), GC_FIRE (P1 button 1, 4 frames
-- in 8). GC_SCROLL: the six scroll registers' addresses, hex, in the order above (the map differs per set).

local OUT    = os.getenv("GC_OUT")
local COIN   = tonumber(os.getenv("GC_COIN") or "0")
local FIRE   = tonumber(os.getenv("GC_FIRE") or "0")
local want, last = {}, 0
for n in string.gmatch(os.getenv("GC_FRAMES") or "", "%d+") do
    want[tonumber(n)] = true
    if tonumber(n) + 1 > last then last = tonumber(n) + 1 end
end
local SCR = {}
for a in string.gmatch(os.getenv("GC_SCROLL") or "", "%x+") do SCR[#SCR + 1] = tonumber(a, 16) end
local PAL = os.getenv("GC_PAL") ~= "0"

local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local prog = cpu.spaces["program"]
local scr  = mach.screens[":screen"]

local sval = {}
KEEP_GC_T = {}
for i, a in ipairs(SCR) do
    sval[i] = 0
    KEEP_GC_T[i] = prog:install_write_tap(a, a + 3, "gc_scr" .. i, function(offset, data, mask)
        if (mask & 0xffff0000) ~= 0 then sval[i] = (data >> 16) & 0xffff end
        return data
    end)
end

local function dump(path, lo, hi)
    local parts = {}
    for a = lo, hi, 4 do parts[#parts + 1] = string.pack(">I4", prog:read_u32(a)) end
    local f = assert(io.open(path, "wb"))
    f:write(table.concat(parts))
    f:close()
end

local function press(field, on)
    for _, p in pairs(mach.ioport.ports) do
        local fld = p.fields[field]
        if fld then fld:set_value(on and 1 or 0) end
    end
end

local frame = 0
KEEP_GC_F = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if want[frame] then
        local base = string.format("%s/f%d", OUT, frame)
        dump(base .. "_vram.bin", 0x80000000, 0x80003fff)
        if PAL then dump(base .. "_pal.bin", 0x4f400000, 0x4f406fff) end
        local f = assert(io.open(base .. "_scr.txt", "w"))
        for i = 1, #SCR do f:write(string.format("%04x ", sval[i])) end
        f:write("\n")
        f:close()
    end
    if want[frame - 1] then
        local base = string.format("%s/f%d", OUT, frame - 1)
        local px, w, h = scr:pixels()
        local f = assert(io.open(base .. "_screen.bin", "wb")); f:write(px); f:close()
        f = assert(io.open(base .. "_screen.txt", "w")); f:write(string.format("%d %d\n", w, h)); f:close()
    end
    if COIN > 0 and frame >= COIN then
        local k = (frame - COIN) % 300
        press("Coin 1", k < 6)
        press("1 Player Start", k >= 30 and k < 36)
    end
    if FIRE > 0 and frame >= FIRE then press("P1 Button 1", (frame - FIRE) % 8 < 4) end
    if frame >= last then mach:exit() end
end)
