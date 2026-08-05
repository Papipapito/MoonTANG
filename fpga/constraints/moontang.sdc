// ============================================================================
// moontang.sdc — restricciones de temporizacion (MoonTANG, WonderTANG 2.00b)
//
// Auditoria 2026-08-05: sin nombrar los relojes de los PLL, Gowin los derivaba
// ambos de clk27 y cronometraba clk_eng <-> clk_108m como SINCRONOS contra una
// alineacion de 0.842 ns (el periodo comun de 37.125 y 108 MHz) -> caminos de
// setup imposibles. Los dos PLL son INDEPENDIENTES: hay que declararlo.
//
// OJO: el parser SDC de Gowin NO admite continuacion de linea con '\'.
// ============================================================================

// ---- reloj base del cristal ----
create_clock -name clk27 -period 37.037 [get_ports {CLK_27M}]

// ---- salidas de los PLL (nombrarlas para poder agruparlas) ----
create_clock -name clk_108m -period 9.259 [get_pins {u_pll_main/rpll_inst/CLKOUT}]
create_clock -name clk_sdram -period 9.259 [get_pins {u_pll_main/rpll_inst/CLKOUTP}]
create_clock -name clk_54m -period 18.518 [get_pins {u_pll_main/rpll_inst/CLKOUTD}]
create_clock -name clk_eng -period 26.936 [get_pins {u_pll_eng/rpll_inst/CLKOUT}]

// ---- los dos PLL no guardan relacion de fase entre si ----
// clk_sdram DEBE quedar en el mismo grupo que clk_108m (es su version desfasada).
set_clock_groups -asynchronous -group [get_clocks {clk_108m clk_sdram clk_54m}] -group [get_clocks {clk_eng}] -group [get_clocks {clk27}]

// ---- FIFO ASINCRONA del host_if del OPL3 (afifo, Gisselquist) ----
// El cruce por codigo Gray de una FIFO asincrona esta DISEÑADO para no cumplir
// hold entre dominios: los registros *_cross son la entrada del sincronizador.
// Al derivar clk_27m del PLL (para matar el skew del pad, que daba 77 holds),
// clk_54m y clk_27m pasan a ser parientes y la herramienta empieza a
// cronometrar ese cruce como si fuera sincrono. Se marca como falso camino;
// el resto de caminos 54<->27 (p.ej. el bus de muestras pcm_out) SI se
// cronometran, que es lo que se quiere.
set_false_path -from [get_regs {u_opl4fm/u_opl3/host_if/afifo/wgray*}] -to [get_regs {u_opl4fm/u_opl3/host_if/afifo/wgray_cross*}]
set_false_path -from [get_regs {u_opl4fm/u_opl3/host_if/afifo/rgray*}] -to [get_regs {u_opl4fm/u_opl3/host_if/afifo/rgray_cross*}]

// ---- primera etapa de los sincronizadores 2FF del opl3 ----
// synchronizer.sv: sync_regs[0] es, por diseño, el registro que ACEPTA entrada
// metaestable; exigirle hold entre dominios no tiene sentido. Es el mismo caso
// que la afifo de arriba (aparecio al emparentar clk_27m con clk_54m).
set_false_path -to [get_regs {*sync_regs[0]*}]

// ---- el bus del slot es asincrono y lentisimo (ciclo de I/O ~1 us) ----
// Ademas cada bit pasa por PIN_FILTER (antirrebote) en el front-end.
set_false_path -from [get_ports {CART_RD_n}]
set_false_path -from [get_ports {CART_WR_n}]
set_false_path -from [get_ports {CART_SLTSL_n}]
set_false_path -from [get_ports {CART_CLOCK}]
set_false_path -from [get_ports {CART_MUX_SIG[*]}]
set_false_path -to [get_ports {CART_MUX_CS_n[*]}]
set_false_path -to [get_ports {CART_DATA_DIR}]
set_false_path -to [get_ports {CART_BUSDIR_n}]
set_false_path -to [get_ports {CART_WAIT_n}]
set_false_path -to [get_ports {CART_INT_n}]
set_false_path -to [get_ports {DAC_BCLK}]
set_false_path -to [get_ports {DAC_LRCLK}]
set_false_path -to [get_ports {DAC_DIN}]
set_false_path -to [get_ports {DAC_SDMODE_n}]
set_false_path -to [get_ports {LED}]
set_false_path -to [get_ports {UART_TX}]
