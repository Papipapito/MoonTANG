# Isolated implementation check for the HDMI + MSX-Audio bitstream.  It keeps
# the release artefacts untouched by using a distinct output base name.
set in [open build_wt_hdmi_audio.tcl r]
set script [read $in]
close $in
set script [string map {
    {set_option -output_base_name moontang_wt_hdmi_audio}
    {set_option -output_base_name moontang_wt_hdmi_audio_verify}
} $script]
uplevel #0 $script
