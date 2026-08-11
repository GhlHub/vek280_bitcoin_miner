connect -url TCP:10.0.1.109:3121
targets -set -filter {name =~ "*Cortex-R5*#0*"}
puts "GEM0_REGS_START"
puts [mrd 0xff0c0000 16]
puts [mrd 0xff0c0100 48]
puts [mrd 0xff0c0400 40]
puts "GEM0_RX_BD"
puts [mrd 0xffff9000 16]
puts "GEM0_TX_BD"
puts [mrd 0xffff9050 16]
puts "GEM0_REGS_DONE"
exit
