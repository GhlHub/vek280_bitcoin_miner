set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set bd_script [file join $repo_dir bd create_vek280_miner_bd.tcl]
set num_miner_slaves 1
if {[info exists ::env(MINER_NUM_SLAVES)] && $::env(MINER_NUM_SLAVES) ne ""} {
    set num_miner_slaves $::env(MINER_NUM_SLAVES)
}
set use_ooc_miner32 0
if {[info exists ::env(MINER_USE_OOC_MINER32)] && $::env(MINER_USE_OOC_MINER32) ne ""} {
    set use_ooc_miner32 $::env(MINER_USE_OOC_MINER32)
}
set explicit_dsp 0
if {[info exists ::env(MINER_EXPLICIT_DSP)] && $::env(MINER_EXPLICIT_DSP) ne ""} {
    set explicit_dsp $::env(MINER_EXPLICIT_DSP)
}
set variant_suffix ""
if {[info exists ::env(MINER_ENABLE_DDR)] && !$::env(MINER_ENABLE_DDR)} {
    set variant_suffix "_noddr"
}
if {$num_miner_slaves != 1} {
    append variant_suffix "_${num_miner_slaves}x32"
}
if {$use_ooc_miner32} {
    append variant_suffix "_ooc"
}
if {$explicit_dsp} {
    append variant_suffix "_dsp"
}
set project_file [file join $repo_dir bd out_vek280_miner${variant_suffix} vek280_miner_bd.xpr]
set impl_reports_dir [file join $repo_dir reports impl_vek280${variant_suffix}]
set xsa_file [file join $impl_reports_dir miner_system_wrapper.xsa]
set vivado_jobs 4
if {[info exists ::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) ne ""} {
    set vivado_jobs $::env(VIVADO_JOBS)
}
set_param general.maxThreads $vivado_jobs

file mkdir $impl_reports_dir

source $bd_script

if {[current_project -quiet] eq ""} {
    open_project $project_file
}
set_property top miner_system_wrapper [current_fileset]
update_compile_order -fileset sources_1

generate_target all [get_files [file join $repo_dir bd out_vek280_miner${variant_suffix} vek280_miner_bd.srcs sources_1 bd miner_system miner_system.bd]]

reset_run synth_1
launch_runs synth_1 -jobs $vivado_jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 did not complete"
}

if {$use_ooc_miner32} {
    set miner32_ooc_suffix "_ooc"
    if {$explicit_dsp} {
        append miner32_ooc_suffix "_dsp"
    }
    set miner32_dcp [file join $repo_dir synth out_miner32${miner32_ooc_suffix} bitcoin_miner_axi_32_ooc.dcp]
    if {![file exists $miner32_dcp]} {
        error "Missing OOC miner checkpoint: $miner32_dcp. Run make synth-miner32-ooc first."
    }

    open_run synth_1
    for {set idx 0} {$idx < $num_miner_slaves} {incr idx} {
        set cell_path [format "miner_system_i/miner_%d/inst" $idx]
        set cell [get_cells -quiet $cell_path]
        if {[llength $cell] == 0} {
            error "OOC insertion cell not found: $cell_path"
        }
        read_checkpoint -cell $cell $miner32_dcp
    }
    read_xdc -quiet [file join $repo_dir impl miner4x32_pblocks.xdc]
    write_checkpoint -force [file join $impl_reports_dir miner_system_wrapper_ooc_linked.dcp]

    opt_design -directive Explore
    write_checkpoint -force [file join $impl_reports_dir miner_system_wrapper_opt.dcp]
    place_design -directive AggressiveExplore
    write_checkpoint -force [file join $impl_reports_dir miner_system_wrapper_placed.dcp]
    phys_opt_design -directive AggressiveExplore
    write_checkpoint -force [file join $impl_reports_dir miner_system_wrapper_physopt.dcp]
    route_design -directive AggressiveExplore
    phys_opt_design -directive Explore
    write_checkpoint -force [file join $impl_reports_dir miner_system_wrapper_routed.dcp]
    write_device_image -force -file [file join $repo_dir bd out_vek280_miner${variant_suffix} miner_system_wrapper.pdi]

    set impl_status "Manual OOC implementation Complete!"
} else {
    launch_runs impl_1 -to_step write_device_image -jobs $vivado_jobs
    wait_on_run impl_1

    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "impl_1 status: $impl_status"

    if {[string match "*Complete!*" $impl_status]} {
        open_run impl_1
    }
}

if {[string match "*Complete!*" $impl_status] || [string match "*Manual OOC implementation Complete!*" $impl_status]} {
    report_utilization -file [file join $impl_reports_dir utilization_impl.rpt] -hierarchical
    report_timing_summary -file [file join $impl_reports_dir timing_summary_impl.rpt]
    report_route_status -file [file join $impl_reports_dir route_status_impl.rpt]
    report_power -file [file join $impl_reports_dir power_impl.rpt]
    write_hw_platform -fixed -include_bit -force -file $xsa_file
}

set status_file [open [file join $impl_reports_dir impl_status.rpt] w]
puts $status_file "impl_1 status: $impl_status"
puts $status_file "Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
close $status_file

if {![string match "*Complete!*" $impl_status] && ![string match "*Manual OOC implementation Complete!*" $impl_status]} {
    error "impl_1 failed or stopped before write_device_image completed: $impl_status"
}
