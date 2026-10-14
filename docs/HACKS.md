# Hacks, approximations and workarounds in this core

Everything in this core's own RTL, scripts or `.mra` layout that is known not to be what the
hardware does: a stand-in, a shortcut, a value chosen to make something work, a workaround for a
tool. Each entry is added in the commit that introduces the hack and removed in the commit that
removes it.

This is not `MAME_KLUDGES.md`. That file lists MAME's own guesses that the core reproduces on
purpose because MAME is the reference. This file lists what is ours.

Rules:

- An entry cites `file:line` (or a module and signal name if the line moves often), and the
  evidence column says what was measured, or "unverified".
- "What would make it correct" names the work, not "fix later".
- A hack whose entry is missing is a bug. A hack whose entry is stale is worse: update it in the
  same commit as the code.
- Severity is what a player or a verifier would see: **visible** (wrong pixels, wrong sound, wrong
  timing a game can hit), **latent** (wrong only for input no in-scope set produces), **tooling**
  (affects the build or the bench, not the bitstream).

| What | Where | Why it is a hack | What would make it correct | Evidence | Severity |
|---|---|---|---|---|---|
| The raster: 6.75 MHz pixels, 432 x 262, visible 320 x 240 from (0, 0), syncs placed by guess | `rtl/video/gs_video.sv`, the counters | MAME has no raster (`set_size(320, 240)`, 60 Hz, no blanking, gstream.cpp 844-847); 432 x 262 is the driver's sprite budget constant (780), 6.75 MHz the 27 MHz crystal / 4. The frame is 59.64 Hz against MAME's 60.00 | A PCB measurement or recording of the line and frame rate and the blanking | unverified | visible |
| The E1 runs on every `clk_sys` clock, not at its 64 MHz | `rtl/gs_main.sv`, `u_cpu` | `e1_pipe` is not cycle-exact to the E1 at any clock; at 60.75 MHz it executes about 2.4 clocks an instruction (play, graphics off the SDRAM) where MAME charges about 1.3 cycles of 64 MHz, so a frame of work takes longer than on MAME and a frame the core cannot finish is a frame of slowdown the original may not have had. Its timer runs at 64 MHz (`cpu_tick`, `cpu_tick2`) | A faster E1 | boot: 2.68 clk/instruction (`sim/sys_tb`, `2e9942e`); play: 2.44 (ROADMAP, Progress, criterion 3) | visible |
| The sound output's low-pass: 4th-order Butterworth at 3.5 kHz, two biquads at 47,986 Hz | `rtl/sound/gs_sound.sv`, `f_*`; `scripts/snd_filter.py` | The board's analog stage after the AD-65s is not known; the filter is chosen so the spectrum matches MAME's, whose resampler removes the images of the chips' held 7.6 kHz samples | A recording or the schematic of the board's audio stage | `sim/sys_tb +wav`, frames 1200-1500: energy at 3.8-8 kHz 0.17% unfiltered, 0.016% filtered, MAME 0.024%; the user: unfiltered is brighter and noisier than MAME | visible |
