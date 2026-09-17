# Zip 恢复与 zip 之后增量清单

日期：2026-09-16。范围：只处理 `D:\FpgaWork` 下的 `f37x_dlrm_rtl` 相关路径。未 commit、未连服务器、未上板。A18 编码继续停。

本清单只记录有文件依据的动作。没有文件依据的项标 **MISSING**，不猜 ABI。

## 1. Zip 核对

| 项 | 值 |
|---|---|
| 路径 | `D:\FpgaWork\f37x_dlrm_rtl.zip` |
| 大小 | 93409180 字节 |
| SHA256 | `62508BB6DA00BB4A12416F2D51BA04FA37B248F54761584BEDF511126310429C` |
| mtime | 2026-09-15 10:06:05 |
| 解压目录 | `D:\FpgaWork\f37x_dlrm_rtl_from_zip`（独立目录，未直接解压进当前工程） |
| 解压文件数 | 3266（含 `.git`） |

## 2. 合并规则（已执行）

1. 当前工程整树复制到 `D:\FpgaWork\f37x_dlrm_rtl_a18_draft_aside`（只拷不删）。
2. 将 zip 解压树覆盖进 `D:\FpgaWork\f37x_dlrm_rtl`：重叠以 zip 为准，不 `/MIR` 清除当前多出来的文件。
3. zip 树中的路径现已全部出现在当前目录（相对 zip：缺失 0）。
4. 当前相对 zip 多出来的文件全部保留（A18 草稿与本对话写入的文档）。

当前工作副本相对 zip 解压树：重叠 3266 个文件中，源码内容仅 `docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md` 有意不同（见第 4 节）。`.git/index` 已从 zip 解压树拷回。

## 3. 从 zip 恢复到当前目录的关键树

这些路径在误删后的残树里曾缺失或不可信，现与 zip 解压树一致：

- `.git/`（HEAD `c0a4fa1`：`docs(stage2n): finalize A17.2 public kernel validation record`，分支 `work/stage2n-a16-multibank-parallel`）
- `host/`（26 个文件）
- `models/`（12 个文件）
- `docs/evidence/`（332 个文件）
- A13 RTL：`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv`、`rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`、`rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv`
- A14 RTL：`rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`、`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv` 及 v1 对照
- A16 RTL：`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv`
- A17 RTL：`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv`、`rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv`
- A17 XSim：`scripts/run_stage2n_a17_2_public_kernel_xsim_v1.ps1` / `.tcl`，以及 `run_stage2n_a17_1_multibank_xsim_v1.*`

A13/A14/A16/A17 源码 SHA 与 zip 解压树一致。未用聊天记录重写这些 RTL。

## 4. Zip 之后增量（只合并有文件依据的）

| 路径 | 依据 | 处理 |
|---|---|---|
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv` | aside / 当前草稿，SHA 与 aside 相同 | 保留（zip 中无此文件） |
| `rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv` | 同上 | 保留。**不是**已核对的 A17 位级派生；A18 编码停，未按冻结 A17 改写 |
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv` | 同上 | 保留 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv` | 同上 | 保留 |
| `scripts/run_stage2n_a18_variable_index_xsim_v1.ps1` | 本对话写过的脚本：TEMP 取 `xvlog --version`、COMPILE/ELAB/SIM 分列、禁止把 2022.1 写成 2020.2 通过 | 保留 |
| `scripts/run_stage2n_a18_variable_index_xsim_v1.tcl` | 本对话：`catch {run all}` 失败则 `quit -force -code 1` | 保留 |
| `scripts/check/check_stage2n_a18_variable_index_v1.py` | aside 草稿 | 保留 |
| `scripts/materialize_stage2n_a18_from_a17_v1.py` | aside 草稿 | 保留；未用它覆盖 A17 |
| `docs/STAGE2N_A18_VARIABLE_INDEX_RTL_V1.md` | aside 草稿 | 保留 |
| `analysis/run_stage2n_a18_l1_workload_analyzer.py` 及 `analysis/stage2n_a18_l1/` | aside / 当前 | 保留 |
| `docs/STAGE2N_A18_L1_WORKLOAD_ANALYZER.md` | aside / 当前 | 保留 |
| `scripts/check/check_stage2n_a18_l1_workload_analyzer_v1.py` | aside / 当前 | 保留 |
| `build/stage2n_a18_recover_v1/` | 本对话恢复脚手架，非冻结源码 | 保留，不作 ABI 依据 |
| `docs/PROJECT_SOURCE_CODE_GUIDE_V1.md` | 本对话 jsonl：Write 行 793 + StrReplace 行 807，全部命中 | 写入当前 `docs/` |
| `docs/SOURCE_HANDOFF_MANIFEST_A13_A17_V1.md` | jsonl Write 行 794 + StrReplace 行 807 | 写入当前 `docs/` |
| `docs/IMPLEMENTATION_FACTS_A13_A17_V1.md` | jsonl Write 行 794 + StrReplace 行 807/814 | 写入当前 `docs/` |
| `docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md` | aside 比 zip 多一段 L1 分析器说明（2026-09-15），文件级 diff | 以 aside 覆盖当前（zip 后增量） |
| A17.x RTL 修复（相对 zip） | 当前 A17 `.sv` SHA == zip | **无增量可合并**（zip 已含当时工作区内容） |
| 从冻结 A17 撤回 A18 CLEAR 放宽 | 本对话要求过，但 A18 编码已停，磁盘上无这次修改 | **MISSING / 未做** |
| 用聊天重写 A13–A17 接口或 AXI-Lite 位图 | 禁止 | **未做** |
| 把 zip 内 A17.6 文档当成 xo_002 / link_004 硅上 identity | 无 `frozen_identities` 核验文件被本轮补写 | **MISSING，不声称** |

aside 与 zip 重叠但字节不同的 `STAGE2N_A17_LITERATURE_REGISTER.md` 以及若干 `.sh`：去掉 CRLF 后文本相同。按「重叠以 zip 为准」保留 zip（LF），不把 aside 的 CRLF 当增量。

## 5. 当前相对 zip 多出来的路径（36）

- A18 RTL / TB / XSim / check / materialize（上表）
- A18 L1 分析器与文档
- `build/stage2n_a18_recover_v1/*`
- `docs/PROJECT_SOURCE_CODE_GUIDE_V1.md`
- `docs/SOURCE_HANDOFF_MANIFEST_A13_A17_V1.md`
- `docs/IMPLEMENTATION_FACTS_A13_A17_V1.md`

`STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md` 在 zip 与当前都有；当前已叠加上 zip 之后 jsonl 的 L1/真实负载契约段落。

## 6. 仍缺 / 无法核实

- 误删前一刻若还有 **未打进 2026-09-15 10:06 zip、也未以文件形式出现在本对话 Write/StrReplace** 的改动：无法恢复。**MISSING**。
- A18 草稿 **不是** 可编译验收件：依赖已从 zip 补回，但 A18 顶层/decode 仍是草稿，接口未按冻结 A17 逐寄存器核验。A18 编码仍停；未把 jsonl 里对 A18 pipeline 的 OOB/`load_all_req_ready` 补丁写回去（那是继续改 RTL）。
- 本对话里讨论过、磁盘与 jsonl Write 都没有正文的 ABI/CLEAR/寄存器位： **MISSING**，不补猜。
- Cursor 本地 History 里与 zip 字节不同的 6 个文件，去掉 CRLF 后与 zip 文本相同，不当增量。
- 回收站数据区空、无卷影副本：zip 以外的永久删除内容无法找回。

## 8. 续做（2026-09-16 晚）：jsonl 回放 zip 之后文档/L1

对照本对话 jsonl 自 A18 文献/L1 起的 Write+StrReplace（行 742–811），在 **old_string 全部命中** 的前提下写回当前树。未改 A13–A17 RTL，未覆盖 A18 RTL 草稿。

已合并：

- `docs/STAGE2N_A17_LITERATURE_REGISTER.md`：核验状态列、`SOURCE_VERIFIED` 总表、`slot0→37` 行号写法
- `docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md`：L1 请求分布说明、§7 真实负载契约、`slot0→37` 表
- `docs/STAGE2N_A18_L1_WORKLOAD_ANALYZER.md` 及 `analysis/stage2n_a18_l1/`、入口与自检脚本

本地自检：`scripts/check/check_stage2n_a18_l1_workload_analyzer_v1.py` → `A18_L1_WORKLOAD_ANALYZER_SELFTEST=PASS`。不是板上结果。

相对 zip 解压树（不含 `.git`）现仅这两份文档内容不同；A17 kernel / A14 lookup / Host / `docs/evidence/stage2n_a17_6/frozen_identities_v1.txt` 仍与 zip 一致。该 identities 文件在 zip 里，不在本轮新造；本轮不根据它重申板上 PASS。

## 7. 归档（非磁盘永久删除）

未清空回收站（会波及其他项目）。将较早的 A14.6 bundle 恢复副本移到：

`D:\FpgaWork\f37x_dlrm_rtl_recovery_archive\`

保留：当前工程、`f37x_dlrm_rtl.zip`、`f37x_dlrm_rtl_from_zip`、`f37x_dlrm_rtl_a18_draft_aside`。

未触碰 `D:\FpgaWork` 下非 `f37x_dlrm_rtl*` 的项目目录。
