// ============================================================================
// tb_mix.v — la mezcla del Y8950 (moontang_mix_y8950.v, el modulo que usa
// moontang_core) con el limitador de rodilla, y el FM real de jtopl
// (moontang_y8950.sv) tocando acordes fuertes.
//
//   A. limitador, exhaustivo sobre los 2^20 valores de entrada de la etapa 2:
//      identidad hasta la rodilla (+-24 576), pendiente 1/2 por encima, tope
//      +-32 767, monotono y simetrico.
//   B. una portadora FM a tope (+-20 500 tras el x5): pasa sin tocar.
//   C. acorde de 3 portadoras a tope (TL = 0) y de 6 canales a TL = 8: cuantas
//      muestras se recortarian contra el rail SIN limitador y cuantas llegan al
//      rail CON el. El limitador tiene que reducirlas (no puede quitarlas: el
//      x5 deja margen para ~1,6 portadoras; ver moontang_mix_y8950.v).
//
// Uso: tools/sim/y8950/run.sh mix   (WSL, Icarus; unos minutos)
// Ojo: jtopl solo sale de X en Icarus con un reset largo (aqui 100 us; en la
// FPGA no hay X: el GSR lo pone todo a 0). Y necesita ~23 us entre escrituras
// de datos (como el Y8950 real): y_w espera 30 us.
// ============================================================================
`timescale 1ns/1ps
module tb_mix;
    reg clk54 = 0, clk108 = 0;
    always #(9.259259) clk54 = ~clk54;
    initial #2 forever #(4.6296296) clk108 = ~clk108;
    reg rst_n = 0;
    reg iorq_n = 1, rd_n = 1, wr_n = 1, m1_n = 1;
    reg [7:0] addr = 0, din = 8'hFF;
    wire rd; wire [7:0] dout; wire int_n;
    wire signed [15:0] fm, adpcm;
    wire wv2_req, wv2_we; wire [21:0] wv2_addr; wire [7:0] wv2_wdata;
    reg [15:0] wv2_dout = 0; reg wv2_done = 0;
    moontang_y8950 dut (.clk_54m(clk54), .clk_108m(clk108), .rst_n(rst_n),
        .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n), .addr(addr), .din(din),
        .rd(rd), .dout(dout), .int_n(int_n), .fm(fm), .adpcm(adpcm),
        .wv2_req(wv2_req), .wv2_we(wv2_we), .wv2_addr(wv2_addr), .wv2_wdata(wv2_wdata),
        .wv2_dout(wv2_dout), .wv2_done(wv2_done));
    // RAM del ADPCM (contrato wv_*), sin uso aqui salvo que el chip la pida
    reg busy = 0; integer cnt = 0;
    always @(posedge clk108) begin
        wv2_done <= 0;
        if (!busy && wv2_req) begin busy <= 1; cnt <= 0; end
        else if (busy && cnt == 12) begin wv2_dout <= 16'h0000; wv2_done <= 1; cnt <= cnt + 1; end
        else if (busy && cnt > 12) begin if (!wv2_req) busy <= 0; end
        else if (busy) cnt <= cnt + 1;
    end

    reg  signed [17:0] mixL = 0, mixR = 0;          // OPL4 callado
    wire signed [15:0] out_l, out_r, out_mono;
    moontang_mix_y8950 u_mix (.clk_54m(clk54), .mixL(mixL), .mixR(mixR),
        .y8950_fm(fm), .y8950_adpcm(adpcm), .out_l(out_l), .out_r(out_r), .out_mono(out_mono));

    // ---- bus (con el /WR retrasado de la WonderTANG) ----
    task io_wr(input [7:0] p, input [7:0] d); begin
        @(negedge clk54); addr = p; m1_n = 1; din = d; iorq_n = 0;
        repeat (5) @(negedge clk54); wr_n = 0;
        repeat (12) @(negedge clk54); din = 8'hFF;
        repeat (4) @(negedge clk54); wr_n = 1; iorq_n = 1;
        repeat (4) @(negedge clk54);
    end endtask
    task y_w(input [7:0] r, input [7:0] d); begin
        io_wr(8'hC0, r); #4000; io_wr(8'hC1, d); #26000;
    end endtask

    integer errors = 0, checks = 0;
    task ok(input c, input [8*120-1:0] s); begin
        checks = checks + 1;
        if (c === 1'b1) $display("  [ok]   %0s", s); else begin $display("  [FAIL] %0s", s); errors = errors + 1; end
    end endtask

    // ---- medida: entrada del limitador (sM) y salida (out_mono) ----
    integer pmax, pmin, omax, omin, n_hard, n_rail, n_comp, n_samp, n_diff;
    reg meas = 0;
    task clr; begin pmax=0; pmin=0; omax=0; omin=0; n_hard=0; n_rail=0; n_comp=0; n_samp=0; n_diff=0; end endtask
    always @(posedge clk54) if (meas && dut.cen) begin       // una muestra por tick del chip
        n_samp = n_samp + 1;
        if (u_mix.sM > pmax) pmax = u_mix.sM; if (u_mix.sM < pmin) pmin = u_mix.sM;
        if (out_mono > omax) omax = out_mono; if (out_mono < omin) omin = out_mono;
        if (u_mix.sM > 32767 || u_mix.sM < -32768) n_hard = n_hard + 1;   // recorte duro (sin limitador)
        if (out_mono >= 32767 || out_mono <= -32767) n_rail = n_rail + 1; // en el rail con limitador
        if (u_mix.sM > 24576 || u_mix.sM < -24576) n_comp = n_comp + 1;   // comprimidas
        if (out_mono != u_mix.sM) n_diff = n_diff + 1;
    end

    // ---- A: modelo del limitador ----
    function integer kmodel(input integer v);
        integer a, y;
        begin
            a = (v < 0) ? -v : v;
            y = (a <= 24576) ? a : 24576 + (a - 24576) / 2;
            if (y > 32767) y = 32767;
            kmodel = (v < 0) ? -y : y;
        end
    endfunction

    integer v, o, oprev, bad_id, bad_mod, bad_mono, bad_sym, bad_cap, ch;
    reg [7:0] fnl [0:8]; reg [7:0] fnh [0:8];
    reg [7:0] mo;
    integer o_pos;
    initial begin
        clr;
        // ============================================================
        $display("== A. limitador, exhaustivo (2^20 entradas) ==");
        bad_id = 0; bad_mod = 0; bad_mono = 0; bad_sym = 0; bad_cap = 0; oprev = -40000;
        for (v = -524288; v <= 524287; v = v + 1) begin
            force u_mix.sM = v[19:0];
            #0.01;
            o = out_mono;
            if (v >= -24576 && v <= 24576 && o != v) bad_id = bad_id + 1;
            if (o != kmodel(v)) begin bad_mod = bad_mod + 1; if (bad_mod < 4) $display("         v=%0d: %0d, modelo %0d", v, o, kmodel(v)); end
            if (o < oprev) bad_mono = bad_mono + 1;
            if (o > 32767 || o < -32767) bad_cap = bad_cap + 1;
            if (v == 30000) o_pos = o;
            if (v == -30000 && o != -kmodel(30000)) bad_sym = bad_sym + 1;
            oprev = o;
        end
        // simetria completa
        for (v = 1; v <= 524287; v = v + 1) begin
            force u_mix.sM = v[19:0];  #0.01; o = out_mono;
            force u_mix.sM = -v;       #0.01;
            if (out_mono != -o) bad_sym = bad_sym + 1;
        end
        release u_mix.sM;
        ok(bad_id == 0,   "identidad por debajo de la rodilla (|x| <= 24576)");
        ok(bad_mod == 0,  "pendiente 1/2 por encima de la rodilla y tope +-32767 (modelo sat16k del MSXimus)");
        ok(bad_mono == 0, "monotono (nunca da la vuelta)");
        ok(bad_cap == 0,  "la salida nunca pasa de +-32767");
        ok(bad_sym == 0,  "simetrico: f(-x) = -f(x)");

        // ============================================================
        #100000; rst_n = 1; #5000;
        $display("== B. una portadora FM a tope ==");
        y_w(8'h20, 8'h21); y_w(8'h23, 8'h21);
        y_w(8'h40, 8'h3F); y_w(8'h43, 8'h00);
        y_w(8'h60, 8'hF0); y_w(8'h63, 8'hF0);
        y_w(8'h80, 8'h0F); y_w(8'h83, 8'h0F);
        y_w(8'hC0, 8'h01);
        y_w(8'hA0, 8'h44); y_w(8'hB0, 8'h32);
        #1000000; clr; meas = 1; #2000000; meas = 0;
        $display("         entrada %0d..%0d | salida %0d..%0d | %0d muestras distintas de la entrada", pmin, pmax, omin, omax, n_diff);
        ok(pmax > 15000 && pmin < -15000, "la portadora suena (x5: unos +-20500)");
        ok(n_diff == 0, "  y pasa por el limitador sin tocar (por debajo de la rodilla)");
        y_w(8'hB0, 8'h12); #2000000;

        // ============================================================
        $display("== C1. acorde de 3 portadoras a tope (TL = 0) ==");
        fnl[0]=8'h44; fnh[0]=8'h32; fnl[1]=8'h6B; fnh[1]=8'h32; fnl[2]=8'h98; fnh[2]=8'h32;
        for (ch = 0; ch < 3; ch = ch + 1) begin
            y_w(8'h20 + ch, 8'h21); y_w(8'h23 + ch, 8'h21);
            y_w(8'h40 + ch, 8'h3F); y_w(8'h43 + ch, 8'h00);
            y_w(8'h60 + ch, 8'hF0); y_w(8'h63 + ch, 8'hF0);
            y_w(8'h80 + ch, 8'h0F); y_w(8'h83 + ch, 8'h0F);
            y_w(8'hC0 + ch, 8'h01);
        end
        for (ch = 0; ch < 3; ch = ch + 1) begin y_w(8'hA0 + ch, fnl[ch]); y_w(8'hB0 + ch, fnh[ch]); end
        #1000000; clr; meas = 1; #5000000; meas = 0;
        $display("         entrada %0d..%0d | salida %0d..%0d | de %0d muestras: %0d (%0.1f %%) recortadas sin limitador, %0d (%0.1f %%) en el rail con el, %0d (%0.1f %%) comprimidas",
                 pmin, pmax, omin, omax, n_samp, n_hard, 100.0*n_hard/n_samp, n_rail, 100.0*n_rail/n_samp, n_comp, 100.0*n_comp/n_samp);
        ok(n_hard > 0, "  (el acorde de verdad pasaria del fondo de escala)");
        ok(n_rail < n_hard, "  el limitador deja menos muestras en el rail que el recorte duro");
        for (ch = 0; ch < 3; ch = ch + 1) y_w(8'hB0 + ch, 8'h12);
        #3000000;

        // ============================================================
        $display("== C2. acorde de 6 canales a TL = 8 (-6 dB por portadora) ==");
        fnl[0]=8'h44; fnh[0]=8'h12; fnl[1]=8'h6B; fnh[1]=8'h12; fnl[2]=8'h98; fnh[2]=8'h12;
        fnl[3]=8'h44; fnh[3]=8'h16; fnl[4]=8'h98; fnh[4]=8'h16; fnl[5]=8'h44; fnh[5]=8'h1A;
        for (ch = 0; ch < 6; ch = ch + 1) begin
            mo = (ch < 3) ? ch : ch + 5;          // modulador de los canales 0-5: 00-02, 08-0A
            y_w(8'h20 + mo, 8'h21); y_w(8'h23 + mo, 8'h21);
            y_w(8'h40 + mo, 8'h3F); y_w(8'h43 + mo, 8'h08);
            y_w(8'h60 + mo, 8'hF0); y_w(8'h63 + mo, 8'hF0);
            y_w(8'h80 + mo, 8'h0F); y_w(8'h83 + mo, 8'h0F);
            y_w(8'hC0 + ch, 8'h01);
        end
        for (ch = 0; ch < 6; ch = ch + 1) begin y_w(8'hA0 + ch, fnl[ch]); y_w(8'hB0 + ch, fnh[ch] | 8'h20); end
        #1000000; clr; meas = 1; #5000000; meas = 0;
        $display("         entrada %0d..%0d | salida %0d..%0d | de %0d muestras: %0d (%0.1f %%) recortadas sin limitador, %0d (%0.1f %%) en el rail con el, %0d (%0.1f %%) comprimidas",
                 pmin, pmax, omin, omax, n_samp, n_hard, 100.0*n_hard/n_samp, n_rail, 100.0*n_rail/n_samp, n_comp, 100.0*n_comp/n_samp);
        ok(n_rail < n_hard, "  el limitador deja menos muestras en el rail que el recorte duro");

        $display("== %0d comprobaciones, %0d errores ==", checks, errors);
        if (errors == 0) $display("RESULTADO: PASS"); else $display("RESULTADO: FAIL");
        $finish;
    end
    initial begin #400_000_000; $display("  [FAIL] timeout"); $display("RESULTADO: FAIL"); $finish; end
endmodule
