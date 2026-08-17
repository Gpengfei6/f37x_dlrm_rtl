# Stage 2N 可靠开发基线恢复方案

日期：2026-08-17

当前活动分支保持为 `work/stage2n-fpga-interaction`，HEAD 保持为 `802573d8b9b0da01539007b23d312f7cd3e16f43`。本阶段未 checkout、reset、clean、rebase、add 或 commit。

## 1. 已执行的只读/引用恢复动作

三个 bundle 均通过 `git bundle verify`，并只导入独立命名空间：

| Ref | Commit | Commit message |
|---|---|---|
| `refs/recovery/stage2n-a4` | `f8dbbd8a4574e10030fa8178daef8a7fca3a4242` | `test(f37x): validate Stage 2N interaction on board` |
| `refs/recovery/stage2n-a5` | `915a49b698c35f5b1dfbfd5eaf02db17ab35c8ce` | `feat(dlrm): add internal bottom interaction top pipeline` |
| `refs/recovery/stage2n-a6` | `a73e04587b184edf975205fdc3de35c254f55384` | `verify(f37x): close Stage 2N-A6 internal timing` |

父链为严格线性关系：

```text
802573d (A3)
  └─ f8dbbd8 (A4 board host/test)
       └─ 915a49b (A5 internal pipeline + XSim source)
            └─ a73e045 (A6 internal OOC timing acceptance)
```

确认可信后已创建但未 checkout：

```text
recovery/stage2n-a6-baseline -> a73e045
```

当前活动分支没有移动，原有未跟踪文件没有被删除或覆盖。

## 2. `a73e045` 是否可信

结论：**可信，可作为 Stage 2N-A6 内部流水恢复点**。

依据：

1. A4/A5/A6 三个 bundle 都记录完整 history，校验通过。
2. `802573d` 是 `f8dbbd8` 的直接父提交，之后依次是 `915a49b` 和 `a73e045`，没有断链或拼接历史。
3. A4 提交的 host v3 和 host-only runner v2 与当前未跟踪同名文件 blob 完全一致。
4. A4 原始 status/log 记录 index 2、BDF `0000:9b:00.1`、MLP result 19、18 个 interaction 输出逐项匹配、stale-done 恢复、firewall GOOD、CU IDLE。
5. A5 五个新增文件与当前未跟踪文件 blob 完全一致；其中四个 source/runner SHA-256 与 A5 status 中记录完全一致。
6. A5 原始 Vivado 2020.2 XSim log 有明确自校验 marker：两次运行、Bottom 8、Interaction 18、Top `-60`、12 周期 backpressure。
7. A6 commit 内直接包含 timing/hold/DRC machine-readable status，而不是只包含总结文档。它记录 100 MHz、internal setup WNS `+1.482 ns`、internal hold WHS `+0.024 ns`、0 internal failing path、0 unrouted、0 latch、0 DRC error。
8. 当前同名 A6 XDC、acceptance doc 和 final timing/hold scripts 与 `a73e045` blob 完全一致。

可信边界：A6 是 `dlrm_internal_pipeline_controller` 的 VU37P 内部 OOC 恢复点。148 条负 hold 路径全部终止于 OOC output ports，已从 internal acceptance 中排除。A6 没有证明 AXI wrapper、完整 F37X shell、XO/xclbin、HBM、host throughput 或自动流水板卡运行。

## 3. `802573d` 之后可靠恢复到哪个阶段

严格按本地原始证据，能够可靠恢复到 **Stage 2N-A6**：

- A4：板卡原始 status/log 与 bundle 可对应；
- A5：source SHA、Vivado 2020.2 XSim status/log 与 bundle 可对应；
- A6：commit 内 machine-readable timing/hold/DRC status 与 source tree 可对应。

A7–A12 不能被称为已恢复的“通过阶段”，因为当前仅有未跟踪源码、runner 和总结文档，没有对应原始 status/log/CSV/XO/xclbin/timing 报告。它们可以恢复为“代码里程碑”，但验证状态必须明确降级为 `NOT RUN / EVIDENCE MISSING`。

## 4. 当前最先进且内部一致的真实硬件结构

当前未跟踪代码中，最先进且接口互相一致的硬件是 **A10 v2 control-only automatic pipeline**：

```text
C++11 XRT HAL
  │ xclRegWrite / xclRegRead
  ▼
AXI-Lite register windows
  ├─ legacy MLP window
  ├─ standalone interaction window
  └─ automatic pipeline window 0x180–0x214
       │ descriptors / weights / biases / dense input
       │ four host-resolved 8×INT16 embedding vectors
       ▼
Bottom MLP 8→16→8
       ▼
Interaction: bottom + 4 embeddings, 5×8→18
       ▼ two activation chunks: 16 + 2
Top MLP 18→32→16→1
       ▼
INT16 result + index/last/final descriptor tag
```

主要参数：

- `MAX_LAYERS=8`；
- `MAX_WEIGHT_VALUES=2048`；
- `MAX_BIAS_VALUES=128`；
- `NUM_PE=16`；
- activation/result INT16、weight INT8、bias INT24、accumulator INT48；
- pipeline version `0x00024E11`；
- Stage 2M shape 为 Bottom `8→16→8`、Interaction `5×8→18`、Top `18→32→16→1`；
- 五个 descriptors、1360 weights、73 biases、最终 descriptor tag 4。

内部 controller 有 Bottom/interaction/Top 状态序列、embedding-loaded mask、result ready/valid、result POP、done latch、error ack、pending command 和 status/error readback。A10 v2 相对 A7 的 RTL 结构变化很小，主要是容量和名称/版本变化；A11/A12 host 使用的寄存器地址、版本和容量与之相符。

必须明确：四个 embedding vectors 由 CPU 根据 categorical IDs 解析后，通过 AXI-Lite 写入 RTL 的 4×128-bit 暂存阵列。它不是 FPGA-side embedding lookup。

## 5. A7–A12 中值得保留的代码

### A7：完整保留为独立代码里程碑

- `docs/STAGE2N_A7_KERNEL_PIPELINE_INTEGRATION.md`
- `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a7.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a7.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a7.sv`
- `scripts/run_stage2n_a7_kernel_pipeline_xsim_v1.sh`

### A8：保留 canonical v3 构建/验收部件

- `tcl/package_stage2n_a8_a7_xo_v3.tcl`
- `scripts/accept_stage2n_a8_xo_package_v3_artifact_v1.sh`
- `scripts/link_stage2n_a8_f37x_xclbin_v3.sh`
- `scripts/accept_stage2n_a8_f37x_link_v3_artifact_v1.sh`

现有 `run_stage2n_a8_xo_package_v3.sh` 被文档明确判定含过时 post-check，不作为 canonical runner。A8 的最终 PASS 文档等待原始证据后再处理。

### A9：保留最终 host/runner/collector

- `docs/STAGE2N_A9_PROTECTED_BOARD_SMOKE.md`
- `host/stage2n_a9_pipeline_board_smoke_v2.cpp`
- `scripts/program_and_run_stage2n_a9_pipeline_board_smoke_v3.sh`
- `scripts/collect_stage2n_a9_board_smoke_evidence_v1.sh`

### A10：保留 v2 RTL 和最终 v3/v4 host/evidence 链

- `docs/STAGE2N_A10_CAPACITY_EXPANSION.md`
- `docs/STAGE2N_A10_CAPACITY_EXPANSION_V2.md`
- `docs/STAGE2N_A10_F37X_LINK_V1.md`
- `docs/STAGE2N_A10_PROTECTED_BOARD_SMOKE_V1.md`
- `docs/STAGE2N_A10_BOARD_SMOKE_TAG_FIX_V2.md`
- `docs/STAGE2N_A10_STALE_RESULT_RECOVERY_V3.md`
- `docs/STAGE2N_A10_FINAL_EVIDENCE_COLLECTOR_FIX_V3.md`
- `docs/STAGE2N_A10_FINAL_EVIDENCE_SCHEMA_FIX_V4.md`
- `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2.sv`
- `scripts/inspect_stage2n_a10_model_inputs_v1.sh`
- `scripts/run_stage2n_a10_capacity_xsim_v2.sh`
- `tcl/package_stage2n_a10_xo_v2.tcl`
- `scripts/run_stage2n_a10_xo_package_v2.sh`
- `scripts/link_stage2n_a10_f37x_xclbin_v1.sh`
- `scripts/accept_stage2n_a10_f37x_link_artifact_v1.sh`
- `host/stage2n_a10_pipeline_board_smoke_v3.cpp`
- `scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v3.sh`
- `scripts/collect_stage2n_a10_final_evidence_v4.sh`

### A11：保留 v2 asset 和 batch host 链

- `docs/STAGE2N_A11_PIPELINE_BATCH_ASSET_V1.md`
- `docs/STAGE2N_A11_PIPELINE_BATCH_ASSET_MAGIC_FIX_V2.md`
- `docs/STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1.md`
- `python/build_stage2n_a11_pipeline_batch_asset_v2.py`
- `scripts/run_stage2n_a11_pipeline_batch_asset_v2.sh`
- `host/stage2n_a11_real_model_batch_board_v1.cpp`
- `scripts/run_stage2n_a11_real_model_batch_board_v1.sh`
- `scripts/collect_stage2n_a11_final_evidence_v1.sh`

### A12：保留 host-visible benchmark 最终代码链

- `docs/STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1.md`
- `docs/STAGE2N_A12_PERFORMANCE_BASELINE_RUNNER_FIX_V2.md`
- `host/stage2n_a12_pipeline_performance_baseline_v1.cpp`
- `scripts/run_stage2n_a12_pipeline_performance_baseline_v2.sh`
- `scripts/collect_stage2n_a12_final_evidence_v1.sh`

## 6. 明确不应进入新基线的文件

### 被 supersede 或含已知错误

- A8 的 `v1/v2` package Tcl、XO runners 和 link runners；现有 v3 XO runner 也不是 canonical。
- A9 host v1、board runner v1/v2。
- A10 非 `_v2` RTL/TB/Tcl/XSim/XO 文件，host v1/v2，board runner v1/v2，collector v2/v3。
- A11 builder v1 和 asset runner v1，其 magic 长度校验有已知错误。
- A12 performance runner v1，其 CSV 字段位置校验有已知错误。

### 重复或放错目录

- `docs/program_and_run_stage2n_a10_pipeline_board_smoke_v1.sh` 与 scripts 目录 v1 文件逐字节重复。
- `host/STAGE2N_A10_FINAL_ACCEPTANCE_V1.md` 与 docs 目录同名文件逐字节重复。

### 缺少原始证据的 PASS 总结

以下文件暂不进入恢复基线，除非找回原始证据，或改写为明确的“历史声称/待复跑”状态：

- `docs/STAGE2N_A8_ACCEPTED_XO_XCLBIN.md`
- `docs/STAGE2N_A9_BOARD_SMOKE_PASS.md`
- `docs/STAGE2N_A10_FINAL_ACCEPTANCE_V1.md`
- `docs/STAGE2N_A11_FINAL_ACCEPTANCE_V1.md`
- `docs/STAGE2N_A12_FINAL_PERFORMANCE_BASELINE_V1.md`

### 生成物与大型文件

任何未来重新生成的 `build/`、`work/`、`xsim.dir/`、DCP、WDB、XO、xclbin、Vivado/XSim 大日志和大 CSV 都不直接进入 Git。轻量 machine-readable status、hash manifest 和必要的小型摘要可以作为独立 evidence commit，经审查后精确添加。

## 7. 哪些“阶段完成”说法缺少证据

当前缺少原始证据的声明包括：

- A7 XSim PASS；
- A8 XO package PASS、F37X link PASS、完整 routed timing PASS 和所述 UUID/size；
- A9 自动 Bottom→Interaction→Top F37X board PASS；
- A10 capacity XSim、XO、link、timing、board 两次 result=36 和 final acceptance；
- A11 asset-v2 generation PASS、256/256 FPGA logits/predictions、228/256 classification；
- A12 5120/5120 exact、4560 classifications、`188.742 us`、`5298.240 samples/s` 等性能数字。

这些声明并非判定为错误，而是本地证据链不完整。在 status/log/CSV/hash 取回或复跑以前，只能记录为 `UNVERIFIED HISTORICAL CLAIM`。

## 8. 新恢复基线建议

建议最终创建：

```text
recovery/stage2n-pre-a13
```

它应基于已创建的 `recovery/stage2n-a6-baseline`，通过小提交逐层加入 canonical A7–A12 代码，不包含旧版、重复项、大型生成物或无证据的最终 PASS 总结。

该基线的状态说明必须分三层：

### 已经确认

- A3 及以前的已提交基础；
- A4 板卡 MLP + standalone interaction 原始证据；
- A5 internal Bottom→Interaction→Top XSim 原始证据；
- A6 internal OOC 100 MHz setup/hold/route/latch/DRC 证据；
- A7–A12 canonical 文件之间的静态依赖、容量、寄存器 ABI 和版本一致性。

### 仅代码存在

- A7 AXI-Lite automatic pipeline top/TB/runner；
- A8 canonical XO/link Tcl/validator；
- A9 automatic pipeline board host/runner；
- A10 v2 8/2048/128 capacity RTL/TB/build/board flow；
- A11 v2 asset builder、256-sample host/runner；
- A12 host-visible performance host/runner/collector。

### 尚未实现

- FPGA-side embedding lookup；
- kernel `m_axi`；
- HBM bank mapping；
- XRT BO/DMA；
- single-bank HBM lookup；
- multi-bank HBM lookup；
- hardware cycle counter；
- pure RTL Bottom/Interaction/Top/total 周期拆分。

## 9. 拟提交批次、文件清单与 commit message

以下仅为计划，本阶段不执行。

### Commit 1

Message：`stage2n: restore A7 AXI-Lite pipeline integration`

文件：A7 小节列出的 5 个文件。

提交前条件：A7 runner 静态检查通过；在有 Vivado 2020.2 的用户环境复跑 XSim，并将结果作为后续 evidence，而不是先写 PASS。

### Commit 2

Message：`build(stage2n): restore canonical A8 packaging flow`

文件：A8 小节列出的 4 个 canonical 文件。

提交前条件：明确记录当前缺少 canonical XO wrapper；不得把缺失的 A8 artifact 记为 PASS。

### Commit 3

Message：`test(stage2n): restore A9 protected board smoke flow`

文件：A9 小节列出的 4 个文件。

提交前条件：只提交 host/runner/collector/测试边界，不提交 board PASS 文档。

### Commit 4

Message：`stage2n: restore A10 capacity-expanded pipeline`

文件：A10 小节中的两份 capacity docs、两份 v2 RTL、v2 TB、model-input inspect、v2 XSim runner、v2 packaging Tcl/runner、link/accept 脚本和 link 流程说明。

精确核心文件为：

- `docs/STAGE2N_A10_CAPACITY_EXPANSION.md`
- `docs/STAGE2N_A10_CAPACITY_EXPANSION_V2.md`
- `docs/STAGE2N_A10_F37X_LINK_V1.md`
- `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2.sv`
- `scripts/inspect_stage2n_a10_model_inputs_v1.sh`
- `scripts/run_stage2n_a10_capacity_xsim_v2.sh`
- `tcl/package_stage2n_a10_xo_v2.tcl`
- `scripts/run_stage2n_a10_xo_package_v2.sh`
- `scripts/link_stage2n_a10_f37x_xclbin_v1.sh`
- `scripts/accept_stage2n_a10_f37x_link_artifact_v1.sh`

### Commit 5

Message：`test(stage2n): restore A10 protected board and evidence flow`

文件：

- `docs/STAGE2N_A10_PROTECTED_BOARD_SMOKE_V1.md`
- `docs/STAGE2N_A10_BOARD_SMOKE_TAG_FIX_V2.md`
- `docs/STAGE2N_A10_STALE_RESULT_RECOVERY_V3.md`
- `docs/STAGE2N_A10_FINAL_EVIDENCE_COLLECTOR_FIX_V3.md`
- `docs/STAGE2N_A10_FINAL_EVIDENCE_SCHEMA_FIX_V4.md`
- `host/stage2n_a10_pipeline_board_smoke_v3.cpp`
- `scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v3.sh`
- `scripts/collect_stage2n_a10_final_evidence_v4.sh`

不含 final acceptance PASS 文档。

### Commit 6

Message：`stage2n: restore A11 trained-model batch flow`

文件：A11 小节列出的 8 个 canonical/contract 文件，不含 A11 final acceptance PASS 文档。

提交前条件：先在本地重新生成并核对 `F37XPB1 v2` asset/status/manifest/CSV；生成物本身默认不进源码提交。

### Commit 7

Message：`perf(stage2n): restore A12 host-visible benchmark flow`

文件：A12 小节列出的 5 个 canonical/contract 文件，不含 A12 final performance PASS 文档。

提交前条件：明确 host-visible 与 pure RTL latency 的边界；不引用未找回的性能数字作为新基线。

### Commit 8（可选文档提交）

Message：`docs: record Stage 2N recovery evidence boundary`

拟包含：

- `PROJECT_RECOVERY_REPORT.md`
- `PROJECT_RECOVERY_CHECKLIST.md`
- `RECOVERY_UNTRACKED_INVENTORY.md`
- `RECOVERY_BASELINE_PLAN.md`

所有提交都必须使用精确 `git add <file...>`，禁止 `git add .`；每次提交前检查 `git diff --check`、staged 文件列表和仓库级 Git 身份 `管鹏飞 <gpengfei623@163.com>`。

## 10. 恢复完成后 A13 的准确起点

A13 的准确起点不是当前 `802573d`，也不是单独的 `a73e045`。它应是未来的 `recovery/stage2n-pre-a13`，并满足：

1. 基于可信 A6 commit `a73e045`；
2. canonical A10 v2 RTL/TB/host ABI 已形成提交；
3. A7 与 A10 XSim 至少重新取得原始 PASS status/log；
4. A11 asset v2 可本地重建并通过 software golden 自检；
5. A11/A12 板卡历史若没有原始证据，仍保持 `UNVERIFIED`，不阻塞保存代码，但不得写入“已验收”状态；
6. 工作树 clean，旧版和生成物不在基线；
7. 明确确认仓库中仍没有 cycle counter。

到这个点以后，A13 才能以“不改变数值通路”为前提定义并实现 Bottom、Interaction、Top、total 和 stall 周期计数。本阶段没有开始该设计。

## 11. 等待用户确认的拟执行方案

建议下一次操作顺序：

1. 用户确认上述 canonical/排除清单和 8 个拟提交批次。
2. 先为当前 113 个未跟踪文件生成 SHA-256 保护清单。
3. 从 `recovery/stage2n-a6-baseline` 建立 `recovery/stage2n-pre-a13`，不删除原分支。
4. 按 Commit 1–8 逐批精确添加；每批先报告 staged 文件和 diff，再等待 commit 确认。
5. 本地仅执行可用的静态/Python检查；Vivado 2020.2、XO/link 和板卡验证由用户执行并返回原始证据。
6. 最终更新状态文档并要求工作树 clean。

在用户确认以前，不执行 `git add`、commit、checkout、A13、HBM、算法或 RTL 功能修改。
