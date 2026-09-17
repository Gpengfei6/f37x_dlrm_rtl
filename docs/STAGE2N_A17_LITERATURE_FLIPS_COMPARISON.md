# Flips 与本项目逐项对照（研究记录）

日期：2026-09-14。状态：**文献对照 / 创新点收紧**。不是新论文版本，不是实验闭合，不改验收结论。

本文件只做研究记录。不修改 RTL、Host、`config/`、xclbin、证据目录、`docs/CURRENT_STATE.md`、`docs/DECISIONS.md` 中的状态句，也不新增 V4 论文稿。

## 0. 阅读边界

仓库内 **没有** Flips / FLiPS / FLIPS 的 PDF、bib 或摘录。V3 Related Work（2026-09-08）已选读 DLRM、Cross-Stack、MicroRec、FleetRec（仅摘要/工件）、SCRec，**未列入 Flips**。本次按仓库规则不联网取原文。

总登记（MicroRec/FleetRec 主线，Flips/HPS 等排查，F-TADOC 类硬件方法）见
`docs/STAGE2N_A17_LITERATURE_REGISTER.md`。下一阶段负载矩阵见
`docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md`。本文件仍只处理 Flips 五轴。

因此：

- **本项目列**：只写已验收文档和归档日志中的事实，可核对。
- **Flips 列**：不能填写已核验的标题、章节号、表号或实验数字。用户指定对照轴为分区、地址映射、Bank 并行、主机/内存协同、实验指标；这些轴用来检查 **本项目还能否写成原创新点**，不用来代替 Flips 原文。
- 把 Flips 的具体加速比、带宽或分区公式写进论文，属于 **未解决问题**，需入库原文后再补。

已入库、可并列阅读的近邻工作仍是 V3 的 MicroRec / FleetRec / SCRec。四 Bank 并行访存、表放置、近存/计算分离在那些工作里已经出现。即使 Flips 书目未闭合，下面的收紧仍然成立。

## 1. 本项目在五轴上的可核验事实

对象：冻结顺序基线 A16.2，以及四 master 路径 A17.6。平台均为一块 Inspur F37X（VU37P HBM，`inspur_f37x_xdma_201920_3`），请求 100 MHz。

### 1.1 分区策略

不是按 `hash(id)`、频次或容量把 **多张业务表** 切到伪通道上。

| | A16.2 | A17.6 |
|---|---|---|
| 逻辑表 | 一份 1024 字节 canonical 镜像 | **同一份**镜像复制到四个 BO |
| 每次推理读的行 | 行 37、38、39、40 | 相同四行 |
| 行到存储的关系 | 四行都在 `HBM[0]` | 端口 *i* 从 `HBM[i]` 读行 `37+i` |
| 敏感性用例 | 改这一份镜像里对应行 | 先四 BO 恢复基线，只改 **BO i** 上端口 *i* 的目标行 |

依据：`docs/STAGE2N_A17_6_FOUR_BO_HOST_V1.md` §3；`docs/STAGE2N_A17_MULTIBANK_ARCHITECTURE_REVIEW_V1.md` §4；V3 §3.2（并发夹具，不是放置算法）。

这是 **槽位→伪通道的静态恒等映射 + 整表复制**，不是 sharding、热冷分层、或共同访问感知放置。四个固定槽、四行、四通道时冲突问题过简，不能支撑「分区算法」贡献。A18 才规划真实 table-id / 共同访问 / 表数超过 Bank 数。

### 1.2 地址映射

设备侧行地址（A14 v2，A16/A17 沿用）：

```text
byte_addr = BASE + (row_index << 4)
```

16 字节一行，8×INT16。A17 在 START 时捕获 BASE0–BASE3；端口 *i* 用 `BASE_i`。Host 把 XRT BO 的 64 位 `paddr` 写入对应 BASE；`paddr==0` 在 16 字节对齐时合法。

链接侧（Vitis `sp`，不是 DRAM 行/Bank/列重排）：

```text
A16:  m_axi_gmem  → HBM[0]
A17:  m_axi_gmemi → HBM[i],  i = 0..3
```

VU37P 上 `HBM[i]` 是平台 **伪通道标签**（证据里每通道 256 MB 窗口），不是本设计可控的 HBM2 Bank Group / 列交织。本项目 **没有** 改 AXI 地址位到 DRAM bank 的哈希、没有单表跨伪通道交织、没有 intra-PC 冲突模型。

依据：`docs/STAGE2N_A14_5_HBM_TABLE_BASE_ABI.md`；`docs/STAGE2N_A14_HBM_LOOKUP_RTL_DESIGN.md`；`analysis/stage2n_a17_4/hbm_mapping_proposal_v1.cfg`；A17.6 Host 的 tag→mem index 解析。

### 1.3 Bank 并行

| 项 | A16.2 | A17.6 |
|---|---|---|
| AXI master | 1 | 4 |
| 每 master | 单拍读 `ARLEN=0`，最多 1 笔 outstanding | 同左，四端口合计最多 4 笔 |
| 注入 | 顺序四槽 | 收齐四路成功后再按 slot0→3 经 **A13 单配置口** 注入 |
| 计算 | 冻结 A13 Bottom–Interaction–Top | 不变 |
| 物理参与 | 一块 `HBM[0]` | 功能闭合：四条独立 BO 路径参与完整推理 |

并发上限是「四笔单拍读」，不是突发、不是每口多 outstanding、不是 32 伪通道、也不是计算与查找重叠。lookup 计时终点是第四槽注入完成，含汇合与注入，不是纯 HBM 服务时间。

依据：`docs/STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1.md`；架构审阅 §2、§5；A17.6 function 记录。

### 1.4 主机 / 内存侧协同

推理过程中 **没有** 从主机 DRAM 再取 embedding；行数据预先在 HBM BO 里。

A16 Host：一块 `HBM[0]` BO，每用例重填整份 1024 字节镜像。

A17 Host：四块 BO；CONNECTIVITY/MEM_TOPOLOGY **按 tag** 解析 mem index，不假设下标等于 Bank 号；每块独立 fill / `xclSyncBO` / paddr / BASE 写回；每用例先四路恢复基线，敏感性只改所属 BO。

这是 XRT 缓冲所有权与 BASE 编程，不是近存处理、不是 SmartSSD 上的核分配、不是 GPU–FPGA 网络拆分（FleetRec 那一类）。进程重启测量里，BO 分配/填充/同步在 FPGA lookup 计数器 **之外**。

依据：`docs/STAGE2N_A17_6_FOUR_BO_HOST_V1.md`；`docs/STAGE2N_A16_A17_PROCESS_RESTART_COMPARABILITY_V1.md` §2。

### 1.5 实验指标

计数器（两边同一套代数，lookup 起点 A 的端口集合不同）：

```text
lookup = D - A + 1
compute = F - C + 1    （本夹具上为 1174）
e2e     = F - S + 1
residual = e2e - lookup - compute   （本夹具上为 3）
```

功能金标准：`-393, -392, -93, -689, -519`。A13 子阶段 `322/100/744/1174`。

已归档进程重启（1 次预热 + 11 次测量，非稳态）：

| | A16-N11 `20260910_163902` lookup min/med/max | A17-N11 `20260910_141722` lookup min/med/max |
|---|---|---|
| CASE0 | 112/114/141 | 33/33/33 |
| CASE1 | 112/112/140 | 33/33/65 |
| CASE2 | 112/112/140 | 33/33/52 |
| CASE3 | 112/132/141 | 33/33/38 |
| CASE4 | 112/112/138 | 33/33/50 |

Compute 两边都是 1174。`PERFORMANCE=NOT_CLAIMED`。`A16_A17_SPEEDUP=NOT_COMPUTED`。Class C 未完成：BO 初始化不同、A16 无 `REPEAT_BASELINE`、非稳态。没有 GB/s、QPS、功耗、bank 冲突率。历史单次 A16 `112/1174/1289/3` 只是分布的下限/众数附近，不是 A16 的唯一 lookup。

依据：两份 `repeatability_v1/ACCEPTANCE.txt`；comparability V1。

V3 正文里 A17 物理 Results 仍写 pending，是 **2026-09-08 写作稿**，本对照不改 V3、不把它升格为论文 Results。

## 2. 与 Flips 五轴对照（Flips 原文未入库）

| 轴 | 本项目（已核验） | Flips（原文未入库，只标对照问题） | 本项目能否写成「相对 Flips 的原创新点」 |
|---|---|---|---|
| 分区 | 4 槽恒等映射到 `HBM[0..3]`；整表复制；无共同访问目标函数 | 待核验：是否按表/行/频次切分、表数是否大于通道数、有无放置目标 | **不能。** 本实现没有分区器 |
| 地址映射 | `BASE+(row<<4)` + Vitis `sp` 伪通道窗口 | 待核验：是否改地址位交织、是否管理 PC 内 Bank 冲突 | **不能。** 无自定义地址位图 |
| Bank 并行 | 4×单拍、每口 1 outstanding；汇合后串行注入 A13 | 待核验：outstanding/突发/通道数/与计算重叠 | **不能当算法贡献。** 工程上已做四路径功能；MicroRec 等已有并行 HBM 访问 |
| 主机协同 | XRT 四 BO + BASE；每进程重填；计数器不含 BO 拷贝 | 待核验：离线放置 vs 运行时搬移、是否近存/多器件 | **不能当存储体系贡献。** 是 Host 所有权协议 |
| 实验指标 | FPGA 周期分布、功能金标准；无加速比 | 待核验：带宽/QPS/冲突率/能效及基线 | **不能写加速或带宽优势。** Class C 未完成 |

Flips 原文一旦入库，应只补 **Flips 列的机制与数字**，不要为了对齐 Flips 去改本项目 RTL 或重写已验收计数边界。

## 3. 必须收紧的原创新点

下列表述在现有证据和已读文献下 **不得再写成已证实的学术原创**（含对 Flips、MicroRec、FleetRec、SCRec 的排他缺口）。工程完成度与论文缺口不是一回事。

1. **「多 Bank / 四通道并行查表」**  
   收紧为：在冻结 A13 上，用四个未改的 A14 v2 引擎和四个 Vitis 伪通道，做 **有界四行并发夹具**。并行 HBM 查找本身不是空白（V3 对 MicroRec 已承认重叠）。

2. **「跨 Bank 地址映射 / HBM 映射方法」**  
   收紧为：`sp` 把 `m_axi_gmemi` 绑到 `HBM[i]`，运行时 BASE 等于 BO `paddr`。不是 DRAM 地址图、不是交织器、不是容量约束放置。

3. **「表分区 / 多表放置」**  
   收紧为：未做。四 BO 拷同一 1024 字节表。放置、共同访问、表数>通道数属于未开始的 A18，不能提前写成贡献。

4. **「主机–HBM 协同设计」**  
   收紧为：XRT 解析 tag、四 BO 恢复/单槽修改、BASE 读回后再 START。不是近存指令集，不是跨器件调度。

5. **「lookup 从约 112 降到约 33 即加速 / 瓶颈迁移」**  
   收紧为：进程重启下的 **lookup 区间观测分布**。e2e 差在 compute/residual 合同时等于 lookup 差，这是区间代数。A16 已是计算主导（1174/1289）。禁止 112/33 或 1289/1210 当加速比。禁止把 ≈1.07× / ≈1.10× 分析界限当 Results（评价计划 §7）。

6. **「独立响应保留 / 乱序汇合 / 验证分层」**  
   可写进 **实现与验证方法**，不能在未对照先验工作的情况下写成独家机制。V3 §2.4 已写：未证明这些机制在先验中不存在。

7. **「未考虑共同访问」作为他人空白**  
   架构审阅 §6 已禁止在未读原文时这样写。Flips 未入库之前更不能写。

8. **稳态吞吐、带宽饱和、PE 饱和**  
   未测。禁止从单次或 n=11 进程重启 latency 推导 QPS。

## 4. 适合本项目 FPGA–HBM 场景的研究问题

不要用「如何设计可扩展多 Bank 架构」这种已可被 MicroRec/Flips 类工作覆盖的问法。应绑在 **这块卡、这套冻结计算、这套计数器、这个 Host/BO 协议** 上。

**RQ1（访问组织，已有功能证据，性能未宣称）**  
在冻结的 A13 流水和包含边沿的 FPGA 计数器下，把四个单拍 embedding 读从「单 master + `HBM[0]` 顺序」改成「四 master + `HBM[0..3]` 并发、再串行注入」，lookup 区间如何分布，它在 FPGA e2e 中还占多少？

**RQ2（可比测量，当前阻塞点）**  
要使 RQ1 的 A16/A17 lookup 成为同一任务下的可比观测，Host 必须固定哪些条件（BO 填充方式、是否进程内 REPEAT_BASELINE、lookup 起点 A 的定义）？在 BO 初始化不同时，能否把区间差解释成访存组织差？

**RQ3（映射/分区，尚未做，才可能与 Flips 正碰）**  
当表数超过所用伪通道、或同一推理内出现共同访问时，静态「槽 i → `HBM[i]` + 整表复制」是否在可测的 lookup 完工时间上暴露冲突？若要降完工时间，需要何种 **可在 Vitis `sp` + BASE 编程下实现** 的分区或地址位约束——而不是再宣称四端口本身？

论文现阶段只应用 RQ1–RQ2 的 **测量与边界** 语言。RQ3 在 A18 之前不是贡献，也还没有对 Flips 原文的机制对照。

## 5. 建议写入后续 Related Work 的句子（仍非 V3 改稿）

可用：

> 本实现把四个固定行静态对应到四个 HBM 伪通道，并用 FPGA 内部区间计数观察顺序与并发夹具；它不提出新的表分区或地址交织算法。

禁用：

> 先验工作未考虑多 Bank 并行 / 共同访问 / 主机协同，因此四 master 映射是原创。

## 6. 未解决问题

1. Flips 的准确书目（作者、venue、版本）和 PDF 仍不在仓库；五轴上 Flips 自己的公式、通道数、指标表未核验。
2. FleetRec 全文仍缺（V3 已声明）。
3. 近存（RecNMP / TensorDIMM / TRiM 等）未在本次展开；与「主机协同」轴相关，但不是 Flips 原文替代。
4. Class C 可比性能未完成；A17 restore 未授权。
5. V3 Related Work 尚未列入 Flips；按本次约束不改 V3、不新增论文版本。
6. 32 个伪通道中只用了 4 个；intra-PC DRAM bank 行为未仪器化。

## 7. 本次未改动的工程面

RTL、Host、config、xclbin、`docs/evidence/**`、CURRENT_STATE / DECISIONS 状态句：未改。无 commit。
