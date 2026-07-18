// ============================================================================
// moontang.sdc — restricciones de temporización (MoonTANG, Tang Nano 20K)
//
// El reloj base es el cristal de 27 MHz; los PLL derivan 108/54/37.125. El bus
// del MSX es asíncrono y lento (~1us/ciclo) frente a la lógica interna, así que
// se declara como falso camino (se sincroniza por 2FF en el top).
// ============================================================================

// reloj base
create_clock -name clk27 -period 37.037 [get_ports {clk}]

// el reloj de bus de 14.318 MHz (sin usar en la lógica, pero es una entrada)
create_clock -name clk14m -period 69.841 [get_ports {clk14m}]

// las señales del slot son asíncronas (sincronizadas por 2FF en moontang_top)
set_false_path -from [get_ports {slot_iorq_n slot_rd_n slot_wr_n slot_reset_n}]
set_false_path -from [get_ports {slot_a[*]}]
set_false_path -from [get_ports {slot_d[*]}]
set_false_path -to   [get_ports {slot_wait slot_intr slot_data_dir oe_n}]
set_false_path -to   [get_ports {audio_l audio_r}]
