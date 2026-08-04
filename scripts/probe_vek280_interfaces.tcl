create_project -force probe_vek280_if reports/probe_vek280_if -part xcve2802-vsvh1760-2MP-e-S
set_property board_part xilinx.com:vek280:part0:1.2 [current_project]

puts "BOARD_INTERFACES:"
foreach bi [lsort [get_board_part_interfaces -quiet]] {
    set name [get_property NAME $bi]
    set vlnv [get_property VLNV $bi]
    set mode [get_property MODE $bi]
    puts "$name MODE=$mode VLNV=$vlnv"
}

puts "BOARD_COMPONENTS:"
foreach bc [lsort [get_board_part_components -quiet]] {
    puts "[get_property NAME $bc]"
}
