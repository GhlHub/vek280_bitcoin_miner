set repo_dir [file normalize [file join [file dirname [info script]] ..]]
create_project -force probe_cips_sysmon [file join $repo_dir reports probe_cips_sysmon] -part xcve2802-vsvh1760-2MP-e-S
set_property board_part xilinx.com:vek280:part0:1.2 [current_project]
create_bd_design probe_cips_sysmon
set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips cips_0]
set_property -dict [list \
    CONFIG.PS_PMC_CONFIG { \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_INTERFACE_TO_USE {I2C} \
        SMON_PMBUS_ADDRESS {0x18} \
        SMON_PMBUS_UNRESTRICTED {0} \
        PS_I2CSYSMON_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 39 .. 40}}} \
    } \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \
] $cips
validate_bd_design
save_bd_design
puts "CIPS_MATCHING_CONFIG_BEGIN"
foreach prop [lsort [list_property $cips CONFIG.*]] {
    if {[regexp -nocase {smon|sysmon|pmbus|i2c|mio39|mio40|mio41} $prop]} {
        set value [get_property $prop $cips]
        puts "$prop=$value"
    }
}
puts "CIPS_MATCHING_CONFIG_END"
puts "PS_PMC_CONFIG_BEGIN"
set cfg [get_property CONFIG.PS_PMC_CONFIG $cips]
foreach {key value} $cfg {
    if {[regexp -nocase {smon|sysmon|pmbus|i2c|mio39|mio40|mio41} $key]} {
        puts "$key=$value"
    }
}
puts "PS_PMC_CONFIG_END"
write_bd_tcl -force [file join $repo_dir reports probe_cips_sysmon probe_cips_sysmon_recreate.tcl]
