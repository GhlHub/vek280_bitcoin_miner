connect -url TCP:10.0.1.109:3121
puts [targets]
targets -set -filter {name =~ "*Cortex-R5*#0*"}
puts "R5_STATE_START"
state
puts "R5_STATE_DONE"
exit
