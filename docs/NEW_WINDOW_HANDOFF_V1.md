# 新窗口 / 新模型接入说明（2026-09-17）

先读本文件，再读 `docs/AI_CONTEXT.md`、`docs/CURRENT_STATE.md`、`AGENTS.md`。
不要从 `README.md` 前半的早期 INT8 小模型介绍推断当前板上合同。

本仓库 GitHub：`https://github.com/Gpengfei6/f37x_dlrm_rtl.git`  
当前工程分支：`work/stage2n-a16-multibank-parallel`  
本快照目的：把 zip 恢复之后的 A17.6 LUTLP 工作树、A18.1/A18.2 源码与板上功能证据推上去，让新对话不必从聊天记录里猜。

`PERFORMANCE=NOT_CLAIMED`。不要写 A16/A17/A18 加速比。

---

## 1. 现在做到哪一步

| 层级 | 状态 | 不能把它说成 |
|---|---|---|
| A13 | 冻结的 INT16 计算基线，计数 322/100/744/1174 | 查找创新 |
| A15.6 | 冻结的单 `HBM[0]` 四行顺序查找 + 完整 DLRM 功能 | 四 Bank 并行 |
| A16.2 | 单 Bank 顺序查找物理基线；N=11 进程重启已验收 | 与 A17 可比的速度结论 |
| A17.6 | 四 master / 四 BO / `HBM[0..3]`，行号写死 37–40；功能 PASS；N=11 已验收 | 可变索引；加速比 |
| A18.1 | 本地 2022.1 XSim：四个运行时查找行号 | 2020.2；板上 |
| **A18.2** | **板上功能 PASS，默认行号 37–40** | 性能 |
| **A18.3** | **五组锁定元组板上功能 PASS `20260917_202130`（GitHub `bcd3f86`）** | 加速比；T>4；extra-run |
| **A18.4** | **L1 E2/E4/E5 几何锁定（占用是构造结果）** | FPGA 时延；放置进 RTL |
| **A18.5** | **本地 T=8/B=4 映射器（Python PASS，XSim NOT RUN）** | 上板；完整 T=8 DLRM |
| **A18.6** | **映射器进 T=8 查找数据通路（未接入已烧 A18 顶层）** | 八路 embedding 进冻结 A13 |
| **A18.7** | **本地一行 cache（未接入已烧 A18 顶层）** | 命中率；带宽 |
| **A18.8** | **T=8 查找 + 每 bank 一行 cache（Python 金模型 PASS）** | 上板；完整 T=8 DLRM |
| **A18.9** | **4 行 cache + pair-fold；本地 2022.1 XSim PASS** | 2020.2；板上；A13 金值 |
| **A18.3 extra-run** | **runner 已写，板上 NOT_RUN** | T>4；加速比 |

卡上最后一次编程是 A18 UUID `32a9c911-af15-47fc-90c8-0bfe3894a3ef`（设备 index 2，BDF `0000:9b:00.1`，`renderD129`）。A18.3 未再 program。不要复位，不要再烧卡。extra-run 必须用 `scripts/run_stage2n_a18_3_extra_run_v1.sh`，该脚本不含 `xbutil program`。

---

## 2. 前因后果（为什么会有 A18）

1. **A17 把四槽行号写死为 37–40。** 文献/负载矩阵要的是可变索引、T>4、共同访问、热点。现硅不能跑那些实验。见 `docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md`。
2. **A18 的工程目标**不是换模型，而是：在冻结 A13 计算和四 Bank 几何不变的前提下，让四个槽的行号可在每次 START 前配置。地址仍是 `BASE[i] + row[i]×16`。
3. **2026-09-15 工作区被 Doubao 删过 `D:\FpgaWork`。** 以 zip 为最完整恢复包；zip 覆盖重叠文件，额外文件保留。不要凭聊天重写 A13–A17 RTL。见 `docs/ZIP_RESTORE_POST_INCREMENT_INVENTORY_V1.md`。
4. **早期 A18 草稿用重建的 AXI-Lite decode，不能用。** 正式 A18 内核必须从已验收 A17 内核拷贝生成：`scripts/generate_stage2n_a18_kernel_from_a17_v1.py`。残留 `rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv` **不要例化、不要当源**。
5. **CLEAR 曾被草稿放宽，已撤回。** A18 CLEAR 只允许 DONE→IDLE 和 ERROR→RECOVER，与 A17 相同。
6. **A18.2 板上第一跑只证明默认行号。** Host 把非 37–40 锁死，因为五组敏感用例仍改的是 `row 37+i`。解开锁却继续跑敏感表，会得到错误金值。

---

## 3. 新窗口必须遵守的硬边界

- 只在本仓库本地改。Agent 不要 SSH、不要碰 `172.17.8.254`、不要进 `/home/chaosuan` 或 `/opt/Xilinx`。
- 用户独自跑 2020.2 的 `v++`、烧卡、Host 执行。没有用户日志，不能写 F37X PASS。
- 不要改已验收 A13 / A14 v2 / A16 / A17 **原件**。A17 集成里的 LUTLP 握手（`compute_idle_q`、START valid 不再 AND A13 ready）是 zip 树上已上板的 A17.6 修复，不是新改 A17。
- 不要 `git clean`、`git reset --hard`、`git add .`。工作区有大量恢复杂文件和专利稿，必须按文件点名暂存。
- 本地 Vivado 是 **2022.1**，目标板是 **2020.2**。2022.1 XSim ≠ 2020.2。
- XSim 身份金值 **36** 不是板上金值。板上五组是 **-393 / -392 / -93 / -689 / -519**。
- 查找周期 33、e2e 1210 与 A17.6 同类观测一致，**不要写成加速**。
- 索引是 AXI-Lite MMIO `0x330-0x33C`，**不是** XO 内核参数。xclbin 签名只有 `TABLE_BASE0..3`。

---

## 4. 关键身份（抄错就整条链作废）

| 项 | 值 |
|---|---|
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a18_v1` |
| CU | `dlrm_a18_1` |
| PIPE_VERSION | `0x00024E18` |
| 索引复位默认 | 37, 38, 39, 40 |
| XO `a18_2_xo_001` SHA256 | `8d3f920aed2e4349d3d2cd6ea773d565b60deeae34e9a2880a58039dd23c84fd` |
| xclbin SHA256 | `bbb0fa1fcb5c39aea2a307eb8c8324eb406c51711b8ba2ae7830bc5fe3a36ec0` |
| xclbin UUID | `32a9c911-af15-47fc-90c8-0bfe3894a3ef` |
| Host 源 SHA256（A18.2） | `0a00e8ab7eab7be90b53905b3e4114921e365e681ecc0aef4a73e9f4565c521f` |
| Host ELF SHA256（A18.2） | `89644eb255bc0fb265f186ab76615f8a63b3dea0d8d117b265e681f5f7a75a32` |
| Host 源 SHA256（A18.3） | `f516896068f6664060cd392b954795f7fb877bdec66935f3163b8e38694dbaa9` |
| Host ELF SHA256（A18.3） | `011a0b8f1630b9cadbba49150f3f28ebfd042cc5c77af840bcc00d27a403187f` |
| 源清单 SHA256 | `e59524bfb085adbeb2b8101b8072163f9c9c35154f89118b4faa2cdd1944c86d` |
| 平台 | `inspur_f37x_xdma_201920_3`（SHA 与 A17.6 相同 `4bd7e119…`） |
| 器件 | `xcvu37p-fsvh2892-2L-e`，请求 100 MHz，WNS 0.000 |

拒绝：A16 UUID `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`；A17 UUID `622c839f-55f4-47c1-92e9-95ee5595ffa4`。  
A18.2 烧卡前实际 UUID 是 `3a4ebb31-933a-45c2-9ce4-04adce88615c`，当时已不是文档里记的 A16。

Linux 构建目录（用户侧，Agent 不去）：

`/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly`

不要覆盖已验收的 A17.6 目录。

---

## 5. 源码从哪读

公开顶层：`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv`（A17 拷贝 + 适配器同文件，不是独立 decode）。  
集成：`rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv`（START 时锁存四个 index）。  
Host：`host/stage2n_a18_2_four_bo_host_v1.cpp`（默认行号，已上板，不要改）。  
A18.3 Host：`host/stage2n_a18_3_index_tuple_host_v1.cpp`（五组元组，板上 PASS `20260917_202130`）。  
寄存器：`0x180-0x224` A13；`0x300` START/CLEAR；`0x304/0x318/0x320/0x328` BASE0–3；`0x30C/0x310` lookup/e2e；**`0x330-0x33C` 行号**。

更完整的 A13/A16/A17 文件表：`docs/SOURCE_HANDOFF_MANIFEST_A13_A17_V1.md`。  
A18 板上验收：`docs/STAGE2N_A18_2_BOARD_FUNCTION_ACCEPTANCE_V1.md`（默认行号）；
`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`（五组锁定元组）。
原件：`docs/evidence/stage2n_a18_2/function_pass_v1/20260917_171608/`；
`docs/evidence/stage2n_a18_3/function_pass_v1/20260917_202130/`。

完整 `post_route_timing_summary.rpt` 约 76MB，不进 GitHub。WNS 记录在 `docs/evidence/stage2n_a18_2/link_001/post_route/post_route_metrics.txt` 与 link 验收摘要。

---

## 6. 决策号（本阶段）

| 编号 | 内容 |
|---|---|
| D-075 | A18.1 本地可变索引；CLEAR 保持 A17 |
| D-076 | A18.2 本地打包/Host；Windows `python3 xo` 不是 2020.2 |
| D-077 | 用户返回的 XO/link 验收；当时 Host/板仍未跑 |
| D-078 | 默认 index 板上五组 + repeat PASS；原件已归档 |
| D-079 | GitHub 快照与新窗口交接 |
| D-080 | A18.3 Host 源与 g++ PASS；当时未上板 |
| D-081 | 用户「授权」五组元组板上执行 |
| D-082 | `20260917_202130` 原件归档验收 PASS |
| D-083 | GitHub 快照：A18.3 五组元组板上功能 `bcd3f86` |
| D-084 | A18.4 L1 E2/E4/E5 几何锁定 |
| D-085 | A18.5 T=8 映射器 |
| D-086 | A18.6 T=8 映射查找 |
| D-087 | A18.3 extra-run runner（不烧卡、不复位） |
| D-088 | A18.7 一行 cache |
| D-089 | 自答下一刀：A18.8 cache 进 T=8 查找；extra-run 现在不跑 |
| D-090 | A18.9 四行 cache + fold + 本地 2022.1 XSim |

更早的 A16/A17 N=11、LUTLP、四 BO 功能见 `docs/DECISIONS.md` D-070 起。

---

## 7. 下一步（未授权就不要做）

已关闭：A18.2 默认行号；A18.3 五组锁定元组（D-082/`bcd3f86`）；A18.4 L1 几何锁定（占用是构造结果，不是 FPGA）。

已授权、本地源码已落地：A18.5 映射器、A18.6 T=8 查找、A18.7 一行 cache、A18.8 带 cache 的 T=8 查找、A18.9 四行 cache + pair-fold（2022.1 XSim PASS）、A18.3 extra-run runner。

未授权、需要用户一句话：

- 再 program / 复位 / 跑 A17 Host / 换卡；
- 把 A18.5–A18.7 打进新 xclbin 并烧卡；
- 写加速比或 Class C 可比性能。

extra-run 已有 runner，板上仍是 `NOT_RUN`。用户若跑，必须 UUID 已是 `32a9c911-…`，且不用 `xbutil program`。

板上已对齐的五组元组（`20260917_202130`）：

- `(37,38,39,40) → -393`
- `(1,2,3,4) → -61`
- `(0,0,0,0) → -60`
- `(0,63,37,40) → -162`
- `(63,62,61,60) → -185`

---

## 8. 提交与推送约定

用户要求定期上传 GitHub，并带详细 markdown，方便新窗口接着干。

- 只点名 `git add` 本阶段文件，禁止 `git add .`。
- 不提交：专利稿、`handoff/*.zip` 解压目录、76MB timing rpt、restore 扫描脚本、xclbin 二进制。
- 没有用户明确说 commit/push 时，不要自己推。重大改动（A18.3 板上功能等）按用户 2026-09-17「有重大改动记得上传 git」上传。
