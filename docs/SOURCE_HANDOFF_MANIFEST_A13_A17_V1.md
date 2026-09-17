# 源码交付清单（A13 / A16 / A17 审阅用）

日期：2026-09-15。只列老师理解与审阅源码所需文件。  
不含：论文草稿、文献对照、L1 几何工具、专利稿、A17.4/A17.5 映射提案、历史失败产物、以及工作区里其它未跟踪杂文件。

图例：

- **板上验证**：该文件所在链路已有用户返回的板级功能/时序验收记录（见对应验收文档）。本清单不改写那些结论。
- **仅本地验证**：仿真/静态检查，不能当成板上结果。
- **受保护**：已验收或功能闭合资产；本轮不得改源码。

---

## A. 说明与入口（先读）

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `README.md` | 仓库入口；前半是早期项目介绍，**不能**当 A13/A17 现状 | 否 | 文档 | 否（历史介绍） |
| `docs/ARCHITECTURE.md` | A13 计算边界与 A14 查找方向 | 否 | 文档 | 否 |
| `docs/PROJECT_SOURCE_CODE_GUIDE_V1.md` | 本批通俗结构说明 | 否 | 文档 | 否 |
| `docs/IMPLEMENTATION_FACTS_A13_A17_V1.md` | 位宽/AXI/时钟等可核对事实 | 否 | 文档 | 否 |
| `AGENTS.md` | 工作边界与保护规则 | 否 | 规则 | 是（规则） |

验收结论正文（只读，不在本轮修改）：

| 文件 | 用途 | 板上 | 受保护 |
|---|---|---|---|
| `docs/STAGE2N_A13_FINAL_ACCEPTANCE.md` | A13 计算+计数板上验收 | 是 | 是 |
| `docs/STAGE2N_A15_6_ALL_HBM_BOARD_FINAL_ACCEPTANCE_V1.md` | A15.6 单 `HBM[0]` 四行功能 | 是 | 是 |
| `docs/STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md` | A16.2 单 Bank 顺序基线 | 是 | 是 |
| `docs/STAGE2N_A17_6_FOUR_BO_HOST_V1.md` | A17.6 四 BO Host 与功能闭合说明 | 是（功能闭合） | 是 |

---

## B. A13 已验收计算链路

公开顶层只有 AXI4-Lite，embedding 由 Host 写入。

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv` | A13 内核顶层 | 是 | 否 | 是 |
| `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv` | `0x180–0x224` 适配 | 是 | 否 | 是 |
| `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv` | 周期计数包装 | 是 | 否 | 是 |
| `rtl/pipeline/dlrm_internal_pipeline_controller.sv` | Bottom→交互→Top 控制器 | 是 | 否 | 是 |
| `rtl/interaction/dlrm_feature_interaction_engine.sv` | 5×8 → 18 特征交互 | 是 | 否 | 是 |
| `rtl/compute/dense_layer_engine.sv` | 稠密层引擎 | 是 | 否 | 是 |
| `rtl/compute/mac_lane.sv` | MAC 通道 | 是 | 否 | 是 |
| `rtl/compute/vector_dot_product_core.sv` | 点积核 | 是 | 否 | 是 |
| `rtl/control/mlp_sequence_controller.sv` | MLP 序列 | 是 | 否 | 是 |
| `rtl/control/mlp_sequence_controller_segmented.sv` | 分段 MLP 序列 | 是 | 否 | 是 |
| `rtl/memory/banked_activation_buffer.sv` | 分银行激活缓冲 | 是 | 否 | 是 |
| `rtl/memory/local_weight_provider.sv` | 片上权重/偏置 | 是 | 否 | 是 |
| `rtl/common/runtime_relu_quant.sv` | 量化/ReLU | 是 | 否 | 是 |
| `rtl/common/rv_fifo.sv` | ready/valid FIFO | 是 | 否 | 是 |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv` | A13 顶层仍挂接的 `0x000–0x17F` 历史窗口 | 随 A13 内核 | 否 | 是 |
| `host/stage2n_a13_cycle_counter_board_v1.cpp` | A13 板上 Host | 是 | 否 | 是 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1.sv` | A13 计数内核仿真 | 否 | 是 | 是 |
| `tb/tb_dlrm_internal_pipeline_controller_v1.sv` | 内部流水仿真 | 否 | 是 | 是 |
| `config/stage2n_a13_v1.cfg` | A13 链接：仅 CU 名，无 HBM `sp` | 构建配置 | 否 | 是 |
| `constraints/stage2n_a13_cycle_counter_100mhz_v1.xdc` | 10.000 ns 约束 | 时序目标 | 否 | 是 |

---

## C. A16 单 Bank 对照链路

在 A15 顺序四行查找上加 lookup/e2e 计数。一个 `m_axi_gmem` → `HBM[0]`。

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv` | A16 公开内核（含计数器模块） | 是 | 否 | 是 |
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv` | 单引擎顺序四行注入 A13 | 是（经 A15.6/A16.2） | 否 | 是 |
| `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv` | 单路 AXI 读查找 | 是 | 否 | 是 |
| `host/stage2n_a16_2_physical_latency_v1.cpp` | A16.2 板上 Host | 是 | 否 | 是 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv` | A16 内核仿真 | 否 | 是 | 是 |
| `tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv` | A14 v2 查找仿真 | 否 | 是 | 是 |
| `config/stage2n_a16_2_target_v1.cfg` | `m_axi_gmem:HBM[0]` | 构建配置 | 否 | 是 |

A16 计算侧复用 B 节 A13 模块，不另列。

---

## D. A17 四 Bank 功能链路

四个 A14 v2 引擎、四个 AXI 口、四个 BO。行号写死为 `slot0→37`、`slot1→38`、`slot2→39`、`slot3→40`。

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` | A17 公开内核 | 是（A17.6 功能） | 否 | 是 |
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` | 四路查找 + A13 门控 | 是 | 否 | 是 |
| `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` | 四引擎并行控制器 | 是 | 否 | 是 |
| `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv` | 同上，四次例化 | 是 | 否 | 是 |
| `host/stage2n_a17_6_four_bo_host_v1.cpp` | 四 BO Host | 是 | 否 | 是 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` | 公开内核仿真 | 否 | 是 | 是 |
| `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` | 集成仿真 | 否 | 是 | 是 |
| `tb/tb_dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` | 四路查找仿真 | 否 | 是 | 是 |
| `config/stage2n_a17_6_target_v1.cfg` | `gmem0..3 → HBM[0..3]` | 构建意图 | 否 | 是 |
| `config/stage2n_a17_6_sources_v1.json` | A17.6 打包源清单 | 构建 | 否 | 是 |
| `scripts/package_stage2n_a17_6_rtl_kernel_v1.tcl` | XO 打包 Tcl | 构建脚本 | 否 | 是 |
| `docs/STAGE2N_A17_6_BUILD_HANDOFF_V1.md` | 构建交接 | 文档 | 否 | 是 |

A17 计算侧同样复用 B 节 A13 模块。

---

## E. 模型与定点说明

当前板上金标准与 A15.6/A16.2/A17.6 共用紧凑资产，**不要**把早期 `config/model_config.json`（INT8、32 行）当成 A13 板级模型。

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `models/stage2n_a15_6/stage2n_a15_6_model_v1.bin` | 描述符/权重/偏置紧凑包 | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_cases_v1.json` | 五用例与金标准 | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_case0_baseline_table_v1.bin` | 1024 字节表；`slot0→row 37` … `slot3→row 40` | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_case1_slot0_sensitivity_table_v1.bin` | 槽0 敏感表 | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_case2_slot1_sensitivity_table_v1.bin` | 槽1 敏感表 | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_case3_slot2_sensitivity_table_v1.bin` | 槽2 敏感表 | 是 | 否 | 是 |
| `models/stage2n_a15_6/stage2n_a15_6_case4_slot3_sensitivity_table_v1.bin` | 槽3 敏感表 | 是 | 否 | 是 |
| `models/stage2m/stage2m_trained_hybrid_dlrm_manifest.json` | A13 验收点名的 hybrid 模型清单（宽高 8×16×8 / 18 / 32×16×1） | 随 A13 资产 | 清单 | 是 |
| `docs/fixed_point_spec_v0.md` | **早期** INT8 embedding / INT32 累加器合同 | 否（与 A13 板级 INT16/INT48 不同） | 历史说明 | 否 |
| `docs/ARCHITECTURE.md` | A13：Host 写入 INT16×8 embedding | 文档 | 否 | 否 |

`stage2m` manifest 里的包路径指向当时生成环境，**不是**本仓库内可执行的 `.f37xhd` 副本；板上复现以 `models/stage2n_a15_6/` 为准。

---

## F. 明确不列入本清单的内容

- `docs/STAGE2N_A17_PAPER_*`、文献登记、Flips 对照
- L1 几何工具 `analysis/stage2n_a18_l1/`（不是板上证据）
- `docs/patent_*`
- `analysis/stage2n_a17_4/`、`analysis/stage2n_a17_5/` 提案
- 工作区既有未跟踪杂文件（例如部分 `tb/*FIXED*`、`tcl/package_stage2n_a8_*`）
- `docs/CURRENT_STATE.md` / `docs/DECISIONS.md`（状态档案；本轮不混入交付编辑）
- 残留 `rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv`（不要例化）

---

## G. A18 可变索引链路（2026-09-17 后补）

四个 master 仍映射 `HBM[0..3]`。行号改为 MMIO `0x330-0x33C`，复位默认仍是 37–40。
板上第一跑只验收了默认行号。五组锁定元组板上功能已验收：
`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`（`20260917_202130`）。
新对话入口：`docs/NEW_WINDOW_HANDOFF_V1.md`。

| 文件 | 用途 | 板上 | 仅本地 | 受保护 |
|---|---|---|---|---|
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv` | A18 公开内核（A17 拷贝 + 索引） | 是（默认 37–40） | 否 | 是（A18.2 身份） |
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv` | START 锁存四索引 | 随 A18 内核 | 否 | 是 |
| `host/stage2n_a18_2_four_bo_host_v1.cpp` | 四 BO Host，默认索引 | 是 | 否 | 是（勿改 SHA） |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv` | 公开口仿真 A–H | 否 | 是 | 否 |
| `docs/STAGE2N_A18_2_BOARD_FUNCTION_ACCEPTANCE_V1.md` | 板上验收叙述 | 是 | 文档 | 是 |
