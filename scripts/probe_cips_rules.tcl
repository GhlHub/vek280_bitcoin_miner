set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set out_dir [file join $repo_dir reports probe_cips_rules]

create_project -force probe_cips_rules $out_dir -part xcve2802-vsvh1760-2MP-e-S
set_property board_part xilinx.com:vek280:part0:1.2 [current_project]
create_bd_design probe_cips
current_bd_design probe_cips

set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips cips_0]

puts "BD_AUTOMATION_HELP_BEGIN"
catch {help apply_bd_automation} help_text
puts $help_text
puts "BD_AUTOMATION_HELP_END"

puts "CIPS_PROPS_BEGIN"
foreach prop [lsort [list_property $cips]] {
    if {[string match CONFIG.* $prop]} {
        set val [get_property $prop $cips]
        if {$val ne ""} {
            puts "$prop=$val"
        }
    }
}
puts "CIPS_PROPS_END"

puts "CIPS_PINS_BEGIN"
foreach pin [lsort [get_bd_pins -quiet cips_0/*]] {
    puts "$pin DIR=[get_property DIR $pin] TYPE=[get_property TYPE $pin]"
}
puts "CIPS_PINS_END"

puts "CIPS_INTF_PINS_BEGIN"
foreach pin [lsort [get_bd_intf_pins -quiet cips_0/*]] {
    puts "$pin MODE=[get_property MODE $pin] VLNV=[get_property VLNV $pin]"
}
puts "CIPS_INTF_PINS_END"
