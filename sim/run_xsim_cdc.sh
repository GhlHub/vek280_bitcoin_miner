#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_dir/sim/xsim_cdc"
xvlog_bin=/tools/Xilinx/2026.1/Vivado/bin/xvlog
xelab_bin=/tools/Xilinx/2026.1/Vivado/bin/xelab
xsim_bin=/tools/Xilinx/2026.1/Vivado/bin/xsim

mkdir -p "$out_dir"
cd "$out_dir"
rm -f xvlog.pb xelab.pb webtalk*.log webtalk*.jou

"$xvlog_bin" -sv \
    "$repo_dir/rtl/dsp58_add32_registered.sv" \
    "$repo_dir/rtl/dsp58_schedule_pipeline.sv" \
    "$repo_dir/rtl/dsp58_schedule_xpm_cdc.sv" \
    "$repo_dir/rtl/sha256_core_iterative.sv" \
    "$repo_dir/rtl/sha256_core_interleaved_proto.sv" \
    "$repo_dir/tb/tb_dsp58_schedule_xpm_cdc.sv" \
    "$repo_dir/tb/tb_sha256_interleaved_proto.sv"
"$xelab_bin" glbl tb_dsp58_schedule_xpm_cdc \
    -L xpm -L unisims_ver -debug typical \
    -s tb_dsp58_schedule_xpm_cdc_sim
"$xsim_bin" tb_dsp58_schedule_xpm_cdc_sim --runall --nolog
"$xelab_bin" glbl tb_sha256_interleaved_proto \
    -L xpm -L unisims_ver -debug typical \
    -s tb_sha256_interleaved_proto_sim
"$xsim_bin" tb_sha256_interleaved_proto_sim --runall --nolog
