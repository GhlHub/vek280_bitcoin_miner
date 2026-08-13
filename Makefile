SHA_RTL := rtl/dsp58_add32.sv rtl/sha256_core_iterative.sv rtl/sha256_core_fabric.sv rtl/sha256_core_dsp.sv rtl/sha256_core_dsp_explicit.sv
FOUR_PHASE_RTL := $(SHA_RTL) rtl/sha256_core_4phase.sv
MINER_RTL := $(SHA_RTL) rtl/bitcoin_sha256_core.sv rtl/bitcoin_sha256_core_dsp_explicit.sv rtl/bitcoin_hash_engine.sv rtl/bitcoin_result_cluster_fifo.sv rtl/bitcoin_miner_axi.sv rtl/irq_or4.v
SHA_TB  := tb/tb_sha256_cores.sv
SCHEDULE_RTL := rtl/dsp58_add32_registered.sv rtl/dsp58_schedule_pipeline.sv
SCHEDULE_TB := tb/tb_dsp58_schedule_pipeline.sv
SCHEDULE_OUT := sim/tb_dsp58_schedule_pipeline.out
MINER_TB := tb/tb_bitcoin_miner_axi.sv
SHA_OUT := sim/tb_sha256_cores.out
FOUR_PHASE_OUT := sim/tb_sha256_4phase.out
MINER_OUT := sim/tb_bitcoin_miner_axi.out
FREERTOS_APP_SRC := $(wildcard software/vek280_freertos/src/*.c)
FREERTOS_APP_INC := \
	-Isoftware/vek280_freertos/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/portable/GCC/ARM_CR5 \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/Compiler/GCC

.PHONY: sim sim-schedule sim-4phase sim-xsim-cdc synth-4phase-ooc synth-5phase-ooc lint sw-syntax bd bd-noddr bd4x32 bd4x32-dsp synth128 synth-miner32-ooc synth-miner32-dsp-ooc impl impl-noddr impl4x32-ooc impl4x32-dsp-ooc xsa vitis-hw vitis-bsp vitis-r5 clean

sim: sim-sha sim-miner sim-schedule

sim-4phase: $(FOUR_PHASE_OUT)
	vvp $(FOUR_PHASE_OUT)

sim-xsim-cdc:
	bash sim/run_xsim_cdc.sh

synth-4phase-ooc:
	vivado -mode batch -source synth/run_sha256_4phase_ooc.tcl

synth-5phase-ooc:
	vivado -mode batch -source synth/run_sha256_5phase_ooc.tcl

sim-sha: $(SHA_OUT)
	vvp $(SHA_OUT)

sim-miner: $(MINER_OUT)
	vvp $(MINER_OUT)

sim-schedule: $(SCHEDULE_OUT)
	vvp $(SCHEDULE_OUT)

$(SCHEDULE_OUT): $(SCHEDULE_RTL) $(SCHEDULE_TB)
	mkdir -p sim
	iverilog -g2012 -Wall -o $(SCHEDULE_OUT) $(SCHEDULE_TB) $(SCHEDULE_RTL)

$(SHA_OUT): $(SHA_RTL) $(SHA_TB)
	mkdir -p sim
	iverilog -g2012 -Wall -o $(SHA_OUT) $(SHA_TB) $(SHA_RTL)

$(MINER_OUT): $(MINER_RTL) $(MINER_TB)
	mkdir -p sim
	iverilog -g2012 -Wall -o $(MINER_OUT) $(MINER_TB) $(MINER_RTL)

$(FOUR_PHASE_OUT): $(FOUR_PHASE_RTL) tb/tb_sha256_4phase.sv
	mkdir -p sim
	iverilog -g2012 -Wall -o $(FOUR_PHASE_OUT) tb/tb_sha256_4phase.sv $(FOUR_PHASE_RTL)

lint:
	verilator --lint-only --timing -Wall --top-module tb_sha256_cores $(SHA_RTL) $(SHA_TB)
	verilator --lint-only --timing -Wall --top-module tb_bitcoin_miner_axi $(MINER_RTL) $(MINER_TB)
	verilator --lint-only --timing -Wall $(SCHEDULE_RTL)
	verilator --lint-only --timing -Wall --top-module sha256_core_4phase $(FOUR_PHASE_RTL)

sw-syntax:
	gcc -fsyntax-only -Wall -Wextra $(FREERTOS_APP_INC) $(FREERTOS_APP_SRC)

bd:
	vivado -mode batch -source bd/create_vek280_miner_bd.tcl

bd-noddr:
	MINER_ENABLE_DDR=0 vivado -mode batch -source bd/create_vek280_miner_bd.tcl

bd4x32:
	MINER_NUM_SLAVES=4 MINER_USE_OOC_MINER32=1 vivado -mode batch -source bd/create_vek280_miner_bd.tcl

bd4x32-dsp:
	MINER_NUM_SLAVES=4 MINER_USE_OOC_MINER32=1 MINER_EXPLICIT_DSP=1 vivado -mode batch -source bd/create_vek280_miner_bd.tcl

synth128:
	vivado -mode batch -source synth/run_synth_128.tcl

synth-miner32-ooc:
	VIVADO_JOBS=1 vivado -mode batch -source synth/run_miner32_ooc.tcl

synth-miner32-dsp-ooc:
	MINER_EXPLICIT_DSP=1 VIVADO_JOBS=4 vivado -mode batch -source synth/run_miner32_ooc.tcl

impl:
	vivado -mode batch -source impl/run_vek280_impl.tcl

impl-noddr:
	MINER_ENABLE_DDR=0 vivado -mode batch -source impl/run_vek280_impl.tcl

impl4x32-ooc: synth-miner32-ooc
	MINER_NUM_SLAVES=4 MINER_USE_OOC_MINER32=1 VIVADO_JOBS=1 vivado -mode batch -source impl/run_vek280_impl.tcl

impl4x32-dsp-ooc: synth-miner32-dsp-ooc
	MINER_NUM_SLAVES=4 MINER_USE_OOC_MINER32=1 MINER_EXPLICIT_DSP=1 VIVADO_JOBS=4 vivado -mode batch -source impl/run_vek280_impl.tcl

xsa: impl

vitis-hw:
	vivado -mode batch -source bd/export_vek280_vitis_hw.tcl

vitis-bsp: vitis-hw
	VITIS_BSP_CLEAN=1 /tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/create_bsp.py

vitis-r5:
	MINER_AXI_INSTANCES=4 MINER_NUM_SLAVES=4 /tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/create_bsp.py --xsa reports/impl_vek280_4x32_ooc/miner_system_wrapper.xsa --clean
	MINER_AXI_INSTANCES=4 MINER_NUM_SLAVES=4 /tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/create_app.py --clean
	/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/build_app.py

clean:
	rm -f $(SHA_OUT) $(MINER_OUT)
