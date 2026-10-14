-- Instructions the main CPU executes per frame, from the debugger's trace (MAME with -debug -nodrc).
-- Drives the same inputs as busy.lua, then traces every instruction's PC for IC_FRAMES frames from
-- IC_START, with a "# frame" line at each frame notifier. "noloop" turns off the debugger's loop
-- collapsing, which would otherwise log a loop's body once.
--
--   IC_OUT     trace file
--   IC_START   first traced frame
--   IC_FRAMES  frames to trace, then exit
--   IC_COIN    frame to insert a coin and press Start, repeated every 300 frames (0 = never)
--   IC_FIRE    frame from which P1 button 1 is tapped, 4 frames down, 4 up (0 = never)
--   A snapshot is taken at IC_START (MAME's -snapshot_directory), to show what was traced.

local OUT    = os.getenv("IC_OUT")
local START  = tonumber(os.getenv("IC_START") or "1500")
local NF     = tonumber(os.getenv("IC_FRAMES") or "10")
local COIN   = tonumber(os.getenv("IC_COIN") or "0")
local FIRE   = tonumber(os.getenv("IC_FIRE") or "0")

local mach = manager.machine
local dbg  = mach.debugger
dbg:command("go")

local function press(field, on)
    for _, p in pairs(mach.ioport.ports) do
        local fld = p.fields[field]
        if fld then fld:set_value(on and 1 or 0) end
    end
end

local frame, tracing = 0, false
KEEP_IC_F = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    if COIN > 0 and frame >= COIN then
        local k = (frame - COIN) % 300
        press("Coin 1", k < 6)
        press("1 Player Start", k >= 30 and k < 36)
    end
    if FIRE > 0 and frame >= FIRE then press("P1 Button 1", (frame - FIRE) % 8 < 4) end
    if frame == START then
        mach.video:snapshot()
        dbg:command(string.format('trace %s,maincpu,noloop,{tracelog "I %%08X ",pc}', OUT))
        tracing = true
    elseif tracing then
        dbg:command(string.format('tracelog "# frame %d\n"', frame))
    end
    if frame >= START + NF then
        dbg:command("trace off,maincpu")
        mach:exit()
    end
end)
