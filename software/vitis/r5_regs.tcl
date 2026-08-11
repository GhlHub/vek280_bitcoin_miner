connect -url TCP:10.0.1.109:3121
puts [targets]
targets -set -filter {name =~ "*Cortex-R5*#0*"}
stop
puts "R5_REGS_START"
rrd
puts "R5_REGS_DONE"
con
exit
