#!/usr/bin/env bash
set -eu

sources="rtl/include/dlrm_config_pkg.sv
rtl/common/rv_fifo.sv
rtl/common/saturating_round.sv
rtl/common/relu_quant.sv
rtl/compute/dot_product_core.sv
rtl/compute/dense_layer_core.sv
rtl/memory/embedding_mem_model.sv
rtl/pipeline/minimal_recommendation_pipeline.sv
rtl/top/dlrm_minimal_top.sv"

mkdir -p logs
if command -v verible-verilog-lint >/dev/null 2>&1; then
  # Word splitting is intentional: one source path per line, with no spaces.
  verible-verilog-lint $sources | tee logs/rtl_lint.log
  echo "lint_rtl: PASS (Verible)"
elif command -v verilator >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  verilator --lint-only -Wall --top-module dlrm_minimal_top $sources \
    | tee logs/rtl_lint.log
  echo "lint_rtl: PASS (Verilator)"
else
  echo "lint_rtl: SKIP - neither Verible nor Verilator was found; nothing was installed." >&2
  exit 2
fi

