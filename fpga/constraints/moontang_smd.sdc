// ============================================================================
// moontang_smd.sdc — restricciones de temporizacion (MoonTANG, MSXhdmi_tn20k_smd)
//
//   clk        27 MHz del cristal; es tambien el reloj de pixel (por BUFG)
//   clk_135m   135 MHz, pll_hdmi: serializador TMDS
//   clk_eng    38,571 MHz, CLKDIV /3,5 de los 135: motor PCM
//   clk_108m / clk_sdram / clk_54m   pll_main: SDRAM, bus y host del OPL4
//   (clk_27m del FM = CLKDIV /4 de clk_108m: lo deriva Gowin como generado)
//   clk_audio  48 kHz, 54 MHz / 1125: muestreo del audio HDMI
//
// OJO: el parser SDC de Gowin NO admite continuacion de linea con '\'.
// ============================================================================

create_clock -name clk -period 37.037 [get_ports {clk}]

create_clock -name clk_108m -period 9.259 [get_pins {u_pll_main/rpll_inst/CLKOUT}]
create_clock -name clk_sdram -period 9.259 [get_pins {u_pll_main/rpll_inst/CLKOUTP}]
create_clock -name clk_54m -period 18.518 [get_pins {u_pll_main/rpll_inst/CLKOUTD}]
create_clock -name clk_135m -period 7.407 [get_pins {u_av/u_pll_hdmi/rpll_inst/CLKOUT}]
// (25,0 ns y no 25,926: el divisor /3,5 alterna periodos largos y cortos si el
//  ciclo de trabajo de los 135 MHz no es del 50 %; se restringe al corto)
create_clock -name clk_eng -period 25.000 [get_pins {u_av/u_diveng/CLKOUT}]
create_clock -name clk_audio -period 20833.333 [get_nets {u_av/clk_audio}]

// ---- dominios sin relacion de fase util entre si ----
//  - el motor PCM cruza con el resto por toggles y handshakes (como en la
//    variante WonderTANG, donde tenia PLL propio);
//  - pixel (cristal) y sistema (pll_main) solo se cruzan con datos casi
//    estaticos: niveles del vumetro (cambian una vez por cuadro) y estado;
//  - clk_audio toma muestras que cambian en su flanco de bajada (medio periodo
//    de margen) y el transmisor HDMI lo sincroniza al reloj de pixel.
set_clock_groups -asynchronous -group [get_clocks {clk_108m clk_sdram clk_54m}] -group [get_clocks {clk_eng}] -group [get_clocks {clk}] -group [get_clocks {clk_135m}] -group [get_clocks {clk_audio}]

// ---- FIFO asincrona del host_if del OPL3 y sincronizadores (ver moontang.sdc) ----
set_false_path -from [get_regs {u_core/u_opl4fm/u_opl3/host_if/afifo/wgray*}] -to [get_regs {u_core/u_opl4fm/u_opl3/host_if/afifo/wgray_cross*}]
set_false_path -from [get_regs {u_core/u_opl4fm/u_opl3/host_if/afifo/rgray*}] -to [get_regs {u_core/u_opl4fm/u_opl3/host_if/afifo/rgray_cross*}]
set_false_path -to [get_regs {*sync_regs[0]*}]
set_false_path -from [get_regs {u_core/rst_sync_2_s0}] -to [get_regs {u_core/u_opl4fm/u_opl3/reset_sync/r*}]

// ---- el bus del slot es asincrono y lentisimo (ciclo de E/S ~1 us) ----
set_false_path -from [get_ports {bus_clock}]
set_false_path -from [get_ports {bus_reset_n}]
set_false_path -from [get_ports {bus_mreq_n}]
set_false_path -from [get_ports {bus_iorq_n}]
set_false_path -from [get_ports {bus_rd_n}]
set_false_path -from [get_ports {bus_wr_n}]
set_false_path -from [get_ports {bus_sltsl_n}]
set_false_path -from [get_ports {bus_a[*]}]
set_false_path -from [get_ports {bus_d[*]}]
set_false_path -to [get_ports {bus_d[*]}]
set_false_path -to [get_ports {datadir}]
set_false_path -to [get_ports {ext_a}]
set_false_path -to [get_ports {ext_b}]
set_false_path -to [get_ports {dbg_txd}]
