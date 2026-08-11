connect -url TCP:10.0.1.109:3121
puts [targets]
targets -set -filter {name =~ "*Cortex-R5*#0*"}
rst -processor
puts "DDR_PROBE_START"
mwr 0x00100000 0x12345678
puts [mrd 0x00100000 1]
mwr 0x00100004 0xA5A55A5A
puts [mrd 0x00100000 2]
puts "DDR_PROBE_DONE"
exit
