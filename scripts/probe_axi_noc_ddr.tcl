set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set out_dir [file join $repo_dir reports probe_axi_noc_ddr]

create_project -force probe_axi_noc_ddr $out_dir -part xcve2802-vsvh1760-2MP-e-S
set_property board_part xilinx.com:vek280:part0:1.2 [current_project]
create_bd_design probe_noc
current_bd_design probe_noc

set noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc axi_noc_0]

puts "NOC_PROPS_BEGIN"
foreach prop [lsort [list_property $noc]] {
    if {[string match CONFIG.* $prop]} {
        set val [get_property $prop $noc]
        if {$val ne ""} {
            puts "$prop=$val"
        }
    }
}
puts "NOC_PROPS_END"

puts "NOC_INTF_PINS_BEGIN"
foreach pin [lsort [get_bd_intf_pins -quiet axi_noc_0/*]] {
    puts "$pin MODE=[get_property MODE $pin] VLNV=[get_property VLNV $pin]"
}
puts "NOC_INTF_PINS_END"

puts "NOC_PINS_BEGIN"
foreach pin [lsort [get_bd_pins -quiet axi_noc_0/*]] {
    puts "$pin DIR=[get_property DIR $pin] TYPE=[get_property TYPE $pin]"
}
puts "NOC_PINS_END"

puts "BOARD_COMPAT_BEGIN"
foreach ip_pin [get_bd_intf_pins -quiet axi_noc_0/*] {
    set vlnv [get_property VLNV $ip_pin]
    set matches [get_board_part_interfaces -quiet -filter "VLNV==$vlnv"]
    if {[llength $matches]} {
        puts "$ip_pin -> [join $matches {,}]"
    }
}
puts "BOARD_COMPAT_END"
