# Stage 2N A7–A12 未跟踪文件恢复清单

生成日期：2026-08-17

审计基准：`work/stage2n-fpga-interaction`，HEAD `802573d8b9b0da01539007b23d312f7cd3e16f43`。

## 1. 统计与字段说明

审计开始时共有 111 个非忽略未跟踪文件；第一阶段新增两份恢复报告后，本次扫描共有 113 个。其中按文件名和实际引用链可以归入 A7–A12 的文件共 79 个：A7 5 个、A8 13 个、A9 8 个、A10 35 个、A11 11 个、A12 7 个。

另外 34 个文件属于 A4–A6、Stage 2L/2M、早期 interaction 修复或恢复报告，不冒充 A7–A12。工作树中没有 A7–A12 对应的非忽略或忽略 build/cache/result/evidence 文件；脚本所引用的 A7–A12 `results/`、`build/`、`docs/evidence/`、`server_results/` 路径均不存在。

字段约定：

- “源码”仅指 RTL/TB、C++ host 或 Python 实现；shell/Tcl/XDC/Markdown 单列为脚本、约束或文档。
- “生成物”表示是否应由工具重新生成；本表 79 个文件均不是生成物。
- “证据”中的“配套结构”表示有 TB/runner/collector，但没有原始 status/log/CSV/XO/xclbin，因此不能视为 PASS。
- “Git 建议”是恢复方案，不是已执行操作：`纳入`、`暂缓`、`排除旧版`、`排除重复`。
- 修改时间是本地文件时间（Asia/Shanghai）。

## 2. A7：AXI-Lite 自动流水集成

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/STAGE2N_A7_KERNEL_PIPELINE_INTEGRATION.md` | 3847 | 2026-07-28 10:29:54 | A7 | docs | 否 | 否 | 配套结构；原始 XSim 缺失 | 纳入，作为寄存器契约和边界 |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a7.sv` | 11332 | 2026-07-28 10:29:05 | A7 | RTL source | 是 | 否 | TB/runner 存在；原始 XSim 缺失 | 纳入 A7 恢复提交 |
| `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a7.sv` | 42703 | 2026-07-28 10:28:47 | A7 | RTL source | 是 | 否 | TB/runner 存在；原始 XSim 缺失 | 纳入 A7 恢复提交 |
| `scripts/run_stage2n_a7_kernel_pipeline_xsim_v1.sh` | 5838 | 2026-07-28 10:29:26 | A7 | XSim script | 否 | 否 | 自校验入口；原始 status/log 缺失 | 纳入，复跑入口 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a7.sv` | 19218 | 2026-07-28 10:29:15 | A7 | TB source | 是 | 否 | 自校验 TB；原始 XSim 缺失 | 纳入 A7 恢复提交 |

A7 五个文件的 runner 引用链完整，并正确依赖 A5 segmented controller、internal pipeline controller、A2 legacy top 和 interaction engine。可作为“代码存在、待复跑”的独立恢复提交。

## 3. A8：A7 XO 与 F37X link 流程

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/STAGE2N_A8_ACCEPTED_XO_XCLBIN.md` | 2579 | 2026-07-28 15:55:53 | A8 | docs | 否 | 否 | 仅总结；原始 XO/link/timing 缺失 | 暂缓，取回证据后再纳入 |
| `docs/STAGE2N_A8_XO_XCLBIN_BUILD.md` | 2428 | 2026-07-28 11:12:02 | A8 | docs | 否 | 否 | 描述 v1；最终链已到 v3 | 排除旧版 |
| `scripts/accept_stage2n_a8_f37x_link_v3_artifact_v1.sh` | 10038 | 2026-07-28 15:55:38 | A8 | validation script | 否 | 否 | 原始 link artifact 缺失 | 纳入，canonical validator |
| `scripts/accept_stage2n_a8_xo_package_v3_artifact_v1.sh` | 12556 | 2026-07-28 14:34:28 | A8 | validation script | 否 | 否 | 原始 XO artifact 缺失 | 纳入，canonical validator |
| `scripts/link_stage2n_a8_f37x_xclbin_v1.sh` | 8748 | 2026-07-28 11:11:51 | A8 | build script | 否 | 否 | 被 v3 取代；无原始证据 | 排除旧版 |
| `scripts/link_stage2n_a8_f37x_xclbin_v2.sh` | 8748 | 2026-07-28 11:57:00 | A8 | build script | 否 | 否 | 被 v3 取代；无原始证据 | 排除旧版 |
| `scripts/link_stage2n_a8_f37x_xclbin_v3.sh` | 8748 | 2026-07-28 14:18:33 | A8 | build script | 否 | 否 | canonical link；原始结果缺失 | 纳入 |
| `scripts/run_stage2n_a8_xo_package_v1.sh` | 6623 | 2026-07-28 11:11:39 | A8 | build script | 否 | 否 | 失败/旧版 | 排除旧版 |
| `scripts/run_stage2n_a8_xo_package_v2.sh` | 6623 | 2026-07-28 11:56:48 | A8 | build script | 否 | 否 | 失败/旧版 | 排除旧版 |
| `scripts/run_stage2n_a8_xo_package_v3.sh` | 6623 | 2026-07-28 14:18:04 | A8 | build script | 否 | 否 | 文档明确称 post-check 已过时 | 排除旧版；需另行修复 canonical runner |
| `tcl/package_stage2n_a8_a7_xo_v1.tcl` | 14436 | 2026-07-28 11:11:20 | A8 | Tcl build source | 否 | 否 | 被 v3 取代 | 排除旧版 |
| `tcl/package_stage2n_a8_a7_xo_v2.tcl` | 16449 | 2026-07-28 11:56:37 | A8 | Tcl build source | 否 | 否 | 被 v3 取代 | 排除旧版 |
| `tcl/package_stage2n_a8_a7_xo_v3.tcl` | 16450 | 2026-07-28 14:17:53 | A8 | Tcl build source | 否 | 否 | canonical Tcl；原始 XO 缺失 | 纳入 |

A8 代码中 canonical 四件套是 v3 Tcl、XO artifact validator、v3 link、link artifact validator。现有 XO runner v3 被其自身总结文档判定带有过时 post-check，因此 A8 尚缺一个被验证的 canonical“一键打包”入口。

## 4. A9：A7 自动流水板卡 smoke

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/STAGE2N_A9_BOARD_SMOKE_PASS.md` | 1719 | 2026-07-28 16:47:56 | A9 | docs | 否 | 否 | 仅总结；原始 status/log 缺失 | 暂缓，不能作为 PASS 提交 |
| `docs/STAGE2N_A9_PROTECTED_BOARD_SMOKE.md` | 1688 | 2026-07-28 16:09:54 | A9 | docs | 否 | 否 | runner/host 存在；原始结果缺失 | 纳入，作为测试设计边界 |
| `host/stage2n_a9_pipeline_board_smoke_v1.cpp` | 22258 | 2026-07-28 16:08:41 | A9 | Host source | 是 | 否 | 被 v2 修复替代 | 排除旧版 |
| `host/stage2n_a9_pipeline_board_smoke_v2.cpp` | 23243 | 2026-07-28 16:41:25 | A9 | Host source | 是 | 否 | v3 runner 实际引用；原始板卡日志缺失 | 纳入，代码存在 |
| `scripts/collect_stage2n_a9_board_smoke_evidence_v1.sh` | 6618 | 2026-07-28 16:47:39 | A9 | evidence script | 否 | 否 | collector 存在；evidence 目录缺失 | 纳入 |
| `scripts/program_and_run_stage2n_a9_pipeline_board_smoke_v1.sh` | 21221 | 2026-07-28 16:08:53 | A9 | board script | 否 | 否 | 被 v3 替代 | 排除旧版 |
| `scripts/program_and_run_stage2n_a9_pipeline_board_smoke_v2.sh` | 22147 | 2026-07-28 16:15:48 | A9 | board script | 否 | 否 | 仍引用 host v1 | 排除旧版 |
| `scripts/program_and_run_stage2n_a9_pipeline_board_smoke_v3.sh` | 22221 | 2026-07-28 16:41:56 | A9 | board script | 否 | 否 | 引用 host v2；原始板卡证据缺失 | 纳入，待用户复跑 |

## 5. A10：Stage 2M 容量自动流水

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/program_and_run_stage2n_a10_pipeline_board_smoke_v1.sh` | 22020 | 2026-07-28 21:31:17 | A10 | misplaced duplicate script | 否 | 否 | 与 scripts/v1 完全重复 | 排除重复 |
| `docs/STAGE2N_A10_BOARD_SMOKE_TAG_FIX_V2.md` | 709 | 2026-07-29 08:41:20 | A10 | docs | 否 | 否 | 解释 v1 host tag bug | 纳入历史决策 |
| `docs/STAGE2N_A10_CAPACITY_EXPANSION.md` | 1490 | 2026-07-28 18:24:25 | A10 | docs | 否 | 否 | 设计说明；v1 文件非 canonical | 纳入背景，须与 v2 说明同时存在 |
| `docs/STAGE2N_A10_CAPACITY_EXPANSION_V2.md` | 812 | 2026-07-28 19:06:08 | A10 | docs | 否 | 否 | 指定 v2 canonical | 纳入 |
| `docs/STAGE2N_A10_F37X_LINK_V1.md` | 772 | 2026-07-28 19:28:26 | A10 | docs | 否 | 否 | 脚本存在；原始 link/timing 缺失 | 纳入为流程说明，不标 PASS |
| `docs/STAGE2N_A10_FINAL_ACCEPTANCE_V1.md` | 1284 | 2026-07-29 09:04:36 | A10 | docs | 否 | 否 | 仅总结；最终 evidence v4 缺失 | 暂缓，不能作为 PASS 提交 |
| `docs/STAGE2N_A10_FINAL_EVIDENCE_COLLECTOR_FIX_V3.md` | 687 | 2026-07-29 09:32:35 | A10 | docs | 否 | 否 | 记录 v2 路径错误 | 纳入历史决策 |
| `docs/STAGE2N_A10_FINAL_EVIDENCE_SCHEMA_FIX_V4.md` | 857 | 2026-07-29 09:42:27 | A10 | docs | 否 | 否 | 对应 canonical collector v4 | 纳入 |
| `docs/STAGE2N_A10_PROTECTED_BOARD_SMOKE_V1.md` | 890 | 2026-07-28 21:42:56 | A10 | docs | 否 | 否 | 测试设计；原始结果缺失 | 纳入，边界说明 |
| `docs/STAGE2N_A10_STALE_RESULT_RECOVERY_V3.md` | 951 | 2026-07-29 08:50:23 | A10 | docs | 否 | 否 | 对应 host v3 | 纳入 |
| `host/STAGE2N_A10_FINAL_ACCEPTANCE_V1.md` | 1284 | 2026-07-29 09:04:36 | A10 | duplicate docs | 否 | 否 | 与 docs 版本完全重复 | 排除重复 |
| `host/stage2n_a10_pipeline_board_smoke_v1.cpp` | 23521 | 2026-07-28 21:30:39 | A10 | Host source | 是 | 否 | tag 预期错误 | 排除旧版 |
| `host/stage2n_a10_pipeline_board_smoke_v2.cpp` | 24615 | 2026-07-29 08:39:30 | A10 | Host source | 是 | 否 | stale VALID/BUSY 顺序未修复 | 排除旧版 |
| `host/stage2n_a10_pipeline_board_smoke_v3.cpp` | 25909 | 2026-07-29 08:49:38 | A10 | Host source | 是 | 否 | v3 runner 实际引用；原始板卡证据缺失 | 纳入，代码存在 |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10.sv` | 11368 | 2026-07-28 18:23:46 | A10 | RTL source | 是 | 否 | 文档指定 v2 canonical | 排除旧版 |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv` | 11377 | 2026-07-28 19:05:09 | A10 | RTL source | 是 | 否 | v2 TB/runner/packager 一致；原始 XSim 缺失 | 纳入 canonical RTL |
| `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10.sv` | 42727 | 2026-07-28 18:23:32 | A10 | RTL source | 是 | 否 | 文档指定 v2 canonical | 排除旧版 |
| `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv` | 42742 | 2026-07-28 19:05:02 | A10 | RTL source | 是 | 否 | 参数 8/2048/128；调用链一致 | 纳入 canonical RTL |
| `scripts/accept_stage2n_a10_f37x_link_artifact_v1.sh` | 7701 | 2026-07-28 21:29:44 | A10 | validation script | 否 | 否 | 原始 xclbin/timing 缺失 | 纳入 |
| `scripts/collect_stage2n_a10_final_evidence_v2.sh` | 9809 | 2026-07-29 09:02:33 | A10 | evidence script | 否 | 否 | 被已知路径错误阻断 | 排除旧版 |
| `scripts/collect_stage2n_a10_final_evidence_v3.sh` | 9984 | 2026-07-29 09:32:09 | A10 | evidence script | 否 | 否 | 被已知 schema 错误阻断 | 排除旧版 |
| `scripts/collect_stage2n_a10_final_evidence_v4.sh` | 11377 | 2026-07-29 09:41:58 | A10 | evidence script | 否 | 否 | canonical collector；输入证据缺失 | 纳入 |
| `scripts/inspect_stage2n_a10_model_inputs_v1.sh` | 6227 | 2026-07-28 17:12:39 | A10 | inspection script | 否 | 否 | 检查 Stage 2M 容量输入 | 纳入 |
| `scripts/link_stage2n_a10_f37x_xclbin_v1.sh` | 10709 | 2026-07-28 19:22:52 | A10 | build script | 否 | 否 | 指向 v2 XO；原始 link 结果缺失 | 纳入 |
| `scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v1.sh` | 22020 | 2026-07-28 21:31:17 | A10 | board script | 否 | 否 | 引用 host v1 | 排除旧版 |
| `scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v2.sh` | 22100 | 2026-07-29 08:40:16 | A10 | board script | 否 | 否 | 引用 host v2 | 排除旧版 |
| `scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v3.sh` | 22100 | 2026-07-29 08:50:02 | A10 | board script | 否 | 否 | 引用 host v3；原始板卡证据缺失 | 纳入，待用户复跑 |
| `scripts/run_stage2n_a10_capacity_xsim_v1.sh` | 5804 | 2026-07-28 18:24:12 | A10 | XSim script | 否 | 否 | 指向非 canonical v1 RTL/TB | 排除旧版 |
| `scripts/run_stage2n_a10_capacity_xsim_v2.sh` | 5828 | 2026-07-28 19:05:31 | A10 | XSim script | 否 | 否 | 指向 v2 RTL/TB；原始 status/log 缺失 | 纳入，复跑入口 |
| `scripts/run_stage2n_a10_xo_package_v1.sh` | 13490 | 2026-07-28 18:47:19 | A10 | build script | 否 | 否 | 指向非 canonical v1 | 排除旧版 |
| `scripts/run_stage2n_a10_xo_package_v2.sh` | 13535 | 2026-07-28 19:05:55 | A10 | build script | 否 | 否 | 与 v2 Tcl/top/adapter 一致；原始 XO 缺失 | 纳入 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity.sv` | 21080 | 2026-07-28 18:23:58 | A10 | TB source | 是 | 否 | 非 canonical v1 | 排除旧版 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2.sv` | 21092 | 2026-07-28 19:05:11 | A10 | TB source | 是 | 否 | 5/1360/73、两次运行、12-cycle backpressure | 纳入 canonical TB |
| `tcl/package_stage2n_a10_xo_v1.tcl` | 16524 | 2026-07-28 18:46:57 | A10 | Tcl build source | 否 | 否 | 指向非 canonical v1 | 排除旧版 |
| `tcl/package_stage2n_a10_xo_v2.tcl` | 16539 | 2026-07-28 19:05:41 | A10 | Tcl build source | 否 | 否 | 与 v2 top/adapter 一致 | 纳入 |

A10 v2 top 与 A7 top 的实质差异仅为 module/adapter 名称和容量版本；A10 v2 adapter 相对 A7 将 `MAX_LAYERS/MAX_WEIGHT_VALUES/MAX_BIAS_VALUES` 从 `4/1024/64` 扩到 `8/2048/128`，保留相同 AXI-Lite ABI 和内部 controller。代码内部一致，但 A10 XSim、XO、link、timing、board 的原始产物均缺失。

## 6. A11：Stage 2M 资产与 256-sample host

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/STAGE2N_A11_FINAL_ACCEPTANCE_V1.md` | 1291 | 2026-07-29 11:05:49 | A11 | docs | 否 | 否 | 仅总结；原始 status/log/CSV 缺失 | 暂缓，不能作为 PASS 提交 |
| `docs/STAGE2N_A11_PIPELINE_BATCH_ASSET_MAGIC_FIX_V2.md` | 803 | 2026-07-29 10:38:38 | A11 | docs | 否 | 否 | 解释 v1 magic bug | 纳入 |
| `docs/STAGE2N_A11_PIPELINE_BATCH_ASSET_V1.md` | 1239 | 2026-07-29 10:11:15 | A11 | docs | 否 | 否 | 资产契约；最终实现为 v2 | 纳入背景，须注明 v2 canonical |
| `docs/STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1.md` | 1236 | 2026-07-29 10:54:34 | A11 | docs | 否 | 否 | 测试设计；原始板卡证据缺失 | 纳入为测试设计，不标 PASS |
| `host/stage2n_a11_real_model_batch_board_v1.cpp` | 40042 | 2026-07-29 10:53:24 | A11 | Host source | 是 | 否 | 与 A10 v2 ABI 一致；原始板卡证据缺失 | 纳入，代码存在 |
| `python/build_stage2n_a11_pipeline_batch_asset_v1.py` | 35182 | 2026-07-29 10:10:21 | A11 | Python source | 是 | 否 | 已知 7/8-byte magic bug | 排除旧版 |
| `python/build_stage2n_a11_pipeline_batch_asset_v2.py` | 35324 | 2026-07-29 10:37:35 | A11 | Python source | 是 | 否 | canonical；输出资产/status/CSV 均缺失 | 纳入，待本地复跑 |
| `scripts/collect_stage2n_a11_final_evidence_v1.sh` | 14243 | 2026-07-29 11:05:08 | A11 | evidence script | 否 | 否 | collector 存在；输入 evidence 缺失 | 纳入 |
| `scripts/run_stage2n_a11_pipeline_batch_asset_v1.sh` | 8114 | 2026-07-29 10:10:50 | A11 | asset script | 否 | 否 | 指向已知错误 builder v1 | 排除旧版 |
| `scripts/run_stage2n_a11_pipeline_batch_asset_v2.sh` | 8114 | 2026-07-29 10:38:17 | A11 | asset script | 否 | 否 | 指向 builder v2；原始资产证据缺失 | 纳入，复跑入口 |
| `scripts/run_stage2n_a11_real_model_batch_board_v1.sh` | 13992 | 2026-07-29 10:54:03 | A11 | board script | 否 | 否 | 依赖缺失的 A10 final v4/A11 asset v2 evidence | 纳入代码；当前不可运行 |

A11 builder v2 确实从 Stage 2M package 重算 Bottom、interaction、Top，生成 5 descriptors、1360 weights、73 biases 和 256 samples；host 与 A10 v2 的地址、版本、容量、最终 tag=4 完全对齐。但本地不存在生成的 `F37XPB1 v2`、manifest、status 或 sample CSV，板卡 runner 的前置 evidence 也不存在。

## 7. A12：host-visible 性能基线

| 路径 | 字节 | 修改时间 | 推测阶段 | 类型 | 源码 | 生成物 | 配套证据 | Git 建议 |
|---|---:|---|---|---|---|---|---|---|
| `docs/STAGE2N_A12_FINAL_PERFORMANCE_BASELINE_V1.md` | 1427 | 2026-07-29 15:06:32 | A12 | docs | 否 | 否 | 仅总结；原始 status/log/CSV 缺失 | 暂缓，不能作为最终基线提交 |
| `docs/STAGE2N_A12_PERFORMANCE_BASELINE_RUNNER_FIX_V2.md` | 1214 | 2026-07-29 14:55:43 | A12 | docs | 否 | 否 | 解释 v1 CSV field bug | 纳入 |
| `docs/STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1.md` | 1358 | 2026-07-29 14:47:26 | A12 | docs | 否 | 否 | 测量定义，不宣称纯 RTL | 纳入 |
| `host/stage2n_a12_pipeline_performance_baseline_v1.cpp` | 24476 | 2026-07-29 14:46:41 | A12 | Host source | 是 | 否 | 复用 A11 host；原始 CSV/log 缺失 | 纳入，代码存在 |
| `scripts/collect_stage2n_a12_final_evidence_v1.sh` | 15396 | 2026-07-29 15:06:14 | A12 | evidence script | 否 | 否 | collector 存在；输入 evidence 缺失 | 纳入 |
| `scripts/run_stage2n_a12_pipeline_performance_baseline_v1.sh` | 17762 | 2026-07-29 14:47:08 | A12 | performance script | 否 | 否 | 已知 CSV field 校验错误 | 排除旧版 |
| `scripts/run_stage2n_a12_pipeline_performance_baseline_v2.sh` | 18248 | 2026-07-29 14:55:28 | A12 | performance script | 否 | 否 | canonical runner；依赖缺失的 A11 evidence | 纳入代码；当前不可运行 |

A12 host 的计时边界真实存在：prepare idle、input program、start issue、wait valid、result read、retire 和 total。它直接 include A11 host 以复用资产解析和寄存器协议。现有代码可以保留，但 `188.742 us`、`5298.240 samples/s` 等数字没有本地原始 CSV/status/log 支撑。

## 8. 非 A7–A12 的 34 个未跟踪文件

这些文件未混入上述 79 个阶段清单：

- A4：6 个。`host/stage2n_a4_integrated_smoke_v3.cpp` 与 `scripts/run_stage2n_a4_host_only_v2.sh` 已精确存在于恢复分支 `f8dbbd8`；其余是旧版或板卡操作脚本。
- A5：2 个显式 A5 文件，另有 3 个无阶段后缀的 A5 RTL/TB。五个 canonical 文件均已精确存在于 `915a49b`。
- A6：15 个。canonical XDC、acceptance 文档和最终 timing/hold 脚本已存在于 `a73e045`；其余 v1/v2 OOC/诊断文件是历史候选，不能另行混入基线。
- 早期/无法归入 A7–A12：9 个，包括 Stage 2L/2M inspect/recovery helper 和 interaction `FIXED` 版本；当前 pre-A13 恢复方案不纳入。
- 恢复文档：2 个，即 `PROJECT_RECOVERY_REPORT.md` 与 `PROJECT_RECOVERY_CHECKLIST.md`；可在恢复过程单独形成 docs 提交。

另有本文件和 `RECOVERY_BASELINE_PLAN.md` 将作为本阶段新增文档；本阶段不执行 `git add` 或 commit。
