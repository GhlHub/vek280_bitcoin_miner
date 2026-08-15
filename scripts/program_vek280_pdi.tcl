set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]

set hw_url "10.0.1.109:3121"
if {[info exists ::env(HW_SERVER_URL)] && $::env(HW_SERVER_URL) ne ""} {
    set hw_url $::env(HW_SERVER_URL)
}

set pdi_file [file join $repo_dir bd out_vek280_miner vek280_miner_bd.runs impl_1 miner_system_wrapper.pdi]
if {[info exists ::env(PDI_FILE)] && $::env(PDI_FILE) ne ""} {
    set pdi_file $::env(PDI_FILE)
}
if {![file exists $pdi_file]} {
    error "PDI file not found: $pdi_file"
}

open_hw_manager
connect_hw_server -url $hw_url
# Keep the JTAG TAP in Test-Logic-Reset before PLM powers the PS domains.
# This is the AMD-documented workaround for Versal APU/RPU power-up hangs
# while a JTAG debugger is attached (Answer 73169).
open_hw_target -jtag_mode true
runtest_hw_jtag -wait_state RESET -end_state IDLE -tck 5
close_hw_target
open_hw_target

set device ""
foreach candidate [get_hw_devices] {
    set part [get_property PART $candidate]
    puts "Found hardware device: $candidate PART=$part"
    if {[string match -nocase "*xcve2802*" $part]} {
        set device $candidate
        break
    }
}
if {$device eq ""} {
    set devices [get_hw_devices]
    if {[llength $devices] == 0} {
        error "No hardware devices found on $hw_url"
    }
    set device [lindex $devices 0]
}

current_hw_device $device
refresh_hw_device $device
puts "Programming $device with $pdi_file"
set_property PROGRAM.FILE $pdi_file $device
set program_status [catch {program_hw_devices $device} program_result]
if {$program_status != 0} {
    puts "PROGRAM_ERROR=$program_result"
}
# program_hw_devices reports transfer completion before the Versal PLM has
# loaded the LPD/FPD/PL partitions.  The VEK280 miner PDI needs about 13 s for
# that handoff; keep the hardware-server session open until PS debug targets
# are available to the subsequent R5 load step.
after 16000
refresh_hw_device $device

foreach prop {
    REGISTER.IR.STATUS.DONE
    REGISTER.ERROR_STATUS
    REGISTER.PMC_ERR1_STATUS
    REGISTER.PMC_ERR2_STATUS
    REGISTER.PMC_BOOT_STATUS
    REGISTER.PL_STATUS
} {
    if {![catch {set value [get_property $prop $device]}]} {
        puts "$prop=$value"
    }
}

close_hw_manager
if {$program_status != 0} {
    error "program_hw_devices failed: $program_result"
}
