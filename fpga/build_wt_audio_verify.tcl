# Isolated implementation check for the WonderTANG OPL4 + MSX-Audio build.
set in [open build_wt_audio.tcl r]
set script [read $in]
close $in
set script [string map {
    {set_option -output_base_name moontang_wt_audio}
    {set_option -output_base_name moontang_wt_audio_verify}
} $script]
uplevel #0 $script
