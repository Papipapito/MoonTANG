// ============================================================================
// moontang_wt_hdmi.sdc — restricciones de temporizacion (MoonTANG, WonderTANG + HDMI)
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
create_clock -name clk_108m -period 9.259 [get_pins {u_wt/u_pll_main/rpll_inst/CLKOUT}]
create_clock -name clk_sdram -period 9.259 [get_pins {u_wt/u_pll_main/rpll_inst/CLKOUTP}]
create_clock -name clk_54m -period 18.518 [get_pins {u_wt/u_pll_main/rpll_inst/CLKOUTD}]
create_clock -name clk_135m -period 7.407 [get_pins {u_av/u_pll_hdmi/rpll_inst/CLKOUT}]
// clk_eng = 135 MHz / 3,5 (CLKDIV) = 38,571 MHz. Se restringe a 25,0 ns y no a
// 25,926: el divisor alterna periodos largos y cortos si el ciclo de trabajo de
// los 135 MHz no es del 50 %.
create_clock -name clk_eng -period 25.000 [get_pins {u_av/u_diveng/CLKOUT}]
// 48 kHz del audio HDMI (54 MHz / 1125)
create_clock -name clk_audio -period 20833.333 [get_nets {u_av/clk_audio}]

// ---- los dos PLL no guardan relacion de fase entre si ----
// clk_sdram DEBE quedar en el mismo grupo que clk_108m (es su version desfasada).
set_clock_groups -asynchronous -group [get_clocks {clk_108m clk_sdram clk_54m}] -group [get_clocks {clk_eng}] -group [get_clocks {clk27}] -group [get_clocks {clk_135m}] -group [get_clocks {clk_audio}]

// ---- FIFO ASINCRONA del host_if del OPL3 (afifo, Gisselquist) ----
// El cruce por codigo Gray de una FIFO asincrona esta DISEÑADO para no cumplir
// hold entre dominios: los registros *_cross son la entrada del sincronizador.
// Al derivar clk_27m del PLL (para matar el skew del pad, que daba 77 holds),
// clk_54m y clk_27m pasan a ser parientes y la herramienta empieza a
// cronometrar ese cruce como si fuera sincrono. Se marca como falso camino;
// el resto de caminos 54<->27 (p.ej. el bus de muestras pcm_out) SI se
// cronometran, que es lo que se quiere.
set_false_path -from [get_regs {u_wt/u_core/u_opl4fm/u_opl3/host_if/afifo/wgray*}] -to [get_regs {u_wt/u_core/u_opl4fm/u_opl3/host_if/afifo/wgray_cross*}]
set_false_path -from [get_regs {u_wt/u_core/u_opl4fm/u_opl3/host_if/afifo/rgray*}] -to [get_regs {u_wt/u_core/u_opl4fm/u_opl3/host_if/afifo/rgray_cross*}]

// ---- primera etapa de los sincronizadores 2FF del opl3 ----
// synchronizer.sv: sync_regs[0] es, por diseño, el registro que ACEPTA entrada
// metaestable; exigirle hold entre dominios no tiene sentido. Es el mismo caso
// que la afifo de arriba (aparecio al emparentar clk_27m con clk_54m).
set_false_path -to [get_regs {*sync_regs[0]*}]

// ---- sincronizador de reset del opl3 (reset_sync.sv) ----
// r0-r2 se ponen a 1 de forma asincrona con el reset del bus y lo sueltan
// sincronizado a clk_27m: la comprobacion de "removal" de ese PRESET contra el
// reloj es justo lo que el sincronizador resuelve (aparecia como 3 endpoints
// de hold violados sin serlo).
set_false_path -from [get_regs {u_wt/u_core/rst_sync_2_s0}] -to [get_regs {u_wt/u_core/u_opl4fm/u_opl3/reset_sync/r*}]

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

// ---- HDMI: el reloj de pixel es el propio cristal (clk27); los 135 MHz solo
// mueven los serializadores. Los niveles del vumetro y el estado cruzan casi
// estaticos; clk_audio toma muestras que cambian en su flanco de bajada.
