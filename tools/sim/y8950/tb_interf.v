// ============================================================================
// tb_interf.v — ¿cuanto le cuesta al motor PCM del OPL4 compartir la SDRAM con
// el ADPCM-B del Y8950 (256 KB, bancos 2-3)?  (MoonTANG, variante wt_audio)
//
// Cadena REAL: wave_sdram + adpcm_sdram (MSXimus) -> wv_to_sdram (dos
// clientes) -> ip_sdram -> sdram_model (el del banco de placa, con ventana de
// dato real). Relojes: 108 / 54 (alineados), SDRAM a 180 grados, motor a
// 38,571 MHz (HDMI) o 37,125 (sin HDMI).
//
// Motor sintetico en clk_eng: pide palabras SIN PAUSA (peor caso: un fallo de
// cache detras de otro), direcciones aleatorias en los 4 MB de la wave, y
// comprueba el dato contra la precarga. Mide latencia (min/media/max) y
// operaciones por microsegundo.
// ADPCM sintetico en clk_54m (contrato toggle de y8950_adpcm): escribe un
// patron y lo relee, con una pausa ADPCM_GAP (ciclos de 54 MHz) entre ops, en
// bloques de A_BLK bytes (A_BLK escrituras de byte, luego A_BLK/2 relecturas de
// palabra).
//
// Cada ejecucion dice RESULTADO: PASS si no hay ni un dato mal (motor y ADPCM),
// ni un error de protocolo en el modelo de la SDRAM, el watchdog no salta, el
// ADPCM avanza y relee al menos una palabra (si lo hay) y la latencia maxima
// del motor queda por debajo de
// MAX_LAT_NS. run.sh compara ademas el ritmo del motor con y sin ADPCM.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none
module tb_interf;
    parameter integer ADPCM_GAP  = 0;        // ciclos de 54 MHz entre ops ADPCM (-1 = sin ADPCM)
    parameter real    ENG_HALF   = 12.963;   // semiperiodo de clk_eng (38,571 MHz)
    parameter integer ENG_GAP    = 0;        // ciclos de clk_eng entre fetches del motor
    parameter integer N_ENG      = 20000;    // fetches del motor a medir
    parameter real    MAX_LAT_NS = 600.0;    // latencia maxima admitida de un fetch del motor
    parameter integer A_BLK      = 2048;     // ADPCM: bytes por bloque (potencia de 2, 4..2048):
                                             // A_BLK escrituras de byte y luego A_BLK/2 relecturas

    reg clk_108m = 1'b0, clk_54m = 1'b0, clk_eng = 1'b0;
    always #4.6296 clk_108m = ~clk_108m;
    always #9.2593 clk_54m  = ~clk_54m;
    initial begin #3.1; forever #(ENG_HALF) clk_eng = ~clk_eng; end
    wire clk_sdram = ~clk_108m;                     // CLKOUTP a 180 grados

    reg rst_n = 1'b0;
    initial begin #200 rst_n = 1'b1; end

    // ---------------- SDRAM ----------------
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

    // ---------------- motor sintetico (clk_eng) ----------------
    reg         e_req = 1'b0;
    reg  [21:0] e_addr = 22'd0;
    wire [7:0]  e_rdata; wire [15:0] e_rword; wire e_done_t;
    wave_sdram u_wave (
        .clk_host(clk_54m), .rst_n(rst_n), .req_toggle(1'b0), .we(1'b0), .addr(22'd0), .wdata(8'd0),
        .rdata(), .done_toggle(), .ready(),
        .clk_eng(clk_eng), .eng_req(e_req), .eng_we(1'b0), .eng_addr(e_addr), .eng_wdata(8'd0),
        .eng_rdata(e_rdata), .eng_rword(e_rword), .eng_done_t(e_done_t), .diag(),
        .clk_108m(clk_108m), .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done));

    // precarga de la wave (bancos 0-1): palabra i = {~i[15:0], i[15:0]}
    function [31:0] wpat(input [19:0] i); wpat = {~i[15:0], i[15:0]}; endfunction
    integer k;
    initial for (k = 0; k < (1<<20); k = k + 1) sdram.mem[k] = wpat(k[19:0]);

    reg         go = 1'b0;                 // arranca la medida (tras el init)
    integer     e_n = 0, e_err = 0, e_lat = 0, e_min = 1<<30, e_max = 0, e_sum = 0, e_hist [0:63];
    real        t_start = 0, t_end = 0;
    reg         e_done_seen = 1'b0;
    reg  [1:0]  e_st = 2'd0;
    integer     e_gap = 0;
    reg  [31:0] rnd;
    initial for (k = 0; k < 64; k = k + 1) e_hist[k] = 0;
    always @(posedge clk_eng) begin
        e_req <= 1'b0;
        if (go && e_n < N_ENG) case (e_st)
            2'd0: begin
                rnd    = $random;
                e_addr <= {rnd[21:1], 1'b0};
                e_req  <= 1'b1; e_lat = 0; e_st <= 2'd1;
                if (e_n == 0) t_start = $realtime;
            end
            2'd1: begin
                e_lat = e_lat + 1;
                if (e_done_t != e_done_seen) begin
                    e_done_seen <= e_done_t;
                    if (e_rword !== (e_addr[1] ? wpat(e_addr[21:2]) >> 16 : wpat(e_addr[21:2]) & 32'hFFFF)) begin
                        e_err = e_err + 1;
                        if (e_err < 5) $display("  [MOTOR] dato mal en %h: %h", e_addr, e_rword);
                    end
                    e_sum = e_sum + e_lat;
                    if (e_lat < e_min) e_min = e_lat;
                    if (e_lat > e_max) e_max = e_lat;
                    e_hist[(e_lat > 63) ? 63 : e_lat] = e_hist[(e_lat > 63) ? 63 : e_lat] + 1;
                    e_n = e_n + 1;
                    if (e_n == N_ENG) t_end = $realtime;
                    e_gap = 0; e_st <= (ENG_GAP > 0) ? 2'd2 : 2'd0;
                end
            end
            2'd2: begin e_gap = e_gap + 1; if (e_gap >= ENG_GAP) e_st <= 2'd0; end
            default: e_st <= 2'd0;
        endcase
    end

    // ---------------- ADPCM sintetico (clk_54m, contrato toggle) ----------------
    reg         a_req_t = 1'b0, a_we = 1'b0;
    reg  [17:0] a_addr = 18'd0;
    reg  [7:0]  a_wdata = 8'd0;
    wire [15:0] a_rword; wire a_done_t;
    adpcm_sdram #(.FALLBACK_BSRAM(0)) u_adpcm (
        .clk_host(clk_54m), .rst_n(rst_n), .req_toggle(a_req_t), .we(a_we), .addr(a_addr),
        .wdata(a_wdata), .rword(a_rword), .done_toggle(a_done_t),
        .clk_108m(clk_108m), .wv_req(wv2_req), .wv_we(wv2_we), .wv_addr(wv2_addr),
        .wv_wdata(wv2_wdata), .wv_dout(wv_dout), .wv_done(wv2_done));

    function [7:0] apat(input [17:0] a); apat = a[7:0] ^ a[15:8] ^ {a[17:16], 6'h2A}; endfunction
    integer a_n = 0, a_err = 0, a_gap = 0, a_wr = 0, a_rd = 0, a_rdn = 0, a_lat = 0, a_max = 0;
    reg     a_seen = 1'b0, a_busy = 1'b0, a_phase_wr = 1'b1;
    reg [17:0] a_ptr = 18'd0;
    always @(posedge clk_54m) begin
        if (go && ADPCM_GAP >= 0 && e_n < N_ENG) begin
            if (a_busy) begin
                a_lat = a_lat + 1;
                if (a_done_t != a_seen) begin
                    a_seen <= a_done_t; a_busy <= 1'b0; a_n = a_n + 1; a_gap = 0;
                    if (a_lat > a_max) a_max = a_lat;
                    if (!a_we) a_rdn = a_rdn + 1;     // relecturas comprobadas
                    if (!a_we && a_rword !== {apat({a_addr[17:1], 1'b1}), apat({a_addr[17:1], 1'b0})}) begin
                        a_err = a_err + 1;
                        if (a_err < 5) $display("  [ADPCM] dato mal en %h: %h", a_addr, a_rword);
                    end
                end
            end
            else if (a_gap >= ADPCM_GAP) begin
                // A_BLK escrituras de byte, luego A_BLK/2 lecturas de palabra, y vuelta
                if (a_phase_wr) begin
                    a_we <= 1'b1; a_addr <= a_ptr; a_wdata <= apat(a_ptr); a_wr = a_wr + 1;
                    a_ptr <= a_ptr + 18'd1;
                    if ((a_ptr & (A_BLK - 1)) == A_BLK - 1) begin a_phase_wr <= 1'b0; end
                end
                else begin
                    a_we <= 1'b0; a_addr <= (a_ptr - A_BLK) & 18'h3FFFE; a_rd = a_rd + 1;
                    a_ptr <= a_ptr + 18'd2;
                    if (((a_ptr | 18'd1) & (A_BLK - 1)) == A_BLK - 1) begin a_phase_wr <= 1'b1; end
                end
                a_req_t <= ~a_req_t; a_busy <= 1'b1; a_lat = 0;
            end
            else a_gap = a_gap + 1;
        end
    end

    // ---------------- secuencia ----------------
    initial begin
        wait (rst_n);
        wait (!init_busy);
        repeat (50) @(posedge clk_108m);
        go = 1'b1;
        wait (e_n == N_ENG);
        #2000;
        $display("CONFIG: ADPCM_GAP=%0d ENG_GAP=%0d f_eng=%.3f MHz", ADPCM_GAP, ENG_GAP, 500.0/ENG_HALF);
        $display("MOTOR : %0d fetches, errores=%0d, latencia ciclos eng min/media/max = %0d / %.2f / %0d  (%.0f / %.0f / %.0f ns)",
                 e_n, e_err, e_min, 1.0*e_sum/e_n, e_max, e_min*2*ENG_HALF, 2*ENG_HALF*e_sum/e_n, e_max*2*ENG_HALF);
        $display("MOTOR : %.3f fetches/us", e_n * 1000.0 / (t_end - t_start));
        $display("ADPCM : %0d ops (%0d wr, %0d rd, %0d relecturas comprobadas, bloque de %0d bytes), errores=%0d, latencia max %0d ciclos de 54 MHz (%.0f ns), %.3f ops/us",
                 a_n, a_wr, a_rd, a_rdn, A_BLK, a_err, a_max, a_max*18.5185, a_n * 1000.0 / (t_end - t_start));
        $display("SDRAM : errores de protocolo del modelo=%0d, watchdog=%0d", sdram.n_err, sd_timeout);
        $write("HIST  :");
        for (k = 0; k < 64; k = k + 1) if (e_hist[k]) $write(" %0d:%0d", k, e_hist[k]);
        $display("");
        if (e_err == 0 && a_err == 0 && sdram.n_err == 0 && sd_timeout === 1'b0 &&
            (ADPCM_GAP < 0 || (a_n > 0 && a_rdn > 0)) && e_max * 2.0 * ENG_HALF < MAX_LAT_NS)
            $display("RESULTADO: PASS");
        else
            $display("RESULTADO: FAIL");
        $finish;
    end
    initial begin #50_000_000; $display("TIMEOUT"); $display("RESULTADO: FAIL"); $finish; end
endmodule
`default_nettype wire
