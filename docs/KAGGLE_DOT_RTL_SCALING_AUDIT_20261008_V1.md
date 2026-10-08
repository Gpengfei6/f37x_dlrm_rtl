# Kaggle DOT RTL 扩容审计 V1

日期：2026-10-08。范围：源码审计和分阶段计划。没有修改生产 RTL，没有跑综合或 implementation，没有把训练中的 validation accuracy 当成最终精度。`REAL_KAGGLE_RTL=NOT_YET_VALIDATED`。`PERFORMANCE=NOT_CLAIMED`。

模型几何按锁定的 `facebookresearch/dlrm` commit `6d75c84d834380a365e2f03d4838bee464157516`。Dense 13，26 个稀疏域，嵌入维 16。Bottom `13→512→256→64→16`。交互 27 个向量、351 个非自身点积，顺序为 `i=1..26`、`j=0..i-1`。Top 输入是 `[Bottom_out_0..15, interaction_0..350]`，即 16+351=367。Top `367→512→256→1`。稠密 MAC 474368，交互乘法 5616，稠密偏置 1617。这些是静态工作量，不是 FPGA 已跑通的证据。

训练进度只作状态：`best_validation.pt` 在 step 42000，validation accuracy 0.7844；总步数约 306969。最终 EVAL 未执行。0.7844 不进入任何验收。

## 1. 现有 RTL 模块清单

生产计算链是 A18/A17/A16 内核包住 A13 计数外壳，A13 再例化 `dlrm_internal_pipeline_controller`。下表的“生产例化”指这条链，不是模块默认参数。

| 模块 | 路径 | 生产例化上的实际边界 | Kaggle DOT |
|---|---|---|---|
| 稠密引擎 | `rtl/compute/dense_layer_engine.sv` | 默认 `MAX_IN_DIM/MAX_OUT_DIM=1024`，`NUM_PE=16`，`MAX_WEIGHT_VALUES=65536`，`MAX_BIAS_VALUES=1024`。A18 内核把它覆写成 64/64、权重 2048、偏置 128 | 不满足 |
| 点积核 | `rtl/compute/vector_dot_product_core.sv`、`rtl/compute/mac_lane.sv` | `NUM_PE` 必须为 2 的幂。乘积宽度是 `INPUT_WIDTH+WEIGHT_WIDTH`，即 INT16×INT8=24 位，再符号扩展进 INT48 | 稠密路径的尾块掩码可用；存储和最大维度不满足 |
| 量化 | `rtl/common/runtime_relu_quant.sv` | 运行时移位，就近、中点远离零，饱和到 INT16，然后可选 ReLU。无 Sigmoid | 移位可保留；最后一层 Sigmoid 不在 RTL 内 |
| 交互 | `rtl/interaction/dlrm_feature_interaction_engine.sv` | 参数默认 5×8，但 `PAIR_COUNT=10`、结果索引 5 位、装入索引 3 位、配对表是 10 项 case | 不满足。改默认参数也不会变成 27×16 |
| 激活缓冲 | `rtl/memory/banked_activation_buffer.sv` | 深度随 `MAX_DIM`。A18 的 `MAX_IN/OUT=64`，块深为 4 | 512 宽层不满足 |
| 权重/偏置 | `rtl/memory/local_weight_provider.sv` | 越界即 `weight_rsp_error` / `bias_rsp_error`。A18 上限 2048 / 128 | 不满足 |
| 层控制器 | `rtl/control/mlp_sequence_controller_segmented.sv` | `MAX_LAYERS=4`。描述符 96 位：输入维 `[10:0]`、输出维 `[21:11]`、权重基址 32 位、偏置基址 32 位、移位 6 位、ReLU 1 位 | 单层 512 能放进 11 位字段；4 个槽装不下 Bottom 4 层加 Top 3 层 |
| 流水线 | `rtl/pipeline/dlrm_internal_pipeline_controller.sv` | 4 个 8 维嵌入，Bottom 结果必须正好 8 个，交互结果必须正好 18 个，Top 只装两块（16+2） | 不满足 |
| A13 外壳 | `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv` | 只加周期计数，计算语义转给上面的流水线 | 随流水线，不满足 |
| 主机接口 | `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv`，以及 A18 内核 `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv` | 嵌入索引 2 位，数据 `8*16` 位。A18 要求 `NUM_PE=16`，`MAX_IN_DIM=64`，`MAX_OUT_DIM=64` | 不满足 |
| 交互测试 | `tb/tb_dlrm_feature_interaction_engine_v2.sv` | 等 18 个结果，并核对 `result_index` | 只覆盖 Toy |
| 旧配置包 | `rtl/include/dlrm_config_pkg.sv` | `EMBED_DIM=8`，`NUM_LOOKUPS=4`，`DATA_WIDTH=8`，`ACC_WIDTH=32` | 不是这条 INT16 生产链，不能拿来当 Kaggle 合同 |

`dlrm_config_pkg.sv` 与当前稠密引擎的 INT16/INT8/INT48 不一致。扩容不以它为合同。

## 2. Toy 与 Kaggle DOT 的容量差距

| 项 | Toy，源码字面量 | Kaggle DOT | 差距 |
|---|---|---|---|
| Bottom | 流水线要求结果数等于 8，`bottom_vector[0:7]` | 最后一层输出 16，且中间层宽 512 | 结果计数和缓冲都写死为 8 |
| 嵌入 | `embedding_mem[0:3]`，每条 `8*INPUT_WIDTH`，索引 `[1:0]` | 26 条、每条 16 维 | 4 槽、8 维 |
| 交互 | 5 向量、维 8、10 对点积、18 个输出 | 27 向量、维 16、351 对、367 个 Top 输入 | 配对表、索引、输出缓冲 |
| Top 装入 | `interaction_vector[0:17]`，chunk0 取 `[0:15]`，chunk1 取 `[16:17]` | 367 个数，23 个 16 宽块，末块 15 个有效 | 只实现了 18→ 两块 |
| 描述符槽 | `MAX_LAYERS=4`，索引 2 位 | Bottom 4 层 + Top 3 层 = 7 | 槽位不够，且启动时两段必须同时在表内 |
| 权重存储 | 内核 2048；引擎默认 65536 | 474368 个 INT8 | 第二层 `512*256=131072` 已超过默认 65536 |
| 偏置存储 | 内核 128；引擎默认 1024 | 1617 个 INT24 | 默认 1024 也不够 |
| 层宽检查 | A18 的 `MAX_IN_DIM/MAX_OUT_DIM=64` | 367 与 512 | 描述符检查会报 `ERROR_BAD_DIMENSION` |

Toy 的 1174 是本仓库已记录的小模型计算计数（Bottom 322、交互 100、Top 744，另有控制交接）。630 与 582 不在本仓库验收日志里。本审计不把 1174→630→582 写成同一整核的优化链，也不把它们按 MAC 比例换成 Kaggle 时延。

## 3. 必须修改的源码，以及本轮不动的文件

本轮不改这些文件。下一阶段用新文件，不在已验收模块上直接改行为。

必须新写或在隔离分支上替换的行为：

| 新行为 | 现在卡住它的文件 | 原因 |
|---|---|---|
| 27×16、351 点积 | `rtl/interaction/dlrm_feature_interaction_engine.sv` | `PAIR_COUNT`、case 表、`result_index[4:0]`、`vector_load_index[2:0]`、`result_last==(index==17)`、Bottom 发到下标 7 都是字面量 |
| 交互接入与 Top 装入 | `rtl/pipeline/dlrm_internal_pipeline_controller.sv` | 4 嵌入、8 个 Bottom 结果、18 个交互结果、两块 Top 装入 |
| 7 个描述符 | `rtl/control/mlp_sequence_controller_segmented.sv` | 数组深度 4 |
| 权重和偏置深度 | `rtl/memory/local_weight_provider.sv`，以及内核覆写 | 2048/128 与 65536/1024 都低于 474368/1617 |
| 层宽 512 | A18 内核参数，不是引擎里的尾块逻辑 | 引擎默认 1024，生产例化是 64 |
| 主机装入 26×16 | A13 AXI-Lite 适配器和 A18 内核 | 嵌入索引 2 位，数据 128 位 |
| 新测试 | `tb/tb_dlrm_feature_interaction_engine_v2.sv` 只锁 18 个结果 | 不能把通过旧 TB 当成 351 通过 |

稠密尾块不需要重写算法。`dense_layer_engine.sv` 里，通道掩码是 `(chunk*NUM_PE+lane) < in_dim`。13、367、256、1 都能被这个掩码表达，前提是 `MAX_IN_DIM/MAX_OUT_DIM` 大于等于该维，并且权重地址落在存储内。

`vector_dot_product_core.sv` 的归约级数是 `$clog2(NUM_PE)`。它只做 INT16×INT8。交互的 INT16×INT16 留在交互引擎里，不能接进这个核来“顺便”完成。

## 4. 索引、地址和缓冲位宽

交互引擎，证据在 `dlrm_feature_interaction_engine.sv`：

- `vector_load_index` 为 `[2:0]`。27 个向量需要至少 5 位。现在大于等于 5 的下标会被当成非法向量，或者根本无法从端口表达。
- `dim_index_reg` 为 `[3:0]`。维 16 的末下标 15 刚好能比较，但配对和结果索引没有跟着参数走，所以这不能算支持维 16。
- `pair_index_reg` 为 `[3:0]`，`PAIR_COUNT=10`。351 需要至少 9 位。
- `result_index` 为 `[4:0]`，`result_last` 在下标 17。367 个 Top 输入的下标 0..366 需要 9 位。
- `pair_row` / `pair_column` 只列出 `(1,0)` 到 `(4,3)`。没有生成 `i=1..26, j=0..i-1` 的电路。
- 向量存储 `vector_mem[VECTOR_COUNT][VECTOR_DIM]` 看起来随参数变，但端口和 case 表不变时，把参数改成 27 和 16 会与 3 位装入索引、4 位配对索引和 10 项表冲突。
- 乘积是 `INPUT_WIDTH*2` 的有符号 32 位。`INT16` 极值乘积不超过 32 位有符号范围。16 次累加的正极值是 `16*(2^30)=2^34`，有符号容器至少 36 位。当前 `ACC_WIDTH=48` 大于这个下界。累加宽度不是交互扩容的缺口；索引和配对电路才是。

流水线，证据在 `dlrm_internal_pipeline_controller.sv` 第 136–144 行和第 431–521 行：

- `embedding_cfg_index` 为 `[1:0]`，`embedding_mem` 只有 4 项，每项 128 位。26×16 的 INT16 向量是 256 位，索引需要至少 5 位。
- Bottom 完成条件是 `bottom_result_count_reg != 8`，并且 `count>=8` 直接报 `ERROR_BOTTOM_PROTOCOL`。Kaggle 的 Bottom 要交出 16 个激活。
- 交互完成条件是计数等于 18，`result_last` 在 17。Kaggle 要接收 367 个有序结果。
- Top 只有 `STATE_LOAD_TOP_CHUNK0` 和 `STATE_LOAD_TOP_CHUNK1`。367 需要按 16 分块，直到覆盖 367。

描述符，证据在 `mlp_sequence_controller_segmented.sv` 第 93–98 行和第 349–360 行：

- 输入维和输出维各取 11 位。512 和 367 都放得下。
- 移位取 6 位，并拒绝大于 `ACC_WIDTH` 的移位。尺度可以后填，不必改字段宽度。
- 权重结束地址是 `base + in_dim*out_dim`，与 `MAX_WEIGHT_VALUES` 比较。`512*256=131072`，大于默认 65536，也大于内核 2048。
- 偏置结束地址是 `base + out_dim`。全部层按序摆放时结束于 1617，大于默认 1024，也大于内核 128。
- 描述符索引宽度是 `$clog2(MAX_LAYERS)=2`。第 5、6、7 层没有槽。

主机结果元数据在 A18 内核里把 `core_result_index` 写入 `result_meta_word[9:4]`，只有 6 位。`MAX_OUT_DIM=64` 时刚好。输出维 512 的下标要 9 位，这个打包会截断。Stage A 的最终结果只有 1 个数，但中间调试口如果仍用这 6 位，不能表示 Bottom 或交互下标。

逻辑通道数不是 DSP 数。`mac_lane.sv` 每通道一个 INT16×INT8 乘积寄存器。已验收整核的布局后 DSP 与 `NUM_PE` 不是同一个数。本审计不把 16 通道写成 16 个 DSP。

## 5. 真实模型的模块连接

Stage A 仍用一个稠密引擎、一对激活缓冲、一个交互引擎。不在本阶段加 HBM 查表。

1. 主机把 13 维稠密输入写入激活缓冲。13 不是 16 的倍数，靠已有 lane mask，不能补成另一个模型。
2. 主机把 26 个 16 维嵌入向量写入交互向量存储的槽 1..26。槽 0 留给 Bottom 输出。
3. Bottom 四层顺序执行。每层 ReLU 由描述符给出，不在 RTL 里新发明。
4. Bottom 的 16 个输出装入交互槽 0，且保持下标 0..15。
5. 交互按 `i=1..26`、`j=0..i-1` 产生 351 个点积。输出流必须是 Bottom 的 16 维在前，点积在后。
6. 这 367 个数按 16 分块写入 Top 的输入缓冲。最后一块只有 15 个有效元素。
7. Top 三层顺序执行。最后一层线性输出交回主机。官方 Sigmoid 不在当前 RTL 中。

Bottom 与 26 个嵌入是并列输入。交互启动条件改为：槽 0 已由 Bottom 写完，且槽 1..26 都已由主机写完。缺任何一个都保持现有的显式错误，不补零静默继续。

## 6. Stage A 数据流与测量边界

Stage A：CPU 做嵌入查表。FPGA 从“13 维稠密输入和 26 个嵌入向量都已到达”开始，做 Bottom、交互和 Top，到预测值有效结束。这个区间记为计算内核时间。主机提交、传输和 CPU 查表另计。

Stage B 以后才把 26 张表放进已核验的 HBM 地址空间。Stage B 不挡住 Stage A。全表是否放得下，本审计没有新的容量测量，不能用名义 HBM 容量代替。

两段时间不能相加后再叫一次推理，除非事件区间没有重叠。当前没有 Kaggle 的板上计数。

## 7. 分阶段计划

总规则：新模块用新文件名。已验收的 A13 流水线、A18 内核和现有 TB 保持可单独复现 Toy。每阶段有自己的仿真记录后才进入下一阶段。C1 与 C2 可以并行，因为它们不接同一条生产流水线；接口在并行期间冻结为下面两句。

冻结接口：

- 交互输出：ready/valid，9 位下标，367 个结果，顺序为 16 个 Bottom 激活后接 351 个点积，点积顺序 `i` 外层、`j=0..i-1`。
- 稠密作业：`in_dim/out_dim` 可到 512，尾块掩码定义不变，权重 INT8，激活 INT16，乘积 24 位，累加 INT48，输出 INT16，移位和 ReLU 仍来自描述符。

### RTL-C0 审计

- 前提：本文件。
- 修改：无生产 RTL。
- 验收：本文件中的判断都能指到源码行。
- 回滚：不涉及 RTL。

### RTL-C1 交互 27×16 / 351

- 前提：C0。新文件，不改 `dlrm_feature_interaction_engine.sv` 的 Toy 行为。
- 修改：新交互模块和新 TB。配对用循环或生成电路产生 351 对，禁止再写 10 项 case。装入索引至少 5 位，点积索引至少 9 位，结果下标至少 9 位，维循环到 16。
- 测试：351 的顺序；缺一个向量；移位非法；结果反压；连续两次请求；复位后的第一次请求。累加用 INT16 极值核对 36 位下界仍落在 INT48 内。
- 验收：与一个独立的整数参考逐项一致，输出顺序满足第 5 节。旧 18 结果 TB 仍只对旧模块运行。
- 风险：把新模块接进旧流水线会立刻与“必须 18 个结果”冲突。C1 不接生产流水线。
- 回滚：删除新文件，不动 Toy 模块。

### RTL-C2 稠密 512 与非整齐维

- 前提：C0。与 C1 并行时不改交互接口。
- 修改：新的参数化例化或新外壳，把 `MAX_IN_DIM/MAX_OUT_DIM` 设到至少 512，`MAX_WEIGHT_VALUES` 至少 474368，`MAX_BIAS_VALUES` 至少 1617。不改 A18 内核里的 64/2048/128。
- 测试：单独跑 `13→512`、`512→256`、`256→64`、`64→16`、`367→512`、`512→256`、`256→1`。每层核对尾块掩码、权重地址和输出个数。用合成 INT8 权重，不使用训练 checkpoint。
- 验收：七层的整数结果与独立参考一致；越界权重仍报错。
- 风险：大数组在仿真中占用内存。若单层 `512→256` 已能证明地址和尾块，全权重映像可以留到 C4，但 C2 不能只跑 `512→512`。
- 回滚：新外壳删除后，A18 仍是 64/2048/128。

### RTL-C3 控制流连接

- 前提：C1 与 C2 的接口冻结未被破坏。
- 修改：新流水线，不改 `dlrm_internal_pipeline_controller.sv`。描述符槽至少 7。Bottom 接收 16 个结果。嵌入槽 26 个、每槽 16 维。Top 装入按 367 分块。
- 测试：槽未齐不能启动；Bottom 与嵌入到达顺序对调；交互输出下标不连续则报错；Top 末块掩码为 15 个有效元素。
- 验收：一条合成请求跑完 Bottom、交互、Top，最终 1 个整数与参考一致。
- 风险：描述符索引从 2 位变成至少 3 位，旧主机脚本不能直接复用。
- 回滚：新流水线不替换 A13 外壳。

### RTL-C4 完整几何仿真

- 前提：C3。权重仍是合成整数。
- 修改：一条顶层仿真，装入全部 474368 个合成权重和 1617 个偏置。
- 测试：至少两条不同输入、连续请求、中间反压、复位后第一拍。
- 验收：逐层激活和最终整数与参考一致。报告仿真周期，并标明这不是板级时延。
- 风险：把仿真周期乘以 Toy 的 1174 比例。禁止。
- 回滚：测试平台删除，RTL 新文件保留到上一个通过的阶段。

### RTL-C5 与冻结定点参考逐层对比

- 前提：GLM 已给出与锁定 commit 语义一致的定点权重、每层移位、ReLU 位和最终 Sigmoid 的定义；训练已经完成并冻结，独立 EVAL 已按预定协议跑完。step 42000 的 0.7844 不能充当这个前提。
- 修改：只加对比测试，不改舍入和饱和来迁就权重。
- 验收：至少 1000 条真实输入的逐层整数一致。模型质量用冻结后的 EVAL，不用这 1000 条代替。
- 回滚：权重包不写入 Toy 测试目录。

### RTL-C6 物理实现

- 前提：C4 已通过；C5 可以后补数值，但不能把未量化的综合结果说成模型已通过。用户在 F37X 上跑 Vivado/Vitis 2020.2。本审计不启动 implementation。
- 验收：同一工具版本的资源、实现频率和时序余量。频率下降则用时间 `周期/频率` 比较，不用周期数单独比较。
- 回滚：不覆盖已有 xclbin 和已验收工程目录。

### RTL-C7 Stage A 板上功能

- 前提：C6 的比特流由用户生成。CPU 查表，FPGA 只算。
- 验收：板上整数与 C4/C5 的参考一致。内核时间与主机传输分开记。
- 回滚：不把这次板级运行写成加速比。

## 8. 资源与时序风险（ESTIMATE）

以下数字是容量估算，不是综合结果。

- 稠密权重 474368 字节，即 463.25 KiB。偏置若按 24 位存放，1617 项约 4.7 KiB。激活双缓冲在 512 维、INT16 下是 2 KiB 量级。交互向量存储 27×16×2 字节约 1 KiB。
- VU37P 的片上存储从容量上看可以放下这组权重。当前 RTL 没有分配这块存储，也没有综合证据。大数组可能被综合成不期望的分布式 RAM，时序不能从 Toy 的 100 MHz 外推。
- 16 个逻辑 MAC 通道不等于 16 个 DSP。交互若保持一拍一对元素的串行乘加，乘法器数量可以很少，但 351×16 次乘法会变成另一段周期。这个周期数要等 C4 计数，不能现在估算成时延。
- 16 通道、100 MHz、每拍每通道一次运算时，仅稠密加交互的理想工作量约为 29999 拍、约 300 μs。这不含供数、归约、量化和控制，也不是本设计已经达到的时间。

## 9. 与 GLM 定点导出的接口合同

RTL 在 C5 之前只接受合成整数。GLM 导出必须逐层给出：

| 项 | 合同 |
|---|---|
| 权重 | INT8，行数与 `in_dim*out_dim` 一致，地址按描述符基址 |
| 偏置 | INT24，每层 `out_dim` 个 |
| 激活与输出 | INT16 |
| 稠密乘积 | 有符号 24 位，累加 INT48 |
| 交互乘积 | 有符号 32 位，16 项累加使用现有 INT48，不改成 24 位 |
| 舍入 | 就近，中点远离零，再饱和到 INT16。禁止为跑通改成截断 |
| 移位 | 每层一个 6 位移位，允许层间不同。Toy 的 `output_shift=0` 不是 Kaggle 尺度 |
| Bottom ReLU | 锁定源码 `sigmoid_bot=-1`，`create_mlp` 在非 Sigmoid 层后接 ReLU。Bottom 四层的 ReLU 位都应为 1，包括 64→16。这是源码行为，不是本审计新加的激活 |
| Top | `sigmoid_top=ln_top.size-2`。367→512 与 512→256 后为 ReLU；256→1 在官方模块里是 Sigmoid。RTL 没有 Sigmoid |
| 最终非线性 | 主机对 RTL 的线性整数做与官方 `nn.Sigmoid` 一致的函数。RTL 不静默插入 Sigmoid 或改阈值 |
| 交互顺序 | `[Bottom_0..15, dot(i,j) for i=1..26 for j=0..i-1]` |
| 未冻结前 | 不得用 `last_state.pt`、`best_validation.pt` 或 0.7844 生成“已通过”的黄金结果 |

## 10. 真正的 blocker

1. 交互引擎不是“参数还没调大”。配对表、结果个数 18、装入索引 3 位、结果索引 5 位都是结构字面量。
2. 生产流水线把 Toy 几何写进了状态机：4 个嵌入、8 个 Bottom 结果、18 个交互结果、两块 Top 装入。只增大 `MAX_IN_DIM` 不会改这些比较。
3. 描述符只有 4 槽，Kaggle 需要 7 个同时驻留的层。
4. 权重和偏置上限在内核上是 2048 和 128，在引擎默认值上是 65536 和 1024。Kaggle 是 474368 和 1617。
5. A18 把最大层宽覆写为 64。367 和 512 会在描述符检查被拒绝。
6. 定点尺度和最终权重还没有。训练未完成。Sigmoid 不在 RTL 中，必须留在导出合同里，不能临时改语义。
7. Stage B 的实际 HBM 可用容量仍未知。它不阻止 Stage A，也不能被写成已经可部署。

## 判断

```text
RTL_SOURCE_AUDIT = PASS
INTERACTION_27V_CAPACITY = REQUIRES_CHANGE
DENSE_512_CAPACITY = REQUIRES_CHANGE
TOP367_MAPPING = REQUIRES_CHANGE
STAGE_A_INTERFACE = REQUIRES_CHANGE
REAL_KAGGLE_RTL = NOT_YET_VALIDATED
FPGA_BOARD_RUN = NOT_STARTED
NEXT_IMPLEMENTATION_STAGE = RTL-C1
```

`RTL_SOURCE_AUDIT=PASS` 只表示这次审计已用源码核对完清单，不表示 RTL 已具备 Kaggle 容量。

`DENSE_512_CAPACITY=REQUIRES_CHANGE` 的证据是生产例化 `MAX_IN_DIM=64` 与权重/偏置上限，不是尾块掩码缺失。掩码在 `dense_layer_engine.sv` 中已经按 `in_dim` 生成。

`NEXT_IMPLEMENTATION_STAGE=RTL-C1`。C2 可与 C1 并行，但不得接入 A13 流水线，也不得修改已验收内核。C3 等到两边的冻结接口都有独立仿真之后。
