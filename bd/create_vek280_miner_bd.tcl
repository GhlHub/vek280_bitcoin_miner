set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set enable_ddr 1
if {[info exists ::env(MINER_ENABLE_DDR)]} {
    set enable_ddr $::env(MINER_ENABLE_DDR)
}
set variant_suffix ""
if {!$enable_ddr} {
    set variant_suffix "_noddr"
}
set out_dir [file join $repo_dir bd out_vek280_miner${variant_suffix}]
set reports_dir [file join $repo_dir reports]
set part_name xcve2802-vsvh1760-2MP-e-S
set board_name xilinx.com:vek280:part0:1.2
set design_name miner_system

file mkdir $reports_dir

create_project -force vek280_miner_bd $out_dir -part $part_name
set_property board_part $board_name [current_project]
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

add_files -fileset sources_1 [list \
    [file join $repo_dir rtl sha256_core_iterative.sv] \
    [file join $repo_dir rtl sha256_core_fabric.sv] \
    [file join $repo_dir rtl bitcoin_hash_engine.sv] \
    [file join $repo_dir rtl bitcoin_result_cluster_fifo.sv] \
    [file join $repo_dir rtl bitcoin_miner_axi.sv] \
    [file join $repo_dir rtl irq_or4.v] \
]
update_compile_order -fileset sources_1

create_bd_design $design_name
current_bd_design $design_name

set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips cips_0]
set cips_config [list \
    CONFIG.CLOCK_MODE {Custom} \
    CONFIG.PS_BOARD_INTERFACE {Custom} \
    CONFIG.IO_CONFIG_MODE {Custom} \
    CONFIG.PS_PL_CONNECTIVITY_MODE {Custom} \
    CONFIG.PS_PMC_CONFIG(IO_CONFIG_MODE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_BOARD_INTERFACE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_NUM_FABRIC_RESETS) {1} \
    CONFIG.PS_PMC_CONFIG(PS_PL_CONNECTIVITY_MODE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_USE_PSPL_IRQ_FPD) {1} \
    CONFIG.PS_PMC_CONFIG(PS_USE_M_AXI_FPD) {1} \
    CONFIG.PS_PMC_CONFIG(PS_USE_PMCPL_CLK0) {1} \
    CONFIG.PS_PMC_CONFIG(PMC_CRP_PL0_REF_CTRL_FREQMHZ) {250} \
    CONFIG.PS_PMC_CONFIG(PMC_CRP_PL0_REF_CTRL_ACT_FREQMHZ) {250} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_PERIPHERAL) {{{ENABLE 1} {IO {PS_MIO 0 .. 11}}}} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_MDIO) {{{ENABLE 1} {IO {PS_MIO 24 .. 25}}}} \
    CONFIG.PS_PMC_CONFIG(PS_GEM_TSU_VALID) {1} \
    CONFIG.PS_PMC_CONFIG(PS_CRL_GEM0_REF_CTRL_FREQMHZ) {125} \
    CONFIG.PS_PMC_CONFIG(PS_CRL_GEM0_REF_CTRL_ACT_FREQMHZ) {125} \
    CONFIG.PS_PMC_CONFIG(PS_UART0_PERIPHERAL) {{{ENABLE 1} {IO {PMC_MIO 42 .. 43}}}} \
    CONFIG.PS_PMC_CONFIG(PS_UART0_BAUD_RATE) {115200} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_PERIPHERAL_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_REF_CTRL_FREQMHZ) {100} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_REF_CTRL_ACT_FREQMHZ) {100} \
    CONFIG.PS_PMC_CONFIG(PS_TTC_APB_CLK_TTC0_SEL) {APB} \
    CONFIG.PS_PMC_CONFIG(PS_I2CSYSMON_PERIPHERAL) {{{ENABLE 1} {IO {PMC_MIO 39 .. 40}}}} \
    CONFIG.PS_PMC_CONFIG(SMON_INTERFACE_TO_USE) {I2C} \
    CONFIG.PS_PMC_CONFIG(SMON_PMBUS_ADDRESS) {0x18} \
    CONFIG.PS_PMC_CONFIG(SMON_PMBUS_UNRESTRICTED) {0} \
]

set ps_pmc_config [list \
        CLOCK_MODE {Custom} \
        DESIGN_MODE {1} \
        IO_CONFIG_MODE {Custom} \
        PS_BOARD_INTERFACE {Custom} \
        PS_NUM_FABRIC_RESETS {1} \
        PS_PL_CONNECTIVITY_MODE {Custom} \
        PS_IRQ_USAGE {{CH0 1} {CH1 1} {CH10 1} {CH11 1} {CH12 1} {CH13 1} {CH14 1} {CH15 1} {CH2 1} {CH3 1} {CH4 1} {CH5 1} {CH6 1} {CH7 1} {CH8 1} {CH9 1}} \
        PS_USE_PSPL_IRQ_FPD {1} \
        PS_USE_M_AXI_FPD {1} \
        PS_USE_FPD_CCI_NOC {1} \
        PMC_USE_PMC_NOC_AXI0 {1} \
        PS_GEM0_ROUTE_THROUGH_FPD {0} \
        PS_ENET0_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 0 .. 11}}} \
        PS_ENET0_MDIO {{ENABLE 1} {IO {PS_MIO 24 .. 25}}} \
        PS_UART0_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 42 .. 43}}} \
        PS_USE_PMCPL_CLK0 {1} \
        PS_TTC0_PERIPHERAL_ENABLE {1} \
        PS_TTC0_REF_CTRL_FREQMHZ {100} \
        PS_TTC0_REF_CTRL_ACT_FREQMHZ {100} \
        PS_TTC_APB_CLK_TTC0_SEL {APB} \
        PMC_CRP_PL0_REF_CTRL_FREQMHZ {250} \
        PMC_CRP_PL0_REF_CTRL_ACT_FREQMHZ {250} \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_INTERFACE_TO_USE {I2C} \
        SMON_PMBUS_ADDRESS {0x18} \
        SMON_PMBUS_UNRESTRICTED {0} \
        PS_I2CSYSMON_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 39 .. 40}}} \
        SMON_ENABLE_TEMP_AVERAGING {0} \
        SMON_TEMP_AVERAGING_SAMPLES {0} \
]

if {$enable_ddr} {
    lappend cips_config \
        CONFIG.DDR_MEMORY_MODE {Connectivity to DDR via NOC} \
        CONFIG.PS_PMC_CONFIG(DDR_MEMORY_MODE) {Connectivity to DDR via NOC}
    lappend ps_pmc_config DDR_MEMORY_MODE {Connectivity to DDR via NOC}
}

lappend cips_config \
    CONFIG.PS_PMC_CONFIG $ps_pmc_config \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \

set_property -dict $cips_config $cips

if {$enable_ddr} {
    set ps_ddr_noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc ps_ddr_noc]
    set_property -dict [list \
    CONFIG.NUM_SI {6} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NMI {4} \
    CONFIG.NUM_CLKS {6} \
] $ps_ddr_noc

    foreach {port connections} {
        S00_AXI {M00_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
        S01_AXI {M01_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
        S02_AXI {M02_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
        S03_AXI {M03_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
        S04_AXI {M00_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
        S05_AXI {M00_INI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4} initial_boot {true}}}
    } {
        set_property -dict [list CONFIG.CONNECTIONS $connections] [get_bd_intf_pins ps_ddr_noc/$port]
    }

    set ddr_noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc ddr_noc]
    set_property -dict [list \
    CONFIG.CONTROLLERTYPE {LPDDR4_SDRAM} \
    CONFIG.CH0_LPDDR4_0_BOARD_INTERFACE {ch0_lpddr4_trip1} \
    CONFIG.CH1_LPDDR4_0_BOARD_INTERFACE {ch1_lpddr4_trip1} \
    CONFIG.sys_clk0_BOARD_INTERFACE {lpddr4_clk1} \
    CONFIG.NUM_SI {0} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NSI {4} \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_CLKS {0} \
    CONFIG.MC_NO_CHANNELS {Dual} \
    CONFIG.MC_SYSTEM_CLOCK {Differential} \
    CONFIG.MC_MEMORY_SPEEDGRADE {LPDDR4-3733} \
    CONFIG.MC_DATAWIDTH {32} \
    CONFIG.MC_FREQ_SEL {MEMORY_CLK_FROM_SYS_CLK} \
    CONFIG.MC_IP_TIMEPERIOD0_FOR_OP {5000} \
    CONFIG.MC_OP_TIMEPERIOD0 {541} \
    CONFIG.MC_LP4_PIN_EFFICIENT {true} \
    CONFIG.MC_LP4_OVERWRITE_IO_PROP {true} \
] $ddr_noc

    foreach {noc_intf board_intf} {
    sys_clk0      lpddr4_clk1
    CH0_LPDDR4_0 ch0_lpddr4_trip1
    CH1_LPDDR4_0 ch1_lpddr4_trip1
    } {
        if {[llength [get_bd_intf_pins -quiet ddr_noc/$noc_intf]]} {
            apply_bd_automation -rule xilinx.com:bd_rule:board \
                -config [list Board_Interface $board_intf] \
                [get_bd_intf_pins ddr_noc/$noc_intf]
        }
    }

    foreach {port connections} {
        S00_INI {MC_0 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}}
        S01_INI {MC_1 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}}
        S02_INI {MC_2 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}}
        S03_INI {MC_3 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}}
    } {
        set_property -dict [list CONFIG.CONNECTIONS $connections] [get_bd_intf_pins ddr_noc/$port]
    }

    connect_bd_intf_net [get_bd_intf_pins cips_0/FPD_CCI_NOC_0] [get_bd_intf_pins ps_ddr_noc/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins cips_0/FPD_CCI_NOC_1] [get_bd_intf_pins ps_ddr_noc/S01_AXI]
    connect_bd_intf_net [get_bd_intf_pins cips_0/FPD_CCI_NOC_2] [get_bd_intf_pins ps_ddr_noc/S02_AXI]
    connect_bd_intf_net [get_bd_intf_pins cips_0/FPD_CCI_NOC_3] [get_bd_intf_pins ps_ddr_noc/S03_AXI]
    connect_bd_intf_net [get_bd_intf_pins cips_0/LPD_AXI_NOC_0] [get_bd_intf_pins ps_ddr_noc/S04_AXI]
    connect_bd_intf_net [get_bd_intf_pins cips_0/PMC_NOC_AXI_0] [get_bd_intf_pins ps_ddr_noc/S05_AXI]
    connect_bd_intf_net [get_bd_intf_pins ps_ddr_noc/M00_INI] [get_bd_intf_pins ddr_noc/S00_INI]
    connect_bd_intf_net [get_bd_intf_pins ps_ddr_noc/M01_INI] [get_bd_intf_pins ddr_noc/S01_INI]
    connect_bd_intf_net [get_bd_intf_pins ps_ddr_noc/M02_INI] [get_bd_intf_pins ddr_noc/S02_INI]
    connect_bd_intf_net [get_bd_intf_pins ps_ddr_noc/M03_INI] [get_bd_intf_pins ddr_noc/S03_INI]
    connect_bd_net [get_bd_pins cips_0/fpd_cci_noc_axi0_clk] [get_bd_pins ps_ddr_noc/aclk0]
    connect_bd_net [get_bd_pins cips_0/fpd_cci_noc_axi1_clk] [get_bd_pins ps_ddr_noc/aclk1]
    connect_bd_net [get_bd_pins cips_0/fpd_cci_noc_axi2_clk] [get_bd_pins ps_ddr_noc/aclk2]
    connect_bd_net [get_bd_pins cips_0/fpd_cci_noc_axi3_clk] [get_bd_pins ps_ddr_noc/aclk3]
    connect_bd_net [get_bd_pins cips_0/lpd_axi_noc_clk] [get_bd_pins ps_ddr_noc/aclk4]
    connect_bd_net [get_bd_pins cips_0/pmc_axi_noc_axi0_clk] [get_bd_pins ps_ddr_noc/aclk5]
}

set num_miner_slaves 1
set miner_engines_per_slave 32
set miner_cluster_size 32
set miner_fifo_depth 2
set miner_base_addr 0xA4000000
set miner_addr_stride 0x00001000

for {set idx 0} {$idx < $num_miner_slaves} {incr idx} {
    set miner [create_bd_cell -type module -reference bitcoin_miner_axi miner_$idx]
    set_property -dict [list \
        CONFIG.NUM_ENGINES $miner_engines_per_slave \
        CONFIG.CLUSTER_SIZE $miner_cluster_size \
        CONFIG.CLUSTER_FIFO_DEPTH $miner_fifo_depth \
        CONFIG.AXI_ADDR_WIDTH 12 \
    ] $miner
}

set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI $num_miner_slaves] $axi_ic

if {$num_miner_slaves > 1} {
    set irq_or [create_bd_cell -type module -reference irq_or4 irq_or]
}

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_pl0]

connect_bd_intf_net [get_bd_intf_pins cips_0/M_AXI_FPD] [get_bd_intf_pins axi_smc/S00_AXI]

connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins rst_pl0/slowest_sync_clk]
connect_bd_net [get_bd_pins cips_0/pl0_resetn] [get_bd_pins rst_pl0/ext_reset_in]
connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins cips_0/m_axi_fpd_aclk]
connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins axi_smc/aresetn]

for {set idx 0} {$idx < $num_miner_slaves} {incr idx} {
    set mi_pin [format "M%02d_AXI" $idx]
    connect_bd_intf_net [get_bd_intf_pins axi_smc/$mi_pin] [get_bd_intf_pins miner_$idx/S_AXI]
    connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins miner_$idx/s_axi_aclk]
    connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins miner_$idx/s_axi_aresetn]
    if {$num_miner_slaves > 1} {
        connect_bd_net [get_bd_pins miner_$idx/irq_o] [get_bd_pins irq_or/irq${idx}_i]
    }
}

set cips_irq_pin [get_bd_pins -quiet cips_0/pl_ps_irq0]
if {![llength $cips_irq_pin]} {
    puts "CIPS_IRQ_PINS_BEGIN"
    foreach pin [lsort [get_bd_pins -quiet cips_0/*irq*]] {
        puts $pin
    }
    puts "CIPS_IRQ_PINS_END"
    error "cips_0/pl_ps_irq0 was not exposed after enabling PS_USE_IRQ_0"
}
if {$num_miner_slaves > 1} {
    connect_bd_net [get_bd_pins irq_or/irq_o] $cips_irq_pin
} else {
    connect_bd_net [get_bd_pins miner_0/irq_o] $cips_irq_pin
}
set_property PFM.IRQ {pl_ps_irq0 {is_range "false"}} [get_bd_cells cips_0]

assign_bd_address
set ps_addr_space [get_bd_addr_spaces cips_0/M_AXI_FPD]
for {set idx 0} {$idx < $num_miner_slaves} {incr idx} {
    set miner_seg [get_bd_addr_segs -quiet miner_$idx/S_AXI/reg0]
    if {[llength $miner_seg] != 0} {
        set offset [format "0x%08X" [expr {$miner_base_addr + ($idx * $miner_addr_stride)}]]
        assign_bd_address -offset $offset -range 4K -target_address_space $ps_addr_space $miner_seg -force
    }
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $out_dir vek280_miner_bd.srcs sources_1 bd $design_name ${design_name}.bd]] -top
add_files -norecurse [file join $out_dir vek280_miner_bd.gen sources_1 bd $design_name hdl ${design_name}_wrapper.v]
set_property top ${design_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

write_bd_tcl -force [file join $repo_dir bd ${design_name}_recreate${variant_suffix}.tcl]
set summary_file [open [file join $reports_dir ${design_name}_summary${variant_suffix}.rpt] w]
puts $summary_file "Block design: $design_name"
puts $summary_file "Part: $part_name"
puts $summary_file "Board: $board_name"
puts $summary_file "Miner: 1 AXI4-Lite slave, NUM_ENGINES=32 CLUSTER_SIZE=32 CLUSTER_FIFO_DEPTH=2"
puts $summary_file "PL0 clock request: 250 MHz; Vivado CIPS actual is expected to be about 249.997498 MHz"
puts $summary_file "PS-PL control: cips_0/M_AXI_FPD -> axi_smc -> miner_0/S_AXI at 0xA4000000"
if {$enable_ddr} {
    puts $summary_file "PS peripherals requested in CIPS config: GEM0 RGMII/MDIO on PS_MIO0..11/24..25, UART0 on PMC_MIO42..43, TTC0, DDR via NoC mode, SysMon I2C on PMC_MIO39/40 at address 0x18"
    puts $summary_file "DDR: ddr_noc LPDDR4 DDRMC subsystem connected to ch0_lpddr4_trip1, ch1_lpddr4_trip1, and lpddr4_clk1"
    puts $summary_file "DDR NoC: four CIPS FPD CCI NoC master ports plus R5/LPD_AXI_NOC_0 and PMC_NOC_AXI_0 enter ps_ddr_noc, then four inter-NoC links feed ddr_noc MC ports."
} else {
    puts $summary_file "PS peripherals requested in CIPS config: GEM0 RGMII/MDIO on PS_MIO0..11/24..25, UART0 on PMC_MIO42..43, TTC0, SysMon I2C on PMC_MIO39/40 at address 0x18; DDR disabled for hardware programming isolation"
    puts $summary_file "DDR: disabled"
}
puts $summary_file "IRQ: miner_0/irq_o -> cips_0/pl_ps_irq0"
close $summary_file
