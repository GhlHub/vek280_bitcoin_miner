set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set out_dir [file join $repo_dir synth out_miner32_ooc]
set reports_dir [file join $repo_dir reports synth_miner32_ooc]
set part_name xcve2802-vsvh1760-2MP-e-S
set jobs 1
if {[info exists ::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) ne ""} {
    set jobs $::env(VIVADO_JOBS)
}
set_param general.maxThreads $jobs

file mkdir $out_dir
file mkdir $reports_dir

read_verilog -sv [list \
    [file join $repo_dir rtl sha256_core_iterative.sv] \
    [file join $repo_dir rtl sha256_core_fabric.sv] \
    [file join $repo_dir rtl sha256_core_dsp.sv] \
    [file join $repo_dir rtl bitcoin_sha256_core.sv] \
    [file join $repo_dir rtl bitcoin_hash_engine.sv] \
    [file join $repo_dir rtl bitcoin_result_cluster_fifo.sv] \
    [file join $repo_dir rtl bitcoin_miner_axi.sv] \
    [file join $repo_dir rtl bitcoin_miner_axi_32.sv] \
]
read_xdc [file join $repo_dir synth bitcoin_miner_250mhz.xdc]

synth_design -top bitcoin_miner_axi_32 -part $part_name -mode out_of_context \
    -flatten_hierarchy none -directive RuntimeOptimized

set_property HD.PARTITION 1 [current_design]
report_utilization -file [file join $reports_dir utilization_miner32_ooc.rpt] -hierarchical
report_timing_summary -file [file join $reports_dir timing_miner32_ooc.rpt]
write_checkpoint -force [file join $out_dir bitcoin_miner_axi_32_ooc.dcp]
