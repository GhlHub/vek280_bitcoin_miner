set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set hw_reports_dir [file join $repo_dir reports vitis_hw]
set xsa_file [file join $hw_reports_dir miner_system_wrapper.xsa]

file mkdir $hw_reports_dir

source [file join $repo_dir bd create_vek280_miner_bd.tcl]

if {[current_project -quiet] eq ""} {
    open_project [file join $repo_dir bd out_vek280_miner vek280_miner_bd.xpr]
}

set_property top miner_system_wrapper [current_fileset]
update_compile_order -fileset sources_1
generate_target all [get_files [file join $repo_dir bd out_vek280_miner vek280_miner_bd.srcs sources_1 bd miner_system miner_system.bd]]
write_hw_platform -fixed -force -file $xsa_file

set status_file [open [file join $hw_reports_dir export_status.rpt] w]
puts $status_file "Generated: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
puts $status_file "XSA: $xsa_file"
puts $status_file "Note: This XSA is for Vitis BSP generation and does not include a post-route PDI."
close $status_file
