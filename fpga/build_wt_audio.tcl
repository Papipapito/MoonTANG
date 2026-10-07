# ============================================================================
#  build_wt_audio.tcl — MoonTANG (OPL4/MoonSound) + MSX-Audio (Y8950)
#              Tang Nano 20K · GW2AR-LV18QN88C8/I7
#              WonderTANG 2.0b / 2.02b SIN HDMI (sonido solo al MSX)
#  Uso: cd fpga && gw_sh build_wt_audio.tcl -> impl/pnr/moontang_wt_audio.fs
#  Mismas restricciones que build.tcl (moontang.cst / moontang.sdc).
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
add_file opl3/mem_simple_dual_port_bram.sv
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

# ----- MSX-Audio (Y8950): FM jtopl2 + ADPCM-B jt10 (jotego, GPL-3) + MSXimus -----
add_file y8950/jtopl/jtopl.v
add_file y8950/jtopl/jtopl2.v
add_file y8950/jtopl/jtopl_acc.v
add_file y8950/jtopl/jtopl_csr.v
add_file y8950/jtopl/jtopl_div.v
add_file y8950/jtopl/jtopl_eg.v
add_file y8950/jtopl/jtopl_eg_cnt.v
add_file y8950/jtopl/jtopl_eg_comb.v
add_file y8950/jtopl/jtopl_eg_ctrl.v
add_file y8950/jtopl/jtopl_eg_final.v
add_file y8950/jtopl/jtopl_eg_pure.v
add_file y8950/jtopl/jtopl_eg_step.v
add_file y8950/jtopl/jtopl_exprom.v
add_file y8950/jtopl/jtopl_lfo.v
add_file y8950/jtopl/jtopl_logsin.v
add_file y8950/jtopl/jtopl_mmr.v
add_file y8950/jtopl/jtopl_noise.v
add_file y8950/jtopl/jtopl_op.v
add_file y8950/jtopl/jtopl_pg.v
add_file y8950/jtopl/jtopl_pg_comb.v
add_file y8950/jtopl/jtopl_pg_inc.v
add_file y8950/jtopl/jtopl_pg_rhy.v
add_file y8950/jtopl/jtopl_pg_sum.v
add_file y8950/jtopl/jtopl_pm.v
add_file y8950/jtopl/jtopl_reg.v
add_file y8950/jtopl/jtopl_reg_ch.v
add_file y8950/jtopl/jtopl_sh.v
add_file y8950/jtopl/jtopl_sh_rst.v
add_file y8950/jtopl/jtopl_single_acc.v
add_file y8950/jtopl/jtopl_slot_cnt.v
add_file y8950/jtopl/jtopl_timers.v
add_file y8950/jt10/jt10_adpcm_div.v
add_file y8950/jt10/jt10_adpcmb.v
add_file y8950/jt10/jt10_adpcmb_interpol.v
add_file y8950/y8950_adpcm.v
add_file y8950/adpcm_sdram.v
add_file src/moontang_y8950.sv
add_file src/moontang_mix_y8950.v

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

# ----- front-end de bus WonderTANG 2.0b/2.02b + I2S (tnCart, BSD-3) -----
add_file wondertang/bus.sv
add_file wondertang/wt_bus.sv
add_file wondertang/i2s_audio_tx.sv
add_file src/i2s_feed.v

# ----- relojes (rPLL GW2A) -----
add_file clocks/pll_main.v
add_file clocks/pll_eng.v

# ----- top -----
add_file src/moontang_core.sv
add_file src/moontang_wt_shell.sv
add_file src/moontang_wt_audio_top.sv

# ----- constraints -----
add_file constraints/moontang.cst
add_file constraints/moontang.sdc

# pines dedicados como GPIO: MSPI=flash del loader; SSPI/JTAG/etc = audio y libres
# SOLO MSPI (la flash del YRW801). NADA de jtag/cpu/done/ready como GPIO:
# activan JTAGAsRegularIO y desconectan el JTAG con el core en marcha = la
# trampa 'Gowin Device not found' que ya se sufrio en el Console 60K.
#   MSPI = flash del YRW801; SSPI = pines 52/54/55/56 (datadir + DAC I2S de la
#   WonderTANG). NADA de jtag/cpu/done/ready.
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module moontang_wt_audio_top -verilog_std sysv2017 -include_path src
set_option -output_base_name moontang_wt_audio
set_option -place_option 2
set_option -route_option 1

run syn
run pnr
