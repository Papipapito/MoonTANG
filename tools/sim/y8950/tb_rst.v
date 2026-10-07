// tb_rst.v — /RESET del MSX (bus_reset_n: en el core solo resetea adpcm_sdram;
// el puente wv_to_sdram va con el reset de encendido) a mitad de operaciones
// del ADPCM, con el motor PCM saturado. Cadena real: ip_sdram + modelo de SDRAM
// + wv_to_sdram + wave_sdram + adpcm_sdram. Resets de RMIN..RMAX ciclos de
// 54 MHz y RELAY ciclos hasta la peticion nueva. PASA si ningun done de una
// operacion abortada llega a una peticion nueva (done AJENO = 0), ninguna
// lectura da un dato malo, nada se cuelga y el watchdog no salta.
// (Un /RESET real dura milisegundos: esto es el caso extremo del contrato.)
`timescale 1ns/1ps
`default_nettype none
module tb_rst;
    parameter integer RMIN = 1;          // ciclos de 54 MHz de reset (min)
    parameter integer RMAX = 40;         // (max)
    parameter integer RELAY = 0;         // ciclos de 54 MHz entre fin de reset y nueva peticion
    parameter integer N_RST = 2000;      // resets a inyectar
    parameter integer ENG_ON = 1;
    reg clk_108m = 1'b0, clk_54m = 1'b0, clk_eng = 1'b0;
    always #4.6296 clk_108m = ~clk_108m;
    always #9.2593 clk_54m  = ~clk_54m;
    initial begin #3.1; forever #(13.468) clk_eng = ~clk_eng; end
    wire clk_sdram = ~clk_108m;
    reg rst_n = 1'b0;
    initial begin #200 rst_n = 1'b1; end

    wire        sd_clk, sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n;
    wire [10:0] sd_a; wire [1:0] sd_ba; wire [3:0] sd_dqm; wire [31:0] sd_dq;
    sdram_model sdram (.clk(sd_clk), .cke(sd_cke), .cs_n(sd_cs_n), .ras_n(sd_ras_n),
        .cas_n(sd_cas_n), .we_n(sd_we_n), .addr(sd_a), .ba(sd_ba), .dqm(sd_dqm), .dq(sd_dq));
    wire [22:2] b_addr; wire b_valid, b_write, b_refresh, b_rden, b_ready, init_busy;
    wire [31:0] b_wdata, b_rdata; wire [3:0] b_mask;
    ip_sdram #(.FREQ(108_000_000), .RD_CAPTURE_CLK(1)) u_sdram (
        .reset_n(rst_n), .clk(clk_108m), .clk_sdram(clk_sdram), .sdram_init_busy(init_busy),
        .bus_address(b_addr), .bus_valid(b_valid), .bus_write(b_write), .bus_refresh(b_refresh),
        .bus_wdata(b_wdata), .bus_wdata_mask(b_mask), .bus_rdata(b_rdata), .bus_rdata_en(b_rden),
        .bus_ready(b_ready),
        .O_sdram_clk(sd_clk), .O_sdram_cke(sd_cke), .O_sdram_cs_n(sd_cs_n), .O_sdram_ras_n(sd_ras_n),
        .O_sdram_cas_n(sd_cas_n), .O_sdram_wen_n(sd_we_n), .IO_sdram_dq(sd_dq),
        .O_sdram_addr(sd_a), .O_sdram_ba(sd_ba), .O_sdram_dqm(sd_dqm));
    wire        wv_req, wv_we, wv_done, wv2_req, wv2_we, wv2_done, sd_timeout;
    wire [21:0] wv_addr, wv2_addr; wire [7:0] wv_wdata, wv2_wdata; wire [15:0] wv_dout;
    wv_to_sdram u_bridge (
        .clk(clk_108m), .rst_n(rst_n),
        .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done), .sd_timeout(sd_timeout),
        .wv2_req(wv2_req), .wv2_we(wv2_we), .wv2_addr(wv2_addr), .wv2_wdata(wv2_wdata), .wv2_done(wv2_done),
        .bus_address(b_addr), .bus_valid(b_valid), .bus_write(b_write), .bus_refresh(b_refresh),
        .bus_wdata(b_wdata), .bus_wdata_mask(b_mask), .bus_rdata(b_rdata), .bus_rdata_en(b_rden),
        .bus_ready(b_ready));
    // motor
    reg e_req = 1'b0; reg [21:0] e_addr = 22'd0;
    wire [7:0] e_rdata; wire [15:0] e_rword; wire e_done_t;
    wave_sdram u_wave (
        .clk_host(clk_54m), .rst_n(rst_n), .req_toggle(1'b0), .we(1'b0), .addr(22'd0), .wdata(8'd0),
        .rdata(), .done_toggle(), .ready(),
        .clk_eng(clk_eng), .eng_req(e_req), .eng_we(1'b0), .eng_addr(e_addr), .eng_wdata(8'd0),
        .eng_rdata(e_rdata), .eng_rword(e_rword), .eng_done_t(e_done_t), .diag(),
        .clk_108m(clk_108m), .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done));
    function [31:0] wpat(input [19:0] i); wpat = {~i[15:0], i[15:0]}; endfunction
    integer k;
    initial for (k = 0; k < (1<<20); k = k + 1) sdram.mem[k] = wpat(k[19:0]);
    reg go = 1'b0, stop = 1'b0;
    integer e_n = 0, e_err = 0; reg e_seen = 1'b0; reg [1:0] e_st = 0; reg [31:0] rnd;
    always @(posedge clk_eng) begin
        e_req <= 1'b0;
        if (go && !stop && ENG_ON) case (e_st)
            0: begin rnd = $random; e_addr <= {rnd[21:1],1'b0}; e_req <= 1'b1; e_st <= 1; end
            1: if (e_done_t != e_seen) begin
                   e_seen <= e_done_t;
                   if (e_rword !== (e_addr[1] ? wpat(e_addr[21:2]) >> 16 : wpat(e_addr[21:2]) & 32'hFFFF)) begin
                       e_err = e_err + 1; if (e_err < 5) $display("  [MOTOR] dato mal %h %h", e_addr, e_rword); end
                   e_n = e_n + 1; e_st <= 0;
               end
            default: e_st <= 0;
        endcase
    end
    // ADPCM: lado 54 MHz con su propio reset (como bus_reset_n: registro en clk_54m)
    reg a_rst_n = 1'b0;
    reg a_req_t = 1'b0, a_we = 1'b0; reg [17:0] a_addr = 0; reg [7:0] a_wdata = 0;
    wire [15:0] a_rword; wire a_done_t;
    adpcm_sdram #(.FALLBACK_BSRAM(0)) u_adpcm (
        .clk_host(clk_54m), .rst_n(a_rst_n), .req_toggle(a_req_t), .we(a_we), .addr(a_addr),
        .wdata(a_wdata), .rword(a_rword), .done_toggle(a_done_t),
        .clk_108m(clk_108m), .wv_req(wv2_req), .wv_we(wv2_we), .wv_addr(wv2_addr),
        .wv_wdata(wv2_wdata), .wv_dout(wv_dout), .wv_done(wv2_done));
    // modelo de la RAM: bit 8 = desconocido (inicio o escritura huerfana)
    reg [8:0] model [0:262143];
    // 4 KB iniciales con patron conocido, en el banco 2 del modelo y en el modelo del TB
    integer k2;
    initial begin
        #1;
        for (k2 = 0; k2 < 262144; k2 = k2 + 1) model[k2] = (k2 < 4096) ? {1'b0, k2[7:0] ^ 8'h5A ^ k2[11:8]} : 9'h100;
        for (k2 = 0; k2 < 1024; k2 = k2 + 1)
            sdram.mem[{2'b10, 3'b000, k2[15:0]}] = {model[4*k2+3][7:0], model[4*k2+2][7:0], model[4*k2+1][7:0], model[4*k2][7:0]};
    end
    integer a_n = 0, a_err = 0, a_rd = 0, a_chk = 0, a_hang = 0, idle_cnt = 0, n_rst = 0, gap = 0, n_orph = 0;
    reg a_seen = 1'b0, a_busy = 1'b0;
    reg [31:0] r2;
    always @(posedge clk_54m) begin
        if (!a_rst_n) begin
            a_req_t <= 1'b0; a_seen <= 1'b0; gap = 0;
            if (a_busy) begin
                if (a_we) model[a_addr] = 9'h100;     // huerfana: puede o no haberse escrito
                n_orph = n_orph + 1;
                a_busy <= 1'b0;
            end
        end
        else if (go && !stop) begin
            if (a_busy) begin
                idle_cnt = idle_cnt + 1;
                if (idle_cnt == 20000) begin a_hang = a_hang + 1; $display("  [ADPCM %0t] COLGADO: sin done en 370 us", $time); end
                if (a_done_t != a_seen) begin
                    a_seen <= a_done_t; a_busy <= 1'b0; a_n = a_n + 1; idle_cnt = 0; gap = 0;
                    if (a_we) model[a_addr] = {1'b0, a_wdata};
                    else begin
                        a_rd = a_rd + 1;
                        if (!model[{a_addr[17:1],1'b0}][8] && a_rword[7:0] !== model[{a_addr[17:1],1'b0}][7:0]) begin
                            a_err = a_err + 1; if (a_err < 10) $display("  [ADPCM %0t] lectura %h: %h, esperado lo %h", $time, a_addr, a_rword, model[{a_addr[17:1],1'b0}][7:0]); end
                        else if (!model[{a_addr[17:1],1'b1}][8] && a_rword[15:8] !== model[{a_addr[17:1],1'b1}][7:0]) begin
                            a_err = a_err + 1; if (a_err < 10) $display("  [ADPCM %0t] lectura %h: %h, esperado hi %h", $time, a_addr, a_rword, model[{a_addr[17:1],1'b1}][7:0]); end
                        else if (!model[{a_addr[17:1],1'b0}][8] && !model[{a_addr[17:1],1'b1}][8]) a_chk = a_chk + 1;
                    end
                end
            end
            else if (gap >= RELAY) begin
                r2 = $random;
                a_addr <= {6'd0, r2[11:0]};
                a_we <= r2[31]; a_wdata <= r2[23:16];
                a_req_t <= ~a_req_t; a_busy <= 1'b1; idle_cnt = 0;
            end
            else gap = gap + 1;
        end
    end
    // instrumentacion en 108: operaciones del cliente 2 huerfanas en el puente
    reg br_orph = 1'b0; integer n_br_orph = 0, n_foreign = 0, n_orph_ign = 0;
    always @(posedge clk_108m) begin
        if (u_bridge.st == 3'd1 && u_bridge.owner2 && u_bridge.st_d == 3'd0) br_orph <= 1'b0;   // nueva op del 2
        if (!a_rst_n && u_bridge.owner2 && (u_bridge.st == 3'd1 || u_bridge.st == 3'd2 || u_bridge.st == 3'd3) && !br_orph) begin
            br_orph <= 1'b1; n_br_orph = n_br_orph + 1;
        end
        if (wv2_done && br_orph) begin
            if (u_adpcm.g_sdram.st == 2'd1) begin
                n_foreign = n_foreign + 1;
                $display("  [PUENTE %0t] done de una op HUERFANA entregado a una peticion NUEVA (we=%0d addr=%h)", $time, wv2_we, wv2_addr);
            end
            else n_orph_ign = n_orph_ign + 1;
            br_orph <= 1'b0;
        end
    end
    integer t_wait, t_len;
    initial begin
        wait (rst_n); wait (!init_busy);
        repeat (50) @(posedge clk_108m);
        @(posedge clk_54m) a_rst_n <= 1'b1;
        go = 1'b1;
        repeat (N_RST) begin
            t_wait = 20 + ({$random} % 400);
            repeat (t_wait) @(posedge clk_54m);
            t_len = RMIN + ({$random} % (RMAX - RMIN + 1));
            a_rst_n <= 1'b0; n_rst = n_rst + 1;
            repeat (t_len) @(posedge clk_54m);
            a_rst_n <= 1'b1;
        end
        repeat (2000) @(posedge clk_54m);
        stop = 1'b1;
        repeat (200) @(posedge clk_54m);
        $display("RESETS %0d (len %0d..%0d, relay %0d), huerfanas %0d | ADPCM ops %0d, lecturas %0d (comprobadas %0d), errores %0d, cuelgues %0d | MOTOR %0d, errores %0d | wdog %0d | sdram err %0d | puente: huerfanas %0d, done ignorado %0d, done AJENO %0d",
                 n_rst, RMIN, RMAX, RELAY, n_orph, a_n, a_rd, a_chk, a_err, a_hang, e_n, e_err, sd_timeout, sdram.n_err, n_br_orph, n_orph_ign, n_foreign);
        if (a_err == 0 && a_hang == 0 && e_err == 0 && sd_timeout === 1'b0 && sdram.n_err == 0 && n_foreign == 0) $display("RESULTADO: PASS");
        else $display("RESULTADO: FAIL");
        $finish;
    end
endmodule
`default_nettype wire
