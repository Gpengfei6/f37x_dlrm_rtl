#!/usr/bin/env bash
set -eu

simulator=""
if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
  simulator="iverilog"
elif command -v verilator >/dev/null 2>&1; then
  simulator="verilator"
else
  echo "run_rtl_tests: SKIP - Icarus and Verilator were not found; nothing was installed." >&2
  exit 2
fi

mkdir -p work/rtl_sim logs results

run_tb() {
  name="$1"
  shift
  if [ "$simulator" = "iverilog" ]; then
    output="work/rtl_sim/${name}.vvp"
    iverilog -g2012 -Wall -s "$name" -o "$output" "$@" "tb/${name}.sv"
    vvp "$output" | tee "logs/${name}.log"
  else
    mdir="work/rtl_sim/verilator_${name}"
    verilator --binary --timing -Wall --top-module "$name" \
      --Mdir "$mdir" -o "${name}.exe" "$@" "tb/${name}.sv"
    "$mdir/${name}.exe" | tee "logs/${name}.log"
  fi
}

run_tb tb_rv_fifo rtl/common/rv_fifo.sv
run_tb tb_saturating_round rtl/common/saturating_round.sv
run_tb tb_relu_quant rtl/common/saturating_round.sv rtl/common/relu_quant.sv
run_tb tb_dot_product_core rtl/compute/dot_product_core.sv
run_tb tb_dense_layer_core \
  rtl/common/saturating_round.sv rtl/common/relu_quant.sv \
  rtl/compute/dot_product_core.sv rtl/compute/dense_layer_core.sv
run_tb tb_embedding_mem_model rtl/memory/embedding_mem_model.sv
run_tb tb_minimal_recommendation_pipeline \
  rtl/common/saturating_round.sv rtl/common/relu_quant.sv \
  rtl/compute/dot_product_core.sv rtl/compute/dense_layer_core.sv \
  rtl/memory/embedding_mem_model.sv \
  rtl/pipeline/minimal_recommendation_pipeline.sv
run_tb tb_dlrm_minimal_top \
  rtl/include/dlrm_config_pkg.sv \
  rtl/common/saturating_round.sv rtl/common/relu_quant.sv \
  rtl/compute/dot_product_core.sv rtl/compute/dense_layer_core.sv \
  rtl/memory/embedding_mem_model.sv \
  rtl/pipeline/minimal_recommendation_pipeline.sv rtl/top/dlrm_minimal_top.sv

python_cmd=""
if command -v python3 >/dev/null 2>&1; then
  python_cmd="python3"
elif command -v python >/dev/null 2>&1; then
  python_cmd="python"
fi
if [ -n "$python_cmd" ]; then
  "$python_cmd" python/compare_results.py \
    --rtl results/rtl_top_outputs.hex \
    --expected tests/expected/top_expected.json
else
  echo "run_rtl_tests: RTL passed, but Python output comparison was not run (Python missing)." >&2
  exit 2
fi

echo "run_rtl_tests: PASS"
