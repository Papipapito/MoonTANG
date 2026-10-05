// ============================================================================
// moontang_core.sv — el MoonSound en si, comun a todas las placas.
//
// SOLO OPL4: FM OPL3 (puertos C4h-C7h) + wavetable PCM de 24 voces (7Eh-7Fh),
// con su memoria de ondas (YRW801 copiada de la flash SPI a la SDRAM embebida
// al arrancar) y la mezcla FM + wave. Sin megaram, sin RAM, sin Nextor.
//
// Cada placa pone alrededor su "carcasa": los PLL, el acceso al bus del slot
// (multiplexado en la WonderTANG, directo en la MSXhdmi SMD) y la salida de
// audio (I2S o HDMI). El nucleo recibe el bus YA en el dominio clk_54m.
//
// Relojes que espera:
//   clk_108m / clk_sdram   108 MHz y su version desfasada -> SDRAM
//   clk_54m                 54 MHz, hermano /2 de clk_108m -> host del OPL4
//   clk_27m                 27 MHz, hermano /4 de clk_108m -> FM (opl3)
//   clk_eng                 motor PCM; CE medio de 33,8688 MHz por la fraccion
//                           ENG_CE_INC / ENG_CE_MOD (asincrono con el resto)
// ============================================================================

`default_nettype none

module moontang_core #(
    // 1 = la SDRAM captura la lectura en posedge clk (punto validado a 108 MHz
    // por el firmware oficial de la WonderTANG y por tnCart). 0 = captura
    // original de HRA (posedge clk_sdram), solo para el control negativo de la
    // simulacion.
    parameter SDRAM_RD_CAPTURE_CLK = 1,
    // fraccion del CE del motor PCM: 33,8688 MHz / f(clk_eng)
    //   37,125 MHz -> 6272/6875      38,5714 MHz (135/3,5) -> 2744/3125
    parameter [23:0] ENG_CE_INC = 24'd6272,
    parameter [23:0] ENG_CE_MOD = 24'd6875,
    // divisor de la UART de telemetria del motor: f(clk_eng) / 115200
    parameter [8:0]  ENG_BAUD_DIV = 9'd322,
    // 1 = las lecturas de la memoria de ondas y del identificador (IN 7Fh) se
    // sirven desde el lado del bus, sin esperar al motor: para placas SIN /WAIT.
    // 0 = como el MSXimus Z (el /WAIT cubre el viaje al motor).
    parameter WAVE_RD_MIRROR = 0
) (
    input  wire        clk_108m,
    input  wire        clk_sdram,
    input  wire        clk_54m,
    input  wire        clk_27m,
    input  wire        clk_eng,
    input  wire        pll_locked,
    output wire        por_reset_n,     // reset de encendido, en clk_54m

    // ---- bus del MSX, en el dominio clk_54m ----
    input  wire        iorq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        m1_n,            // 1 si la placa no lo trae
    input  wire [7:0]  addr,
    input  wire [7:0]  din,
    input  wire        slot_reset_n,    // /RESET del slot (nivel)
    input  wire        slot_clk,        // CLOCK del slot (nivel, cualquier dominio)

    output wire [7:0]  rd_data,         // dato para una lectura nuestra
    output wire        rd_active,       // 1 = lectura de C4-C7 / 7E-7F en curso (y bus vivo)
    output wire        wait_n,          // 0 = pedir /WAIT (ya con la guarda de bus)
    output wire        int_n,           // 0 = pedir /INT  (ya con la guarda de bus)
    output wire        bus_reset_n,     // /RESET del slot sincronizado
    output wire        clk_alive,       // el reloj del slot esta presente

    // ---- audio, en clk_54m ----
    output wire signed [15:0] fm_l,     // FM ya atenuado por el registro F8
    output wire signed [15:0] fm_r,
    output wire signed [15:0] wave_l,   // wave ya con su >>1 de mezcla
    output wire signed [15:0] wave_r,
    output reg  signed [15:0] mix_l = 16'sd0,   // FM + wave, saturado
    output reg  signed [15:0] mix_r = 16'sd0,
    output reg  signed [15:0] mix_mono = 16'sd0, // (L+R)/2

    // ---- estado ----
    output wire        sdram_init_busy,
    output wire        wl_done,         // YRW801 cargada (o reintentos agotados)
    output wire        wl_error,        // la carga fallo
    output wire        wl_badimg,       // copiada, pero no es la YRW801 (suma distinta)
    output wire        sd_timeout,      // el puente SDRAM disparo el watchdog
    output wire        dbg_tx,          // telemetria del motor PCM (115200 8N1)

    // ---- flash SPI (imagen YRW801) ----
    output wire        mspi_cs,
    output wire        mspi_sclk,
    input  wire        mspi_miso,
    output wire        mspi_mosi,

    // ---- SDRAM embebida ----
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
    assign por_reset_n = por_sync[3];

    reg       s_reset_n;
    always @(posedge clk_54m) s_reset_n <= slot_reset_n;
    reg [2:0] rst_sync = 3'd0;
    always @(posedge clk_54m or negedge por_reset_n) begin
        if (!por_reset_n) rst_sync <= 3'd0;
        else              rst_sync <= {rst_sync[1:0], s_reset_n};
    end
    assign bus_reset_n = rst_sync[2];

    // ==================================================================
    //  OPL4 FM (opl4fm) — C4h-C7h
    // ==================================================================
    wire        opl4fm_rd, opl4fm_wrd, opl4fm_int_n;
    wire [7:0]  opl4fm_dout, opl4fm_wdout;
    wire signed [15:0] opl4fm_wav;                    // mono (L+R)/2, sin usar aqui
    wire signed [15:0] opl4fm_wav_l, opl4fm_wav_r;    // estereo real del OPL3
    wire [1:0]  wave_status;

    opl4fm u_opl4fm (
        .rst_n(bus_reset_n), .clk_host(clk_54m), .clk_opl3(clk_27m),
        .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n),
        .addr(addr), .din(din), .wave_status(wave_status),
        .fm_rd(opl4fm_rd), .wave_rd(opl4fm_wrd), .dout(opl4fm_dout),
        .wave_dout(opl4fm_wdout), .pcm_out(opl4fm_wav),
        .pcm_out_l(opl4fm_wav_l), .pcm_out_r(opl4fm_wav_r), .int_n(opl4fm_int_n)
    );

    // ==================================================================
    //  OPL4 PCM wavetable (opl4_pcm) — 7Eh-7Fh
    // ==================================================================
    wire        opl4pcm_rd, opl4pcm_wait_n;
    wire [7:0]  opl4pcm_dout, opl4pcm_diag;
    wire [5:0]  opl4_mixfm;
    wire signed [15:0] opl4pcm_l, opl4pcm_r;
    wire        weng_req, weng_we;
    wire [21:0] weng_addr;
    wire [7:0]  weng_wdata, weng_rdata;
    wire [15:0] weng_rword;
    wire        weng_done_t;

    opl4_pcm #(
        .CE_INC(ENG_CE_INC), .CE_MOD(ENG_CE_MOD), .DBG_BAUD_DIV(ENG_BAUD_DIV),
        .RD_MIRROR(WAVE_RD_MIRROR)
    ) u_opl4pcm (
        .rst_n(bus_reset_n), .clk_host(clk_54m),
        .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n),
        .addr(addr), .din(din),
        .wave_rd(opl4pcm_rd), .wave_dout(opl4pcm_dout),
        .wave_wait_n(opl4pcm_wait_n), .wave_status(wave_status),
        .mix_fm(opl4_mixfm), .pcm_l(opl4pcm_l), .pcm_r(opl4pcm_r),
        .clk_eng(clk_eng), .eng_rst_n(bus_reset_n & wl_done),
        .mem_req(weng_req), .mem_we(weng_we), .mem_addr(weng_addr),
        .mem_wdata(weng_wdata), .mem_rdata(weng_rdata),
        .mem_rword(weng_rword), .mem_done_t(weng_done_t),
        .diag(opl4pcm_diag), .dbg_tx(dbg_tx), .vid_diag(4'd0)
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

    wv_to_sdram u_bridge (
        .clk(clk_108m), .rst_n(por_reset_n),
        .wv_req(wv_req), .wv_we(wv_we), .wv_addr(wv_addr), .wv_wdata(wv_wdata),
        .wv_dout(wv_dout), .wv_done(wv_done), .sd_timeout(sd_timeout),
        .bus_address(sd_address), .bus_valid(sd_valid), .bus_write(sd_write),
        .bus_refresh(sd_refresh), .bus_wdata(sd_wdata), .bus_wdata_mask(sd_wdata_mask),
        .bus_rdata(sd_rdata), .bus_rdata_en(sd_rdata_en), .bus_ready(sd_ready)
    );

    ip_sdram #(.FREQ(108_000_000), .RD_CAPTURE_CLK(SDRAM_RD_CAPTURE_CLK)) u_sdram (
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
    wire [2:0]  wl_dbg_state;
    wire        loader_start = por_reset_n & ~sdram_init_busy;

    wire wl_sum_ok;
    assign wl_badimg = wl_done & ~wl_error & ~wl_sum_ok;

    yrw801_loader u_loader (
        .clk(clk_54m), .rst_n(por_reset_n), .start(loader_start),
        .flash_addr(fl_addr), .flash_rd(fl_rd), .flash_dout(fl_dout),
        .flash_data_ready(fl_data_ready), .flash_busy(fl_busy),
        .flash_terminate(fl_terminate),
        .wl_req_toggle(wl_req_toggle), .wl_we(wl_we), .wl_addr(wl_addr),
        .wl_wdata(wl_wdata), .wl_done_toggle(wl_done_toggle),
        .wl_done(wl_done), .wl_error(wl_error), .wl_sum_ok(wl_sum_ok),
        .wl_dbg_state(wl_dbg_state)
    );

    flash u_flash (
        .clk(clk_54m), .reset_n(por_reset_n),
        .SCLK(mspi_sclk), .CS(mspi_cs), .MISO(mspi_miso), .MOSI(mspi_mosi),
        .addr(fl_addr), .rd(fl_rd), .dout(fl_dout),
        .data_ready(fl_data_ready), .busy(fl_busy), .terminate(fl_terminate),
        .write_enable(1'b0), .write_din(8'd0), .write_addr(24'd0),
        .write_busy(), .write_terminate(1'b0), .write_counter()
    );

    // ==================================================================
    //  Vuelta al bus: dato leido + WAIT + INT, con la guarda de bus vivo
    // ==================================================================
    wire any_rd = opl4fm_rd | opl4pcm_rd;
    assign rd_data = opl4fm_rd ? opl4fm_dout : opl4pcm_dout;

    // GUARDA DE BUS VIVO (leccion de SlotDoctor en una WonderTANG real, 23/07/2026):
    // con la Tang alimentada por USB y el MSX apagado o arrancando, las lineas
    // del slot FLOTAN (a menudo a 0) y un decodificador ingenuo puede creer que
    // le leen: conduce D0-D7 contra una maquina que arranca y la deja en bucle de
    // reset. Solo se toca el bus (datos, /WAIT, /INT) si el reloj del slot esta
    // presente y la maquina no esta en /RESET. Ventana de 2^17 ciclos de 54 MHz
    // (2,4 ms): con 3,58 MHz caben ~17000 flancos; se piden 64.
    reg  [2:0]  ck_s = 3'b000;
    reg  [16:0] ck_win = 17'd0;
    reg  [6:0]  ck_edges = 7'd0;
    reg         ck_alive = 1'b0;
    always @(posedge clk_54m) begin
        ck_s   <= {ck_s[1:0], slot_clk};
        ck_win <= ck_win + 17'd1;
        if (ck_win == 17'd0) begin
            ck_alive <= ck_edges[6];
            ck_edges <= 7'd0;
        end
        else if ((ck_s[2] ^ ck_s[1]) && !ck_edges[6])
            ck_edges <= ck_edges + 7'd1;
    end
    assign clk_alive = ck_alive;
    wire bus_ok = ck_alive & bus_reset_n;

    assign rd_active = any_rd & bus_ok;
    // /WAIT: SOLO el stretch de la lectura wave (el motor ya limita a ~19 us).
    // NO se mete sdram_init_busy: si un PLL no engancha, el MSX quedaria muerto.
    assign wait_n = opl4pcm_wait_n | ~bus_ok;
    assign int_n  = opl4fm_int_n   | ~bus_ok;

    // ==================================================================
    //  Mezcla = la del MSXimus Z (top_zynq.v, _180 + estereo del 23/09/2026):
    //   - FM: cada lado a nivel nativo con la atenuacion canon del registro F8
    //     (MixCalc -3 dB/paso; 0,75x = (x>>1)+(x>>2)). El shift vive en un wire
    //     SIGNED propio: un literal sin signo en el ternario degrada el >>> a
    //     shift logico y rectifica los negativos (leccion _85/_115).
    //   - wave: L y R del motor con >>1 (|fm| < 2^15, |pcm>>1| < 2^14: la suma
    //     cabe en 17 bits). Es el balance FM/wave validado de oido en el MSXimus.
    // ==================================================================
    wire signed [15:0] o4fm_sl = $signed(opl4fm_wav_l);
    wire signed [15:0] o4fm_sr = $signed(opl4fm_wav_r);
    wire signed [15:0] o4fm_bl = opl4_mixfm[0] ? (o4fm_sl >>> 1) + (o4fm_sl >>> 2) : o4fm_sl;
    wire signed [15:0] o4fm_br = opl4_mixfm[0] ? (o4fm_sr >>> 1) + (o4fm_sr >>> 2) : o4fm_sr;
    wire signed [15:0] o4fm_al = o4fm_bl >>> opl4_mixfm[2:1];
    wire signed [15:0] o4fm_ar = o4fm_br >>> opl4_mixfm[2:1];
    assign fm_l = (opl4_mixfm[2:0] == 3'd7) ? 16'sd0 : o4fm_al;
    assign fm_r = (opl4_mixfm[2:0] == 3'd7) ? 16'sd0 : o4fm_ar;

    assign wave_l = opl4pcm_l >>> 1;
    assign wave_r = opl4pcm_r >>> 1;

    function automatic signed [15:0] sat16(input signed [17:0] v);
        sat16 = (v >  18'sd32767) ? 16'sh7FFF :
                (v < -18'sd32768) ? 16'sh8000 : v[15:0];
    endfunction

    wire signed [17:0] mixL = {{2{fm_l[15]}}, fm_l} + {{2{wave_l[15]}}, wave_l};
    wire signed [17:0] mixR = {{2{fm_r[15]}}, fm_r} + {{2{wave_r[15]}}, wave_r};
    wire signed [18:0] mixS = {mixL[17], mixL} + {mixR[17], mixR};
    wire signed [17:0] mixM = mixS[18:1];                 // (L+R)/2

    always @(posedge clk_54m) begin
        mix_l    <= sat16(mixL);
        mix_r    <= sat16(mixR);
        mix_mono <= sat16(mixM);
    end

endmodule

`default_nettype wire
