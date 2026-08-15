connect -url TCP:10.0.1.109:3121
puts [targets]
# On a JTAG boot the whole RPU group remains held in reset.  Release the
# group before selecting R5 #0; resetting only the core fails while its parent
# RPU reset is still asserted.
targets -set -filter {name =~ "*RPU*"}
rst -cores -clear-registers
targets -set -filter {name =~ "*Cortex-R5*#0*"}
dow vitis_ws/vek280_miner_app/build/vek280_miner_app.elf
con
exit
