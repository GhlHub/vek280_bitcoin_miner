set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set out_dir [file join $repo_dir bd out_vek280_miner]
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
]
update_compile_order -fileset sources_1

create_bd_design $design_name
current_bd_design $design_name

set cips [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips cips_0]
set_property -dict [list \
    CONFIG.CLOCK_MODE {Custom} \
    CONFIG.PS_BOARD_INTERFACE {Custom} \
    CONFIG.IO_CONFIG_MODE {Custom} \
    CONFIG.PS_PL_CONNECTIVITY_MODE {Custom} \
    CONFIG.DDR_MEMORY_MODE {Connectivity to DDR via NOC} \
    CONFIG.PS_PMC_CONFIG(DDR_MEMORY_MODE) {Connectivity to DDR via NOC} \
    CONFIG.PS_PMC_CONFIG(IO_CONFIG_MODE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_BOARD_INTERFACE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_NUM_FABRIC_RESETS) {1} \
    CONFIG.PS_PMC_CONFIG(PS_PL_CONNECTIVITY_MODE) {Custom} \
    CONFIG.PS_PMC_CONFIG(PS_USE_PSPL_IRQ_FPD) {1} \
    CONFIG.PS_PMC_CONFIG(PS_USE_M_AXI_FPD) {1} \
    CONFIG.PS_PMC_CONFIG(PS_USE_PMCPL_CLK0) {1} \
    CONFIG.PS_PMC_CONFIG(PMC_CRP_PL0_REF_CTRL_FREQMHZ) {250} \
    CONFIG.PS_PMC_CONFIG(PMC_CRP_PL0_REF_CTRL_ACT_FREQMHZ) {250} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_PERIPHERAL_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_PERIPHERAL_IO) {PMC_MIO_26:37} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_GRP_MDIO_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_ENET0_GRP_MDIO_IO) {PMC_MIO_50:51} \
    CONFIG.PS_PMC_CONFIG(PS_GEM_TSU_VALID) {1} \
    CONFIG.PS_PMC_CONFIG(PS_CRL_GEM0_REF_CTRL_FREQMHZ) {125} \
    CONFIG.PS_PMC_CONFIG(PS_CRL_GEM0_REF_CTRL_ACT_FREQMHZ) {125} \
    CONFIG.PS_PMC_CONFIG(PS_UART0_PERIPHERAL_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_UART0_PERIPHERAL_IO) {PMC_MIO_0:1} \
    CONFIG.PS_PMC_CONFIG(PS_UART0_BAUD_RATE) {115200} \
    CONFIG.PS_PMC_CONFIG(PS_UART1_PERIPHERAL_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_UART1_PERIPHERAL_IO) {PMC_MIO_4:5} \
    CONFIG.PS_PMC_CONFIG(PS_UART1_BAUD_RATE) {115200} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_PERIPHERAL_ENABLE) {1} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_REF_CTRL_FREQMHZ) {100} \
    CONFIG.PS_PMC_CONFIG(PS_TTC0_REF_CTRL_ACT_FREQMHZ) {100} \
    CONFIG.PS_PMC_CONFIG(PS_TTC_APB_CLK_TTC0_SEL) {APB} \
    CONFIG.PS_PMC_CONFIG { \
        CLOCK_MODE {Custom} \
        DDR_MEMORY_MODE {Connectivity to DDR via NOC} \
        DESIGN_MODE {1} \
        IO_CONFIG_MODE {Custom} \
        PS_BOARD_INTERFACE {Custom} \
        PS_NUM_FABRIC_RESETS {1} \
        PS_PL_CONNECTIVITY_MODE {Custom} \
        PS_IRQ_USAGE {{CH0 1} {CH1 1} {CH10 1} {CH11 1} {CH12 1} {CH13 1} {CH14 1} {CH15 1} {CH2 1} {CH3 1} {CH4 1} {CH5 1} {CH6 1} {CH7 1} {CH8 1} {CH9 1}} \
        PS_USE_PSPL_IRQ_FPD {1} \
        PS_USE_M_AXI_FPD {1} \
        PS_USE_PMCPL_CLK0 {1} \
        PS_TTC0_PERIPHERAL_ENABLE {1} \
        PS_TTC0_REF_CTRL_FREQMHZ {100} \
        PS_TTC0_REF_CTRL_ACT_FREQMHZ {100} \
        PS_TTC_APB_CLK_TTC0_SEL {APB} \
        PMC_CRP_PL0_REF_CTRL_FREQMHZ {250} \
        PMC_CRP_PL0_REF_CTRL_ACT_FREQMHZ {250} \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_ENABLE_TEMP_AVERAGING {0} \
        SMON_TEMP_AVERAGING_SAMPLES {0} \
    } \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \
] $cips

set ddr_noc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc axi_noc_0]
set_property -dict [list \
    CONFIG.CONTROLLERTYPE {LPDDR4_SDRAM} \
    CONFIG.CH0_LPDDR4_0_BOARD_INTERFACE {ch0_lpddr4_trip1} \
    CONFIG.CH1_LPDDR4_0_BOARD_INTERFACE {ch1_lpddr4_trip1} \
    CONFIG.sys_clk0_BOARD_INTERFACE {lpddr4_clk1} \
    CONFIG.NUM_SI {6} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_CLKS {6} \
    CONFIG.MC_NO_CHANNELS {Dual} \
    CONFIG.MC_MEMORY_DENSITY {2GB} \
    CONFIG.MC_MEMORY_DEVICETYPE {Components} \
    CONFIG.MC_MEMORY_DEVICE_DENSITY {16Gb} \
    CONFIG.MC_MEMORY_SPEEDGRADE {LPDDR4-3733} \
    CONFIG.MC_MEM_DEVICE_WIDTH {x32} \
    CONFIG.MC_SYSTEM_CLOCK {Differential} \
    CONFIG.MC_INPUT_FREQUENCY0 {200.000} \
    CONFIG.MC_INPUTCLK0_PERIOD {9738} \
    CONFIG.MC_FREQ_SEL {MEMORY_CLK_FROM_SYS_CLK} \
    CONFIG.MC_FREQ_PARAM {F0} \
    CONFIG.MC_MEMORY_FREQUENCY1 {625} \
    CONFIG.MC_MEMORY_FREQUENCY2 {625} \
    CONFIG.MC_MEMORY_TIMEPERIOD0 {541} \
    CONFIG.MC_MEMORY_TIMEPERIOD1 {541} \
    CONFIG.MC_ROWADDRESSWIDTH {16} \
    CONFIG.MC_COLUMNADDRESSWIDTH {10} \
    CONFIG.MC_ADDR_WIDTH {6} \
    CONFIG.MC_BA_WIDTH {3} \
    CONFIG.MC_BG_WIDTH {0} \
    CONFIG.MC_RANK {1} \
    CONFIG.MC_STACKHEIGHT {1} \
    CONFIG.MC_MEM_ADDRESS_MAP {ROW_COLUMN_BANK} \
    CONFIG.MC_ADDRESSMAP {ROW_COLUMN_BANK} \
    CONFIG.MC_PRE_DEF_ADDR_MAP_SEL {ROW_BANK_COLUMN} \
    CONFIG.MC_USER_DEFINED_ADDRESS_MAP {16RA-3BA-10CA} \
    CONFIG.MC_CHAN_REGION0 {DDR_LOW0} \
    CONFIG.MC_CHAN_REGION1 {DDR_LOW1} \
    CONFIG.MC_INTERLEAVE_SIZE {128} \
    CONFIG.MC_LP4_CA_A_WIDTH {6} \
    CONFIG.MC_LP4_CA_B_WIDTH {6} \
    CONFIG.MC_LP4_CKE_A_WIDTH {1} \
    CONFIG.MC_LP4_CKE_B_WIDTH {1} \
    CONFIG.MC_LP4_CKT_A_WIDTH {1} \
    CONFIG.MC_LP4_CKT_B_WIDTH {1} \
    CONFIG.MC_LP4_CS_A_WIDTH {1} \
    CONFIG.MC_LP4_CS_B_WIDTH {1} \
    CONFIG.MC_LP4_DMI_A_WIDTH {2} \
    CONFIG.MC_LP4_DMI_B_WIDTH {2} \
    CONFIG.MC_LP4_DQS_A_WIDTH {2} \
    CONFIG.MC_LP4_DQS_B_WIDTH {2} \
    CONFIG.MC_LP4_DQ_A_WIDTH {16} \
    CONFIG.MC_LP4_DQ_B_WIDTH {16} \
    CONFIG.MC_LP4_RESETN_WIDTH {1} \
    CONFIG.MC_LP4_OPERATING_TEMP {STANDARD} \
    CONFIG.MC_LP4_OVERWRITE_IO_PROP {true} \
    CONFIG.MC_LP4_PIN_EFFICIENT {true} \
    CONFIG.MC_LPDDR4_REFRESH_TYPE {ALL_BANK} \
    CONFIG.MC_CH0_LP4_CHA_ENABLE {true} \
    CONFIG.MC_CH0_LP4_CHB_ENABLE {true} \
    CONFIG.MC_CH1_LP4_CHA_ENABLE {true} \
    CONFIG.MC_CH1_LP4_CHB_ENABLE {true} \
] $ddr_noc

foreach {noc_intf board_intf} {
    sys_clk0      lpddr4_clk1
    CH0_LPDDR4_0 ch0_lpddr4_trip1
    CH1_LPDDR4_0 ch1_lpddr4_trip1
} {
    if {[llength [get_bd_intf_pins -quiet axi_noc_0/$noc_intf]]} {
        apply_bd_automation -rule xilinx.com:bd_rule:board \
            -config [list Board_Interface $board_intf] \
            [get_bd_intf_pins axi_noc_0/$noc_intf]
    }
}

set noc_masters {
    FPD_CCI_NOC_0
    FPD_CCI_NOC_1
    FPD_CCI_NOC_2
    FPD_CCI_NOC_3
    LPD_AXI_NOC_0
    PMC_NOC_AXI_0
}
set noc_clocks {
    fpd_cci_noc_axi0_clk
    fpd_cci_noc_axi1_clk
    fpd_cci_noc_axi2_clk
    fpd_cci_noc_axi3_clk
    lpd_axi_noc_clk
    pmc_axi_noc_axi0_clk
}
for {set idx 0} {$idx < [llength $noc_masters]} {incr idx} {
    set ps_intf [lindex $noc_masters $idx]
    set noc_intf [format "S%02d_AXI" $idx]
    set ps_clk [lindex $noc_clocks $idx]
    set noc_clk [format "aclk%d" $idx]
    connect_bd_intf_net [get_bd_intf_pins cips_0/$ps_intf] [get_bd_intf_pins axi_noc_0/$noc_intf]
    connect_bd_net [get_bd_pins cips_0/$ps_clk] [get_bd_pins axi_noc_0/$noc_clk]
}

set miner [create_bd_cell -type module -reference bitcoin_miner_axi miner_0]
set_property -dict [list \
    CONFIG.NUM_ENGINES 128 \
    CONFIG.CLUSTER_SIZE 32 \
    CONFIG.CLUSTER_FIFO_DEPTH 2 \
    CONFIG.AXI_ADDR_WIDTH 12 \
] $miner

set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect axi_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $axi_ic

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_pl0]

connect_bd_intf_net [get_bd_intf_pins cips_0/M_AXI_FPD] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins miner_0/S_AXI]

connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins rst_pl0/slowest_sync_clk]
connect_bd_net [get_bd_pins cips_0/pl0_resetn] [get_bd_pins rst_pl0/ext_reset_in]
connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins cips_0/m_axi_fpd_aclk]
connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins axi_smc/aresetn]
connect_bd_net [get_bd_pins cips_0/pl0_ref_clk] [get_bd_pins miner_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_pl0/peripheral_aresetn] [get_bd_pins miner_0/s_axi_aresetn]

set cips_irq_pin [get_bd_pins -quiet cips_0/pl_ps_irq0]
if {![llength $cips_irq_pin]} {
    puts "CIPS_IRQ_PINS_BEGIN"
    foreach pin [lsort [get_bd_pins -quiet cips_0/*irq*]] {
        puts $pin
    }
    puts "CIPS_IRQ_PINS_END"
    error "cips_0/pl_ps_irq0 was not exposed after enabling PS_USE_IRQ_0"
}
connect_bd_net [get_bd_pins miner_0/irq_o] $cips_irq_pin
set_property PFM.IRQ {pl_ps_irq0 {is_range "false"}} [get_bd_cells cips_0]

assign_bd_address
set ps_addr_space [get_bd_addr_spaces cips_0/M_AXI_FPD]
set miner_seg [get_bd_addr_segs -quiet miner_0/S_AXI/reg0]
if {[llength $miner_seg] != 0} {
    assign_bd_address -offset 0xA4000000 -range 4K -target_address_space $ps_addr_space $miner_seg -force
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $out_dir vek280_miner_bd.srcs sources_1 bd $design_name ${design_name}.bd]] -top
add_files -norecurse [file join $out_dir vek280_miner_bd.gen sources_1 bd $design_name hdl ${design_name}_wrapper.v]
set_property top ${design_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

write_bd_tcl -force [file join $repo_dir bd ${design_name}_recreate.tcl]
set summary_file [open [file join $reports_dir ${design_name}_summary.rpt] w]
puts $summary_file "Block design: $design_name"
puts $summary_file "Part: $part_name"
puts $summary_file "Board: $board_name"
puts $summary_file "Miner: NUM_ENGINES=128 CLUSTER_SIZE=32 CLUSTER_FIFO_DEPTH=2"
puts $summary_file "PL0 clock request: 250 MHz; Vivado CIPS actual is expected to be about 249.997498 MHz"
puts $summary_file "PS-PL control: cips_0/M_AXI_FPD -> axi_smc -> miner_0/S_AXI at 0xA4000000"
puts $summary_file "PS peripherals requested in CIPS config: GEM0 RGMII/MDIO, UART0, UART1, TTC0, DDR via NoC mode"
puts $summary_file "DDR: axi_noc_0 LPDDR4 DDRMC subsystem connected to ch0_lpddr4_trip1, ch1_lpddr4_trip1, and lpddr4_clk1"
puts $summary_file "DDR warning: Vivado still reports incomplete NoC address-path warnings during BD validation; wrapper generation succeeds."
puts $summary_file "IRQ: miner_0/irq_o -> cips_0/pl_ps_irq0"
close $summary_file
