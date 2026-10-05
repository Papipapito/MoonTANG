// ============================================================================
// moontang_wt_hdmi_top.sv — MoonTANG sobre WonderTANG 2.0b / 2.02b, CON HDMI.
//                           Tang Nano 20K (GW2AR-18C)
//
// Lo mismo que moontang_top.sv y ADEMAS, a la vez, por el HDMI de la Tang:
// el sonido en estereo y un vumetro en pantalla (moontang_av). El MSX sigue
// recibiendo el audio por SOUNDIN como siempre; el HDMI es una salida mas.
//
// Unica diferencia interna: el GW2AR-18 solo tiene dos PLL y el HDMI necesita
// uno (135 MHz), asi que el motor PCM deja su PLL propio y toma el reloj de
// esos 135 MHz:
//   clk_eng 38,571 MHz  135 / 3,5 (CLKDIV)  -> motor PCM (CE 2744/3125 -> 44,1 kHz)
// Es la misma configuracion de relojes que la placa MSXhdmi_tn20k_smd.
// ============================================================================

`default_nettype none

module moontang_wt_hdmi_top #(
    parameter [8*10-1:0] BUILD = "2026-10-05",
    parameter AUDIO_MONO = 1,               // ver moontang_wt_shell
    parameter SDRAM_RD_CAPTURE_CLK = 1      // ver moontang_core
) (

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
    output wire [3:0]  O_sdram_dqm,

    // ---- HDMI de la Tang ----
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n
);

    wire clk_eng, lock_hdmi;
    wire clk_54m, lock_main;
    wire signed [15:0] fm_l, fm_r, wave_l, wave_r, mix_l, mix_r;
    wire wl_done, wl_error, wl_badimg, clk_alive;

    moontang_wt_shell #(
        .AUDIO_MONO(AUDIO_MONO), .SDRAM_RD_CAPTURE_CLK(SDRAM_RD_CAPTURE_CLK),
        .ENG_CE_INC(24'd2744), .ENG_CE_MOD(24'd3125),   // 33,8688 / 38,5714 MHz
        .ENG_BAUD_DIV(9'd335)                           // 38,5714e6 / 115200
    ) u_wt (
        .clk_eng(clk_eng), .lock_eng(lock_hdmi),
        .clk_54m(clk_54m), .lock_main(lock_main),
        .fm_l(fm_l), .fm_r(fm_r), .wave_l(wave_l), .wave_r(wave_r),
        .mix_l(mix_l), .mix_r(mix_r),
        .wl_done(wl_done), .wl_error(wl_error), .wl_badimg(wl_badimg), .clk_alive(clk_alive),
        .CLK_27M(CLK_27M),
        .CART_BUSDIR_n(CART_BUSDIR_n),
        .CART_INT_n(CART_INT_n),
        .CART_WAIT_n(CART_WAIT_n),
        .CART_SLTSL_n(CART_SLTSL_n),
        .CART_RD_n(CART_RD_n),
        .CART_WR_n(CART_WR_n),
        .CART_CLOCK(CART_CLOCK),
        .CART_MUX_SIG(CART_MUX_SIG),
        .CART_MUX_CS_n(CART_MUX_CS_n),
        .CART_DATA_SIG(CART_DATA_SIG),
        .CART_DATA_DIR(CART_DATA_DIR),
        .DAC_BCLK(DAC_BCLK),
        .DAC_LRCLK(DAC_LRCLK),
        .DAC_DIN(DAC_DIN),
        .DAC_SDMODE_n(DAC_SDMODE_n),
        .LED(LED),
        .UART_TX(UART_TX),
        .mspi_cs(mspi_cs),
        .mspi_sclk(mspi_sclk),
        .mspi_miso(mspi_miso),
        .mspi_mosi(mspi_mosi),
        .mspi_hold(mspi_hold),
        .O_sdram_clk(O_sdram_clk),
        .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_ras_n(O_sdram_ras_n),
        .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm)
    );

    // HDMI: sonido estereo a 48 kHz + vumetro, y el reloj del motor PCM.
    // AUDIO_BUFG(0): esta variante ya ocupa las 8 redes globales de reloj; los
    // 48 kHz (una treintena de registros) van por rutado normal.
    moontang_av #(.BUILD(BUILD), .AUDIO_BUFG(0)) u_av (
        .clk(CLK_27M), .clk_54m(clk_54m), .sys_locked(lock_main),
        .clk_eng(clk_eng), .lock(lock_hdmi),
        .fm_l(fm_l), .fm_r(fm_r), .wave_l(wave_l), .wave_r(wave_r),
        .mix_l(mix_l), .mix_r(mix_r),
        .wl_done(wl_done), .wl_error(wl_error), .wl_badimg(wl_badimg), .clk_alive(clk_alive),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

endmodule

`default_nettype wire
