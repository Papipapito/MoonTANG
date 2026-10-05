// tb_timer_stop.cpp - el temporizador del OPL3 parado en el ciclo critico.
//
// Si el timer se para justo cuando su preescalador vale TICK-1, el codigo
// original seguia dando ticks en cada ciclo: el timer parado desbordaba sin
// parar y los flags y /INT volvian despues de cada ack y de cada /RESET.
// Este banco para el timer exactamente en ese ciclo de varias maneras (00h, 78h,
// /RESET, 40h con el timer en FF) y comprueba que el estado queda limpio, y que
// los periodos normales no cambian (T1 = 80 us x n, T2 = 320 us x n).
// DUT: opl4fm.v (54/27 MHz) con el nucleo OPL3 de MoonTANG. Verilator.
#include "verilated.h"
#include "Vopl4fm.h"
#include "Vopl4fm___024root.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#define TM(x) d->rootp->opl4fm__DOT__u_opl3__DOT__genblk1__DOT__timers__DOT__##x
static Vopl4fm *d;
static uint64_t now = 0, nxH = 9259, nxO = 9259;
static const uint64_t hpH = 9259, hpO = 18518, T = 279365;
static uint64_t ocyc = 0;                     // flancos de subida de clk_opl3
static int st1_prev = 0, ft1_prev = 0;
static int stop_tick = -1, stop_pulse = -1, stop_tmr = -1;
static std::vector<uint64_t> ft1_rise;
static unsigned tick1() { return (unsigned)TM(timer1_inst__DOT__tick_counter); }
static void step() {
    uint64_t e = nxH < nxO ? nxH : nxO; now = e;
    bool orise = false;
    if (nxH == e) { d->clk_host = !d->clk_host; nxH += hpH; }
    if (nxO == e) { d->clk_opl3 = !d->clk_opl3; nxO += hpO; if (d->clk_opl3) { orise = true; ocyc++; } }
    d->eval();
    if (orise) {
        int s = TM(st1), f = TM(ft1);
        if (st1_prev && !s) { stop_tick = tick1(); stop_pulse = TM(timer1_inst__DOT__tick_pulse); stop_tmr = TM(timer1_inst__DOT__timer); }
        if (!ft1_prev && f) ft1_rise.push_back(ocyc);
        st1_prev = s; ft1_prev = f;
    }
}
static void run_to(uint64_t t) { while ((nxH < nxO ? nxH : nxO) <= t) step(); now = t; }
static void tst(double n) { run_to(now + (uint64_t)(n * T)); }
static void us(double n) { run_to(now + (uint64_t)(n * 1e6)); }
static void io_wr(uint8_t port, uint8_t v) {
    d->addr = port; d->din = v; d->eval(); tst(1);
    d->iorq_n = 0; d->wr_n = 0; d->eval(); tst(2.5);
    d->iorq_n = 1; d->wr_n = 1; d->eval(); tst(0.5);
}
static uint8_t io_rd(uint8_t port) {
    d->addr = port; d->eval(); tst(1);
    d->iorq_n = 0; d->rd_n = 0; d->eval(); tst(2.5);
    uint8_t v = d->dout; d->iorq_n = 1; d->rd_n = 1; d->eval(); tst(0.5); return v;
}
static void wr(uint8_t r, uint8_t v) { tst(7); io_wr(0xC4, r); tst(15); io_wr(0xC5, v); tst(10); }
static void wait_tick(unsigned v) { long n = 0; while (tick1() != v) { step(); if (++n > 400000000L) { printf("TIMEOUT wait_tick\n"); return; } } }
static void wait_tmr(unsigned v) { long n = 0; while ((unsigned)TM(timer1_inst__DOT__timer) != v || tick1() > 50) { step(); if (++n > 400000000L) { printf("TIMEOUT wait_tmr\n"); return; } } }
static int L = 0;
static int errors = 0, checks = 0;
static void ok(bool c, const char *what) { checks++; if (!c) { errors++; printf("  [FAIL] %s\n", what); } else printf("  [ok]   %s\n", what); }
static void data_strobe(uint8_t v) { d->addr = 0xC5; d->din = v; d->iorq_n = 0; d->wr_n = 0; d->eval(); tst(2.5); d->iorq_n = 1; d->wr_n = 1; d->eval(); tst(10); }
// escribe reg4=v con el dato cayendo de forma que st1 baje con tick==target
static void stop_at(uint8_t v, unsigned target, bool want_ff) {
    tst(7); io_wr(0xC4, 4); tst(15);
    if (want_ff) wait_tmr(0xFF);
    stop_tick = -1;
    wait_tick(target - L);
    data_strobe(v);
}
static void sane() { wr(4, 0x60); wr(4, 0x80); wr(4, 0x01); us(20); wr(4, 0x60); wr(4, 0x80); us(100); ft1_rise.clear(); }
static uint64_t first_ft1_after(uint8_t v) {
    wr(4, 0x80); ft1_rise.clear();
    tst(7); io_wr(0xC4, 4); tst(15); uint64_t c0 = ocyc; io_wr(0xC5, v);
    long g = 0; while (ft1_rise.empty() && ++g < 100000000L) step();
    return ft1_rise.empty() ? 0 : ft1_rise[0] - c0;
}
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const char *var = argc > 1 ? argv[1] : "?";
    const unsigned TICK = 2160;
    d = new Vopl4fm;
    d->rst_n = 0; d->iorq_n = 1; d->rd_n = 1; d->wr_n = 1; d->m1_n = 1; d->addr = 0; d->din = 0; d->wave_status = 0;
    d->clk_host = 0; d->clk_opl3 = 0; d->eval();
    us(5); d->rst_n = 1; us(200);
    printf("===== variante %s =====\n", var);
    // calibrar latencia WR(dato) -> st1=0
    wr(2, 0xF5); wr(4, 0x80); wr(4, 0x41); us(200);
    tst(7); io_wr(0xC4, 4); tst(15); wait_tick(1000); stop_tick = -1; data_strobe(0x40);
    L = stop_tick - 1000;
    printf("[cal] latencia WR->st1 = %d ciclos de 27 MHz\n", L);

    // R1: periodos con el patron VGMPlay (80h, 39h, ISR ack 0BFh)
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x39);
    for (int i = 0; i < 6; i++) {
        size_t n0 = ft1_rise.size(); long g = 0; while (ft1_rise.size() == n0 && ++g < 100000000L) step();
        us(10); tst(7); io_wr(0xC4, 4); uint8_t s = io_rd(0xC4); if (s & 0x40) io_wr(0xC5, (uint8_t)~0x40);
    }
    printf("[R1] T1=F5 con ack 0BFh: periodos =");
    for (size_t i = 1; i < ft1_rise.size(); i++) printf(" %llu", (unsigned long long)(ft1_rise[i] - ft1_rise[i-1]));
    printf("  (esperado 23760)\n");
    { bool g = ft1_rise.size() >= 4; for (size_t i = 1; i < ft1_rise.size(); i++) g = g && (ft1_rise[i] - ft1_rise[i-1] == 23760);
      ok(g, "timer 1 (F5h, ack BFh como VGMPlay): periodo de 23760 ciclos = 880 us"); }
    wr(4, 0x78); us(50);
    // R2: T2=FF, ack 80h
    sane(); wr(3, 0xFF); wr(4, 0x80); wr(4, 0x02);
    { std::vector<uint64_t> r; for (int i = 0; i < 4; i++) { uint64_t c0 = ocyc;
        while (!TM(ft2) && ocyc - c0 < 100000) step(); r.push_back(ocyc); us(5); wr(4, 0x80); }
      printf("[R2] T2=FF ack 80h: periodos ="); for (size_t i = 1; i < r.size(); i++) printf(" %llu", (unsigned long long)(r[i]-r[i-1])); printf("  (esperado 8640)\n");
      bool g = r.size() >= 3; for (size_t i = 1; i < r.size(); i++) g = g && (r[i] - r[i-1] == 8640);
      ok(g, "timer 2 (FFh, ack 80h): periodo de 8640 ciclos = 320 us"); }
    wr(4, 0x60); wr(4, 0x80); us(50);
    // R3: parada y rearranque normales
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x01); us(300); wr(4, 0x40); us(500);
    { uint64_t f = first_ft1_after(0x01);
      printf("[R3] rearranque normal: primer FT1 a %llu ciclos del WR (esperado ~23760 + latencia)\n", (unsigned long long)f);
      ok(f >= 23760 && f <= 23800, "parada y rearranque normales: el primer desbordamiento llega a su tiempo"); }
    wr(4, 0x60); wr(4, 0x80); us(50);

    // F2: parada SIN mascara (00h) en el ciclo critico
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x01); us(200); wr(4, 0x80);
    stop_at(0x00, TICK - 1, false);
    printf("[F2] 00h critico: tick en la parada=%d (TICK-1=%u) tick_pulse=%d", stop_tick, TICK - 1, stop_pulse);
    us(1000); { uint8_t s1 = io_rd(0xC4); wr(4, 0x80); us(100); uint8_t s2 = io_rd(0xC4); int i2 = d->int_n;
      printf(" | 1 ms despues status=%02X; tras ack 80h status=%02X /INT=%d", s1, s2, i2);
      d->rst_n = 0; us(50); d->rst_n = 1; us(1000);
      uint8_t s3 = io_rd(0xC4); int i3 = d->int_n;
      printf(" | tras /RESET status=%02X /INT=%d\n", s3, i3);
      ok(s2 == 0x00 && i2 == 1, "parada sin mascara (00h) en el ciclo critico: el ack limpia y /INT se suelta");
      ok(s3 == 0x00 && i3 == 1, "  y tras un /RESET sigue limpio"); }
    // F3: /RESET con T1 en marcha en el ciclo critico
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x01); us(200);
    wait_tick(1000); stop_tick = -1; d->rst_n = 0; us(5); int Lr = stop_tick - 1000; d->rst_n = 1; us(300);
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x01); us(200);
    wait_tick(TICK - 1 - Lr); stop_tick = -1; d->rst_n = 0; us(50); d->rst_n = 1; us(1000);
    { uint8_t s = io_rd(0xC4); int i = d->int_n;
      printf("[F3] /RESET critico (lat=%d): tick en la parada=%d; 1 ms despues status=%02X /INT=%d\n", Lr, stop_tick, s, i);
      ok(s == 0x00 && i == 1, "/RESET del MSX en el ciclo critico: nada se queda contando"); }
    // F4: Stop 78h en el ciclo critico y luego /RESET
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x39); us(200); wr(4, 0x80);
    stop_at(0x78, TICK - 1, false); us(2000);
    { uint8_t s1 = io_rd(0xC4); int i1 = d->int_n;
      printf("[F4] 78h critico: tick en la parada=%d; 2 ms despues status=%02X /INT=%d", stop_tick, s1, i1);
      d->rst_n = 0; us(50); d->rst_n = 1; us(1000);
      uint8_t s2 = io_rd(0xC4); int i2 = d->int_n;
      printf(" | tras /RESET status=%02X /INT=%d\n", s2, i2);
      ok(s1 == 0x00 && i1 == 1 && s2 == 0x00 && i2 == 1, "parada de VGMPlay (78h) en el ciclo critico, y /RESET despues: limpio"); }
    // F5: parada ENMASCARADA (40h) en el ciclo critico con timer==FF; luego rearranque sin mascara (01h)
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x41); us(200);
    stop_at(0x40, TICK - 1, true);
    printf("[F5] 40h critico con timer=FF: tick=%d timer=%02X;", stop_tick, stop_tmr);
    us(500);
    { uint64_t f = first_ft1_after(0x01);
      printf(" rearranque 01h: primer FT1 a %llu ciclos del WR (normal ~23760)\n", (unsigned long long)f);
      ok(f >= 23760 && f <= 23800, "parada enmascarada (40h) con el timer en FF: el rearranque no da un desbordamiento espurio"); }
    wr(4, 0x60); wr(4, 0x80); us(50);
    // F6: parada SIN mascara (00h) en el ciclo critico con timer==FF
    sane(); wr(2, 0xF5); wr(4, 0x80); wr(4, 0x01); us(200); wr(4, 0x80);
    stop_at(0x00, TICK - 1, true); us(100);
    { uint8_t s1 = io_rd(0xC4); wr(4, 0x80); us(1000); uint8_t s2 = io_rd(0xC4);
      int i2 = d->int_n;
      printf("[F6] 00h critico con timer=FF: tick=%d timer=%02X; status=%02X; tras ack 80h y 1 ms status=%02X /INT=%d\n", stop_tick, stop_tmr, s1, s2, i2);
      ok(s2 == 0x00 && i2 == 1, "parada sin mascara con el timer en FF: el ack limpia y /INT se suelta"); }
    printf("== %d comprobaciones, %d errores ==\n", checks, errors);
    printf(errors == 0 ? "RESULTADO: PASS\n" : "RESULTADO: FAIL\n");
    d->final(); delete d; return errors ? 1 : 0;
}
