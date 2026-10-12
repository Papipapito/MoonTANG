// tb_opl4eng.v — the PCM engine (ymf278b_gowin.v) alone, measured against the
// YMF278B as openMSX models it. No bus glue, no SDRAM: a zero-latency memory
// model answers MA/MDI, CE is 1 on every clock (the engine only counts CEs).
//
// A 64-sample 16-bit sine (±30000) is written into the sample RAM at 201000h
// through registers 02h-06h, with a 12-byte header for tone 384 at 200000h
// (register 02h: WTH = 4 -> headers of tones 384+ at 200000h), the way
// OPL4SIN.BAS of the ZEMMIX does on a real MoonSound. Then:
//
//   T1  pan: slot 0 at TL 0 with PAN = 2 (left -6 dB), then PAN = 1 (-3 dB).
//       Expected L/R: 0.50 and 0.71 (openMSX pan_left, 3 dB per step).
//   T2  TL ramp: key on at TL 3Fh (level direct), then TL 00h WITHOUT level
//       direct: the level must rise towards full over ~850 samples (one
//       step every 13.5 samples), then TL 3Fh without LD: fall over ~1700
//       (one step every 27 samples). openMSX YMF278::advance().
//   T3  decay level: AR 15, D1R 15, DL 4 (-12 dB), D2R 0: the sustain must
//       sit 12 dB below the peak (openMSX dl_tab: 3 dB per step), ratio 0.25.
//   T4  accumulator: 8 slots of the same sine at TL 0: 8 x 30000 = 240000,
//       the chip saturates to 32767 (a 24-slot sum needs 21 bits).
//
// Run: bash tools/sim/opl4eng/run.sh   (prints each measure and PASS/FAIL)
`timescale 1ns/1ps
module tb_opl4eng;

reg clk = 0;
always #13.468 clk = ~clk;              // 37.125 MHz
reg rst_n = 0;

// ---- engine ----
reg  [2:0] a = 0;
reg  [7:0] di = 0;
wire [7:0] dout;
reg        rd_n = 1, wr_n = 1, cs_n = 1;
wire [20:0] ma;
wire [7:0]  mdo;
wire        mrd_n, mwr_n;
wire [9:0]  mcs_n;
wire [4:0]  mem_slot;
wire [5:0]  mix_fm;
wire [15:0] o0l, o0r, o1l, o1r, o2l, o2r;
wire        cycle1_next;
reg  [7:0]  mdi;

YMF278B u_eng (
    .CLK(clk), .RST_N(rst_n), .EN(1'b1), .CE(1'b1),
    .A(a), .DI(di), .DO(dout), .RD_N(rd_n), .WR_N(wr_n), .CS_N(cs_n), .IC_N(rst_n),
    .IRQ_N(), .MA(ma), .MDI(mdi), .MDO(mdo), .MRD_N(mrd_n), .MWR_N(mwr_n), .MCS_N(mcs_n),
    .MEM_SLOT(mem_slot), .MIX_FM(mix_fm),
    .OUT0_L(o0l), .OUT0_R(o0r), .OUT1_L(o1l), .OUT1_R(o1r), .OUT2_L(o2l), .OUT2_R(o2r),
    .SND_EN(3'b111), .CYCLE1_NEXT(cycle1_next)
);

// ---- wave memory: 128 KB at 200000h (the test only uses 200000h-2010FFh),
// read in one clock (the engine samples MDI about 7 CE after MRD_N); the ROM
// half (A21 = 0) is read-only and reads as 00h
reg [7:0] mem [0:(1<<17)-1];
integer mi;
initial for (mi = 0; mi < (1 << 17); mi = mi + 1) mem[mi] = 8'h00;   // no X: the SDRAM holds something
wire [21:0] maddr = {~mcs_n[1], ma};
reg mwr_d = 1;
always @(posedge clk) begin
    mdi   <= maddr[21] ? mem[maddr[16:0]] : 8'h00;
    mwr_d <= mwr_n;
    if (!mwr_n && mwr_d && maddr[21]) mem[maddr[16:0]] <= mdo;
end

// ---- bus: one register write (falling edge of WR_N under CE, CS_N low) ----
task bus_wr(input [2:0] ad, input [7:0] d);
    begin
        @(posedge clk); #1; a = ad; di = d; cs_n = 0; wr_n = 0;
        repeat (2) @(posedge clk); #1; wr_n = 1;
        repeat (14) @(posedge clk); #1; cs_n = 1;
    end
endtask
task wreg(input [7:0] idx, input [7:0] d);     // wave register (7Eh / 7Fh)
    begin bus_wr(3'd4, idx); bus_wr(3'd5, d); end
endtask
task set_addr(input [21:0] ad);
    begin wreg(8'h03, ad[21:16]); wreg(8'h04, ad[15:8]); wreg(8'h05, ad[7:0]); end
endtask
task wait_samples(input integer n);
    repeat (n * 768) @(posedge clk);
endtask

// ---- peak of |OUT1| over n samples (one sample = 768 CE) ----
integer pk_l, pk_r;
task peak(input integer n);
    integer i, v;
    begin
        pk_l = 0; pk_r = 0;
        for (i = 0; i < n * 768; i = i + 1) begin
            @(posedge clk);
            v = $signed(o1l); if (v < 0) v = -v; if (v > pk_l) pk_l = v;
            v = $signed(o1r); if (v < 0) v = -v; if (v > pk_r) pk_r = v;
        end
    end
endtask

task engine_reset;
    begin
        rst_n = 0; repeat (20) @(posedge clk); #1; rst_n = 1; repeat (20) @(posedge clk);
        bus_wr(3'd2, 8'h05); bus_wr(3'd3, 8'h03);      // NEW2
        wreg(8'h02, 8'h10);                              // WTH = 4, MA = 0
        wait_samples(2);
    end
endtask

// header of tone 384 at 200000h: 16-bit, start 201000h, loop 0, end 65536 - 64
task header(input [7:0] ar_d1r, input [7:0] dl_d2r);
    begin
        wreg(8'h02, 8'h11);                              // MA = 1
        set_addr(22'h200000);
        wreg(8'h06, 8'hA0); wreg(8'h06, 8'h10); wreg(8'h06, 8'h00);
        wreg(8'h06, 8'h00); wreg(8'h06, 8'h00);
        wreg(8'h06, 8'hFF); wreg(8'h06, 8'hC0);
        wreg(8'h06, 8'h00); wreg(8'h06, ar_d1r); wreg(8'h06, dl_d2r);
        wreg(8'h06, 8'h0F); wreg(8'h06, 8'h00);
        wreg(8'h02, 8'h10);                              // MA = 0
    end
endtask

// slot s: tone 384 at OCT 0 / FN 0 (read at 22.05 kHz: the 64 samples last
// 128 output samples), TL with or without level direct, key on with a pan
task slot_tone(input [4:0] s);
    begin
        wreg(8'h20 + s, 8'h01);                          // FN low = 0, tone bit 8
        wreg(8'h38 + s, 8'h00);                          // OCT 0, FN high 0
        wreg(8'h08 + s, 8'h80);                          // tone 384 -> loads the header
        wait_samples(20);
    end
endtask
task slot_tl(input [4:0] s, input [6:0] tl, input ld);
    wreg(8'h50 + s, {tl, ld});
endtask
task slot_key(input [4:0] s, input on, input [3:0] pan);
    wreg(8'h68 + s, {on, 3'b000, pan});
endtask

integer nsc, dump = 0;
task sign_changes(input integer n);           // of OUT1_L, one sample per 768 CE
    integer i, prev, cur;
    begin
        nsc = 0; prev = 0;
        for (i = 0; i < n; i = i + 1) begin
            repeat (768) @(posedge clk);
            if (dump) $fwrite(dump, "%0d %0d\n", $signed(o1l), $signed(o1r));
            cur = $signed(o1l) < 0 ? -1 : ($signed(o1l) > 0 ? 1 : prev);
            if (i > 0 && cur != prev) nsc = nsc + 1;
            prev = cur;
        end
    end
endtask

integer i, errors, ref_l, p0, p1, p2, p3;
real r;
task check(input ok, input [255:0] what);
    begin
        if (ok) $display("  [ok]   %0s", what);
        else begin $display("  [FAIL] %0s", what); errors = errors + 1; end
    end
endtask

initial begin
    errors = 0;
    // the sine in RAM (high byte first), written like OPL4SIN.BAS
    engine_reset;
    wreg(8'h02, 8'h11);
    set_addr(22'h201000);
    for (i = 0; i < 64; i = i + 1) begin
        r = 30000.0 * $sin(6.283185307 * i / 64.0);
        wreg(8'h06, $rtoi(r) >> 8 & 8'hFF);
        wreg(8'h06, $rtoi(r) & 8'hFF);
    end
    wreg(8'h02, 8'h10);
    header(8'hF0, 8'h00);                                 // AR 15, D1R 0, DL 0, D2R 0

    // ---- T1: pan ----
    $display("T1 pan (3 dB per step)");
    engine_reset;
    slot_tone(0);
    slot_tl(0, 7'd0, 1'b1);
    slot_key(0, 1'b1, 4'd0);
    wait_samples(300); peak(128); ref_l = pk_l;
    dump = $fopen("build/t1_samples.txt", "w");
    sign_changes(512);
    $fclose(dump); dump = 0;
    $display("  PAN 0: L %0d R %0d, sign changes in 512 samples: %0d (8 = period of 128)", pk_l, pk_r, nsc);
    check(pk_l > 25000 && pk_r > 25000, "PAN 0: full level on both sides");
    slot_key(0, 1'b1, 4'd2);
    wait_samples(300); peak(128);
    $display("  PAN 2: L %0d R %0d  L/R = %0.3f (expected 0.50)", pk_l, pk_r, 1.0 * pk_l / pk_r);
    check(pk_l > pk_r * 0.44 && pk_l < pk_r * 0.56, "PAN 2: left at -6 dB");
    slot_key(0, 1'b1, 4'd1);
    wait_samples(300); peak(128);
    $display("  PAN 1: L %0d R %0d  L/R = %0.3f (expected 0.71)", pk_l, pk_r, 1.0 * pk_l / pk_r);
    check(pk_l > pk_r * 0.63 && pk_l < pk_r * 0.79, "PAN 1: left at -3 dB");
    slot_key(0, 1'b0, 4'd0);

    // ---- T2: TL ramp ----
    $display("T2 TL ramp (openMSX: +1 step / 13.5 samples louder, / 27 softer)");
    engine_reset;
    slot_tone(0);
    slot_tl(0, 7'h3F, 1'b1);                              // quiet, level direct
    slot_key(0, 1'b1, 4'd0);
    wait_samples(300); peak(128); p0 = pk_l;
    slot_tl(0, 7'h00, 1'b0);                              // loud, ramp
    wait_samples(300); peak(128); p1 = pk_l;
    wait_samples(300); peak(128); p2 = pk_l;
    wait_samples(1000); peak(128); p3 = pk_l;
    $display("  TL 3Fh: %0d; TL 00h after 300: %0d, 700: %0d, 1800: %0d", p0, p1, p2, p3);
    check(p1 > p0 && p2 > p1 && p3 >= p2, "TL 3Fh -> 00h: the level rises");
    check(p3 > 25000, "TL 00h reached (full level)");
    check(p1 < 25000 && p2 > p1, "it is a ramp, not a jump (~850 samples)");
    p0 = p3;
    slot_tl(0, 7'h3F, 1'b0);                              // quiet, ramp
    wait_samples(500); peak(128); p1 = pk_l;
    wait_samples(500); peak(128); p2 = pk_l;
    wait_samples(1500); peak(128); p3 = pk_l;
    $display("  TL 00h -> 3Fh after 500: %0d, 1100: %0d, 2700: %0d", p1, p2, p3);
    check(p1 < p0 && p2 < p1 && p3 <= p2, "TL 00h -> 3Fh: the level falls");
    check(p3 < ref_l / 8, "TL 3Fh reached (below -18 dB)");
    slot_key(0, 1'b0, 4'd0);

    // ---- T3: decay level ----
    $display("T3 decay level (DL 4 = -12 dB, 3 dB per step)");
    header(8'hFF, 8'h40);                                 // AR 15, D1R 15, DL 4, D2R 0
    engine_reset;
    slot_tone(0);
    slot_tl(0, 7'd0, 1'b1);
    slot_key(0, 1'b1, 4'd0);
    wait_samples(400); peak(128);
    $display("  sustain: L %0d  of %0d = %0.3f (expected 0.25)", pk_l, ref_l, 1.0 * pk_l / ref_l);
    check(pk_l > ref_l * 0.21 && pk_l < ref_l * 0.30, "sustain 12 dB below the peak");
    slot_key(0, 1'b0, 4'd0);
    header(8'hF0, 8'h00);

    // ---- T4: accumulator ----
    $display("T4 accumulator (8 slots x 30000 saturate to 32767)");
    engine_reset;
    for (i = 0; i < 8; i = i + 1) begin
        slot_tone(i[4:0]);
        slot_tl(i[4:0], 7'd0, 1'b1);
    end
    for (i = 0; i < 8; i = i + 1) slot_key(i[4:0], 1'b1, 4'd0);
    wait_samples(300); peak(128);
    // a saturated sine keeps the sign of the sine: 2 zero crossings per period
    // (128 samples); a sum that wraps round changes sign at every peak
    dump = $fopen("build/t4_samples.txt", "w");
    sign_changes(512);
    $fclose(dump); dump = 0;
    $display("  8 slots: peak L %0d R %0d, sign changes in 4 periods: %0d (8 if saturated)", pk_l, pk_r, nsc);
    check(pk_l >= 32767 && nsc >= 6 && nsc <= 10, "the sum saturates (no wrap at the peaks)");

    if (errors == 0) $display("RESULTADO: PASS");
    else             $display("RESULTADO: FAIL (%0d)", errors);
    $finish;
end

endmodule
