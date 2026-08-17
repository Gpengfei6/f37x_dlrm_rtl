# F37X DLRM FPGA 项目恢复检查清单

日期：2026-08-17

状态定义：`PASS` = 有可追溯实现和相应证据；`PARTIAL` = 有实现但范围或证据不完整；`NOT STARTED` = 未发现实现；`BLOCKED` = 需要用户提供外部证据/执行。

## A. 当前现场

- [x] `PASS` 工作目录确认：`D:\FpgaWork\f37x_dlrm_rtl`
- [x] `PASS` 当前分支确认：`work/stage2n-fpga-interaction`
- [x] `PASS` 当前 HEAD：`802573d8b9b0da01539007b23d312f7cd3e16f43`
- [x] `PASS` Git identity：`管鹏飞 <gpengfei623@163.com>`
- [x] `PASS` 已跟踪文件无修改、无删除
- [x] `PASS` 审计开始时的 111 个非忽略未跟踪文件已识别并保持原样；本轮新增两份报告后总数为 113
- [x] `PASS` 未跟踪文件中未发现零字节文件
- [ ] `BLOCKED` 远端同步状态：仓库无 remote、分支无 upstream，无法确认
- [ ] `BLOCKED` 服务器实时状态：本地规则禁止访问服务器

## B. 可恢复 Git/证据基线

- [x] `PASS` 当前本地提交基线：`802573d`（Stage 2N-A3）
- [x] `PASS` A4 board bundle 完整：`f8dbbd8...`
- [x] `PASS` A5 XSim bundle 完整：`915a49b...`
- [x] `PASS` A6 timing bundle 完整：`a73e045...`
- [x] `PASS` A5 关键未跟踪源文件 SHA-256 与返回状态一致
- [x] `PASS` A2 xclbin 本地 hash 验证记录存在
- [ ] `PARTIAL` A7–A10：源码/脚本/文档存在，但未提交且本地缺少对应原始证据
- [ ] `PARTIAL` A11：asset/host/runner/docs 存在；无 commit/bundle/raw status/log/CSV
- [ ] `PARTIAL` A12：performance host/runner/collector/docs 存在；无 commit/raw status/log/CSV
- [ ] `NOT STARTED` A13：未发现周期计数器实现

## C. 功能模块

- [x] `PASS` Bottom MLP：`8→16→8` 定点数据通路已形成
- [x] `PASS` Feature interaction：`5×8→18`，18 个输出有 A4 板卡精确匹配证据
- [x] `PASS` Top MLP：`18→32→16→1` 已进入 Stage 2M/A5 自动流水验证范围
- [x] `PASS` rounding/saturation/ReLU 与 INT16/INT8/INT24/ACC48 契约已形成
- [x] `PASS` ready/valid/backpressure：A5 记录包含 12 周期 backpressure
- [x] `PASS` 自动 Bottom→Interaction→Top controller：A5 XSim 证据存在
- [ ] `PARTIAL` AXI-Lite 自动 pipeline top：A7/A10 源码存在但未提交，板卡原始证据不在本地
- [ ] `PARTIAL` model loader：Stage 2M package loader 已提交；A11 batch asset/host 未提交
- [x] `PASS` C++11/XRT HAL register host：Stage 2J–2M 已提交，A4 有板卡返回证据

## D. Embedding 与内存数据面

- [x] `PASS` 合成 embedding table/package：Stage 2M 含 4 张表（64/80/96/128 行，dim 8）
- [ ] `PARTIAL` embedding 参与自动流水：CPU 解析 4 个向量后经 AXI-Lite 写入 RTL 暂存寄存器
- [ ] `NOT STARTED` FPGA categorical-ID lookup
- [ ] `NOT STARTED` kernel `m_axi` 接口
- [ ] `NOT STARTED` 单 HBM bank embedding table
- [ ] `NOT STARTED` 多 HBM bank/channel mapping
- [ ] `NOT STARTED` host BO allocation/bank placement/sync
- [ ] `NOT STARTED` DMA/batch input data path
- [ ] `NOT STARTED` RTL request coalescer/scheduler

## E. 验证与性能

- [x] `PASS` A4 MLP + standalone interaction F37X smoke：本地状态/日志/bundle 证据存在
- [x] `PASS` A5 internal pipeline XSim：Bottom 8、Interaction 18、Top `-60`，2 runs
- [x] `PASS` A6 100 MHz internal OOC setup：WNS `+1.482 ns`、内部 hold failure 0
- [ ] `PARTIAL` A6 完整 implementation：当前证据仅限内部 OOC 边界
- [ ] `PARTIAL` A10 automatic pipeline xclbin/board：未跟踪文档声称通过，原始证据缺失
- [ ] `PARTIAL` A11 256-sample board batch：未跟踪文档声称 256/256 exact，原始证据缺失
- [ ] `PARTIAL` A12 性能：未跟踪文档声称 mean `188.742 us`，原始 CSV/日志缺失
- [ ] `NOT STARTED` RTL hardware cycle counter
- [ ] `NOT STARTED` 纯 RTL Bottom/Interaction/Top/total 周期拆分
- [ ] `NOT STARTED` CPU 同模型性能对比
- [ ] `NOT STARTED` GPU 同模型性能对比
- [ ] `NOT STARTED` 真实 Criteo 数据验证
- [ ] `NOT STARTED` Meta 标准 DLRM 模型复现

## F. 恢复动作（等待用户确认）

- [ ] 保存未跟踪文件 path/size/SHA-256 清单
- [ ] 导入 A4/A5/A6 bundle 到独立 recovery refs
- [ ] 验证 bundle commit 父链和 tree，不切换当前脏工作树
- [ ] 对照 A5/A6 bundle 与当前未跟踪源文件
- [ ] 确定 A7/A8 的最终 runner/packager/link 版本
- [ ] 确定 A9/A10 的最终 capacity/board/evidence collector 版本
- [ ] 找回或重新生成 A11 raw status/log/CSV/hash
- [ ] 找回或重新生成 A12 raw status/log/CSV/hash
- [ ] 按 A7→A12 建立小而可审查的恢复提交
- [ ] 更新已有 CURRENT_STATE/DECISIONS/RISK_REGISTER/README
- [ ] 将工作树恢复到 clean，并记录最终恢复 commit

## G. 下一阶段建议

- [ ] A13-1：先冻结计数器事件定义和寄存器 ABI
- [ ] A13-2：加入 Bottom/Interaction/Top/total 64-bit 锁存计数器
- [ ] A13-3：加入 backpressure/stall 计数和 reset/restart TB
- [ ] A13-4：host/CSV 同时记录硬件 cycles 与 host wall time
- [ ] A13-5：在原始证据中记录 xclbin SHA、UUID、BDF、平台、工具版本、时钟
- [ ] A14-1：设计单 HBM bank、只读 embedding lookup 最小接口
- [ ] A14-2：加入 `m_axi`、`sp=...:HBM[x]`、host BO 与 DMA
- [ ] A14-3：以 categorical IDs 输入和 bit-exact embedding 输出做独立验收
- [ ] A14-4：单 bank 稳定后再评估 multi-bank/coalescing/scheduling

## H. 明确的证据边界

- [ ] `BLOCKED` 服务器当前状态：未访问，无法确认
- [ ] `BLOCKED` A7–A12 原始服务器证据：本地缺失，需用户提供或执行复跑
- [ ] `BLOCKED` 完整 implementation/place-and-route：未由本轮验证
- [ ] `BLOCKED` 自动 pipeline xclbin：本轮未生成或验证
- [ ] `BLOCKED` F37X/VU37P 板卡：本轮未访问或运行

在上述 `BLOCKED` 项目获得用户返回的原始日志以前，不把文档中的 PASS 声明升级为已确认工程结论。
