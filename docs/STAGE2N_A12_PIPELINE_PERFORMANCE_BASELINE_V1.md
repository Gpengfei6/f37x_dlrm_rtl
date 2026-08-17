# Stage 2N-A12 Host-Visible Performance Baseline v1

> 恢复状态：历史代码/总结存在，但当前恢复阶段未重新验证。当前本地缺少对应的原始 status/log/CSV 证据。

Stage 2N-A12 measures the current register-driven automatic pipeline without
changing the accepted A10 hardware image.

Default workload:

```text
1 warm-up pass
20 measured passes
256 samples per pass
5,120 measured inferences
```

The model is configured once. Each measured sample is split into:

1. idle preparation;
2. four embedding writes plus dense-input programming;
3. pipeline configuration and start-command issue;
4. wait for the valid result;
5. result reads;
6. POP, terminal completion, phase-count reads, and CLEAR_DONE.

The Host reports min, mean, p50, p95, p99, and max latency for each phase,
plus per-pass time and host-visible throughput. The primary throughput uses
the sum of measured per-sample execution intervals, so CSV emission is
excluded. A separate instrumented wall-clock result records measurement and
CSV overhead. Percentiles use nearest-rank selection.

These are host-visible end-to-end measurements of the current AXI-Lite
register-driven path. They are not pure RTL cycle latency and must not be
reported as kernel-only throughput.

Correctness remains mandatory for every warm-up and measured inference. The
runner is locked to index 2, BDF `0000:9b:00.1`, render node `renderD129`, and
the accepted A10 UUID. It performs no FPGA programming, reset, or rollback.
