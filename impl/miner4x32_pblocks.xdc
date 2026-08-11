# Coarse locality constraints for four 32-engine miner islands.
#
# These pblocks intentionally use broad ranges so the placer has room to solve
# local routing. Adjust ranges after the first successful 4x32 route report.

set miner_cells [list \
    [get_cells -quiet miner_system_i/miner_0/inst] \
    [get_cells -quiet miner_system_i/miner_1/inst] \
    [get_cells -quiet miner_system_i/miner_2/inst] \
    [get_cells -quiet miner_system_i/miner_3/inst] \
]

foreach idx {0 1 2 3} {
    set cell [lindex $miner_cells $idx]
    if {[llength $cell] == 0} {
        continue
    }
    set pb [create_pblock pblock_miner_$idx]
    add_cells_to_pblock $pb $cell
}
