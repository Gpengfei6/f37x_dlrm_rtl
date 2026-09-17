# A17 本地文献登记（FleetRec 引用树与重复性排查）

日期：2026-09-14。状态：**本地研究整理**。不是论文新版本，不改验收结论，不连接服务器。

配套：

- 五轴对照（Flips 原文仍缺）：`docs/STAGE2N_A17_LITERATURE_FLIPS_COMPARISON.md`
- 下一阶段负载矩阵（不实现 RTL）：`docs/STAGE2N_A18_WORKLOAD_EXPERIMENT_DESIGN.md`
- V3 已选读五篇：`docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md` §II

## 0. 阅读与目录边界

- 仓库内仍无这些 PDF。本次不联网、不打开 GitHub、不打开 CCF 官网。
- **CCF 等级**按对《中国计算机学会推荐国际学术会议和期刊目录》（常用 2022 版记忆）的对照，标为 `CCF记忆`，不是官网截图。
- **是否有源码**分三档：`工件页曾记载`（V3 或通行作者页提到过仓库）、`常见公开系统`（工业开源，本次未克隆）、`未见/未核验`。
- **核验状态**（2026-09-15 起，每条文献只标一档）：
  - `SOURCE_VERIFIED`：作者公开源码 **URL 已写入本登记**；**未**在本项目克隆或复现；
  - `PAPER_ONLY`：论文身份可用于对照，仓库无 PDF、也无本登记确认的源码链接；
  - `BIBLIOGRAPHY_ONLY`：书目可对应到题目/会议，但 PDF 与源码均未在仓库核验；
  - `NOT_VERIFIED`：名称尚未闭合到可核验的具体论文或链接。
- FleetRec **全文仍未在仓库核验**（V3 只用摘要与作者工件概述）。下表「引用树」= 该主线及相关近邻，不是从 FleetRec PDF 逐条抄出的参考文献列表。
- 本项目冻结事实只作对照，不在此改写：A16.2 单 `HBM[0]` 顺序；A17.6 四 BO、`HBM[0..3]`、五用例功能 PASS；可比性能未形成；性能/吞吐/带宽/加速比均未宣称。

三类用法（不要混）：

| 类别 | 成员 | 在本论文中的用法 |
|---|---|---|
| **核心主线参考** | MicroRec、FleetRec | 对标 FPGA 推荐推理与异构拆分；承认并行 HBM 查找不是空白 |
| **方法与重复性排查** | Flips、Hetero-Rec、HPS、RECom、CARINA、nMARS（及近存近邻 RecNMP / TensorDIMM / TRiM） | 分区、映射、缓存、压缩、调度；防止把已有机制写成独家 |
| **硬件与实验方法参考** | F-TADOC、HBM Connect，以及其它 HBM-FPGA 测量工作 | 伪通道绑定、带宽/延迟怎么报；工作负载不是 DLRM 不等于方法可抄 |

## 1. 核心主线：MicroRec / FleetRec

| ID | 题目 | 年 | 期刊/会议 | CCF记忆 | 源码 | 核验状态 | 核心方法 | 与本项目重合 | 接近度 |
|---|---|---|---|---|---|---|---|---|---|
| R3 | *MicroRec: Efficient Recommendation Inference by Hardware and Data Structure Solutions*（Wenqi Jiang et al.） | 2021 | MLSys | **未列入 CCF 目录** | 作者公开源码（**未克隆、未复现**）：https://github.com/fpgasystems/FPGA-Recommendation-Accelerator | SOURCE_VERIFIED | 表笛卡尔积/组合减少查找次数；embedding 在 HBM/DDR/片上之间放置；并行查找 + 流水 DNN；FPGA 实测推理 | **高**：并行 HBM 查找、表放置、完整推理评测。本项目四伪通道 + 整表复制是其放置问题的退化夹具，不是新放置算法 | **最接近的 FPGA embedding 主线** |
| R4 | *FleetRec: Large-Scale Recommendation Inference on Hybrid GPU-FPGA Clusters*（Wenqi Jiang et al.） | 2021 | KDD | **A**（数据挖掘） | 作者公开源码（**未克隆、未复现**）：https://github.com/fpgasystems/GPU-FPGA-Recommendation-System | SOURCE_VERIFIED | 网络化 GPU–FPGA：存算拆分、集群推理；FPGA/GPU 分实现。全文 PDF 仍未入库 | **中**：系统级主机/加速器协同。本项目是 **单卡、无 GPU、无网络**。不能把「Host 填四 BO」写成相对 FleetRec 的协同创新 | 主线，部署层级不同 |
| R1 | *Deep Learning Recommendation Model…*（Naumov et al.） | 2019 | arXiv | 非正式会议论文 | 无本登记确认的源码 URL | PAPER_ONLY | 稀疏 embedding + Bottom/Interaction/Top | **结构继承**，不是加速器创新 | 模型基础 |
| R2 | *Cross-Stack Workload Characterization of Deep Recommendation Systems*（Hsia et al.） | 2020 | IISWC | **目录未记/非 CCF 主会** | 未见本仓库核验 | BIBLIOGRAPHY_ONLY | CPU/GPU、batch、算子级瓶颈随部署变化 | **指标边界**：其 e2e 含加载；本项目 FPGA 内部区间不可直接比 91% | 瓶颈解释 |

MicroRec 已在 V3 做章节级阅读。FleetRec 仍缺全文：调度、FPGA/GPU 切分、评测表数字 **不得引用为已核验**。二者 GitHub 仅登记为作者公开源码位置，**不是**本项目复现。

## 2. 方法与重复性排查：Flips / Hetero-Rec / HPS / RECom / CARINA / nMARS

下列名称由排查清单给出。除 HPS（工业层次参数服务器）与近存三篇可较稳对应外，**Flips、Hetero-Rec、RECom、CARINA、nMARS 的书目在仓库内仍未闭合**。先按机制轴登记，避免用错论文。

| 名称 | 题目（当前能对应的） | 年 | 期刊/会议 | CCF记忆 | 源码 | 核心方法（待原文确认的部分已标明） | 重合风险 | 优先轴 |
|---|---|---|---|---|---|---|---|---|
| **Flips** | **未闭合**。仓库无 PDF。五轴对照见独立文件 | — | — | — | 未核验 | 用户指定轴：分区、地址映射、Bank 并行、主机/内存协同、实验指标 | **高（排查优先）**：若原文确有 HBM 分区/交织，则本项目静态槽→`HBM[i]` 不能当原创映射 | 分区、映射、Bank |
| **Hetero-Rec** | **未闭合**。本树中已核验的异构推理主论文是 FleetRec | — | — | — | 未核验 | 异构（CPU/GPU/FPGA）推荐推理一类 | **中**：与 FleetRec 同类。单卡四 BO 不是异构集群 | 主机协同 |
| **HPS** | NVIDIA Merlin / HugeCTR **Hierarchical Parameter Server**（层次化 embedding 参数服务；以产品与文档为主，不是一篇 CCF 论文） | ~2021– | 工业系统 | 非会议论文 | 常见公开系统 HugeCTR / Merlin（本次未克隆） | GPU 热缓存 + CPU/SSD 下层；按频次/层次放 embedding | **中（缓存轴）**：本项目 **无热点缓存**。若以后做热行缓存，HPS 是必须对标对象，不能宣称「首次层次化 embedding」 | 热点缓存 |
| **RECom** | **未闭合**。名称指向推荐编译器或可重构 embedding 加速，可能与 FPGA 实现重叠 | — | — | — | 未核验 | 待原文：编译映射 / 可重构数据通路 / 表布局 | **高（若为 FPGA embedding）**：在确认前禁止写「本项目首次把表映射到 HBM Bank」 | 分区、映射、调度 |
| **CARINA** | **未闭合**。名称常与 cache-aware / FPGA 加速器相关 | — | — | — | 未核验 | 待原文：热点或缓存感知的推荐/查找 | **高（若含片上热缓存）**：本项目无 cache，不能抢缓存贡献；若无 cache 则重合下降 | 热点缓存 |
| **nMARS** | **未闭合**。近存推荐加速一类 | — | — | — | 未核验 | 待原文：近 DRAM/HBM 做 embedding reduction | **低–中**：本项目是 FPGA 侧 AXI 读 HBM，**不是** NMP/PIM 指令 | 压缩/近存 |
| RecNMP | *RecNMP: Accelerating Personalized Recommendation with Near-Memory Processing*（Ke et al.） | 2020 | ISCA | **A** | 未见公开 RTL 为常态（未核验） | DIMM 侧近存处理 embedding | 路径不同；禁止把 AXI-HBM 读说成 NMP | 近存 |
| TensorDIMM | *TensorDIMM: A Practical Near-Memory Processing Architecture for Embeddings and Tensor Operations in Deep Learning*（Kwon et al.） | 2019 | MICRO | **A** | 未核验 | 近存 DIMM 上 embedding/张量 | 同上 | 近存 |
| TRiM | *TRiM: Enhancing Processor-Memory Interfaces with Scalable Near-Memory Accelerators for Embedding Operations*（Park et al. 一类近存 embedding 工作，MICRO 2021） | 2021 | MICRO | **A** | 未核验 | 近存加速 embedding 聚合 | 同上 | 近存 |
| SCRec | *SCRec: … Statistical Sharding and Tensor-train Decomposition…*（Yang et al.） | 2025 | arXiv preprint | 非正式发表 | 未核验 | 统计切分、TT 压缩、SmartSSD 核分配 | **高（A18 放置/压缩）**：本项目未做 sharding/TT。V3 已读 §III–IV | 分区、压缩 |
| RecShard | 训练侧 embedding 切分（MLSys 一带） | ~2021 | MLSys 等 | 未列入 | 部分公开系统未核验 | 按代价切表到多 GPU | 训练而非本推理夹具；切分思想与 A18 相关 | 分区 |
| DeepRecSys | *DeepRecSys: A System for Optimizing End-To-End CPU-GPU Deep Recommendation Inference*（Gupta et al.） | 2020 | HPCA | **A** | 未核验 | 查询调度、批、级联与尾延迟 | **调度轴**：本项目无请求队列/批调度 | 请求调度 |
| RecPipe | *RecPipe: Co-designing Models and Hardware to Jointly Optimize Recommendation Quality and Performance*（Gupta et al.） | 2020 | MICRO | **A** | 未核验 | 级联模型与硬件协同 | 模型级联，非 HBM Bank 映射 | 调度 |

**与本项目当前实现最接近、必须写进 Related Work 的排查对象：** MicroRec（FPGA 并行查找+放置）> Flips/RECom（书目闭合后）> SCRec（切分/压缩，面向 A18）> HPS/CARINA（仅当引入缓存）> FleetRec（异构系统，部署不同）> nMARS/RecNMP（近存，路径不同）。

## 3. 硬件与实验方法参考：F-TADOC 及其他 HBM-FPGA

| ID | 题目/系统 | 年 | 期刊/会议 | CCF记忆 | 源码 | 核心方法 | 与本项目 | 用法 |
|---|---|---|---|---|---|---|---|---|
| **F-TADOC** | FPGA 上直接对压缩文本做分析（TADOC 的 FPGA/HBM 实现一线；**精确书目未入库**） | ~2021+ | 待核验 | 待核验 | 未核验 | 压缩态分析、HBM 流式、常为 HLS | **低（负载）**：不是 embedding 表。**中（方法）**：HBM 通道、突发、带宽怎么测，可作实验写法参考，不可把带宽数字搬到 DLRM | 实验方法 |
| HBM Connect | *HBM Connect: High-Performance HLS Interconnect for FPGA HBM*（Choi / Cong 等，FPGA 会议一线） | 2021 一带 | FPGA | **B**（FPGA 研讨会） | 部分学术工件未核验 | HLS 多伪通道、交叉开关、地址到 PC 的映射对带宽的影响 | **中（映射方法）**：说明 Vitis `HBM[i]` 绑定和地址对齐会改变实测带宽。本项目未做 PC 内地址交织，也 **未测 GB/s** | 硬件方法 |
| 本项目 A16/A17 | 见验收档案 | 2026 | 工程 | — | 本仓库 | 单拍 AXI、四或一伪通道、FPGA 周期计数 | 自身基线 | 不可当文献创新 |

F-TADOC / HBM Connect **不能**用来主张推荐模型上的原创；只能约束「如何报告 HBM 实验」：必须写清伪通道数、突发长度、outstanding、是否含 Host DMA、是否稳态。

## 4. 机制轴：谁已经做了、本项目做了什么

| 轴 | 文献侧（已读或强嫌疑） | 本项目现状 | 重复性结论 |
|---|---|---|---|
| Embedding 分区 | MicroRec 放置；SCRec/RecShard 切分；Flips/RECom 待核验 | 槽 i → `HBM[i]`，四份同一 1024B 表 | **无分区器**。禁止原创声称 |
| Bank 映射 | HBM Connect 讨论 PC/地址；MicroRec 多存储器 | `sp`：`gmemi→HBM[i]`；`BASE+(row<<4)` | **静态恒等映射**。禁止「映射方法」原创 |
| 热点缓存 | HPS 层次缓存；CARINA 待核验 | 无 cache | 不是贡献；引入前必须对标 HPS/CARINA |
| 压缩 | SCRec TT；其它 embedding 压缩大量存在 | 无 | 不是贡献 |
| 请求调度 | DeepRecSys / RecPipe / FleetRec 集群调度 | 每任务四次固定行查找，无队列 | 不是贡献 |
| HBM/FPGA 实测 | MicroRec、FleetRec（全文数字未核）、HBM Connect、F-TADOC | A16 顺序周期分布；A17 四路径功能 + 进程重启 lookup 分布；无 GB/s | 可写 **本夹具上的区间观测**；不可写带宽/加速独家 |

RTL 仍把行号写死为 `slot0→37`、`slot1→38`、`slot2→39`、`slot3→40`（`dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` 参数）。可变索引、超过四张表 **不是** 当前硅上能力。

## 5. 候选创新点：保留 / 降级 / 删除

**删除（不得再写成独家创新或已证实空白）：**

- 四路 AXI、四个 HBM 伪通道功能 PASS；
- 简单固定槽位映射；
- 把 lookup 112→33 或 e2e 1289→1210 写成加速比或瓶颈迁移；
- 把 n=11 进程重启写成性能方法创新或充分分布；
- 「先验工作未考虑共同访问 / 多 Bank」——MicroRec 已并行访存；共同访问实验尚未做；Flips 原文未读。

**降级为研究问题（见实验设计稿 RQ）：**

- 表数 > 伪通道或共同访问下的放置（相对 MicroRec/SCRec/Flips 必须有消融才可能谈贡献）；
- 使 A16/A17 在相同 BO 协议下可比（Class C）；
- 热点缓存、压缩、调度——当前未实现，只是开放问题。

**可以保留的，仅作为工程与写作内容，不是独家算法：**

- 在 **冻结 A13 定点流水** 上扩展查找，金标准与计算周期 `322/100/744/1174` 保持不变；
- 公开计数边界 S/A/D/C/F，lookup 含注入、residual 为代数差；
- 分层证据：仿真 ≠ 链接映射 ≠ 板卡功能 ≠ 可比性能；
- 明确进程重启 ≠ 稳态，BO 初始化是实验条件。

V3 已写 academic novelty **not claimed**。本次排查不把它改成已建立。

## 6. 仍缺的文献证据

1. FleetRec 全文（调度与评测表）。
2. Flips、Hetero-Rec、RECom、CARINA、nMARS、F-TADOC 的 PDF 与准确题名/页码。
3. 上述源码仓库的克隆与许可证核对。
4. CCF 官网或最新目录截图。
5. MicroRec 与本夹具的表规模/精度/通道数对照表（避免数字横比）。

入库 PDF 后只改本登记与 Flips 对照的 **文献列**，不改 A16/A17 验收档案。

## 7. 核验状态总表（2026-09-15）

未在本项目克隆任何外部仓库。`SOURCE_VERIFIED` 只表示作者公开 URL 已写入，不表示复现。

| 名称 | 核验状态 | 说明 |
|---|---|---|
| MicroRec | SOURCE_VERIFIED | https://github.com/fpgasystems/FPGA-Recommendation-Accelerator ；V3 有章节级阅读；未克隆 |
| FleetRec | SOURCE_VERIFIED | https://github.com/fpgasystems/GPU-FPGA-Recommendation-System ；全文 PDF 仍未入库；未克隆 |
| DLRM（Naumov） | PAPER_ONLY | 无本登记确认的源码 URL |
| Hsia IISWC | BIBLIOGRAPHY_ONLY | 仓库无 PDF |
| Flips | NOT_VERIFIED | 书目未闭合 |
| Hetero-Rec | NOT_VERIFIED | 书目未闭合 |
| HPS / HugeCTR / Merlin | BIBLIOGRAPHY_ONLY | 工业系统；本次无确认链接，未克隆 |
| RECom | NOT_VERIFIED | 书目未闭合 |
| CARINA | NOT_VERIFIED | 书目未闭合 |
| nMARS | NOT_VERIFIED | 书目未闭合 |
| RecNMP | BIBLIOGRAPHY_ONLY | 题目/ISCA 可对应；未见本仓库核验的源码链接 |
| TensorDIMM | BIBLIOGRAPHY_ONLY | 题目/MICRO 可对应；源码未核验 |
| TRiM | BIBLIOGRAPHY_ONLY | 近存一类；源码未核验 |
| SCRec | PAPER_ONLY | V3 已读 §III–IV；无本登记确认的源码 URL |
| RecShard | BIBLIOGRAPHY_ONLY | 无确认链接 |
| DeepRecSys | BIBLIOGRAPHY_ONLY | 无确认链接 |
| RecPipe | BIBLIOGRAPHY_ONLY | 无确认链接 |
| F-TADOC | NOT_VERIFIED | 精确书目未入库 |
| HBM Connect | BIBLIOGRAPHY_ONLY | 题目/FPGA 会议一线；源码未核验 |

