set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set out_dir [file join $repo_dir synth out_128]
file mkdir $out_dir

set part_name xcve2802-vsvh1760-2MP-e-S

create_project -force bitcoin_miner_128_synth $out_dir -part $part_name
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

add_files -fileset sources_1 [list \
    [file join $repo_dir rtl sha256_core_iterative.sv] \
    [file join $repo_dir rtl sha256_core_fabric.sv] \
    [file join $repo_dir rtl bitcoin_hash_engine.sv] \
    [file join $repo_dir rtl bitcoin_result_cluster_fifo.sv] \
    [file join $repo_dir rtl bitcoin_miner_axi.sv] \
]
add_files -fileset constrs_1 [file join $script_dir bitcoin_miner_250mhz.xdc]

set_property top bitcoin_miner_axi [current_fileset]
set_property generic {NUM_ENGINES=128 CLUSTER_SIZE=16 CLUSTER_FIFO_DEPTH=2 AXI_ADDR_WIDTH=12} [current_fileset]
update_compile_order -fileset sources_1

synth_design -top bitcoin_miner_axi -part $part_name -generic NUM_ENGINES=128 -generic CLUSTER_SIZE=16 -generic CLUSTER_FIFO_DEPTH=2 -generic AXI_ADDR_WIDTH=12 -mode out_of_context

report_utilization -file [file join $out_dir utilization_synth.rpt] -hierarchical
report_timing_summary -file [file join $out_dir timing_summary_synth.rpt]
report_clock_utilization -file [file join $out_dir clock_utilization_synth.rpt]
write_checkpoint -force [file join $out_dir bitcoin_miner_128_synth.dcp]
