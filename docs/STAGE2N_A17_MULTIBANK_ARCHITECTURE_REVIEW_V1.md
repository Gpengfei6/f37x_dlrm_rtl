# A17 多 Bank 并行查表方案审阅 V1

日期：2026-09-08。状态：方案分析完成；RTL、仿真、目标构建和板卡验证均未开始。

## 1. 核验结果与边界

本次按用户交接要求核对本地工程并分析 A17，不重新实现 A13～A16.2。

- 本地 HEAD：`ec062ba6c8a0a22c29b28abc73e0b94668e03fd7`。
- 当前分支：`work/stage2n-a16-multibank-parallel`，与交接中的 A15 分支不同，但两者当前指向同一提交。
- 已跟踪文件在分析开始前无改动；存在历史未跟踪文件，全部保留。
- 本地 origin/A15 分支引用也指向此提交；未联网核实远端实时状态。
- 重新运行 `scripts/validate_stage2n_a16_2_final_evidence_v1.py --evidence-root docs/evidence/stage2n_a16_2/final_acceptance_v1`，退出码 0，`A16_2_FINAL_EVIDENCE_VALIDATION=PASS`，清单 31 项通过。此为历史证据的本地复核，不是重新运行 FPGA。
- A16.2 xclbin SHA256：`5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4`。
- UUID：`f18571de-4a43-46bd-8ab9-a89dd4b11f8e`。
- 100 MHz；单 master → HBM[0]；四次顺序 lookup；lookup/compute/FPGA e2e/residual = `112/1174/1289/3` cycles。
- 板卡五组输出为 `-393/-392/-93/-689/-519`。早期仿真输出 `36` 属于另一测试用例。
- 112 cycles 的边界为首次 AR 握手至第四槽注入完成，包含中间控制与注入；不能称为纯 HBM 服务时间。1289 cycles 不包含 Host 数据搬运和轮询开销。
- WNS/TNS 为 0/0 ns，证明 100 MHz 时序门槛通过，不代表有正余量。55 条 methodology critical warnings 仍需保留；验收资源是平台链接整体统计，不是 kernel 单独资源。

仓库原文称下一架构阶段 A16.3，本文按用户新交接称 A17；不重命名历史阶段或修改旧验收状态。

## 2. 最小架构方案

保持一个 CU、100 MHz、原模型与定点运算。新增 A17 顶层和集成控制器，实例化四份未经修改的 `dlrm_hbm_embedding_lookup_stage2n_a14_v2`，继续实例化原 A13 计算控制器。A15 v2 的顺序状态机留作冻结参照，不在原文件内改成并行。

```text
START → 捕获本次四个 base → 独立请求四个读引擎
                                │
                  AXI0/1/2/3 → HBM[0]/[1]/[2]/[3]
                                │
                  四槽响应暂存与错误记录
                                │
                  按 slot0→slot3 向 A13 单端口注入
                                │
                  本次四槽全部提交 → 原 A13 START
                                │
                  Bottom → Interaction → Top → result
```

每个 master 保持 64 位地址、128 位数据、单拍读（ARLEN=0、ARSIZE=4）、每端口最多一笔 outstanding；四个端口合计最多四笔。ID 可继续各自为 0，返回归属由端口确定。不是在同一总线上同时发送四个无法区分的 ID=0 请求。

请求握手独立维护 issued mask，不能等待四个 ready 同时有效；已接受的请求不可重复发送。各通道返回可乱序或同周期到达，每槽暂存一份 128 位数据和状态，不得因单一 A13 配置端口而丢失响应。四槽原始数据容量为 512 bit，实际资源开销还包括四份引擎、控制和互连，需综合后测量。

V1 建议先收齐四路成功响应，再固定顺序注入。其代价是固定汇合等待，但协议简单、易于复核，并保留“第四槽注入完成”的计时终点。注入 data/index/valid 在 backpressure 下保持稳定。只能在本次 committed mask=0xF、A13 loaded mask=0xF、无错误且 START ready 时启动计算；不能依赖上次遗留的 loaded mask。

任一路错误应禁止计算，记录错误槽位，继续排空已经发出的其他合法事务；全部在途请求收尾后才能接受下一次启动，避免旧响应污染新任务。未发出的请求可停止。若某通道永不返回，应报告未完成并由 Host 超时退出，不能直接重用事务状态假装恢复。非法多拍响应属于协议故障；现有单拍引擎不能被宣称具备通用 burst 恢复能力。

## 3. RTL 与配套文件范围（提议，尚未创建）

| 新文件 | 目的 |
|---|---|
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` | 四引擎编排、暂存、注入、完成和错误控制 |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` | 四个 m_axi 端口、四 base、原控制语义和计时 |
| `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` | 控制器独立自检 |
| `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` | 公开端口端到端自检 |
| `scripts/run_stage2n_a17_1_multibank_xsim_v1.ps1/.tcl` | 新模块仿真入口 |
| `scripts/package_stage2n_a17_rtl_kernel_v1.tcl` | 四 master 与四 pointer 的 XO 元数据 |
| `config/stage2n_a17_target_v1.cfg` | 一 CU、四个独立 HBM 映射 |
| `host/stage2n_a17_multibank_v1.cpp` | 四 BO、base、golden、计时与释放 |
| 新版 A17 元数据/日志校验器与目标 runner | 四路连接门槛与独立证据目录 |

冻结 A13/A14/A15/A16.2 RTL、Host、runner、模型和证据都不修改。A17 旧接口相关行为应回归验证；新增四端口顶层并不与 A16 二进制兼容，必须有独立 kernel/CU/artifact 身份，不能加载 A16 xclbin 配合 A17 Host。

## 4. AXI-Lite、HBM 与 Host

保留 A13 地址、`0x300` 控制、`0x304/0x308`（作为 BASE0）、`0x30C/0x310` 计时。建议新增 BASE1/2/3 于 `0x318/0x320/0x328`，各占 8 字节；这是待完整地址冲突审计的提案，不是已发布 ABI。START 时原子捕获全部 base，运行期间不能改变当前请求地址。

候选 connectivity：

```ini
[connectivity]
nk=dlrm_f37x_rtl_kernel_stage2n_a17_v1:1:dlrm_a17_1
sp=dlrm_a17_1.m_axi_gmem0:HBM[0]
sp=dlrm_a17_1.m_axi_gmem1:HBM[1]
sp=dlrm_a17_1.m_axi_gmem2:HBM[2]
sp=dlrm_a17_1.m_axi_gmem3:HBM[3]
```

四个 kernel pointer 各与一个 master 关联。每个接口都须正确关联 clock/reset 和地址空间；保留 Vitis 2020.2 兼容的 64 位跨层元数据检查。HBM[0..3] 是拟采用的平台连接标签，实际可用性、路由和共享资源关系仍需目标元数据与链接证据确认；不能从四个端口推断四倍物理吞吐。

Host 沿用已验收的 C++11/XRT C API 模式。按 CONNECTIVITY + MEM_TOPOLOGY 解析各 pointer 对应的 memory index，校验 HBM 标签、used 属性及四个目标互异，不能直接假定标签数字等于 topology 数组下标。

分配四个 BO（首版可各 4096 bytes），上传并同步对应数据，读取真实 paddr，再写四组 base 并读回。物理地址 0 合法，不作分配失败标记；分配失败以 API 返回和属性状态判定。任一步失败都释放已创建 BO。

为了保持地址公式与已有 golden，首版可在每个 BO 放相同 1024-byte canonical table，在端口 i 读取原 row 37+i。每个敏感性用例只修改目标端口的目标行，其余输入不变。此为等价验证夹具，消耗四份表空间，不能包装成无复制代价的存储优化。后续无复制分区应另设实验并保持逻辑输入一致。

四个固定槽、同一表的四行不是四张真实独立业务表。A17 首版只证明跨 Bank 并发；A18 必须另有 table-id、row-id、size、访问与共同访问数据，才能研究真实 placement。

## 5. 计时与验证方案

成功路径继续采用包含首尾边沿的区间：S=接受 START，A=四端口中首次 AR 握手，D=本次第四槽注入完成，C=接受计算 START，F=首次结果可见。

`lookup=D-A+1`，`compute=F-C+1`，`e2e=F-S+1`，`residual=(A-S)+(C-D)-1`。

首个 AR 前的等待仍不在 lookup 内，必须一起报告 e2e 和 residual。每任务仅允许一次 lookup counter 起点，不能在完成后因另一端口事件重新启动。错误计数不能混入成功延迟样本。可另加各通道 AR→R 与 ready 等待诊断计数，但不改变原比较指标。

验证逐层推进：

1. 独立仿真：四路同时返回、24 种返回顺序、独立 AR/R 延迟与 A13 backpressure；每路一请求一响应、每槽一次注入、lane 顺序与黄金模型逐 bit 一致；大于 4 GiB 的 base、合法零地址、未对齐和溢出；各路错误、混合成功/错误、busy START、无 reset 重启和旧 loaded mask；计数器包含边沿与饱和行为。
2. 顶层仿真：从 AXI-Lite 写入到公开 result，覆盖原五组 golden；A13 周期仍为 322/100/744/1174；至少观察到两路 AR 在第一笔 R 之前完成握手，以直接证明并发。检查四路在途收尾后才能恢复。
3. 本地包与校验器：四端口/四 pointer/一 CU，64 位地址、128 位数据、无旧 A14 参数混入；错误映射、重复 Bank、遗漏端口、错误 arg index、旧 kernel、错频率必须拒绝。不得削弱冻结 A16 validator。
4. 用户控制的目标构建：Vivado/Vitis 2020.2、准确 part/platform、100 MHz、时序及新增 kernel 资源；单独记录警告、XO/xclbin SHA 与 UUID。
5. 用户控制的板卡验证：四 BO 的实际映射、四槽敏感性与最终输出、计时、清理；重复运行报告样本数、分布及异常。Host 总耗时与 FPGA 内部计时分开。A17 结果出现前不得宣称物理加速。

A17 初期不重跑 A13～A16 全套验收；使用冻结证据与必要回归。后续正式性能对照应对 A16 与 A17 使用相同输入、时钟和计数边界；复测 A16 是对照实验，不是重建 baseline。

## 6. 预期收益与研究贡献

依据冻结样本计算，compute 占 e2e 的 1174/1289≈91.08%，lookup 占约 8.69%。100 MHz 下，lookup=1.12 μs，compute=11.74 μs，FPGA e2e=12.89 μs。

若仅作理想化假设 lookup=112/4=28 cycles，compute=1174、residual=3 不变，则 e2e=1205 cycles、加速=1289/1205≈1.070 倍、延迟降低约 6.52%。28 不是预测或验收门槛，串行注入、控制、互连和最慢通道都会影响实际值。假设 lookup 成本完全消失且其他两项不变，极限也仅约 1289/1177=1.095 倍。

A17 的四 master/四 Bank 实现是工程基线，单凭该结构不足以确立论文新颖性。本次没有联网审阅 MicroRec、FleetRec 原文；交接中关于它们“未考虑共同访问”等排他性论断仍待文献核查，不能写成已证实的研究空白。

A18 可检验的贡献候选是：在容量约束下，用真实共同访问关系和测得的 Bank 服务代价估计请求完工时间，优化映射，并对比轮转、容量均衡、频率均衡及去掉共同访问/实测代价的消融。若只有四个固定请求对应四个空闲 Bank，冲突问题过于简单；需要表数超过 Bank 数或真实变化的访问组合、容量和负载才能检验价值。训练/调参 trace 与评估 trace 应分离。

A19 应以测量验证瓶颈迁移和资源取舍。建议最终采用 baseline、仅访存优化、仅计算优化、二者结合的四组对照，并报告 kernel 资源增量、时序、lookup/e2e、稳态吞吐和可用的功耗测量。稳态吞吐必须有连续任务实验，不能直接从单次 latency 推导。

下一具体工作单元建议为 A17.1：上述四引擎控制器及其独立自检，随后再做公开 kernel 集成；当前交接要求的架构审阅已完成。
