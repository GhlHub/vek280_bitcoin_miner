create_project -force probe_vek280_bd reports/probe_vek280_bd -part xcve2802-vsvh1760-2MP-e-S
set_property board_part xilinx.com:vek280:part0:1.2 [current_project]

puts "BOARD_PARTS:"
foreach bp [get_board_parts -quiet *vek280*] {
    puts $bp
}

puts "CIPS_IP:"
foreach ip [get_ipdefs -quiet *versal_cips*] {
    puts $ip
}

puts "NOC_IP:"
foreach ip [get_ipdefs -quiet *axi_noc*] {
    puts $ip
}

puts "CLOCK_WIZ_IP:"
foreach ip [get_ipdefs -quiet *clk_wiz*] {
    puts $ip
}
