// ============================================================================
// moontang_smd_top.sv — MoonTANG sobre el cartucho MSXhdmi_tn20k_smd (rev B)
//                       Tang Nano 20K (GW2AR-18C), bus directo, salida HDMI
//
// El mismo MoonSound (moontang_core) que en la WonderTANG, pero aqui el sonido
// sale por el HDMI de la Tang, con un vumetro sencillo en pantalla: esta placa
// no lleva la entrada de audio del slot (SOUNDIN) hasta la FPGA.
//
// LO QUE ESTA PLACA NO TIENE (y que consecuencias tiene):
//   /INT   no llega al conector -> el OPL4 no puede interrumpir al MSX. Los
//          flags de los timers se leen igual por C4h, pero el software que
//          espera la interrupcion del timer no avanza.
//   /WAIT  no llega -> no se puede alargar la lectura de la memoria de ondas.
//   /BUSDIR no llega -> en maquinas que lo necesitan para leer E/S de un
//          cartucho, las lecturas de C4h-C7h y 7Eh-7Fh no llegan a la CPU.
//   /M1    no llega -> se da por inactivo (en el reconocimiento de interrupcion
//          /RD y /WR estan inactivos, asi que no hay acceso espurio).
// Quedan dos pines en el zocalo del ESP-01S (J2.1 = pin 75, J2.8 = pin 79).
// Dentro de la Tang los dos llevan una resistencia a masa (y el 79 el LED
// WS2812), asi que NO sirven para tirar directamente de una linea del slot:
// hace falta un transistor por linea (puerta/base al pin, colector abierto a
// la linea), igual que en la WonderTANG. Por eso salen ACTIVOS A NIVEL ALTO
// (1 = activar la linea) y en reposo valen 0, que es tambien lo que hay
// mientras la FPGA se configura. Por defecto no sacan nada (EXT_A/EXT_B = 0):
// es una prevision para un apaño o para una revision de la placa.
//
// Relojes (del cristal de 27 MHz):
//   clk_108m  108 MHz   pll_main CLKOUT     -> SDRAM, arbitraje wave
//   clk_sdram 108 MHz   pll_main CLKOUTP    -> reloj al chip SDRAM (desfasado)
//   clk_54m    54 MHz   pll_main CLKOUTD    -> bus y host del OPL4
//   clk_27m    27 MHz   CLKDIV /4 de 108    -> FM (opl3)
//   y, dentro de moontang_av (HDMI + vumetro):
//   pixel 27 MHz (cristal), 135 MHz (pll_hdmi), 48 kHz de audio, y
//   clk_eng  38,57 MHz  CLKDIV /3,5 de 135  -> motor PCM (CE 2744/3125 -> 44,1k)
// ============================================================================

`default_nettype none

module moontang_smd_top #(
    parameter [8*10-1:0] BUILD = "2026-10-05",
    // que linea saca cada pin del zocalo del ESP-01S (activa a nivel ALTO, para
    // un transistor): 0 = nada, 1 = /INT, 2 = /BUSDIR, 3 = /WAIT
    parameter [1:0] EXT_A = 2'd0,        // pin 75 (J2.1)
    parameter [1:0] EXT_B = 2'd0,        // pin 79 (J2.8)
    // ver moontang_core: 0 solo para el control negativo de la simulacion.
    parameter SDRAM_RD_CAPTURE_CLK = 1
) (
    input  wire        clk,             // 27 MHz de la Tang (pin 4)

    // ---- HDMI de la Tang ----
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,

    // ---- slot MSX (bus directo por U1-U4) ----
    input  wire        bus_clock,
    input  wire        bus_reset_n,
    input  wire        bus_mreq_n,      // sin uso (el MoonSound es solo E/S)
    input  wire        bus_iorq_n,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    input  wire        bus_sltsl_n,     // sin uso
    input  wire [15:0] bus_a,           // solo se decodifica A0-A7
    inout  wire [7:0]  bus_d,
    output wire        datadir,         // sentido de U3: 1 = MSX -> FPGA

    // ---- zocalo del ESP-01S: salidas opcionales para transistores ----
    output wire        ext_a,           // pin 75 (J2.1), ver EXT_A
    output wire        ext_b,           // pin 79 (J2.8), ver EXT_B

    // ---- telemetria del motor PCM por el USB de la Tang (115200 8N1) ----
    output wire        dbg_txd,

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
    // (el reloj de pixel, los 135 MHz y clk_eng los genera moontang_av)
    wire clk_108m, clk_sdram, clk_54m, lock_main;
    pll_main u_pll_main (
        .clkin(clk), .clk_108m(clk_108m), .clk_sdram(clk_sdram),
        .clk_54m(clk_54m), .lock(lock_main)
    );

    wire clk_eng, lock_hdmi;
    wire pll_locked = lock_main & lock_hdmi;

    // clk_27m para el FM: 108/4 (hermano de clk_54m; no el del cristal)
    wire clk_27m;
    CLKDIV u_div27 (.CLKOUT(clk_27m), .HCLKIN(clk_108m), .RESETN(lock_main), .CALIB(1'b0));
    defparam u_div27.DIV_MODE = "4";
    defparam u_div27.GSREN    = "false";

    // ------------------------------------------------------------------
    //  Bus del MSX
    // ------------------------------------------------------------------
    wire        s_iorq_n, s_rd_n, s_wr_n;
    wire [7:0]  s_addr, s_din;
    wire [7:0]  rd_data;
    wire        rd_active, bus_driving;

    smd_bus u_bus (
        .clk(clk_54m),
        .a_pin(bus_a[7:0]), .d_pin(bus_d),
        .iorq_n_pin(bus_iorq_n), .rd_n_pin(bus_rd_n), .wr_n_pin(bus_wr_n),
        .datadir(datadir),
        .iorq_n(s_iorq_n), .rd_n(s_rd_n), .wr_n(s_wr_n),
        .addr(s_addr), .din(s_din),
        .rd_data(rd_data), .rd_active(rd_active),
        .driving(bus_driving)
    );

    // ------------------------------------------------------------------
    //  El MoonSound
    // ------------------------------------------------------------------
    wire        por_reset_n, wait_n, int_n, bus_reset_n_s, clk_alive;
    wire signed [15:0] fm_l, fm_r, wave_l, wave_r, mix_l, mix_r, mix_mono;
    wire        sdram_init_busy, wl_done, wl_error, wl_badimg, sd_timeout;

    moontang_core #(
        .SDRAM_RD_CAPTURE_CLK(SDRAM_RD_CAPTURE_CLK),
        .ENG_CE_INC(24'd2744), .ENG_CE_MOD(24'd3125),   // 33,8688 / 38,5714 MHz
        .ENG_BAUD_DIV(9'd335),                          // 38,5714e6 / 115200
        .WAVE_RD_MIRROR(1)                              // esta placa no tiene /WAIT
    ) u_core (
        .clk_108m(clk_108m), .clk_sdram(clk_sdram), .clk_54m(clk_54m),
        .clk_27m(clk_27m), .clk_eng(clk_eng),
        .pll_locked(pll_locked), .por_reset_n(por_reset_n),
        .iorq_n(s_iorq_n), .rd_n(s_rd_n), .wr_n(s_wr_n), .m1_n(1'b1),
        .addr(s_addr), .din(s_din),
        .slot_reset_n(bus_reset_n), .slot_clk(bus_clock),
        .rd_data(rd_data), .rd_active(rd_active), .wait_n(wait_n), .int_n(int_n),
        .bus_reset_n(bus_reset_n_s), .clk_alive(clk_alive),
        .fm_l(fm_l), .fm_r(fm_r), .wave_l(wave_l), .wave_r(wave_r),
        .mix_l(mix_l), .mix_r(mix_r), .mix_mono(mix_mono),
        .sdram_init_busy(sdram_init_busy), .wl_done(wl_done), .wl_error(wl_error), .wl_badimg(wl_badimg),
        .sd_timeout(sd_timeout), .dbg_tx(dbg_txd),
        .mspi_cs(mspi_cs), .mspi_sclk(mspi_sclk), .mspi_miso(mspi_miso), .mspi_mosi(mspi_mosi),
        .O_sdram_clk(O_sdram_clk), .O_sdram_cke(O_sdram_cke), .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_wen_n(O_sdram_wen_n), .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr), .O_sdram_ba(O_sdram_ba), .O_sdram_dqm(O_sdram_dqm)
    );
    assign mspi_hold = 1'b1;            // /HOLD inactivo

    // lineas opcionales para transistores (1 = activar; ya con la guarda de bus)
    function automatic ext_line(input [1:0] sel, input i_n, input busdir, input w_n);
        case (sel)
            2'd1:    ext_line = ~i_n;
            2'd2:    ext_line = busdir;
            2'd3:    ext_line = ~w_n;
            default: ext_line = 1'b0;
        endcase
    endfunction
    assign ext_a = ext_line(EXT_A, int_n, bus_driving, wait_n);
    assign ext_b = ext_line(EXT_B, int_n, bus_driving, wait_n);

    // ------------------------------------------------------------------
    //  HDMI: sonido estereo a 48 kHz + vumetro (y el reloj del motor PCM)
    // ------------------------------------------------------------------
    moontang_av #(.BUILD(BUILD), .AUDIO_BUFG(1)) u_av (
        .clk(clk), .clk_54m(clk_54m), .sys_locked(lock_main),
        .clk_eng(clk_eng), .lock(lock_hdmi),
        .fm_l(fm_l), .fm_r(fm_r), .wave_l(wave_l), .wave_r(wave_r),
        .mix_l(mix_l), .mix_r(mix_r),
        .wl_done(wl_done), .wl_error(wl_error), .wl_badimg(wl_badimg), .clk_alive(clk_alive),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );

endmodule

`default_nettype wire
