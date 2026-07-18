// ============================================================================
// moontang_top.v — MoonTANG: cartucho MoonSound (OPL4) para MSX sobre
// Tang Nano 20K + carrier tipo WonderTANG.  (EXPERIMENTAL)
//
// El OPL4 (YMF278B) = FM OPL3 (18 ch, opl4fm) + wavetable PCM (24 slots,
// opl4_pcm + motor YMF278B de srg320) con su ROM de ondas YRW801 (2 MB) en la
// SDRAM embebida de la placa. Puro periférico de I/O del bus MSX: puertos
// C4-C7 (FM) y 7E-7F (wave). No usa /SLTSL ni memoria — sólo I/O.
//
// Estructura:
//   bus MSX (slot_*) --2FF--> opl4fm + opl4_pcm  (decodifican C4-C7 / 7E-7F)
//        lecturas -> mux -> tristate de slot_d (con slot_data_dir al transceptor)
//        opl4_pcm.mem_* <-> wave_sdram <-> wv_to_sdram <-> ip_sdram <-> SDRAM
//        yrw801_loader: flash SPI --(YRW801 2MB)--> wave_sdram (host) al boot
//        mezcla FM+wave -> DAC sigma-delta -> pines de audio
//
// Relojes (de un cristal de 27 MHz):
//   clk_opl3 = 27      MHz (FM, directo del cristal; CLK_DIV_COUNT=545 -> fs 49.5k)
//   clk_54m  = 54      MHz (bus host)                              [pll_main]
//   clk_108m = 108     MHz (SDRAM + arbitraje wave)               [pll_main]
//   clk_sdram= 108     MHz desfasado (reloj al chip SDRAM)        [pll_main]
//   clk_eng  = 37.125  MHz (motor PCM; CE 6272/6875 -> fs 44.1k)  [pll_eng]
//
// AVISO: EXPERIMENTAL. El mapeo de pines (constraints) es del cartucho V9968 de
// hra1129 y DEBE verificarse contra el esquemático real del WonderTANG antes de
// grabar. Sin poder probar en HW, esto es un primer intento coherente.
// ============================================================================

module moontang_top (
    input  wire        clk,           // 27 MHz (cristal onboard)
    input  wire        clk14m,        // 14.318 MHz del bus (sin usar; disponible)

    // ---- bus del slot MSX (vía transceptores del carrier) ----
    input  wire        slot_reset_n,
    input  wire        slot_iorq_n,
    input  wire        slot_rd_n,
    input  wire        slot_wr_n,
    input  wire [7:0]  slot_a,
    inout  wire [7:0]  slot_d,
    output wire        slot_wait,
    output wire        slot_intr,
    output wire        slot_data_dir, // 0: MSX->cart (write/idle), 1: cart->MSX (read)
    output wire        oe_n,          // habilitación del transceptor de datos

    // ---- audio (a filtro RC -> jack / pin SOUND del slot) ----
    output wire        audio_l,
    output wire        audio_r,

    // ---- flash SPI onboard (YRW801) ----
    output wire        flash_sclk,
    output wire        flash_cs,
    output wire        flash_mosi,
    input  wire        flash_miso,

    // ---- SDRAM embebida (Tang Nano 20K, GW2AR-18, 32b, pines IMPLÍCITOS) ----
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm,

    // ---- diagnóstico ----
    output wire        ws2812_led,
    input  wire [1:0]  button
);
    // ------------------------------------------------------------------
    //  Relojes
    // ------------------------------------------------------------------
    wire clk_27m = clk;               // FM directo del cristal
    wire clk_108m, clk_sdram, clk_54m, lock_main;
    wire clk_eng, lock_eng;

    pll_main u_pll_main (
        .clkin(clk), .clk_108m(clk_108m), .clk_sdram(clk_sdram),
        .clk_54m(clk_54m), .lock(lock_main)
    );
    pll_eng u_pll_eng (
        .clkin(clk), .clk_eng(clk_eng), .lock(lock_eng)
    );

    wire pll_locked = lock_main & lock_eng;

    // ------------------------------------------------------------------
    //  Resets
    //   por_reset_n : subsistema de memoria (SDRAM/loader/wave) — 1 sola vez
    //                 al lock de los PLL; NO se toca en cada reset del MSX.
    //   bus_reset_n : lógica del chip (opl4fm/opl4_pcm) — sigue al slot.
    // ------------------------------------------------------------------
    reg [3:0] por_sync;
    always @(posedge clk_54m or negedge pll_locked) begin
        if (!pll_locked) por_sync <= 4'd0;
        else             por_sync <= {por_sync[2:0], 1'b1};
    end
    wire por_reset_n = por_sync[3];

    reg [2:0] rst_sync;
    always @(posedge clk_54m or negedge por_reset_n) begin
        if (!por_reset_n) rst_sync <= 3'd0;
        else              rst_sync <= {rst_sync[1:0], slot_reset_n};
    end
    wire bus_reset_n = rst_sync[2];

    // ------------------------------------------------------------------
    //  Sincronización del bus (2FF a clk_54m)
    // ------------------------------------------------------------------
    reg [1:0] iorq_s, rd_s, wr_s;
    reg [7:0] a_s0, a_s1, d_s0, d_s1;
    always @(posedge clk_54m) begin
        iorq_s <= {iorq_s[0], slot_iorq_n};
        rd_s   <= {rd_s[0],   slot_rd_n};
        wr_s   <= {wr_s[0],   slot_wr_n};
        a_s0 <= slot_a;  a_s1 <= a_s0;
        d_s0 <= slot_d;  d_s1 <= d_s0;
    end
    wire       s_iorq_n = iorq_s[1];
    wire       s_rd_n   = rd_s[1];
    wire       s_wr_n   = wr_s[1];
    wire [7:0] s_addr   = a_s1;
    wire [7:0] s_din    = d_s1;
    wire       s_m1_n   = 1'b1;      // el carrier no trae /M1 -> nunca ciclo M1

    // ==================================================================
    //  OPL4 FM (opl4fm) — puertos C4-C7 + stub 7F
    // ==================================================================
    wire        opl4fm_rd, opl4fm_wrd, opl4fm_int_n;
    wire [7:0]  opl4fm_dout, opl4fm_wdout;
    wire signed [15:0] opl4fm_wav;
    wire [1:0]  wave_status;

    opl4fm u_opl4fm (
        .rst_n(bus_reset_n), .clk_host(clk_54m), .clk_opl3(clk_27m),
        .iorq_n(s_iorq_n), .rd_n(s_rd_n), .wr_n(s_wr_n), .m1_n(s_m1_n),
        .addr(s_addr), .din(s_din), .wave_status(wave_status),
        .fm_rd(opl4fm_rd), .wave_rd(opl4fm_wrd), .dout(opl4fm_dout),
        .wave_dout(opl4fm_wdout), .pcm_out(opl4fm_wav), .int_n(opl4fm_int_n)
    );

    // ==================================================================
    //  OPL4 PCM wavetable (opl4_pcm) — puertos 7E-7F + motor
    // ==================================================================
    wire        opl4pcm_rd, opl4pcm_wait_n;
    wire [7:0]  opl4pcm_dout;
    wire [5:0]  opl4_mixfm;
    wire signed [15:0] opl4pcm_l, opl4pcm_r;
    // puerto de memoria del motor <-> wave_sdram
    wire        weng_req, weng_we;
    wire [21:0] weng_addr;
    wire [7:0]  weng_wdata, weng_rdata;
    wire [15:0] weng_rword;
    wire        weng_done_t;
    wire        wl_done;

    opl4_pcm u_opl4pcm (
        .rst_n(bus_reset_n), .clk_host(clk_54m),
        .iorq_n(s_iorq_n), .rd_n(s_rd_n), .wr_n(s_wr_n), .m1_n(s_m1_n),
        .addr(s_addr), .din(s_din),
        .wave_rd(opl4pcm_rd), .wave_dout(opl4pcm_dout),
        .wave_wait_n(opl4pcm_wait_n), .wave_status(wave_status),
        .mix_fm(opl4_mixfm), .pcm_l(opl4pcm_l), .pcm_r(opl4pcm_r),
        .clk_eng(clk_eng), .eng_rst_n(bus_reset_n & wl_done),
        .mem_req(weng_req), .mem_we(weng_we), .mem_addr(weng_addr),
        .mem_wdata(weng_wdata), .mem_rdata(weng_rdata),
        .mem_rword(weng_rword), .mem_done_t(weng_done_t),
        .diag(), .dbg_tx(), .vid_diag(4'd0)
    );

    // ==================================================================
    //  wave_sdram (arbitra loader + motor) <-> wv_to_sdram <-> ip_sdram
    //  ip_sdram + pines SDRAM IMPLÍCITOS = enfoque PROBADO del V9968 (hra1129)
    //  en esta misma GW2AR-18C.
    // ==================================================================
    // host port (loader)
    wire        wl_req_toggle, wl_we, wl_done_toggle;
    wire [21:0] wl_addr;
    wire [7:0]  wl_wdata;
    // wv_* (a la SDRAM vía puente)
    wire        wv_req, wv_we;
    wire [21:0] wv_addr;
    wire [7:0]  wv_wdata;
    wire [15:0] wv_dout;
    wire        wv_done;

    wave_sdram u_wave (
        .clk_host(clk_54m), .rst_n(por_reset_n),
        .req_toggle(wl_req_toggle), .we(wl_we), .addr(wl_addr), .wdata(wl_wdata),
        .rdata(), .done_toggle(wl_done_toggle), .ready(),
        .clk_eng(clk_eng), .eng_req(weng_req), .eng_we(weng_we),
        .eng_addr(weng_addr), .eng_wdata(weng_wdata),
        .eng_rdata(weng_rdata), .eng_rword(weng_rword), .eng_done_t(weng_done_t),
        .diag(),
        .clk_108m(clk_108m),
        .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done)
    );

    // puente wv_* (byte, 16b) <-> ip_sdram (palabra, 32b) + refresh
    wire [22:2] sd_address;
    wire        sd_valid, sd_write, sd_refresh, sd_rdata_en, sd_ready;
    wire [31:0] sd_wdata, sd_rdata;
    wire [3:0]  sd_wdata_mask;

    wv_to_sdram u_bridge (
        .clk(clk_108m), .rst_n(por_reset_n),
        .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done),
        .bus_address(sd_address), .bus_valid(sd_valid), .bus_write(sd_write),
        .bus_refresh(sd_refresh), .bus_wdata(sd_wdata), .bus_wdata_mask(sd_wdata_mask),
        .bus_rdata(sd_rdata), .bus_rdata_en(sd_rdata_en), .bus_ready(sd_ready)
    );

    wire sdram_init_busy;
    ip_sdram #(.FREQ(108_000_000)) u_sdram (
        .reset_n(por_reset_n), .clk(clk_108m), .clk_sdram(clk_sdram),
        .sdram_init_busy(sdram_init_busy),
        .bus_address(sd_address), .bus_valid(sd_valid), .bus_write(sd_write),
        .bus_refresh(sd_refresh), .bus_wdata(sd_wdata), .bus_wdata_mask(sd_wdata_mask),
        .bus_rdata(sd_rdata), .bus_rdata_en(sd_rdata_en), .bus_ready(sd_ready),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_wen_n(O_sdram_wen_n), .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );

    // ==================================================================
    //  Loader YRW801 (flash -> wave_sdram host) + flash_rw
    // ==================================================================
    wire [23:0] fl_addr;
    wire        fl_rd, fl_data_ready, fl_busy, fl_terminate;
    wire [7:0]  fl_dout;
    wire        loader_start = por_reset_n & ~sdram_init_busy;

    yrw801_loader u_loader (
        .clk(clk_54m), .rst_n(por_reset_n), .start(loader_start),
        .flash_addr(fl_addr), .flash_rd(fl_rd), .flash_dout(fl_dout),
        .flash_data_ready(fl_data_ready), .flash_busy(fl_busy),
        .flash_terminate(fl_terminate),
        .wl_req_toggle(wl_req_toggle), .wl_we(wl_we), .wl_addr(wl_addr),
        .wl_wdata(wl_wdata), .wl_done_toggle(wl_done_toggle),
        .wl_done(wl_done), .wl_dbg_state()
    );

    flash u_flash (
        .clk(clk_54m), .reset_n(por_reset_n),
        .SCLK(flash_sclk), .CS(flash_cs), .MISO(flash_miso), .MOSI(flash_mosi),
        .addr(fl_addr), .rd(fl_rd), .dout(fl_dout),
        .data_ready(fl_data_ready), .busy(fl_busy), .terminate(fl_terminate),
        .write_enable(1'b0), .write_din(8'd0), .write_addr(24'd0),
        .write_busy(), .write_terminate(1'b0), .write_counter()
    );

    // ==================================================================
    //  Mux de lectura + tristate del bus de datos
    //   FM (C4-C7) tiene prioridad; si no, wave (7E-7F) del motor.
    // ==================================================================
    wire       any_rd  = opl4fm_rd | opl4pcm_rd;
    wire [7:0] rd_data = opl4fm_rd ? opl4fm_dout : opl4pcm_dout;

    reg        drive_r;
    reg [7:0]  drive_data;
    always @(posedge clk_54m or negedge bus_reset_n) begin
        if (!bus_reset_n) begin drive_r <= 1'b0; drive_data <= 8'd0; end
        else begin drive_r <= any_rd; drive_data <= rd_data; end
    end

    assign slot_d         = drive_r ? drive_data : 8'hZZ;
    assign slot_data_dir  = drive_r;                 // 1 = cart->MSX
    assign oe_n           = 1'b0;                     // transceptor siempre activo
    assign slot_intr      = ~opl4fm_int_n;            // activo-alto al carrier
    // /WAIT (activo-alto = stall): init de SDRAM + handshake de lectura wave
    assign slot_wait      = sdram_init_busy | ~opl4pcm_wait_n;

    // ==================================================================
    //  Mezcla de audio (OPL4: FM + wave L/R) con saturación -> DAC
    // ==================================================================
    // atenuación del FM según opl4_mixfm (registro F8 del OPL4), como MSXimus
    wire signed [15:0] o4fm_base = opl4_mixfm[0] ? (opl4fm_wav >>> 1) + (opl4fm_wav >>> 2)
                                                 : opl4fm_wav;
    wire signed [15:0] o4fm_att  = o4fm_base >>> opl4_mixfm[2:1];
    wire signed [15:0] fm_term   = (opl4_mixfm[2:0] == 3'd7) ? 16'sd0 : o4fm_att;

    function signed [15:0] sat16(input signed [17:0] v);
        sat16 = (v >  18'sd32767)  ? 16'sh7FFF :
                (v < -18'sd32768)  ? 16'sh8000 : v[15:0];
    endfunction

    wire signed [17:0] mixL = {{2{fm_term[15]}}, fm_term} + {{2{opl4pcm_l[15]}}, opl4pcm_l};
    wire signed [17:0] mixR = {{2{fm_term[15]}}, fm_term} + {{2{opl4pcm_r[15]}}, opl4pcm_r};

    reg signed [15:0] sampL, sampR;
    always @(posedge clk_54m) begin
        sampL <= sat16(mixL);
        sampR <= sat16(mixR);
    end

    sigma_delta_dac u_dac_l (.clk(clk_108m), .rst_n(por_reset_n), .din(sampL), .dout(audio_l));
    sigma_delta_dac u_dac_r (.clk(clk_108m), .rst_n(por_reset_n), .din(sampR), .dout(audio_r));

    // ==================================================================
    //  LED de diagnóstico (activo-bajo apagado): parpadea al cargar
    // ==================================================================
    assign ws2812_led = 1'b0;   // reservado; el driver WS2812 se puede añadir luego

endmodule
