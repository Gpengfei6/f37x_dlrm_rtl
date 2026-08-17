# Stage 2N-A12 Performance Baseline Runner Fix v2

> 恢复状态：历史代码/总结存在，但当前恢复阶段未重新验证。当前本地缺少对应的原始 status/log/CSV 证据。

The v1 Host completed all 5,120 measured inferences and emitted a PASS marker.
The wrapper then failed only during CSV metadata validation because its `awk`
field numbers were shifted by one column.

The actual sample CSV layout is:

```text
1 measured_pass
2 sample_id
3 label
4 expected_logit
5 fpga_logit
6 expected_prediction
7 fpga_prediction
8 classification_correct
9 result_index
10 result_tag
11 bottom_count
12 interaction_count
13-19 timing fields
```

The v1 runner incorrectly checked:

```text
$10 == 0 and $11 == 4
$12 == 8 and $13 == 18
```

Runner v2 checks the correct fields:

```text
$9 == 0 and $10 == 4
$11 == 8 and $12 == 18
```

It also validates the exact CSV header before interpreting column numbers and
uses new v2 build, result, log, and status paths. The C++ Host and FPGA image
are unchanged.

The v1 run already demonstrated:

- 5,120/5,120 exact logits;
- 5,120/5,120 exact predictions;
- 4,560 correct classifications;
- host-visible throughput of 5,144.861 samples/s;
- no FPGA programming or reset.

A v2 rerun is still required so the protected wrapper can complete its
post-run device checks and generate a PASS status file.
