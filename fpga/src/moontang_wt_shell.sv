// ============================================================================
// moontang_wt_shell.sv — carcasa de la WonderTANG 2.0b / 2.02b alrededor de
//                        moontang_core (el MoonSound en si).
//
// Es todo lo que la placa necesita menos una cosa: el reloj del motor PCM, que
// llega de fuera (clk_eng). Asi sirve para los dos tops de esta placa:
//   moontang_top.sv          sin HDMI: clk_eng de un PLL propio (37,125 MHz)
//   moontang_wt_hdmi_top.sv  con HDMI: clk_eng de los 135 MHz del transmisor
//
// El bus del slot NO llega directo: la WonderTANG multiplexa A0-A15 y el
// control (MERQ/IORQ/CS1/CS2/RESET/RFSH/CS12/M1) en mp[7:0] con msel_n[2:0].
// El front-end (WT200B_BUS + BUS_IF + PIN_FILTER) es de tnCart/tnCartWonder
// (Shinobu Hashimoto / Albert Herranz, BSD-3) — codigo VALIDADO en esta placa.
// El audio sale por el amplificador I2S de la propia Tang Nano 20K (MAX98357A,
// MONO), cuya salida de altavoz la WonderTANG lleva por J3 al SOUNDIN del slot:
// el MoonSound suena por el audio del MSX, mezclado en mono.
//
// Relojes (del cristal de 27 MHz):
//   clk_108m  108 MHz   pll_main CLKOUT   -> bus, SDRAM, arbitraje wave
//   clk_sdram 108 MHz   pll_main CLKOUTP  -> reloj al chip SDRAM (desfasado)
//   clk_54m    54 MHz   pll_main CLKOUTD  -> host de opl4fm/opl4_pcm
//   clk_27m    27 MHz   CLKDIV /4 de 108  -> FM (opl3, CLK_DIV_COUNT=545)
//                       (NO del pad: colgarlo del cristal daba skew -2.57 ns
//                        y 77 violaciones de hold contra clk_54m)
//   clk_21m  21.6 MHz   CLKDIV /5 de 108  -> recuperacion del reloj del MSX
//   clk_dac 1.542 MHz   27/5/3.5          -> BCLK del I2S (48 kHz x 32)
//   clk_eng             (entrada)         -> motor PCM; su CE fraccionario va
//                                            en ENG_CE_INC / ENG_CE_MOD
// ============================================================================

`default_nettype none

module moontang_wt_shell #(
    // 1 = las dos tramas I2S llevan (L+R)/2. OBLIGADO en la WonderTANG 2.0x: el
    // audio sale por el amplificador de la propia Tang Nano 20K (MAX98357A, MONO,
    // cuya salida de altavoz va por J3 al SOUNDIN del slot). Con PA_EN a nivel
    // alto ese chip reproduce UN solo canal: mandarle estereo real dejaria mudo
    // medio MoonSound. El firmware oficial y tnCart tambien mandan mono.
    // 0 = estereo real (para una placa con DAC estereo).
    parameter AUDIO_MONO = 1,
    // ver moontang_core: 0 solo para el control negativo de la simulacion.
    parameter SDRAM_RD_CAPTURE_CLK = 1,
    // fraccion del CE del motor PCM (33,8688 MHz / f(clk_eng)) y divisor de la
    // UART de telemetria (f(clk_eng) / 115200)
    parameter [23:0] ENG_CE_INC   = 24'd6272,
    parameter [23:0] ENG_CE_MOD   = 24'd6875,
    parameter [8:0]  ENG_BAUD_DIV = 9'd322
) (
    // ---- reloj del motor PCM, del top ----
    input  wire        clk_eng,
    input  wire        lock_eng,

    // ---- para una salida de audio/video adicional (HDMI): todo en clk_54m ----
    output wire        clk_54m,
    output wire        lock_main,
    output wire signed [15:0] fm_l,
    output wire signed [15:0] fm_r,
    output wire signed [15:0] wave_l,
    output wire signed [15:0] wave_r,
    output wire signed [15:0] mix_l,
    output wire signed [15:0] mix_r,
    output wire        wl_done,
    output wire        wl_error,
    output wire        wl_badimg,
    output wire        clk_alive,


    input  wire        CLK_27M,        // pin 4

    // ---- bus del cartucho (WonderTANG 2.0b / 2.02b, multiplexado) ----
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

    // ---- amplificador I2S de la Tang ----
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
    wire clk_108m, clk_sdram;

    pll_main u_pll_main (
        .clkin(CLK_27M), .clk_108m(clk_108m), .clk_sdram(clk_sdram),
        .clk_54m(clk_54m), .lock(lock_main)
    );
    // (clk_eng, el reloj del motor PCM, lo pone el top: de un PLL propio o,
    //  con HDMI, de los 135 MHz del transmisor)

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

    wire por_reset_n;

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

    // El bus vive en clk_108m; el nucleo en clk_54m (hermano /2 del mismo PLL
    // -> cruce sincrono, basta un registro). Las señales del bus son
    // cuasi-estaticas a escala del ciclo de I/O del Z80 (~1 us).
    reg        s_iorq_n, s_rd_n, s_wr_n, s_m1_n, s_reset_n, s_clk;
    reg [7:0]  s_addr, s_din;
    always @(posedge clk_54m) begin
        s_iorq_n  <= Bus.IORQ_n;
        s_rd_n    <= Bus.RD_n;
        s_wr_n    <= Bus.WR_n;
        s_m1_n    <= Bus.M1_n;
        s_addr    <= Bus.ADDR[7:0];
        s_din     <= Bus.DIN;
        s_reset_n <= Bus.RESET_n;
        s_clk     <= Bus.CLK;
    end

    // ------------------------------------------------------------------
    //  El MoonSound
    // ------------------------------------------------------------------
    wire [7:0] rd_data;
    wire       rd_active, wait_n, int_n, bus_reset_n;
    wire signed [15:0] mix_mono;
    wire       sdram_init_busy, sd_timeout, opl4_dbg_tx;

    moontang_core #(
        .SDRAM_RD_CAPTURE_CLK(SDRAM_RD_CAPTURE_CLK),
        .ENG_CE_INC(ENG_CE_INC), .ENG_CE_MOD(ENG_CE_MOD),
        .ENG_BAUD_DIV(ENG_BAUD_DIV)
    ) u_core (
        .clk_108m(clk_108m), .clk_sdram(clk_sdram), .clk_54m(clk_54m),
        .clk_27m(clk_27m), .clk_eng(clk_eng),
        .pll_locked(pll_locked), .por_reset_n(por_reset_n),
        .iorq_n(s_iorq_n), .rd_n(s_rd_n), .wr_n(s_wr_n), .m1_n(s_m1_n),
        .addr(s_addr), .din(s_din),
        .slot_reset_n(s_reset_n), .slot_clk(s_clk),
        .rd_data(rd_data), .rd_active(rd_active), .wait_n(wait_n), .int_n(int_n),
        .bus_reset_n(bus_reset_n), .clk_alive(clk_alive),
        .fm_l(fm_l), .fm_r(fm_r), .wave_l(wave_l), .wave_r(wave_r),
        .mix_l(mix_l), .mix_r(mix_r), .mix_mono(mix_mono),
        .sdram_init_busy(sdram_init_busy), .wl_done(wl_done), .wl_error(wl_error), .wl_badimg(wl_badimg),
        .sd_timeout(sd_timeout), .dbg_tx(opl4_dbg_tx),
        .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk), .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_wen_n(O_sdram_wen_n), .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );
    assign mspi_hold = 1'b1;            // /HOLD inactivo

    // ------------------------------------------------------------------
    //  Vuelta al bus (el front-end invierte /WAIT e /INT para los NPN)
    // ------------------------------------------------------------------
    assign Bus.DOUT      = rd_data;
    assign Bus.BUSDIR_n  = ~rd_active;       // 0 = reclamamos el bus de datos
    assign Bus.WAIT_n    = wait_n;
    assign Bus.INT_n     = int_n;

    // ------------------------------------------------------------------
    //  Audio: mezcla del nucleo -> amplificador I2S de la Tang
    // ------------------------------------------------------------------
    wire signed [15:0] sampL = AUDIO_MONO ? mix_mono : mix_l;
    wire signed [15:0] sampR = AUDIO_MONO ? mix_mono : mix_r;

    // I2S: el transmisor carga UNA muestra por canal en el flanco de LRCLK.
    // i2s_feed la deja preparada y quieta desde clk_54m (ver i2s_feed.v y
    // tools/sim/tb_i2s.v). En mono las dos tramas son iguales.
    wire        dac_lrclk_w;
    wire signed [15:0] i2s_sample;
    i2s_feed u_i2s_feed (
        .clk(clk_54m), .lrclk(dac_lrclk_w),
        .samp_l(sampL), .samp_r(sampR), .sample(i2s_sample)
    );

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

    // ------------------------------------------------------------------
    //  LED de diagnostico (pin 75). Codigo de parpadeo:
    //    PLL sin lock      -> apagado
    //    SDRAM iniciando   -> parpadeo rapido
    //    cargando YRW801   -> parpadeo lento
    //    error de carga    -> doble destello
    //    imagen no valida  -> rafagas rapidas cada 0,6 s (la suma no es la de la YRW801)
    //    sin reloj del MSX -> destello corto (cartucho fuera o MSX apagado)
    //    todo OK           -> fijo
    // ------------------------------------------------------------------
    reg [24:0] blink = 25'd0;
    always @(posedge clk_54m) blink <= blink + 25'd1;

    // Telemetria del motor PCM al USB-serie de la placa (BL616). OJO: dbg_tx va
    // relojado bajo eng_rst_n, asi que esta MUDO mientras el loader no termina
    // — es una sonda del motor, no del arranque. Para el arranque, el LED.
    assign UART_TX = opl4_dbg_tx;

    assign LED = !pll_locked     ? 1'b0            :
                 sdram_init_busy ? blink[21]       :
                 wl_error        ? (blink[23] & blink[21]) :
                 wl_badimg       ? (blink[24] & blink[21]) :
                 !wl_done        ? blink[23]       :
                 !clk_alive      ? (blink[24] & blink[23] & blink[22]) :
                                   1'b1;

endmodule

`default_nettype wire
