# 源码结构说明（交给审阅用）

日期：2026-09-15。范围：只根据本仓库源码与已验收说明整理。不是新实验、不是性能报告。

实现语言：当前计算与查找通路是**手写 SystemVerilog RTL**。仓库内这些模块没有 HLS `#pragma HLS`，也不是 CNN 卷积层。特征交互是 DLRM 的向量点积（五条 8 维向量 → 18 维），不是图像卷积。

当前板上功能夹具 **A17** 是四路固定槽位、固定行号：

```text
slot0 → row 37
slot1 → row 38
slot2 → row 39
slot3 → row 40
```

它**不是**通用多表 embedding 服务：不能按请求选择任意表集合，也不能按请求改行号。

---

## 1. A13、A15、A16、A17 分别是什么

| 阶段 | 一句话 | 查表怎么做 | 和计算的关系 |
|---|---|---|---|
| **A13** | 已验收的 FPGA 计算基线：Bottom MLP → 特征交互 → Top MLP，并带四级周期计数 | Host 在 CPU 上查好 embedding，经 AXI4-Lite 写入四个槽 | 计算本身冻结。无 `m_axi`，不读 HBM |
| **A15** | 把四个槽改成 FPGA 侧 HBM 查找后再交给同一套 A13 计算 | **一条** AXI 读主接口，**顺序**读四行（`slot0→37` … `slot3→40`），注入槽 0–3 | 不改 A13 算术。A15.6 已在板上用 `HBM[0]` 做过功能验收 |
| **A16** | 在 A15 单口顺序查找上增加 lookup / FPGA 端到端周期计数 | 仍是一个 `m_axi_gmem` → `HBM[0]`，四行顺序（同上四行） | 计算计数仍是 A13 的 `322/100/744/1174`。A16.2 已验收为单 Bank 顺序基线 |
| **A17** | 四个独立查找引擎、四个 AXI 读口、四个 BO | 槽 *i* 走 `m_axi_gmemi` → `HBM[i]`；`slot0→37`，`slot1→38`，`slot2→39`，`slot3→40` | 计算模块仍是 A13。A17.6 四 BO 功能已闭合。**不是**分区器，也不是可变索引服务 |

不要把 A17 理解成“四张业务表的通用查询接口”。四个口读的是同一份 1024 字节表的四个固定行；敏感用例只改其中一个槽对应行的内容。

---

## 2. 完整数据流（以当前 A17 夹具为准）

```text
Host
  1. 打开 xclbin / CU（A17：dlrm_a17_1）
  2. 配置层描述符、权重、偏置、稠密输入（AXI4-Lite，与 A13 相同窗口）
  3. 分配 4 个 1024 字节 BO，写入 embedding 表镜像，同步到设备
  4. 把每个 BO 的物理地址写入四个 TABLE_BASE 寄存器
  5. 写 0x300 = START
        |
        v
  四个 AXI 读主接口并行发出各一拍读
        |
        v
  HBM[0..3] 上各一份表（Host 填的 BO）
        |
        v
  四个 A14 v2 查找引擎：地址 = TABLE_BASE + (行号 << 4)
  slot0 → row 37
  slot1 → row 38
  slot2 → row 39
  slot3 → row 40
        |
        v
  每个响应 128 bit（8 个 INT16 通道）依次注入 A13 的 embedding 槽 0..3
        |
        v
  embedding_loaded_mask == 4'hF 后，自动启动 A13：
      Bottom MLP → Feature Interaction → Top MLP
        |
        v
  最终 INT16 结果出现在 0x200；Host 读回并 POP
```

A13 单独运行时没有步骤 3–4 的 HBM 读：四个 embedding 由 Host 直接写寄存器。

---

## 3. 核心文件各自负责什么

### `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv`

A13 的 **F37X 内核顶层**。只有 AXI4-Lite 控制口，没有 HBM 主接口。把地址分成两段：低于 `0x180` 仍接到历史 A2 窗口；`0x180` 起接到 A13 流水线适配器。

### `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`

在冻结的内部流水控制器外包一层 **32 位饱和周期计数**：Bottom / Interaction / Top / Total。算术模块本身不改。一次 START 走完 Bottom → 交互 → Top。

### `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv`

A17 的 **四路并行查找控制器**。例化四个已验收的 A14 v2 引擎。四路都收到响应后，再按槽 0→3 依次向 A13 写 embedding。任一路出错则整组失败，不启动计算。

### `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv`

把四路查找接到 A13。行号参数写死为 `slot0→37`、`slot1→38`、`slot2→39`、`slot3→40`。Host 再经 AXI-Lite 写 embedding 会被拒绝。只有查找四槽都加载完成，才允许 A13 START。

### `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv`

A17 的 **公开内核顶层**：AXI4-Lite + 四个只读 `m_axi_gmem0..3`（写通道 `awvalid` 恒为 0）。保留 A13 寄存器到 `0x224`，A15 窗口 `0x300/0x304/0x308`，A16 计数 `0x30C/0x310`，并增加另外三个 64 位表基址。

### `host/stage2n_a17_6_four_bo_host_v1.cpp`

A17.6 板上 Host。四个 BO 独立分配、填充、同步、写基址、释放。五用例金标准 `-393/-392/-93/-689/-519`。检查 A13 计算计数是否仍为 `322/100/744/1174`。不把 lookup/e2e 写成加速比。

---

## 4. 输入、输出、启动、完成、关键寄存器

时钟与复位：内核端口为 `ap_clk`、`ap_rst_n`（低有效）。周期计数在 `ap_clk` 上升沿上累加。

### A13 内核 / 流水控制器

| 项 | 源码事实 |
|---|---|
| 输入 | AXI4-Lite：层描述符、激活、四个 embedding、权重、偏置、Bottom/Top 配置、START |
| 输出 | 最终结果（有符号 16 位）、index、last、tag；`busy`/`done`；四级周期计数 |
| 启动 | 写 `0x180`，命令字低 16 位 `0x0020`（`PIPE_CMD_START`）。需要配置通路 ready，且核心 `pipeline_start_ready` |
| 完成 | 核心 `done` 锁存到状态寄存器 bit1；`result_valid` 为状态 bit2。Host 写 `0x0040` POP 结果 |
| 关键寄存器 | `0x180` 控制/状态；`0x200` 结果；`0x20C` embedding 已加载掩码；`0x218/0x21C/0x220/0x224` Bottom/交互/Top/合计周期 |

A13 适配器里 embedding 仍可通过 `0x1D0` 与 `PIPE_CMD_EMB_COMMIT=0x0004` 写入。A17 集成后这条 Host 写路径会被拒绝。

### A17 并行查找

| 项 | 源码事实 |
|---|---|
| 输入 | `load_valid`；四个 64 位 `table_base_addr`；四个 32 位 `lookup_index`（集成层喂入 `slot0→37` … `slot3→40`） |
| 输出 | 四个 AXI 读口；`cfg_valid/cfg_index/cfg_data`（128 位）给 A13；`all_loaded`/`done`/`error_mask` |
| 启动 | `load_valid && load_ready`（空闲或已加载态） |
| 完成 | 四路都收到响应且无错后进入注入；槽 3 注入成功时 `done` 一拍，进入 `LOADED` |

### A17 集成层

| 项 | 源码事实 |
|---|---|
| 查找启动 | `load_all_req_valid` 且计算空闲 |
| 计算启动 | `hbm_all_loaded && fresh_group` 等门控满足后，才把 START 传给 A13 |
| Host embedding | `host_embedding_cfg_rejected`：Host 写槽会被拒绝 |

### A17 公开内核 + Host

| 项 | 源码事实 |
|---|---|
| 查找+计算启动 | Host 确认 `0x300` 的 START_READY（bit6）后，写 `0x300 = 0x0001` |
| 完成（Host） | 轮询 `0x180` 的结果有效（bit2）；并检查 `0x300` 的 RESULT_VALID（bit7）。`0x300` bit4 为状态机 `A15_DONE` |
| 表基址 | 槽0：`0x304/0x308`；槽1：`0x318/0x31C`；槽2：`0x320/0x324`；槽3：`0x328/0x32C`（各 64 位，低字在前） |
| 计数 | A13：`0x218..0x224`；lookup：`0x30C`；FPGA 端到端：`0x310` |

四个表基址的**数值**来自运行时 BO 物理地址，不是 RTL 常量。

---

## 5. 明确不是什么

- 不是 HLS IP，不是从 C++/OpenCL 综合出来的计算核。
- 不是 CNN：没有卷积层；交互模块按 DLRM 方式做向量两两点积。
- A17 不是通用多表服务：表数固定为 4 个槽；`slot0→row 37`，`slot1→row 38`，`slot2→row 39`，`slot3→row 40`；映射固定为槽 *i* → 口 *i*。
