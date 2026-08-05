// ============================================================================
// moontang_top.sv — MoonTANG: cartucho MoonSound (OPL4) para MSX
//                   Tang Nano 20K (GW2AR-18C) sobre WonderTANG 2.00b
//
// SOLO OPL4: FM OPL3 (puertos C4h-C7h) + wavetable PCM 24 slots (7Eh-7Fh).
// Sin megaram, sin RAM, sin Nextor: un MoonSound y nada mas.
//
// El bus del slot NO llega directo: la WonderTANG multiplexa A0-A15 y el
// control (MERQ/IORQ/CS1/CS2/RESET/RFSH/CS12/M1) en mp[7:0] con msel_n[2:0].
// El front-end (WT200B_BUS + BUS_IF + PIN_FILTER) es de tnCart/tnCartWonder
// (Shinobu Hashimoto / Albert Herranz, BSD-3) — codigo VALIDADO en esta placa.
// El audio sale por el DAC I2S de la propia placa (como el MoonSound real,
// que tambien lleva su jack) via I2S_AUDIO_TX.
//
// Relojes (del cristal de 27 MHz):
//   clk_108m  108 MHz   pll_main CLKOUT   -> bus, SDRAM, arbitraje wave
//   clk_sdram 108 MHz   pll_main CLKOUTP  -> reloj al chip SDRAM (desfasado)
//   clk_54m    54 MHz   pll_main CLKOUTD  -> host de opl4fm/opl4_pcm
//   clk_27m    27 MHz   CLKDIV /4 de 108  -> FM (opl3, CLK_DIV_COUNT=545)
//                       (NO del pad: colgarlo del cristal daba skew -2.57 ns
//                        y 77 violaciones de hold contra clk_54m)
//   clk_21m  21.6 MHz   CLKDIV /5 de 108  -> recuperacion del reloj del MSX
//   clk_eng 37.125 MHz  pll_eng           -> motor PCM (CE 6272/6875 -> 44.1k)
//   clk_dac 1.542 MHz   27/5/3.5          -> BCLK del I2S (48 kHz x 32)
// ============================================================================

`default_nettype none

module moontang_top (
    input  wire        CLK_27M,        // pin 4

    // ---- bus del cartucho (WonderTANG 2.00b, multiplexado) ----
    output wire        CART_BUSDIR_n,
    output wire        CART_INT_n,
    output wire        CART_WAIT_n,
    input  wire        CART_SLTSL_n,
    input  wire        CART_RD_n,
    input  wire        CART_WR_n,
    input  wire        CART_CLOCK,
    input  wire [7:0]  CART_MUX_SIG,
    output wire [2:0]  CART_MUX_CS_n,
    inout  wire [7:0]  CART_DATA_SIG,
    output wire        CART_DATA_DIR,

    // ---- DAC I2S de la placa ----
    output wire        DAC_BCLK,
    output wire        DAC_LRCLK,
    output wire        DAC_DIN,
    output wire        DAC_SDMODE_n,   // 1 = desmuteado

    // ---- diagnostico ----
    output wire        LED,
    output wire        UART_TX,        // telemetria del motor PCM (115200 8N1)

    // ---- flash SPI (imagen YRW801) ----
    output wire        mspi_cs,
    output wire        mspi_sclk,
    input  wire        mspi_miso,
    output wire        mspi_mosi,
    output wire        mspi_hold,

    // ---- SDRAM embebida (32 bits, pines implicitos del encapsulado) ----
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm
);

    // ------------------------------------------------------------------
    //  Relojes
    // ------------------------------------------------------------------
    wire clk_108m, clk_sdram, clk_54m, lock_main;
    wire clk_eng, lock_eng;

    pll_main u_pll_main (
        .clkin(CLK_27M), .clk_108m(clk_108m), .clk_sdram(clk_sdram),
        .clk_54m(clk_54m), .lock(lock_main)
    );
    pll_eng u_pll_eng (
        .clkin(CLK_27M), .clk_eng(clk_eng), .lock(lock_eng)
    );

    wire pll_locked = lock_main & lock_eng;

    // clk_27m para el FM: DERIVADO del PLL (108/4), no del pad del cristal.
    wire clk_27m;
    CLKDIV u_div27 (.CLKOUT(clk_27m), .HCLKIN(clk_108m), .RESETN(lock_main), .CALIB(1'b0));
    defparam u_div27.DIV_MODE = "4";
    defparam u_div27.GSREN    = "false";

    // clk_21m para la recuperacion del reloj del MSX en el front-end (108/5)
    wire clk_21m;
    CLKDIV u_div21 (.CLKOUT(clk_21m), .HCLKIN(clk_108m), .RESETN(lock_main), .CALIB(1'b0));
    defparam u_div21.DIV_MODE = "5";
    defparam u_div21.GSREN    = "false";

    // reloj del DAC: 27/5 = 5.4 MHz -> /3.5 = 1.542 MHz (48 kHz x 32)
    wire clk_5m4, clk_dac;
    CLKDIV u_div5m4 (.CLKOUT(clk_5m4), .HCLKIN(CLK_27M), .RESETN(pll_locked), .CALIB(1'b0));
    defparam u_div5m4.DIV_MODE = "5";
    defparam u_div5m4.GSREN    = "false";
    CLKDIV u_divdac (.CLKOUT(clk_dac), .HCLKIN(clk_5m4), .RESETN(pll_locked), .CALIB(1'b0));
    defparam u_divdac.DIV_MODE = "3.5";
    defparam u_divdac.GSREN    = "false";

    // ------------------------------------------------------------------
    //  Resets
    //   por_reset_n : subsistema de memoria (SDRAM/loader/wave). Solo depende
    //                 del lock de los PLL: la wave SOBREVIVE a un reset del MSX.
    //   bus_reset_n : logica del chip. Sigue al /RESET del slot.
    // ------------------------------------------------------------------
    reg [3:0] por_sync = 4'd0;
    always @(posedge clk_54m or negedge pll_locked) begin
        if (!pll_locked) por_sync <= 4'd0;
        else             por_sync <= {por_sync[2:0], 1'b1};
    end
    wire por_reset_n = por_sync[3];

    // ------------------------------------------------------------------
    //  Front-end del bus MSX (tnCart / tnCartWonder, BSD-3)
    // ------------------------------------------------------------------
    BUS_IF Bus();

    WT200B_BUS u_bus (
        .RESET_n        (por_reset_n),
        .CLK            (clk_108m),
        .CLK_21M        (clk_21m),
        .CART_BUSDIR_n  (CART_BUSDIR_n),
        .CART_INT_n     (CART_INT_n),
        .CART_WAIT_n    (CART_WAIT_n),
        .CART_SLTSL_n   (CART_SLTSL_n),
        .CART_RD_n      (CART_RD_n),
        .CART_WR_n      (CART_WR_n),
        .CART_CLOCK     (CART_CLOCK),
        .CART_MUX_SIG   (CART_MUX_SIG),
        .CART_MUX_CS_n  (CART_MUX_CS_n),
        .CART_DATA_SIG  (CART_DATA_SIG),
        .CART_DATA_DIR  (CART_DATA_DIR),
        .Bus            (Bus)
    );

    // El bus vive en clk_108m; los modulos OPL4 en clk_54m (hermano /2 del
    // mismo PLL -> cruce sincrono, basta un registro). Las señales del bus son
    // cuasi-estaticas a escala del ciclo de I/O del Z80 (~1 us).
    reg        s_iorq_n, s_rd_n, s_wr_n, s_m1_n, s_reset_n;
    reg [7:0]  s_addr, s_din;
    always @(posedge clk_54m) begin
        s_iorq_n  <= Bus.IORQ_n;
        s_rd_n    <= Bus.RD_n;
        s_wr_n    <= Bus.WR_n;
        s_m1_n    <= Bus.M1_n;
        s_addr    <= Bus.ADDR[7:0];
        s_din     <= Bus.DIN;
        s_reset_n <= Bus.RESET_n;
    end

    reg [2:0] rst_sync = 3'd0;
    always @(posedge clk_54m or negedge por_reset_n) begin
        if (!por_reset_n) rst_sync <= 3'd0;
        else              rst_sync <= {rst_sync[1:0], s_reset_n};
    end
    wire bus_reset_n = rst_sync[2];

    // ==================================================================
    //  OPL4 FM (opl4fm) — C4h-C7h
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
    //  OPL4 PCM wavetable (opl4_pcm) — 7Eh-7Fh
    // ==================================================================
    wire        opl4pcm_rd, opl4pcm_wait_n, opl4_dbg_tx;
    wire [7:0]  opl4pcm_dout, opl4pcm_diag;
    wire [5:0]  opl4_mixfm;
    wire signed [15:0] opl4pcm_l, opl4pcm_r;
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
        .diag(opl4pcm_diag), .dbg_tx(opl4_dbg_tx), .vid_diag(4'd0)
    );

    // ==================================================================
    //  Cadena de memoria de ondas: wave_sdram -> wv_to_sdram -> ip_sdram
    // ==================================================================
    wire        wl_req_toggle, wl_we, wl_done_toggle;
    wire [21:0] wl_addr;
    wire [7:0]  wl_wdata;
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

    wire [22:2] sd_address;
    wire        sd_valid, sd_write, sd_refresh, sd_rdata_en, sd_ready;
    wire [31:0] sd_wdata, sd_rdata;
    wire [3:0]  sd_wdata_mask;
    wire        sd_timeout;

    wv_to_sdram u_bridge (
        .clk(clk_108m), .rst_n(por_reset_n),
        .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done), .sd_timeout(sd_timeout),
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
    //  Loader del YRW801 (flash SPI -> SDRAM) al arranque
    // ==================================================================
    wire [23:0] fl_addr;
    wire        fl_rd, fl_data_ready, fl_busy, fl_terminate;
    wire [7:0]  fl_dout;
    wire        wl_error;
    wire [2:0]  wl_dbg_state;
    wire        loader_start = por_reset_n & ~sdram_init_busy;

    yrw801_loader u_loader (
        .clk(clk_54m), .rst_n(por_reset_n), .start(loader_start),
        .flash_addr(fl_addr), .flash_rd(fl_rd), .flash_dout(fl_dout),
        .flash_data_ready(fl_data_ready), .flash_busy(fl_busy),
        .flash_terminate(fl_terminate),
        .wl_req_toggle(wl_req_toggle), .wl_we(wl_we), .wl_addr(wl_addr),
        .wl_wdata(wl_wdata), .wl_done_toggle(wl_done_toggle),
        .wl_done(wl_done), .wl_error(wl_error), .wl_dbg_state(wl_dbg_state)
    );

    flash u_flash (
        .clk(clk_54m), .reset_n(por_reset_n),
        .SCLK(mspi_sclk), .CS(mspi_cs), .MISO(mspi_miso), .MOSI(mspi_mosi),
        .addr(fl_addr), .rd(fl_rd), .dout(fl_dout),
        .data_ready(fl_data_ready), .busy(fl_busy), .terminate(fl_terminate),
        .write_enable(1'b0), .write_din(8'd0), .write_addr(24'd0),
        .write_busy(), .write_terminate(1'b0), .write_counter()
    );
    assign mspi_hold = 1'b1;            // /HOLD inactivo

    // ==================================================================
    //  Vuelta al bus: dato leido + BUSDIR + WAIT + INT
    // ==================================================================
    wire       any_rd  = opl4fm_rd | opl4pcm_rd;
    wire [7:0] rd_data = opl4fm_rd ? opl4fm_dout : opl4pcm_dout;

    assign Bus.DOUT      = rd_data;
    assign Bus.BUSDIR_n  = ~any_rd;          // 0 = reclamamos el bus de datos
    // /WAIT: SOLO el stretch de la lectura wave (el motor ya limita a ~19 us).
    // NO se mete sdram_init_busy: si un PLL no engancha, el MSX quedaria muerto.
    assign Bus.WAIT_n    = opl4pcm_wait_n;
    assign Bus.INT_n     = opl4fm_int_n;

    // ==================================================================
    //  Audio: mezcla OPL4 (FM + wave L/R) con saturacion -> DAC I2S
    // ==================================================================
    // atenuacion canon del FM segun el registro F8 (MixCalc -3dB/paso)
    wire signed [15:0] o4fm_base = opl4_mixfm[0] ? (opl4fm_wav >>> 1) + (opl4fm_wav >>> 2)
                                                 : opl4fm_wav;
    wire signed [15:0] o4fm_att  = o4fm_base >>> opl4_mixfm[2:1];
    wire signed [15:0] fm_term   = (opl4_mixfm[2:0] == 3'd7) ? 16'sd0 : o4fm_att;

    function automatic signed [15:0] sat16(input signed [17:0] v);
        sat16 = (v >  18'sd32767) ? 16'sh7FFF :
                (v < -18'sd32768) ? 16'sh8000 : v[15:0];
    endfunction

    wire signed [17:0] mixL = {{2{fm_term[15]}}, fm_term} + {{2{opl4pcm_l[15]}}, opl4pcm_l};
    wire signed [17:0] mixR = {{2{fm_term[15]}}, fm_term} + {{2{opl4pcm_r[15]}}, opl4pcm_r};

    reg signed [15:0] sampL = 16'sd0, sampR = 16'sd0;
    always @(posedge clk_54m) begin
        sampL <= sat16(mixL);
        sampR <= sat16(mixR);
    end

    // I2S: el transmisor pide UNA muestra por canal. En el instante de carga
    // LRCLK aun lleva el valor del semi-ciclo anterior -> LRCLK=1 carga L.
    wire        dac_lrclk_w;
    reg signed [15:0] i2s_sample;
    always @(posedge clk_dac) i2s_sample <= dac_lrclk_w ? sampL : sampR;

    I2S_AUDIO_TX #(.SAMPLE_WIDTH(16)) u_i2s (
        .CLK_DAC   (clk_dac),
        .RESET_n   (por_reset_n),
        .SAMPLE_IN (i2s_sample),
        .REQ       (),
        .DAC_BCLK  (DAC_BCLK),
        .DAC_LRCLK (dac_lrclk_w),
        .DAC_DIN   (DAC_DIN)
    );
    assign DAC_LRCLK    = dac_lrclk_w;
    assign DAC_SDMODE_n = por_reset_n;      // desmutea al arrancar

    // ==================================================================
    //  LED de diagnostico (pin 75). Codigo de parpadeo:
    //    PLL sin lock      -> apagado
    //    SDRAM iniciando   -> parpadeo rapido
    //    cargando YRW801   -> parpadeo lento
    //    error de carga    -> doble destello
    //    todo OK           -> fijo
    // ==================================================================
    reg [24:0] blink = 25'd0;
    always @(posedge clk_54m) blink <= blink + 25'd1;

    // Telemetria del motor PCM al USB-serie de la placa (BL616). OJO: dbg_tx va
    // relojado bajo eng_rst_n, asi que esta MUDO mientras el loader no termina
    // — es una sonda del motor, no del arranque. Para el arranque, el LED.
    assign UART_TX = opl4_dbg_tx;

    assign LED = !pll_locked    ? 1'b0            :
                 sdram_init_busy ? blink[21]       :
                 wl_error        ? (blink[23] & blink[21]) :
                 !wl_done        ? blink[23]       :
                                   1'b1;

endmodule

`default_nettype wire
