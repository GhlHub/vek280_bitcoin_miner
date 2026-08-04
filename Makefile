SHA_RTL := rtl/sha256_core_iterative.sv rtl/sha256_core_fabric.sv rtl/sha256_core_dsp.sv
MINER_RTL := $(SHA_RTL) rtl/bitcoin_hash_engine.sv rtl/bitcoin_result_cluster_fifo.sv rtl/bitcoin_miner_axi.sv
SHA_TB  := tb/tb_sha256_cores.sv
MINER_TB := tb/tb_bitcoin_miner_axi.sv
SHA_OUT := sim/tb_sha256_cores.out
MINER_OUT := sim/tb_bitcoin_miner_axi.out

.PHONY: sim lint clean

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

clean:
	rm -f $(SHA_OUT) $(MINER_OUT)
