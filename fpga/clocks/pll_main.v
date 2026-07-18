// ============================================================================
// pll_main.v — PLL principal de MoonTANG (rPLL GW2AR-18, cristal 27 MHz)
//
//   CLKIN  = 27.000 MHz (cristal onboard de la Tang Nano 20K, pin 4)
//   CLKOUT = 108.000 MHz  (27 x 4)          -> clk_108m  (SDRAM + arbitraje wv)
//   CLKOUTP= 108.000 MHz desfasado          -> clk_sdram (reloj al chip SDRAM)
//   CLKOUTD= 54.000  MHz  (108 / 2)         -> clk_54m   (bus host)
//
//   VCO = CLKOUT x ODIV = 108 x 8 = 864 MHz (rango válido 400-1200).
//   PFD = CLKIN / IDIV  = 27 / 1  = 27 MHz  (holgado).
//
// NOTA HW: la fase de CLKOUTP (PSDA_SEL) fija el margen setup/hold del reloj
// que ve el chip SDRAM. Se deja en ~180 grados como punto de partida; es un
// parámetro a AFINAR en placa real (la SDRAM de la Tang no es igual en todas
// las revisiones). Derivado del patrón rPLL de hra1129 (V9968).
// ============================================================================

module pll_main (
    input  wire clkin,       // 27 MHz
    output wire clk_108m,    // CLKOUT
    output wire clk_sdram,   // CLKOUTP (108 MHz desfasado)
    output wire clk_54m,     // CLKOUTD
    output wire lock
);
    wire clkoutd3_o;
    wire gw_gnd = 1'b0;

    rPLL rpll_inst (
        .CLKOUT   (clk_108m),
        .LOCK     (lock),
        .CLKOUTP  (clk_sdram),
        .CLKOUTD  (clk_54m),
        .CLKOUTD3 (clkoutd3_o),
        .RESET    (gw_gnd),
        .RESET_P  (gw_gnd),
        .CLKIN    (clkin),
        .CLKFB    (gw_gnd),
        .FBDSEL   ({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .IDSEL    ({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .ODSEL    ({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .PSDA     ({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .DUTYDA   ({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
        .FDLY     ({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
    );

    defparam rpll_inst.FCLKIN          = "27";
    defparam rpll_inst.DYN_IDIV_SEL    = "false";
    defparam rpll_inst.IDIV_SEL        = 0;      // /1  -> PFD 27 MHz
    defparam rpll_inst.DYN_FBDIV_SEL   = "false";
    defparam rpll_inst.FBDIV_SEL       = 3;      // x4  -> 108 MHz
    defparam rpll_inst.DYN_ODIV_SEL    = "false";
    defparam rpll_inst.ODIV_SEL        = 8;      // VCO 864 MHz
    defparam rpll_inst.PSDA_SEL        = "1000"; // ~180 deg (afinar en HW)
    defparam rpll_inst.DYN_DA_EN       = "true";
    defparam rpll_inst.DUTYDA_SEL      = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR   = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR  = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP= 0;
    defparam rpll_inst.CLKFB_SEL       = "internal";
    defparam rpll_inst.CLKOUT_BYPASS   = "false";
    defparam rpll_inst.CLKOUTP_BYPASS  = "false";
    defparam rpll_inst.CLKOUTD_BYPASS  = "false";
    defparam rpll_inst.DYN_SDIV_SEL    = 2;      // CLKOUTD = CLKOUT/2 = 54 MHz
    defparam rpll_inst.CLKOUTD_SRC     = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC    = "CLKOUT";
    defparam rpll_inst.DEVICE          = "GW2AR-18C";
endmodule
