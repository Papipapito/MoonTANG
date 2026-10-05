# ============================================================================
#  build_smd.tcl — MoonTANG sobre el cartucho MSXhdmi_tn20k_smd (rev B)
#                  Tang Nano 20K · GW2AR-LV18QN88C8/I7 · audio por HDMI + vumetro
#  Uso: cd fpga && gw_sh build_smd.tcl
# ============================================================================
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

# ----- nucleo comun (OPL3 + motor PCM + memoria de ondas + loader) -----
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
add_file opl4wave/ymf278b_gowin.v
add_file src/opl4_pcm.v
add_file src/wave_sdram.v
add_file src/wv_to_sdram.v
add_file src/ip_sdram_tangnano20k_c.v
add_file src/yrw801_loader.v
add_file src/flash_rw.v
add_file src/moontang_core.sv

# ----- HDMI con audio (hdl-util/hdmi, MIT / Apache-2.0) -----
add_file hdmi/tmds_channel.sv
add_file hdmi/serializer.sv
add_file hdmi/packet_picker.sv
add_file hdmi/packet_assembler.sv
add_file hdmi/audio_clock_regeneration_packet.sv
add_file hdmi/audio_sample_packet.sv
add_file hdmi/audio_info_frame.sv
add_file hdmi/auxiliary_video_information_info_frame.sv
add_file hdmi/source_product_description_info_frame.sv
add_file hdmi/hdmi.sv

# ----- relojes (rPLL GW2A) -----
add_file clocks/pll_main.v
add_file clocks/pll_hdmi.v

# ----- carcasa de la placa SMD: bus directo, vumetro, top -----
add_file src/smd_bus.v
add_file src/font8x8.v
add_file src/vu_meter.v
add_file src/vu_screen.v
add_file src/moontang_av.sv
add_file src/moontang_smd_top.sv

# ----- constraints -----
add_file constraints/moontang_smd.cst
add_file constraints/moontang_smd.sdc

# MSPI = flash del YRW801; SSPI = pines 52-56, que en esta placa son lineas del
# bus. NADA de jtag/cpu/done/ready como GPIO (desconectan el JTAG en marcha).
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
set_option -top_module moontang_smd_top -verilog_std sysv2017 -include_path src
set_option -output_base_name moontang_smd
set_option -place_option 2
set_option -route_option 1

run syn
run pnr
