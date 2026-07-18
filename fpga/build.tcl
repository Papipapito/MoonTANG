# ============================================================================
#  build.tcl — MoonTANG (OPL4/MoonSound) · Tang Nano 20K · GW2AR-LV18QN88C8/I7
#  Uso: cd fpga && gw_sh build.tcl
# ============================================================================
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

# ----- core FM OPL3 (gtaylormb/opl3_fpga, fork mangOPL4) — paquete PRIMERO -----
add_file opl3/opl3_pkg.sv
add_file opl3/afifo.v
add_file opl3/calc_envelope_shift.sv
add_file opl3/calc_phase_inc.sv
add_file opl3/calc_rhythm_phase.sv
add_file opl3/channels.sv
add_file opl3/clk_div.sv
add_file opl3/control_operators.sv
add_file opl3/dac_prep.sv
add_file opl3/edge_detector.sv
add_file opl3/envelope_generator.sv
add_file opl3/host_if.sv
add_file opl3/ksl_add_rom.sv
add_file opl3/leds.sv
add_file opl3/mem_multi_bank.sv
add_file opl3/mem_multi_bank_reset.sv
add_file opl3/mem_simple_dual_port.sv
add_file opl3/mem_simple_dual_port_async_read.sv
add_file opl3/operator.sv
add_file opl3/opl3.sv
add_file opl3/opl3_exp_lut.sv
add_file opl3/opl3_log_sine_lut.sv
add_file opl3/phase_generator.sv
add_file opl3/pipeline_sr.sv
add_file opl3/reset_sync.sv
add_file opl3/synchronizer.sv
add_file opl3/timer.sv
add_file opl3/timers.sv
add_file opl3/tremolo.sv
add_file opl3/trick_sw_detection.sv
add_file opl3/vibrato.sv
add_file src/opl4fm.v

# ----- motor PCM wavetable (srg320 YMF278B via sv2v) + shim wave -----
add_file opl4wave/ymf278b_gowin.v
add_file src/opl4_pcm.v
add_file src/wave_sdram.v

# ----- subsistema de memoria: puente + controlador SDRAM (hra1129, PROBADO) -----
add_file src/wv_to_sdram.v
add_file src/ip_sdram_tangnano20k_c.v

# ----- loader YRW801 + lector de flash SPI -----
add_file src/yrw801_loader.v
add_file src/flash_rw.v

# ----- audio -----
add_file src/sigma_delta_dac.v

# ----- relojes (rPLL GW2A) -----
add_file clocks/pll_main.v
add_file clocks/pll_eng.v

# ----- top -----
add_file src/moontang_top.v

# ----- constraints -----
add_file constraints/moontang.cst
add_file constraints/moontang.sdc

# pines dedicados como GPIO: MSPI=flash del loader; SSPI/JTAG/etc = audio y libres
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1 -use_jtag_as_gpio 1 -use_cpu_as_gpio 1 -use_done_as_gpio 1 -use_ready_as_gpio 1
set_option -top_module moontang_top -verilog_std sysv2017 -include_path src
set_option -place_option 2
set_option -route_option 1

run syn
run pnr
