# clk_sys, 60.75 MHz (docs/ROADMAP.md, Clocks)
create_clock -name clk -period 16.461 [get_ports clk]
derive_clock_uncertainty
set_false_path -from [get_ports {prst rst x2 pause cpu_tick* vblank_irq in* x_* spr_rd* pal_rd* oki_dout* nv_* dl_* mem_ack mem_dout*}]
set_false_path -to [get_ports {spr_* pal_* scroll* oki_* nv_* dl_busy mem_*}]
