# Isolated implementation check: same HDL/constraints as the HDMI release,
# but a distinct output base so existing implementation artefacts stay intact.
set in [open build_wt_hdmi.tcl r]
set script [read $in]
close $in
set script [string map {
    {set_option -output_base_name moontang_wt_hdmi}
    {set_option -output_base_name moontang_wt_hdmi_verify}
} $script]
uplevel #0 $script
