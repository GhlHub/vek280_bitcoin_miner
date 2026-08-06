SHA_RTL := rtl/sha256_core_iterative.sv rtl/sha256_core_fabric.sv rtl/sha256_core_dsp.sv
MINER_RTL := $(SHA_RTL) rtl/bitcoin_hash_engine.sv rtl/bitcoin_result_cluster_fifo.sv rtl/bitcoin_miner_axi.sv
SHA_TB  := tb/tb_sha256_cores.sv
MINER_TB := tb/tb_bitcoin_miner_axi.sv
SHA_OUT := sim/tb_sha256_cores.out
MINER_OUT := sim/tb_bitcoin_miner_axi.out
FREERTOS_APP_SRC := $(wildcard software/vek280_freertos/src/*.c)
FREERTOS_APP_INC := \
	-Isoftware/vek280_freertos/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/portable/GCC/ARM_CR5 \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/include \
	-IFreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/Compiler/GCC

.PHONY: sim lint sw-syntax bd synth128 impl xsa vitis-hw vitis-bsp clean

sim: sim-sha sim-miner

sim-sha: $(SHA_OUT)
	vvp $(SHA_OUT)

sim-miner: $(MINER_OUT)
	vvp $(MINER_OUT)

$(SHA_OUT): $(SHA_RTL) $(SHA_TB)
	mkdir -p sim
	iverilog -g2012 -Wall -o $(SHA_OUT) $(SHA_TB) $(SHA_RTL)

$(MINER_OUT): $(MINER_RTL) $(MINER_TB)
	mkdir -p sim
	iverilog -g2012 -Wall -o $(MINER_OUT) $(MINER_TB) $(MINER_RTL)

lint:
	verilator --lint-only --timing -Wall --top-module tb_sha256_cores $(SHA_RTL) $(SHA_TB)
	verilator --lint-only --timing -Wall --top-module tb_bitcoin_miner_axi $(MINER_RTL) $(MINER_TB)

sw-syntax:
	gcc -fsyntax-only -Wall -Wextra $(FREERTOS_APP_INC) $(FREERTOS_APP_SRC)

bd:
	vivado -mode batch -source bd/create_vek280_miner_bd.tcl

synth128:
	vivado -mode batch -source synth/run_synth_128.tcl

impl:
	vivado -mode batch -source impl/run_vek280_impl.tcl

xsa: impl

vitis-hw:
	vivado -mode batch -source bd/export_vek280_vitis_hw.tcl

vitis-bsp: vitis-hw
	VITIS_BSP_CLEAN=1 /tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/create_bsp.py

clean:
	rm -f $(SHA_OUT) $(MINER_OUT)
