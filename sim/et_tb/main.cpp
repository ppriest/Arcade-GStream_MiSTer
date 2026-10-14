// SPDX-License-Identifier: GPL-3.0-or-later
// gs_et_scan against the empty-tile table computed here from the image (SD_SPR, 65,536 tiles of 256 bytes).
//   run_verilator.sh et_tb +img=<image.bin> [+lat=N] [+busy=P]
#include "Vtb_et.h"
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
	for (int i = 1; i < argc; i++) if (!strncmp(argv[i], key, n)) return std::string(argv[i] + n);
	return def;
}
int main(int argc, char **argv) {
#ifdef _WIN32
	_fmode = _O_BINARY;
#endif
	Verilated::commandArgs(argc, argv);
	FILE *f = fopen(arg(argc, argv, "+img=").c_str(), "rb");
	if (!f) { fprintf(stderr, "no +img\n"); return 2; }
	std::vector<uint8_t> img(0x2100000);
	if (fread(img.data(), 1, img.size(), f) != img.size()) { fprintf(stderr, "short image\n"); return 2; }
	fclose(f);
	int lat = atoi(arg(argc, argv, "+lat=", "40").c_str()), busy_pct = atoi(arg(argc, argv, "+busy=", "30").c_str());
	std::vector<uint8_t> want(8192, 0), got(8192, 0xaa);
	for (int t = 0; t < 65536; t++) {
		bool z = true;
		for (int i = 0; i < 256 && z; i++) z = img[0x500000 + (size_t)t * 256 + i] == 0;
		if (z) want[t >> 3] |= 1 << (t & 7);
	}
	Vtb_et *t = new Vtb_et;
	auto tick = [&]() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); };
	t->start = 0; t->ddr_busy = 0; t->dv = 0;
	tick(); t->start = 1; tick(); t->start = 0;
	struct B { uint64_t at; uint64_t word; int n; };
	std::deque<B> pend;
	uint64_t clk = 0; int writes = 0;
	srand(3);
	while (t->busy && clk < 100000000) {
		bool busy = (rand() % 100) < busy_pct;
		t->ddr_busy = busy; t->dv = 0;
		if (!pend.empty() && clk >= pend.front().at) {
			B &b = pend.front();
			uint64_t w = 0;
			size_t byte = (size_t)(b.word - 0x6000000) * 8;   // DDRAM_ADDR's 0x30000000 base
			for (int i = 0; i < 8; i++) w |= (uint64_t)img[byte + i] << (8 * i);
			t->dv = 1; t->dout = w; b.word++; b.at = clk + 1;
			if (--b.n == 0) pend.pop_front();
		}
		t->eval();
		bool take = t->rd && !busy;
		uint32_t a = t->addr; int n = t->burst;
		tick(); clk++;
		if (take) pend.push_back({clk + (uint64_t)lat, a, n});
		if (t->et_we) { got[t->et_addr] = t->et_data; writes++; }
	}
	int bad = 0;
	for (int a = 0; a < 8192; a++) if (got[a] != want[a]) { if (bad < 5) printf("byte %d: got %02x want %02x\n", a, got[a], want[a]); bad++; }
	printf("%llu clocks, %d table writes, %d of 8192 bytes differ\n", (unsigned long long)clk, writes, bad);
	delete t;
	return bad ? 1 : 0;
}
