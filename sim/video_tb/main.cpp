// SPDX-License-Identifier: GPL-3.0-or-later
// Video bench: one captured frame through gs_video.
//
//   run_verilator.sh video_tb +img=<image.bin> +cap=<dir>/f<N> +out=<file.ppm> [+lat=N] [+busy=P] [+flip=1]
//
// +cap names a capture of scripts/gs_capture.py (f<N>_vram.bin, _pal.bin, _scr.txt). The VRAM and palette go in
// through the CPU ports, the scroll registers as inputs, the empty-sprite-tile table is computed from the image's
// sprites (SD_SPR, 16 MB), and the DDR3 port reads the image: a burst's beats come back in order, +lat clocks after
// it is accepted (default 30), one a clock; with +busy=P the port is busy in P% of clocks. The second frame's
// visible 320 x 240 is written to +out; scripts/video_check.py compares it with render_model.py's frame.
#include "Vtb_video.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <deque>
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
	std::string cap = arg(argc, argv, "+cap=");
	std::vector<uint8_t> vram = slurp(cap + "_vram.bin"), pal = slurp(cap + "_pal.bin");
	unsigned scr[6] = {0};
	{
		FILE *f = fopen((cap + "_scr.txt").c_str(), "r");
		if (!f || fscanf(f, "%x %x %x %x %x %x", &scr[0], &scr[1], &scr[2], &scr[3], &scr[4], &scr[5]) != 6) {
			fprintf(stderr, "cannot read %s_scr.txt\n", cap.c_str()); return 2;
		}
		fclose(f);
	}
	int lat = atoi(arg(argc, argv, "+lat=", "30").c_str());
	int busy_pct = atoi(arg(argc, argv, "+busy=", "0").c_str());
	const size_t SD_SPR = 0x500000;

	Vtb_video *t = new Vtb_video;
	auto tick = [&]() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); };
	t->rst = 1; t->spr_we = 0; t->pal_we = 0; t->et_we = 0; t->gfx_busy = 0; t->gfx_dv = 0;
	t->scrollx0 = scr[0]; t->scrolly0 = scr[1]; t->scrollx1 = scr[2]; t->scrolly1 = scr[3];
	t->scrollx2 = scr[4]; t->scrolly2 = scr[5];
	t->flip = atoi(arg(argc, argv, "+flip=", "0").c_str());
	for (int i = 0; i < 4; i++) tick();
	for (int a = 0; a < 4096; a++) {
		t->spr_we = 1; t->spr_be = 0xf; t->spr_addr = a;
		t->spr_wd = (uint32_t)vram[4 * a] << 24 | vram[4 * a + 1] << 16 | vram[4 * a + 2] << 8 | vram[4 * a + 3];
		tick();
	}
	t->spr_we = 0;
	for (int a = 0; a < 7168; a++) {
		t->pal_we = 1; t->pal_be = 0xf; t->pal_addr = a;
		t->pal_wd = (uint32_t)pal[4 * a] << 24 | pal[4 * a + 1] << 16 | pal[4 * a + 2] << 8 | pal[4 * a + 3];
		tick();
	}
	t->pal_we = 0;
	int empty = 0;
	for (int a = 0; a < 8192; a++) {
		uint8_t byte = 0;
		for (int k = 0; k < 8; k++) {
			const uint8_t *tile = &img[SD_SPR + (size_t)(8 * a + k) * 256];
			bool z = true;
			for (int i = 0; i < 256 && z; i++) z = tile[i] == 0;
			if (z) { byte |= 1 << k; empty++; }
		}
		t->et_we = 1; t->et_addr = a; t->et_data = byte;
		tick();
	}
	t->et_we = 0;
	printf("empty sprite tiles: %d\n", empty);
	t->rst = 0;

	struct Burst { uint64_t at; uint32_t addr; int n; };
	std::deque<Burst> pend;
	uint64_t clk = 0, beats = 0;
	srand(1);
	int frame = 0;
	std::vector<uint8_t> pix;
	int prev_vb = 1;
	std::string outp = arg(argc, argv, "+out=");
	while (frame < 2) {
		// DDR3 model: accept a burst when not busy; return its beats in order after the latency
		bool busy = busy_pct > 0 && (rand() % 100) < busy_pct;
		t->gfx_busy = busy;
		t->gfx_dv = 0;
		if (!pend.empty() && clk >= pend.front().at) {
			Burst &bu = pend.front();
			uint64_t w = 0;
			for (int i = 0; i < 8; i++) w |= (uint64_t)img[(size_t)bu.addr * 8 + i] << (8 * i);
			t->gfx_dv = 1; t->gfx_dout = w;
			beats++;
			bu.addr++; bu.at = clk + 1;
			if (--bu.n == 0) pend.pop_front();
		}
		t->eval();
		bool take = t->gfx_rd && !busy;
		uint32_t ta = t->gfx_addr; int tn = t->gfx_burst;
		tick();
		clk++;
		if (take) pend.push_back({clk + (uint64_t)lat, ta, tn});
		if (t->ce_pix) {
			if (frame == 1 && !t->hblank && !t->vblank) { pix.push_back(t->r); pix.push_back(t->g); pix.push_back(t->b); }
			if (!prev_vb && t->vblank) frame++;
			prev_vb = t->vblank;
		}
	}
	printf("%llu clocks, %llu beats, overrun lines %u, longest pass %u clocks of 3888\n", (unsigned long long)clk,
	       (unsigned long long)beats, t->dbg_overrun, t->dbg_maxbusy);
	if (pix.size() != 320 * 240 * 3) { fprintf(stderr, "frame has %zu bytes\n", pix.size()); return 1; }
	FILE *o = fopen(outp.c_str(), "wb");
	fprintf(o, "P6\n320 240\n255\n");
	fwrite(pix.data(), 1, pix.size(), o);
	fclose(o);
	delete t;
	return 0;
}
