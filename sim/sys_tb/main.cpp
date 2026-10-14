// SPDX-License-Identifier: GPL-3.0-or-later
// System bench: the gstream board from reset, on the real SDRAM controller and a chip model.
//
//   run_verilator.sh sys_tb +img=<image.bin> [+nv=<gstream.nv>] [+frames=N] [+pctrace=<instr.trace>]
//                    [+bustrace=<bus.trace>] [+busmax=N] [+idle=lo:hi] [+lat=N] [+busy=P] [+coin=F] [+start=F]
//                    [+coinrep=N] [+startrep=N] [+hold=K] [+fire=F] [+vramdump=<file>] [+snap=F1,F2,..] [+out=<dir>] [+v=1]
//                    [+okilog=<file>] [+wav=<file>] [+filtchk=<prefix>]
//
// +img is the download image (scripts/build_mra.py --image <set> <file>), written into the chip model's array
// before the clock starts, up to SD_SDRAM_END (the graphics are read from DDR3). +nv is MAME's backup RAM default (the set's gstream.nv: the RAM's dwords in host,
// little-endian, order), loaded through nv_load_* in the CPU's byte order while the board is in reset; without
// it the RAM is zero.
// +pctrace compares the CPU's retired PCs with a MAME instruction trace (docs/E1_TRACE_FORMAT.md) and reports the
// first difference: up to the first interrupt the two must agree, after it timing differs. +bustrace compares the
// CPU's program-space data accesses, in order, with MAME's bus trace (one row an access, mask = the lanes).
// +idle=lo:hi names the game's idle loop: per frame, the clocks from the frame's start (the vblank interrupt) to
// the CPU's last entry into the loop are its busy clocks; a frame in which it never reaches the loop is lost.
// The video's DDR3 reads are answered from the image: a burst's beats in order, +lat clocks after it is accepted (40),
// the port busy in +busy percent of clocks (0); the empty-tile table is computed from the image and loaded.
// +snap: for each listed frame, <out>/f<N>_rtl.ppm (the 320 x 240 shown before frame N's vblank interrupt) and the
// VRAM, palette and scroll registers it was drawn from (f<N>_vram.bin, _pal.bin, _scr.txt, as scripts/gs_capture.py
// writes MAME's), for scripts/sys_video_check.py.
// +coin / +start press COIN1 / START1 at frame F for +hold frames (6), repeated every +coinrep / +startrep frames;
// from +fire, P1 button 1 is pressed 4 frames in 8 (as scripts/mame/busy.lua).
// +vramdump appends the VRAM at every frame's end (the vblank interrupt), 4096 big-endian dwords a frame, as
// scripts/mame/vdump.lua writes MAME's; scripts/vram_compare.py matches the two.
// +okilog writes "<frame> <chip> <byte>" for each OKI command byte and "<frame> bank <b1> <b2>" for each bank
// change, frame counted from the vblank interrupts as MAME's notifier (scripts/mame/okilog.lua writes MAME's).
// +filtchk writes the output low-pass's input and output at each of its samples to <prefix>_in.raw and _out.raw
// (16-bit; the output lags a sample); scripts/snd_filter.py --check compares them with its model.
// +wav records the sound output, mono 16-bit, a sample every 1266 clocks (47,986 Hz).
// Per frame (+v=1, else every 60): instructions retired, I- and D-cache misses, busy clocks, and the lines (from
// the interrupt) of the frame's last VRAM and palette writes.
#include "Vtb_sys.h"
#include "Vtb_sys___024root.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <fcntl.h>

double sc_time_stamp() { return 0; }

static std::string arg(int argc, char **argv, const char *key, const char *def = "") {
	size_t n = strlen(key);
	for (int i = 1; i < argc; i++)
		if (!strncmp(argv[i], key, n)) return std::string(argv[i] + n);
	return def;
}

static std::vector<uint8_t> slurp(const std::string &p) {
	std::vector<uint8_t> v;
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(2); }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	v.resize(n);
	if (fread(v.data(), 1, n, f) != (size_t)n) { fprintf(stderr, "short read %s\n", p.c_str()); exit(2); }
	fclose(f);
	return v;
}

int main(int argc, char **argv) {
#ifdef _WIN32
	_fmode = _O_BINARY;
#endif
	Verilated::commandArgs(argc, argv);
	std::vector<uint8_t> img = slurp(arg(argc, argv, "+img="));
	std::string nvp = arg(argc, argv, "+nv=");
	int nframes = atoi(arg(argc, argv, "+frames=", "10").c_str());
	int coin_f = atoi(arg(argc, argv, "+coin=", "-1").c_str());
	int start_f = atoi(arg(argc, argv, "+start=", "-1").c_str());
	int fire_f = atoi(arg(argc, argv, "+fire=", "-1").c_str());
	int hold = atoi(arg(argc, argv, "+hold=", "6").c_str());
	int coinrep = atoi(arg(argc, argv, "+coinrep=", "0").c_str());
	int startrep = atoi(arg(argc, argv, "+startrep=", "0").c_str());
	int verbose = atoi(arg(argc, argv, "+v=", "0").c_str());
	uint32_t idle_lo = 0, idle_hi = 0;
	sscanf(arg(argc, argv, "+idle=", "").c_str(), "%x:%x", &idle_lo, &idle_hi);
	auto pressed = [&](int k, int at, int rep) {
		if (at < 0 || k < at) return false;
		return rep > 0 ? (k - at) % rep < hold : k < at + hold;
	};

	std::vector<uint32_t> mame_pc;
	std::vector<bool> mame_trap;   // TRAP (0xfc00-0xffff): retire_pc is the halfword after it
	{
		std::string p = arg(argc, argv, "+pctrace=");
		if (!p.empty()) {
			FILE *t = fopen(p.c_str(), "r");
			if (!t) { fprintf(stderr, "cannot open +pctrace\n"); return 2; }
			static char line[8192];
			while (fgets(line, sizeof line, t)) {
				if (line[0] == '#') continue;
				unsigned long long idx; unsigned pc, op;
				if (sscanf(line, "%llu %x %x", &idx, &pc, &op) == 3) {
					mame_pc.push_back(pc);
					mame_trap.push_back(op >= 0xfc00);
				}
			}
			fclose(t);
			printf("pctrace: %zu instructions\n", mame_pc.size());
		}
	}
	struct BusRow { uint64_t idx; char kind; uint32_t addr, data, mask; };
	std::vector<BusRow> mrows;
	{
		std::string p = arg(argc, argv, "+bustrace=");
		if (!p.empty()) {
			FILE *t = fopen(p.c_str(), "r");
			if (!t) { fprintf(stderr, "cannot open +bustrace\n"); return 2; }
			char line[512];
			while (fgets(line, sizeof line, t)) {
				unsigned long long idx; char kind, space; unsigned a, d, m;
				if (line[0] == '#' || sscanf(line, "%llu %c %c %x %x %x", &idx, &kind, &space, &a, &d, &m) != 6) continue;
				if (kind == 'F' || space != 'P') continue;
				mrows.push_back({idx, kind, a, d, m});
			}
			fclose(t);
			printf("bustrace: %zu data accesses\n", mrows.size());
		}
	}
	int busmax = atoi(arg(argc, argv, "+busmax=", "4").c_str());
	FILE *vdump = nullptr;
	{
		std::string p = arg(argc, argv, "+vramdump=");
		if (!p.empty()) vdump = fopen(p.c_str(), "wb");
	}

	Vtb_sys *top = new Vtb_sys;
	auto &mem = top->rootp->tb_sys__DOT__u_chip__DOT__mem;
	for (size_t i = 0; i + 1 < img.size() && i < 0x500000; i += 2)   // SD_SDRAM_END: the graphics are DDR3's
		mem[i >> 1] = (uint16_t)(img[i] | (img[i + 1] << 8));

	top->clk = 0; top->rst = 1; top->prst = 1; top->pause = 0; top->x2 = 0;
	top->in0 = 0xffff; top->in1 = 0xffff;
	top->gfx_busy = 0; top->gfx_dv = 0; top->et_we = 0;
	top->nv_blank = 0; top->nv_load = 0; top->nv_load_we = 0;
	auto tick = [&]() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); };
	for (int i = 0; i < 8; i++) tick();           // the PLL locks: the memory side's power-up reset
	top->prst = 0;
	top->nv_blank = 1;
	for (int i = 0; i < 2100; i++) tick();
	top->nv_blank = 0;
	if (!nvp.empty()) {
		std::vector<uint8_t> nv = slurp(nvp);
		top->nv_load = 1;
		for (int a = 0; a < 0x2000 && a < (int)nv.size(); a++) {
			top->nv_load_we = 1; top->nv_load_addr = a; top->nv_load_data = nv[(a & ~3) | (3 - (a & 3))];
			tick();
		}
		top->nv_load_we = 0; top->nv_load = 0;
		tick();
	}
	for (int a = 0; a < 8192; a++) {              // the empty-tile table, as gs_et_scan builds it
		uint8_t byte = 0;
		for (int k = 0; k < 8; k++) {
			const uint8_t *tile = &img[0x500000 + (size_t)(8 * a + k) * 256];
			bool z = true;
			for (int i = 0; i < 256 && z; i++) z = tile[i] == 0;
			if (z) byte |= 1 << k;
		}
		top->et_we = 1; top->et_addr = a; top->et_data = byte;
		tick();
	}
	top->et_we = 0;
	for (int i = 0; i < 20000; i++) tick();       // the SDRAM's initialisation, the caches' sweep
	top->rst = 0;
	int lat = atoi(arg(argc, argv, "+lat=", "40").c_str()), busy_pct = atoi(arg(argc, argv, "+busy=", "0").c_str());
	struct Burst { uint64_t at; uint32_t addr; int n; };
	std::vector<Burst> pend;
	size_t pend_rd = 0;
	std::vector<int> snaps;
	{
		std::string sl = arg(argc, argv, "+snap=");
		for (size_t q = 0; q < sl.size();) {
			size_t c = sl.find(',', q);
			snaps.push_back(atoi(sl.substr(q, c == std::string::npos ? std::string::npos : c - q).c_str()));
			if (c == std::string::npos) break;
			q = c + 1;
		}
	}
	std::string outd = arg(argc, argv, "+out=", ".");
	std::vector<uint8_t> pix;
	srand(5);
	FILE *okil = nullptr, *wav = nullptr;
	if (!arg(argc, argv, "+okilog=").empty()) okil = fopen(arg(argc, argv, "+okilog=").c_str(), "w");
	if (!arg(argc, argv, "+wav=").empty()) { wav = fopen(arg(argc, argv, "+wav=").c_str(), "wb"); uint8_t h[44] = {0}; fwrite(h, 1, 44, wav); }
	uint32_t wav_n = 0, wav_div = 0;
	int okib = -1;
	uint64_t oki_takes[2] = {0, 0}, oki_late[2] = {0, 0};
	int oki_st_prev[2] = {0, 0};
	unsigned snd_late[2] = {0, 0}, snd_wait[2] = {0, 0};
	std::string fchk_p = arg(argc, argv, "+filtchk=");
	bool fchk = !fchk_p.empty();
	FILE *fchk_in = fchk ? fopen((fchk_p + "_in.raw").c_str(), "wb") : nullptr;
	FILE *fchk_out = fchk ? fopen((fchk_p + "_out.raw").c_str(), "wb") : nullptr;

	uint64_t ninstr = 0, frame_instr = 0, clocks = 0, frame_clk = 0, pc_ok = 0;
	bool pc_done = mame_pc.empty();
	size_t bus_pos = 0;
	int bus_bad = 0;
	uint32_t im0 = 0, dm0 = 0;
	int frame = 0;
	bool in_idle = false;
	uint64_t last_entry = 0;            // the clock of the CPU's last entry into the idle loop, this frame
	bool entered = false;
	int lost = 0;
	std::vector<double> busy;
	long last_vram = -1, last_pal = -1;     // the frame's last write, clocks from its start
	while (frame < nframes) {
		int fr1 = frame + 1;
		uint16_t i0 = 0xffff;
		if (pressed(fr1, coin_f, coinrep)) i0 &= ~0x0200;
		if (pressed(fr1, start_f, startrep)) i0 &= ~0x0400;
		if (fire_f >= 0 && fr1 >= fire_f && (fr1 - fire_f) % 8 < 4) i0 &= ~0x0010;
		top->in0 = i0;
		bool dbusy = busy_pct > 0 && (rand() % 100) < busy_pct;
		top->gfx_busy = dbusy; top->gfx_dv = 0;
		if (pend_rd < pend.size() && clocks >= pend[pend_rd].at) {
			Burst &bu = pend[pend_rd];
			uint64_t w = 0;
			for (int i = 0; i < 8; i++) w |= (uint64_t)img[(size_t)bu.addr * 8 + i] << (8 * i);
			top->gfx_dv = 1; top->gfx_dout = w;
			bu.addr++; bu.at = clocks + 1;
			if (--bu.n == 0) { pend_rd++; if (pend_rd > 1024) { pend.erase(pend.begin(), pend.begin() + pend_rd); pend_rd = 0; } }
		}
		top->eval();
		{
			// jt6295_rom takes the ADPCM byte at st == 2, one cen32 after setting the address, without waiting
			auto *q = top->rootp;
			bool ok[2] = {(bool)q->tb_sys__DOT__u_snd__DOT__chip__BRA__0__KET____DOT__u_oki__DOT__u_rom__DOT__rom_ok,
			              (bool)q->tb_sys__DOT__u_snd__DOT__chip__BRA__1__KET____DOT__u_oki__DOT__u_rom__DOT__rom_ok};
			int st[2] = {q->tb_sys__DOT__u_snd__DOT__chip__BRA__0__KET____DOT__u_oki__DOT__u_rom__DOT__st,
			             q->tb_sys__DOT__u_snd__DOT__chip__BRA__1__KET____DOT__u_oki__DOT__u_rom__DOT__st};
			for (int c = 0; c < 2; c++) if (st[c] == 2 && oki_st_prev[c] != 2) {
				oki_takes[c]++;
				if (!ok[c]) { oki_late[c]++; if (oki_late[c] <= 5) printf("late ADPCM byte: chip %d, frame %d\n", c + 1, frame + 1); }
			}
			oki_st_prev[0] = st[0]; oki_st_prev[1] = st[1];
		}
		if (fchk && top->rootp->tb_sys__DOT__u_snd__DOT__f_div == 0) {
			int16_t xi = (int16_t)top->rootp->tb_sys__DOT__u_snd__DOT__mixc, yo = (int16_t)top->rootp->tb_sys__DOT__u_snd__DOT__f_out;
			fwrite(&xi, 2, 1, fchk_in); fwrite(&yo, 2, 1, fchk_out);
		}
		bool take = top->gfx_rd && !dbusy;
		uint32_t ta = top->gfx_addr; int tn = top->gfx_burst;
		tick();
		clocks++; frame_clk++;
		if (take) pend.push_back({clocks + (uint64_t)lat, ta, tn});
		if (top->ce_pix && !top->hblank && !top->vblank) { pix.push_back(top->vid_r); pix.push_back(top->vid_g); pix.push_back(top->vid_b); }
		auto *r = top->rootp;
		if (r->tb_sys__DOT__spr_we) last_vram = frame_clk;
		if (r->tb_sys__DOT__pal_we) last_pal = frame_clk;
		if (okil) {
			if (r->tb_sys__DOT__oki_wr) fprintf(okil, "%d %d %02x\n", frame, r->tb_sys__DOT__oki_wr == 1 ? 1 : 2, r->tb_sys__DOT__oki_wd);
			int b = r->tb_sys__DOT__oki_bank1 << 2 | r->tb_sys__DOT__oki_bank2;
			if (b != okib) { fprintf(okil, "%d bank %d %d\n", frame, b >> 2, b & 3); okib = b; }
		}
		if (wav && ++wav_div == 1266) { wav_div = 0; int16_t v = (int16_t)top->snd; fwrite(&v, 2, 1, wav); wav_n++; }
		if (bus_pos < mrows.size() && bus_bad < busmax && r->tb_sys__DOT__u_main__DOT__bus_req &&
		    r->tb_sys__DOT__u_main__DOT__bus_ack && !r->tb_sys__DOT__u_main__DOT__bus_io) {
			uint32_t a = r->tb_sys__DOT__u_main__DOT__bus_addr, be = r->tb_sys__DOT__u_main__DOT__bus_be;
			bool wr = r->tb_sys__DOT__u_main__DOT__bus_wr;
			uint32_t d = wr ? r->tb_sys__DOT__u_main__DOT__bus_wdata : r->tb_sys__DOT__u_main__DOT__bus_rdata;
			uint32_t lane = (be & 8 ? 0xff000000u : 0) | (be & 4 ? 0x00ff0000u : 0) | (be & 2 ? 0x0000ff00u : 0) |
			                (be & 1 ? 0x000000ffu : 0);
			uint32_t ra = be == 0xf ? a & ~3u : (be == 0xc || be == 0x3) ? a & ~1u : a;
			const BusRow &m = mrows[bus_pos];
			if (m.kind != (wr ? 'W' : 'R') || m.addr != ra || m.mask != lane || (m.data & lane) != (d & lane)) {
				bus_bad++;
				printf("bustrace: access %zu differs (RTL instr %llu, MAME idx %llu, frame %d)\n"
				       "  RTL  %c %08x data %08x lanes %08x\n  MAME %c %08x data %08x mask %08x\n",
				       bus_pos, (unsigned long long)ninstr, (unsigned long long)m.idx, fr1, wr ? 'W' : 'R', ra,
				       d & lane, lane, m.kind, m.addr, m.data & m.mask, m.mask);
			}
			bus_pos++;
		}
		if (top->retire) {
			ninstr++;
			bool idle = idle_hi && top->retire_pc >= idle_lo && top->retire_pc <= idle_hi;
			if (!idle) frame_instr++;
			if (idle && !in_idle) { last_entry = frame_clk; entered = true; }
			in_idle = idle;
			if (!pc_done) {
				if (pc_ok < mame_pc.size() && (top->retire_pc == mame_pc[pc_ok] ||
				    (mame_trap[pc_ok] && top->retire_pc == mame_pc[pc_ok] + 2))) pc_ok++;
				else {
					pc_done = true;
					if (pc_ok < mame_pc.size())
						printf("pctrace: first difference at instruction %llu (frame %d): RTL %08x, MAME %08x\n",
						       (unsigned long long)pc_ok, fr1, top->retire_pc, mame_pc[pc_ok]);
				}
				if (!pc_done && pc_ok == mame_pc.size()) {
					pc_done = true;
					printf("pctrace: all %llu instructions agree\n", (unsigned long long)pc_ok);
				}
			}
		}
		if (top->vblank_irq) {                      // a frame ends: MAME's frame notifier
			frame++;
			if (top->oki_late1 != snd_late[0] || top->oki_late2 != snd_late[1] || top->oki_maxlat1 != snd_wait[0] ||
			    top->oki_maxlat2 != snd_wait[1]) {
				printf("frame %4d: gs_sound late ADPCM bytes %u, %u; longest wait for rom_ok %u, %u clocks\n", frame,
				       top->oki_late1, top->oki_late2, top->oki_maxlat1, top->oki_maxlat2);
				snd_late[0] = top->oki_late1; snd_late[1] = top->oki_late2;
				snd_wait[0] = top->oki_maxlat1; snd_wait[1] = top->oki_maxlat2;
			}
			double b = -1;
			if (idle_hi) {
				if (entered && in_idle) b = (double)last_entry / frame_clk;
				else lost++;
				if (b >= 0) busy.push_back(b);
			}
			if (verbose || frame % 60 == 0)
				printf("frame %4d: %7llu instr outside idle, %5u I-miss, %6u D-miss, %7llu clk, busy %s, last VRAM write "
				       "line %ld, palette %ld, video overruns %u\n",
				       frame, (unsigned long long)frame_instr, top->st_imiss - im0, top->st_dmiss - dm0,
				       (unsigned long long)frame_clk, b < 0 ? (idle_hi ? "lost" : "-") : std::to_string(b).substr(0, 5).c_str(),
				       last_vram < 0 ? -1L : (long)(last_vram / 3888), last_pal < 0 ? -1L : (long)(last_pal / 3888),
				       top->vid_overrun);
			if (std::find(snaps.begin(), snaps.end(), frame) != snaps.end() && pix.size() == 320 * 240 * 3) {
				char p[512];
				snprintf(p, sizeof p, "%s/f%d_rtl.ppm", outd.c_str(), frame);
				FILE *o = fopen(p, "wb"); fprintf(o, "P6\n320 240\n255\n"); fwrite(pix.data(), 1, pix.size(), o); fclose(o);
				auto dump = [&](const char *suffix, auto &m, int n) {
					snprintf(p, sizeof p, "%s/f%d_%s", outd.c_str(), frame, suffix);
					FILE *d = fopen(p, "wb");
					for (int k = 0; k < n; k++) { uint32_t w = m[k]; uint8_t be4[4] = {(uint8_t)(w >> 24), (uint8_t)(w >> 16), (uint8_t)(w >> 8), (uint8_t)w}; fwrite(be4, 1, 4, d); }
					fclose(d);
				};
				dump("vram.bin", r->tb_sys__DOT__u_video__DOT__u_vram__DOT__mem, 4096);
				dump("pal.bin", r->tb_sys__DOT__u_video__DOT__u_pal__DOT__mem, 7168);
				snprintf(p, sizeof p, "%s/f%d_scr.txt", outd.c_str(), frame);
				FILE *d = fopen(p, "w");
				fprintf(d, "%04x %04x %04x %04x %04x %04x\n", r->tb_sys__DOT__scrollx0, r->tb_sys__DOT__scrolly0, r->tb_sys__DOT__scrollx1,
				        r->tb_sys__DOT__scrolly1, r->tb_sys__DOT__scrollx2, r->tb_sys__DOT__scrolly2);
				fclose(d);
			}
			pix.clear();
			if (vdump) {
				auto &vm = r->tb_sys__DOT__u_video__DOT__u_vram__DOT__mem;
				for (int k = 0; k < 4096; k++) {
					uint32_t w = vm[k];
					uint8_t be4[4] = {(uint8_t)(w >> 24), (uint8_t)(w >> 16), (uint8_t)(w >> 8), (uint8_t)w};
					fwrite(be4, 1, 4, vdump);
				}
			}
			last_vram = last_pal = -1;
			im0 = top->st_imiss; dm0 = top->st_dmiss;
			frame_instr = 0; frame_clk = 0; entered = false;
			in_idle = false;
		}
	}
	if (!pc_done) printf("pctrace: %llu of %zu instructions agree (run ended)\n", (unsigned long long)pc_ok, mame_pc.size());
	if (!mrows.empty())
		printf("bustrace: %zu of %zu data accesses compared, %d differ%s\n", bus_pos, mrows.size(), bus_bad,
		       bus_bad >= busmax ? " (stopped at +busmax)" : "");
	if (idle_hi && !busy.empty()) {
		std::vector<double> s = busy;
		std::sort(s.begin(), s.end());
		auto pct = [&](double q) { return s[std::min(s.size() - 1, (size_t)(q * s.size()))]; };
		printf("busy fraction over %zu frames: median %.3f, 90%% %.3f, 99%% %.3f, max %.3f; %d frames lost\n",
		       s.size(), pct(0.5), pct(0.9), pct(0.99), s.back(), lost);
	}
	printf("%d frames, %llu instructions, %llu clocks (%.2f clk/instr), video overrun lines %u, longest pass %u\n", frame,
	       (unsigned long long)ninstr, (unsigned long long)clocks, ninstr ? (double)clocks / ninstr : 0.0, top->vid_overrun, top->vid_maxbusy);
	if (vdump) fclose(vdump);
	printf("ADPCM bytes taken: chip 1 %llu (%llu late), chip 2 %llu (%llu late)\n", (unsigned long long)oki_takes[0],
	       (unsigned long long)oki_late[0], (unsigned long long)oki_takes[1], (unsigned long long)oki_late[1]);
	printf("gs_sound: late ADPCM bytes %u, %u; longest wait for rom_ok %u, %u clocks\n", top->oki_late1, top->oki_late2,
	       top->oki_maxlat1, top->oki_maxlat2);
	if (okil) fclose(okil);
	if (fchk) { fclose(fchk_in); fclose(fchk_out); }
	if (wav) {
		auto le32 = [](uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = v >> (8 * i); };
		uint8_t h[44] = {'R','I','F','F',0,0,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,2,0,16,0,'d','a','t','a'};
		le32(h + 4, 36 + 2 * wav_n); le32(h + 24, 47986); le32(h + 28, 2 * 47986); le32(h + 40, 2 * wav_n);
		fseek(wav, 0, SEEK_SET); fwrite(h, 1, 44, wav); fclose(wav);
	}
	delete top;
	return 0;
}
