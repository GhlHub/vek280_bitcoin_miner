set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set out_dir [file join $repo_dir synth out_sha256_5phase]
set reports_dir [file join $repo_dir reports synth_sha256_5phase]
set part_name xcve2802-vsvh1760-2MP-e-S
file mkdir $out_dir
file mkdir $reports_dir
create_project -force sha256_5phase_ooc $out_dir -part $part_name
set_property target_language Verilog [current_project]
add_files -fileset sources_1 [list \
    [file join $repo_dir rtl dsp58_add32.sv] \
    [file join $repo_dir rtl sha256_core_iterative.sv] \
    [file join $repo_dir rtl sha256_core_dsp_explicit.sv]]
add_files -fileset constrs_1 [file join $script_dir sha256_4phase.xdc]
synth_design -top sha256_core_dsp_explicit -part $part_name -mode out_of_context -flatten_hierarchy none
report_utilization -file [file join $reports_dir utilization.rpt] -hierarchical
report_timing_summary -file [file join $reports_dir timing_summary.rpt]
write_checkpoint -force [file join $out_dir sha256_core_5phase_ooc.dcp]
