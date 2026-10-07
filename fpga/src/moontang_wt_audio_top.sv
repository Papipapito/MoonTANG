// ============================================================================
// moontang_wt_audio_top.sv — MoonTANG + MSX-Audio: MoonSound (OPL4) y Y8950
//                   Tang Nano 20K (GW2AR-18C) sobre WonderTANG 2.0b / 2.02b
//
// Variante SIN HDMI y CON MSX-Audio: lo mismo que moontang_top.sv (el sonido va
// solo al MSX: amplificador de la Tang -> J3 -> SOUNDIN) y ademas el Y8950 en
// C0h-C1h, con sus 256 KB de RAM de muestras en la SDRAM.
//
// Mismos puertos y mismos nombres de instancia (u_pll_eng, u_wt) que
// moontang_top.sv: usa sus mismas restricciones (moontang.cst, moontang.sdc).
// Quien tenga un MSX-Audio de verdad en otro slot debe usar el bitstream sin
// Y8950 (moontang_wt): los dos contestarian a las lecturas de C0h-C1h.
// ============================================================================

`default_nettype none

module moontang_wt_audio_top #(
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
    output wire [3:0]  O_sdram_dqm
);

    wire clk_eng, lock_eng;
    pll_eng u_pll_eng (
        .clkin(CLK_27M), .clk_eng(clk_eng), .lock(lock_eng)
    );

    moontang_wt_shell #(
        .AUDIO_MONO(AUDIO_MONO), .SDRAM_RD_CAPTURE_CLK(SDRAM_RD_CAPTURE_CLK),
        .ENG_CE_INC(24'd6272), .ENG_CE_MOD(24'd6875),   // 33,8688 / 37,125 MHz
        .ENG_BAUD_DIV(9'd322),
        .Y8950(1)                                        // MSX-Audio en C0h-C1h
    ) u_wt (
        .clk_eng(clk_eng), .lock_eng(lock_eng),
        .clk_54m(), .lock_main(),
        .fm_l(), .fm_r(), .wave_l(), .wave_r(), .mix_l(), .mix_r(),
        .wl_done(), .wl_error(), .wl_badimg(), .clk_alive(),
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

endmodule

`default_nettype wire
