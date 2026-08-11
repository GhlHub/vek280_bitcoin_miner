connect -url TCP:10.0.1.109:3121
puts [targets]
targets -set -filter {name =~ "*Cortex-R5*#0*"}
rst -processor -clear-registers
dow vitis_ws/vek280_miner_app/build/vek280_miner_app.elf
con
exit
