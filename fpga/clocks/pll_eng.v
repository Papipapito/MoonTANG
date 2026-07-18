// ============================================================================
// pll_eng.v — PLL del motor PCM de MoonTANG (rPLL GW2AR-18, cristal 27 MHz)
//
//   CLKIN  = 27.000 MHz
//   CLKOUT = 37.125 MHz  (27 x 11 / 8)  -> clk_eng (motor YMF278B)
//
//   PFD = 27 / 8 = 3.375 MHz (>= 3 MHz, válido).
//   VCO = 37.125 x 16 = 594 MHz (rango 400-1200).
//
// El motor usa un CE fraccionario CE_INC/CE_MOD = 6272/6875 para promediar
// 33.8688 MHz exactos (fs = 44.1 kHz) a partir de estos 37.125 MHz — ver
// opl4_pcm.v. (37.5 MHz habría exigido un PFD de 1.5 MHz, fuera de rango.)
// ============================================================================

module pll_eng (
    input  wire clkin,       // 27 MHz
    output wire clk_eng,     // 37.125 MHz
    output wire lock
);
    wire clkoutp_o, clkoutd_o, clkoutd3_o;
    wire gw_gnd = 1'b0;

    rPLL rpll_inst (
        .CLKOUT   (clk_eng),
        .LOCK     (lock),
        .CLKOUTP  (clkoutp_o),
        .CLKOUTD  (clkoutd_o),
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
    defparam rpll_inst.IDIV_SEL        = 7;      // /8  -> PFD 3.375 MHz
    defparam rpll_inst.DYN_FBDIV_SEL   = "false";
    defparam rpll_inst.FBDIV_SEL       = 10;     // x11 -> 37.125 MHz
    defparam rpll_inst.DYN_ODIV_SEL    = "false";
    defparam rpll_inst.ODIV_SEL        = 16;     // VCO 594 MHz
    defparam rpll_inst.PSDA_SEL        = "0000";
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
    defparam rpll_inst.DYN_SDIV_SEL    = 2;
    defparam rpll_inst.CLKOUTD_SRC     = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC    = "CLKOUT";
    defparam rpll_inst.DEVICE          = "GW2AR-18C";
endmodule
